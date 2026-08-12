import SwiftUI

/// Counts Canvas draws so the morph is profiled with real numbers rather than vibes.
@MainActor
final class FrameProbe {
    private var count = 0
    private var start: CFTimeInterval?

    func begin() { count = 0; start = CACurrentMediaTime() }
    func tick() { count += 1 }

    func report() -> (frames: Int, seconds: Double, fps: Double)? {
        guard let start, count > 0 else { return nil }
        let elapsed = CACurrentMediaTime() - start
        guard elapsed > 0 else { return nil }
        return (count, elapsed, Double(count) / elapsed)
    }
}

struct PanelRootView: View {
    @Bindable var state: PanelState
    var store: TodoStore
    var intelligence: IntelligenceBridge
    var reminders: ReminderScheduler
    var probe: FrameProbe?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let full = CGRect(origin: .zero, size: proxy.size)
            let insetX = PanelState.shadowMargin + state.subpointOffsetX

            // Canvas does not interpolate a value animated by withAnimation, so the morph is
            // driven from a clock instead. This also gives deliberate per frame control, which
            // a metaball needs and which chained springs make unavoidable.
            TimelineView(.animation(minimumInterval: nil, paused: state.morphIsSettled)) { timeline in
                let p = state.progress(at: timeline.date, reduceMotion: reduceMotion)
                ZStack(alignment: .topLeading) {
                    // The one shadow. It follows the real metaball outline and falls on the
                    // wallpaper, never on the panel.
                    MetaballCanvas(progress: p,
                                   geometry: state.geometry,
                                   insetX: insetX,
                                   onDraw: { probe?.tick() })
                        .shadow(color: Tokens.shadowCast, radius: 30, x: 0, y: 12)

                    SpecularOverlay(geometry: state.geometry, insetX: insetX, progress: p)

                    if reminders.peekVisible && !state.isExpanded {
                        PeekView(scheduler: reminders, store: store, progress: p)
                            .frame(width: Tokens.Geo.panelWidth)
                            .offset(x: insetX, y: state.geometry.hostHeight)
                    } else {
                        PanelContentView(store: store, state: state, intelligence: intelligence, progress: p, isExpanded: state.isExpanded)
                        .frame(width: Tokens.Geo.panelWidth)
                        .offset(x: insetX, y: state.geometry.hostHeight)
                        .allowsHitTesting(p > 0.9)
                    }
                    // Only live while collapsed. Once open, this layer must not sit above the
                    // content or it swallows every click before a row can see it.
                    if p < 0.5 {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { state.onToggle?() }
                    }
                }
                .frame(width: full.width, height: full.height)
            }
        }
        .ignoresSafeArea()
        .onChange(of: reminders.level) { _, lvl in
            state.pendant = lvl.pendant
        }
        .onChange(of: reminders.peekVisible) { _, showing in
            // The peek is a smaller panel, not the full one, and it never becomes the full one.
            state.peekMode = showing
            if showing { state.beginOpen() } else if !state.isExpanded { state.beginClose(from: 1) }
        }
    }
}
