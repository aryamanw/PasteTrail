// PasteTrail/App/KeyboardShortcutManager.swift
import Carbon
import AppKit

final class KeyboardShortcutManager {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handlerUPP: EventHandlerUPP?
    var onActivate: (() -> Void)?

    private let hotKeyID = EventHotKeyID(signature: fourCharCode("PTRL"), id: 1)

    // MARK: - Register / Unregister

    func register() {
        handlerUPP = { (_, event, userData) -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<KeyboardShortcutManager>.fromOpaque(userData).takeUnretainedValue()
            manager.onActivate?()
            return noErr
        }

        let eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            handlerUPP,
            1,
            [eventSpec],
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        // ⌘⇧V: cmdKey | shiftKey, kVK_ANSI_V = 9
        RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    deinit { unregister() }
}

// MARK: - Helpers

private func fourCharCode(_ string: String) -> OSType {
    precondition(string.unicodeScalars.count == 4, "fourCharCode requires exactly 4 characters")
    var result: OSType = 0
    for char in string.unicodeScalars {
        result = (result << 8) + OSType(char.value)
    }
    return result
}
