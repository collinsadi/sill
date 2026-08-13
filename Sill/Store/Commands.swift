import Foundation
import AppKit
import ServiceManagement
import Observation

/// Settings, and where they live.
///
/// There is no window, so there is no preferences window. The capture field is the command
/// line: it is the only input in the product and it is already focused every time you open
/// it, so giving it a second mode costs no new surface at all. The list replaces the todos
/// rather than covering them, because an overlay would need a container and a container
/// would be a card.
@MainActor
@Observable
final class AppSettings {

    var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }

    init() {
        soundEnabled = UserDefaults.standard.bool(forKey: "soundEnabled")
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                // Registration can fail for an unnotarized build. Failing quietly is correct
                // here: the toggle simply will not stick, and nothing else breaks.
            }
        }
    }
}

/// One command. Words, never icons, because an icon earns its place only where a word cannot
/// do the job faster.
@MainActor
struct Command: Identifiable {
    nonisolated let id = UUID()
    let title: String
    /// Shown on the right, in mono, the way a value is shown rather than a control.
    var value: String?
    let run: @MainActor () -> Void
}

@MainActor
enum CommandList {
    /// The full list, filtered by whatever follows the slash.
    static func all(settings: AppSettings, hotkeyLabel: String) -> [Command] {
        [
            Command(title: "Launch at login",
                    value: settings.launchAtLogin ? "on" : "off") {
                settings.launchAtLogin.toggle()
            },
            Command(title: "Reminder sound",
                    value: settings.soundEnabled ? "on" : "off") {
                settings.soundEnabled.toggle()
            },
            Command(title: "Hotkey", value: hotkeyLabel) { },
            Command(title: "Quit Sill", value: nil) { NSApp.terminate(nil) }
        ]
    }

    /// A leading slash switches capture into commands. Everything after it filters.
    nonisolated static func query(from draft: String) -> String? {
        guard draft.hasPrefix("/") else { return nil }
        return String(draft.dropFirst()).lowercased()
    }

    static func filter(_ commands: [Command], _ query: String) -> [Command] {
        guard !query.isEmpty else { return commands }
        return commands.filter { $0.title.lowercased().contains(query) }
    }
}
