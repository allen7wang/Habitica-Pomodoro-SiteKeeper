import Cocoa
import Carbon

// MARK: - Global HotKey Manager (Alt+Shift+P)
class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?

    func register() {
        // Alt+Shift+P = keyCode 35 (P) + option + shift
        let eventId = EventHotKeyID(signature: OSType(0x48504f4d), id: 1)  // "HPOM"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            UInt32(activeShortcutModifers) | UInt32(cmdKey) | UInt32(optionKey),
            eventId,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRef = ref
            installEventHandler()
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private var activeShortcutModifers: Int { 0 }

    private func installEventHandler() {
        let eventSpec = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))]
        // Use the modern way
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                PomodoroEngine.shared.activate()
            }
            return noErr
        }, 1, eventSpec, nil, nil)
    }
}
