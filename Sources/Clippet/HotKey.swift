import AppKit
import Carbon.HIToolbox

/// System-wide hotkey via Carbon RegisterEventHotKey — works without any special permission.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let callback: () -> Void

    private static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
        "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "space": 49, "`": 50,
    ]

    /// Spec format: modifiers and one key joined by "+", e.g. "cmd+shift+v".
    /// Modifiers: cmd/command, shift, opt/option/alt, ctrl/control.
    init?(spec: String, callback: @escaping () -> Void) {
        self.callback = callback

        var modifiers: UInt32 = 0
        var keyCode: UInt32?
        for part in spec.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "cmd", "command": modifiers |= UInt32(cmdKey)
            case "shift": modifiers |= UInt32(shiftKey)
            case "opt", "option", "alt": modifiers |= UInt32(optionKey)
            case "ctrl", "control": modifiers |= UInt32(controlKey)
            default: keyCode = Self.keyCodes[part]
            }
        }
        guard let keyCode, modifiers != 0 else {
            NSLog("Clippet: invalid hotkey spec '\(spec)'")
            return nil
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        var installedHandler: EventHandlerRef?
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().callback()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &installedHandler)
        handlerRef = installedHandler

        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_5054), id: 1) // "CLPT"
        var registered: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &registered)
        guard status == noErr, registered != nil else {
            NSLog("Clippet: RegisterEventHotKey failed with status \(status)")
            return nil
        }
        hotKeyRef = registered
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
