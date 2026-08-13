import AppKit
import SwiftUI
import Observation

/// Panel state shared with the view layer. Views know this; they know nothing about NSPanel.
@MainActor
@Observable
final class PanelState {
    /// Verification hook, not a feature. `SILL_START_EXPANDED=1` launches expanded so a
    /// milestone screenshot can capture that state without synthesising clicks, which would
    /// otherwise need Accessibility permission.
    var isExpanded = ProcessInfo.processInfo.environment["SILL_START_EXPANDED"] == "1"
    var metrics: HostMetrics?

    /// NSWindow rounds frame origins to integer points, but a notch of odd width has a
    /// half point centre. Without correcting for that the drawn notch block sits half a
    /// point off the real one, which is a one pixel seam at 2x, at exactly the junction
    /// the design says must have no seam. The remainder is applied to the content instead.
    var subpointOffsetX: CGFloat = 0

    /// Clock driven morph. `morphStart` is nil when nothing is animating.
    var morphStart: Date?
    var morphOpening = true
    /// Progress at the moment a close began, so an interrupted open retracts from where it is.
    var morphCloseFrom: Double = 1
    /// Resting value when no animation is in flight.
    var morphResting: Double = ProcessInfo.processInfo.environment["SILL_START_EXPANDED"] == "1" ? 1 : 0

    var morphIsSettled: Bool { morphStart == nil }

    /// Set by the controller. The view layer knows nothing about NSPanel, so a tap is
    /// reported upward rather than acted on here.
    var onToggle: (() -> Void)?

    /// Keyboard focus. Held here rather than in the view because the key monitor lives in
    /// AppKit and both have to agree on which row is focused.
    var focusedRowID: UUID?
    var editingRowID: UUID?
    /// Set when focus moves to a row, so the capture field stops swallowing keystrokes.
    var captureFocused = true
    /// Raised when a row asks to be snoozed from the keyboard.
    var snoozeRequestID: UUID?

    /// Model phase. Drives the waterline and nothing else: capture never waits on it.
    var aiPhase: IntelligenceBridge.Phase = .idle
    /// Set when the model is missing or the call failed. Tertiary, below the fold of
    /// attention, because this is a working app and not a broken one.
    var aiMessage: String?

    /// A held pendant while something is due. It never detaches: detaching means the app
    /// opened something, holding means there is something here.
    var pendant: Double = 0
    /// Peek height, used instead of the full panel while a reminder is showing.
    var peekMode = false
    static let peekHeight: CGFloat = 150

    /// Progress at a given instant. Pure function of the clock, which is what lets the Canvas
    /// redraw every frame instead of once per withAnimation call.
    func progress(at date: Date, reduceMotion: Bool) -> Double {
        // Collapsed but something is due: hold the pendant rather than sitting flat.
        guard let start = morphStart else { return max(morphResting, isExpanded ? 0 : pendant) }
        let t = date.timeIntervalSince(start)

        if reduceMotion {
            let d = 0.16
            let f = max(0, min(1, t / d))
            let v = morphOpening ? f : morphCloseFrom * (1 - f)
            if t >= d { finish(at: morphOpening ? 1 : 0) }
            return v
        }

        if morphOpening {
            if t >= MorphTimeline.totalDuration { finish(at: 1); return 1 }
            return MorphTimeline.openProgress(at: t)
        } else {
            if t >= MorphTimeline.closeDuration { finish(at: 0); return 0 }
            return MorphTimeline.closeProgress(from: morphCloseFrom, at: t)
        }
    }

    private func finish(at value: Double) {
        morphResting = value
        morphStart = nil
    }

    func beginOpen(now: Date = Date()) {
        morphOpening = true
        morphStart = now
    }

    func beginClose(now: Date = Date(), from current: Double) {
        morphOpening = false
        morphCloseFrom = current
        morphStart = now
    }

    /// Maximum panel size. The window is sized for this once and never resized again.
    static let panelWidth: CGFloat = 400
    static let maxPanelHeight: CGFloat = 460
    /// Room for the cast shadow, which falls on the wallpaper outside the silhouette.
    static let shadowMargin: CGFloat = 60

    var geometry: Silhouette.Geometry {
        let m = metrics
        return Silhouette.Geometry(
            hostWidth: m?.hostWidth ?? HostMetrics.fallbackPillWidth,
            hostHeight: m?.hostHeight ?? HostMetrics.fallbackPillHeight,
            panelWidth: Self.panelWidth,
            panelHeight: peekMode ? Self.peekHeight : Self.maxPanelHeight,
            hardwareRadius: m?.hardwareCornerRadius ?? 9
        )
    }
}

@MainActor
final class PanelController {

    private var panel: NotchPanel?
    private var maskView: HitMaskView?
    private var keyMonitor: Any?
    let state = PanelState()
    let store = TodoStore()
    let intelligence = IntelligenceBridge()
    let reminders = ReminderScheduler()
    let settings = AppSettings()
    private let hotKey = HotKey()
    let probe = FrameProbe()

    private var windowSize: CGSize {
        CGSize(width: PanelState.panelWidth + PanelState.shadowMargin * 2,
               height: PanelState.maxPanelHeight + PanelState.shadowMargin)
    }

    func start() {
        refreshMetrics()
        buildPanel()

        reminders.panelIsVisible = { [weak self] in self?.state.isExpanded ?? false }
        reminders.start(store: store)
        reminders.soundEnabled = settings.soundEnabled

        // Works on first launch with no permission prompt of any kind.
        hotKey.register { [weak self] in
            guard let self else { return }
            if !self.state.isExpanded { self.toggle() }
            else { NSApp.activate(ignoringOtherApps: true) }
        }
        // Clicking anywhere else closes the panel. Resigning active covers another app,
        // the desktop, and Mission Control, and needs no permission prompt, unlike a global
        // mouse monitor.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state.isExpanded else { return }
                self.toggle()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshMetrics()
                self?.reposition()
            }
        }
    }

    private func refreshMetrics() {
        state.metrics = ScreenGeometry.currentMetrics()
    }

    private func buildPanel() {
        let size = windowSize
        let panel = NotchPanel(contentRect: NSRect(origin: .zero, size: size))

        let mask = HitMaskView(frame: NSRect(origin: .zero, size: size))
        mask.autoresizingMask = [.width, .height]

        let root = PanelRootView(state: state, store: store, intelligence: intelligence,
                                 reminders: reminders, settings: settings, probe: probe)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = mask.bounds
        hosting.autoresizingMask = [.width, .height]
        // The hosting view must not swallow clicks that fall outside the silhouette.
        mask.addSubview(hosting)

        // One source for both the drawing and the hit region.
        mask.maskProvider = { [weak state] in
            guard let state else { return Path() }
            let rect = CGRect(origin: .zero, size: size)
            let local = CGRect(x: PanelState.shadowMargin + state.subpointOffsetX, y: 0,
                               width: rect.width - PanelState.shadowMargin * 2, height: rect.height)
            return Silhouette.path(expanded: state.isExpanded, in: local, g: state.geometry)
        }

        state.onToggle = { [weak self] in self?.toggle() }
        panel.contentView = mask
        self.panel = panel
        self.maskView = mask

        reposition()
        panel.orderFrontRegardless()

        // Escape retracts. The first Escape must never destroy anything, which is why it
        // closes the panel rather than clearing the field.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // NSEvent is not Sendable under strict concurrency, so only the key code crosses
            // the boundary. The monitor already runs on the main thread.
            let code = event.keyCode
            let handled = MainActor.assumeIsolated { self.handleKey(code) }
            return handled ? nil : event
        }
    }

    private func reposition() {
        guard let panel, let m = state.metrics else { return }
        let size = windowSize
        let desiredX = m.hostCenterX - size.width / 2
        // Snap to the device pixel grid rather than the point grid, so a half point notch
        // centre survives on a 2x display instead of becoming a seam.
        let scale = panel.screen?.backingScaleFactor ?? 2
        let snappedX = (desiredX * scale).rounded() / scale
        let originY = m.screenTopY - size.height
        panel.setFrame(NSRect(x: snappedX, y: originY, width: size.width, height: size.height),
                       display: true)
        state.subpointOffsetX = desiredX - panel.frame.origin.x

        if ProcessInfo.processInfo.environment["SILL_TRACE"] == "1" {
            print("[sill] notched=\(m.isNotched) host=\(m.hostWidth)x\(m.hostHeight) centerX=\(m.hostCenterX)")
            print("[sill] screenTopY=\(m.screenTopY) screen=\(m.screenFrame)")
            print("[sill] panel frame=\(panel.frame)")
            print("[sill] panel top == screen top: \(panel.frame.maxY == m.screenTopY)")
            print("[sill] canBecomeKey=\(panel.canBecomeKey) hasShadow=\(panel.hasShadow) level=\(panel.level.rawValue)")
            let rect = CGRect(origin: .zero, size: size)
            let inset = CGRect(x: PanelState.shadowMargin + state.subpointOffsetX, y: 0,
                               width: rect.width - PanelState.shadowMargin * 2, height: rect.height)
            let collapsed = Silhouette.path(expanded: false, in: inset, g: state.geometry)
            let expanded = Silhouette.path(expanded: true, in: inset, g: state.geometry)
            print("[sill] collapsed bounds=\(collapsed.boundingRect)")
            print("[sill] expanded  bounds=\(expanded.boundingRect)")
            // Hit mask correctness: a point in the middle of the notch must hit, a point far
            // out in the shadow margin must miss, in both states.
            let inNotch = CGPoint(x: rect.midX, y: 10)
            let outside = CGPoint(x: 10, y: 10)
            print("[sill] hit inNotch collapsed=\(collapsed.contains(inNotch)) expanded=\(expanded.contains(inNotch))")
            print("[sill] hit outside collapsed=\(collapsed.contains(outside)) expanded=\(expanded.contains(outside))")
            print("[sill] subpointOffsetX=\(state.subpointOffsetX)")
            print("[sill] drawn notch centre on screen=\(panel.frame.origin.x + collapsed.boundingRect.midX) want=\(m.hostCenterX)")
            fflush(stdout)
        }
    }

    /// Row keys are only intercepted when a row actually has focus, so typing an "s" into
    /// the capture field types an "s" rather than snoozing something.
    private func handleKey(_ keyCode: UInt16) -> Bool {
        guard state.isExpanded else { return false }
        let rows = store.visible

        // Escape always wins. While editing it cancels the edit; the first Escape must never
        // destroy anything, so only the second one retracts the panel.
        if keyCode == 53 {
            if state.editingRowID != nil { state.editingRowID = nil; return true }
            if state.focusedRowID != nil { state.focusedRowID = nil; state.captureFocused = true; return true }
            toggle()
            return true
        }

        // Editing a title: everything else belongs to the text field.
        if state.editingRowID != nil { return false }

        func focusIndex() -> Int? { rows.firstIndex { $0.id == state.focusedRowID } }

        switch keyCode {
        case 125:  // Down
            guard !rows.isEmpty else { return true }
            let next = focusIndex().map { min($0 + 1, rows.count - 1) } ?? 0
            state.focusedRowID = rows[next].id
            state.captureFocused = false
            return true
        case 126:  // Up
            guard let i = focusIndex() else { return false }
            if i == 0 {
                state.focusedRowID = nil
                state.captureFocused = true
            } else {
                state.focusedRowID = rows[i - 1].id
            }
            return true
        default:
            break
        }

        guard let id = state.focusedRowID else { return false }
        switch keyCode {
        case 36:  // Return opens the title in place
            state.editingRowID = id
            return true
        case 49:  // Space completes
            store.complete(id)
            state.focusedRowID = nil
            state.captureFocused = true
            return true
        case 1:   // S snoozes
            state.snoozeRequestID = id
            return true
        default:
            return false
        }
    }

    func toggle(reduceMotion: Bool = false) {
        state.isExpanded.toggle()
        probe.begin()
        if state.isExpanded {
            // An LSUIElement app with a non activating panel will not receive keystrokes
            // until it activates. Without this the capture field silently swallows input,
            // which looks exactly like a SwiftUI bug and is not one.
            NSApp.activate(ignoringOtherApps: true)
            panel?.makeKeyAndOrderFront(nil)
            state.beginOpen()
        } else {
            state.focusedRowID = nil
            state.editingRowID = nil
            state.captureFocused = true
            state.beginClose(from: state.progress(at: Date(), reduceMotion: reduceMotion))
            panel?.resignKey()
            NSApp.hide(nil)
        }
    }

    /// Drives one full open and reports the measured draw rate over the animation window.
    func profileMorph() async -> (frames: Int, seconds: Double, fps: Double)? {
        state.isExpanded = true
        state.morphResting = 0
        probe.begin()
        state.beginOpen()
        let window = MorphTimeline.totalDuration
        try? await Task.sleep(nanoseconds: UInt64(window * 1_000_000_000))
        let r = probe.report()
        return r
    }
}
