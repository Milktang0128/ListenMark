import AppKit
import Carbon.HIToolbox

/// Global hotkey via Carbon's RegisterEventHotKey. Unlike an NSEvent global
/// monitor, this fires system-wide WITHOUT requiring Accessibility permission,
/// so the trigger works even before the user grants access.
final class HotkeyManager {
    static let shared = HotkeyManager()
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    var onFire: (() -> Void)?

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            HotkeyManager.shared.onFire?()
            return noErr
        }, 1, &spec, nil, &handler)
    }

    /// Carbon modifier mask = cmdKey | optionKey | controlKey | shiftKey.
    func register(keyCode: UInt32, carbonModifiers: UInt32) {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        let id = EventHotKeyID(signature: OSType(0x47454257), id: 1) // 'GEBW'
        RegisterEventHotKey(keyCode, carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
    }
}
