import AppKit

/// The floating panel that sits over the menu bar.
///
/// `canBecomeKey` is the whole reason this subclass exists. A non activating panel refuses
/// keyboard focus, so the capture field silently swallows every keystroke, and it presents
/// exactly like a SwiftUI bug when it is not one.
final class NotchPanel: NSPanel {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        // Follow the user across spaces and sit above full screen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        backgroundColor = .clear
        isOpaque = false
        // The design draws its own shadow onto the wallpaper. The AppKit one would fight it.
        hasShadow = false

        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }
}
