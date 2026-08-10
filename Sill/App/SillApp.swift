import SwiftUI
import AppKit

@main
struct SillApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // LSUIElement app: no windows of its own. Everything lives in the notch panel,
        // which AppDelegate owns.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = PanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A missing bundled face must be a reported failure, never a silent fallback to
        // the system font, because that would be a design change nobody approved.
        let fonts = Tokens.verifyFonts()
        for (name, ok) in fonts.sorted(by: { $0.key < $1.key }) {
            if !ok { NSLog("[sill] FONT MISSING: \(name)") }
        }
        if ProcessInfo.processInfo.environment["SILL_TRACE"] == "1" {
            print("[sill] fonts:", fonts.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "))
        }

        controller.start()

        // First run only. Removed at M3 when capture can create these for real.
        if controller.store.todos.isEmpty {
            controller.store.add(title: "Water the fig")
            controller.store.add(title: "Call the dentist",
                                 due: Calendar.current.date(byAdding: .hour, value: -30, to: Date()))
            controller.store.add(title: "Send the lease back",
                                 due: Calendar.current.date(byAdding: .day, value: 2, to: Date()))
            controller.store.saveNow()
        }

        let env = ProcessInfo.processInfo.environment
        if let dir = env["SILL_FILMSTRIP"] {
            let files = Verification.writeFilmstrip(geometry: controller.state.geometry, to: dir)
            files.forEach { print("[sill] wrote \($0)") }
            fflush(stdout)
            NSApp.terminate(nil)
            return
        }
        if env["SILL_PROFILE"] == "1" {
            Task { @MainActor in
                if let r = await controller.profileMorph() {
                    print(String(format: "[sill] morph frames=%d elapsed=%.3fs measured=%.1f fps",
                                 r.frames, r.seconds, r.fps))
                } else {
                    print("[sill] morph profile produced no frames")
                }
                fflush(stdout)
                NSApp.terminate(nil)
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        controller.store.saveNow()
    }
}
