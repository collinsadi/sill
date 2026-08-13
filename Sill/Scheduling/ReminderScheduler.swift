import Foundation
import AppKit
import UserNotifications
import Observation

/// Reminders.
///
/// A reminder should feel like the machine noticing something, not like an alert firing.
/// The in notch channel is primary and calm by default. Escalation increases presence and
/// never volume, and it has a ceiling: after the second step the app has said everything it
/// is going to say and it stops.
@MainActor
@Observable
final class ReminderScheduler {

    /// Presence, not volume. Each step changes how far the droplet hangs, nothing else.
    enum Level: Int, Sendable, Comparable {
        case none = 0, due = 1, escalated = 2, ceiling = 3
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

        /// How far the pendant hangs, as morph progress. It never detaches: detaching would
        /// mean the app opened something, and holding means there is something here.
        var pendant: Double {
            switch self {
            case .none: return 0
            case .due: return 0.13
            case .escalated, .ceiling: return 0.21
            }
        }
    }

    /// The todo currently being reminded about, if any.
    private(set) var active: Todo?
    private(set) var level: Level = .none
    /// How many others also came due. The peek never stacks.
    private(set) var queued: Int = 0
    /// True while the peek is showing. It retreats on its own.
    var peekVisible = false

    /// Quiet hours is app owned. Focus state is not readable from any public API and we do
    /// not fake it: the system suppresses its own notifications, and the in notch channel is
    /// ours to hold back.
    var quietHoursEnabled = true
    var quietStartHour = 22
    var quietEndHour = 8

    /// One sound exists: a single short click at the due moment. Never on escalation, never
    /// on completion, never on capture. Off by default, because a menu bar utility that makes
    /// a noise on first run gets uninstalled on first run.
    var soundEnabled = false

    private weak var store: TodoStore?
    private var timer: Timer?
    private var firstSeen: [UUID: Date] = [:]
    private var notified: Set<UUID> = []
    private var peekTask: Task<Void, Never>?

    /// Panel visibility, supplied by the controller. When the panel is not on screen the
    /// reminder goes through Notification Center instead.
    var panelIsVisible: () -> Bool = { false }

    func start(store: TodoStore) {
        self.store = store
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    var isQuiet: Bool {
        guard quietHoursEnabled else { return false }
        let h = Calendar.current.component(.hour, from: Date())
        return quietStartHour > quietEndHour
            ? (h >= quietStartHour || h < quietEndHour)
            : (h >= quietStartHour && h < quietEndHour)
    }

    func tick() {
        guard let store else { return }
        let now = Date()
        let due = store.visible.filter { !$0.isCompleted && ($0.due.map { $0 <= now } ?? false) }

        guard let first = due.first else {
            active = nil; level = .none; queued = 0; peekVisible = false
            return
        }

        // Two or five, the peek never stacks. It shows the most urgent and counts the rest.
        queued = max(0, due.count - 1)

        let seen = firstSeen[first.id] ?? now
        firstSeen[first.id] = seen
        let elapsed = now.timeIntervalSince(seen)

        let newLevel: Level
        if elapsed >= 6 * 3600 { newLevel = .ceiling }
        else if elapsed >= 3600 { newLevel = .escalated }
        else { newLevel = .due }

        let isNew = active?.id != first.id
        active = first
        level = newLevel

        // Suppressed: no droplet motion, no peek, no sound. The sill goes cold and that is
        // the entire signal, which is what suppressed should mean.
        guard !isQuiet else { peekVisible = false; return }

        if isNew {
            if panelIsVisible() {
                showPeek()
            } else {
                if !notified.contains(first.id) {
                    notified.insert(first.id)
                    Self.post(id: first.id.uuidString,
                              title: first.title,
                              body: queued > 0 ? "Due now. \(queued) more came due." : "Due now.")
                }
            }
            if soundEnabled { NSSound(named: "Pop")?.play() }
        }
    }

    /// Shows the one thing, then retreats on its own.
    func showPeek() {
        peekVisible = true
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            self?.peekVisible = false
        }
    }

    func dismissPeek() {
        peekTask?.cancel()
        peekVisible = false
    }

    /// Acting on a reminder clears it, and clears the escalation with it.
    func resolve(_ id: UUID) {
        firstSeen[id] = nil
        notified.remove(id)
        dismissPeek()
        tick()
    }

    // MARK: System fallback

    /// When the panel is not on screen this goes through Notification Center. We control the
    /// payload, not the material: same voice, same two actions, no marketing.
    ///
    /// `nonisolated static` on purpose. A closure declared inside a @MainActor type inherits
    /// that isolation, and UNUserNotificationCenter runs its completion handler on a
    /// background queue, so the isolation check trapped and took the whole app down on launch.
    /// Bookkeeping stays isolated; only plain values cross.
    nonisolated static func post(id: String, title: String, body: String) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert]) { granted, _ in
                guard granted else { return }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = nil
                UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: id, content: content, trigger: nil))
            }
    }
}
