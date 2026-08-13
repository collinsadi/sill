import AppKit
import Carbon.HIToolbox

/// Global hotkey via Carbon.
///
/// `RegisterEventHotKey` needs no permission at all, so the hotkey works on first launch.
/// `NSEvent.addGlobalMonitorForEvents` would need Input Monitoring, which means a system
/// prompt asking to receive keystrokes from any application, a trip to System Settings, and
/// usually a relaunch. That is a heavy toll for a todo app, so this uses the old API on purpose.
@MainActor
final class HotKey {

    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    /// Carbon hands back a C callback with no context, so the action lives here.
    fileprivate static var action: (() -> Void)?

    nonisolated static let optionSpace = (key: UInt32(kVK_Space), modifiers: UInt32(optionKey))

    func register(key: UInt32 = optionSpace.key,
                  modifiers: UInt32 = optionSpace.modifiers,
                  action: @escaping () -> Void) {
        unregister()
        Self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { HotKey.action?() }
            return noErr
        }, 1, &eventType, nil, &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x53494C4C), id: 1)  // 'SILL'
        RegisterEventHotKey(key, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    // No deinit: a nonisolated deinit cannot touch the Carbon pointers under strict
    // concurrency, and this object lives for the whole process anyway. Call unregister()
    // explicitly if that ever stops being true.
}
