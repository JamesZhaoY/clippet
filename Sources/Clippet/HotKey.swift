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

    enum Failure: Error, CustomStringConvertible {
        /// The spec could not be parsed into modifiers + one key.
        case invalidSpec(String)
        /// The system refused the combination. (A combo another app already holds usually
        /// registers fine and simply never fires, so this is rare.)
        case registrationFailed(String, OSStatus)

        var description: String {
            switch self {
            case .invalidSpec(let spec):
                return "'\(spec)' is not a valid hotkey (expected e.g. \"cmd+shift+v\")"
            case .registrationFailed(let spec, let status):
                return "\(HotKey.displaySymbols(for: spec)) could not be registered (status \(status))"
            }
        }
    }

    /// Spec format: modifiers and one key joined by "+", e.g. "cmd+shift+v".
    /// Modifiers: cmd/command, shift, opt/option/alt, ctrl/control.
    init(spec: String, callback: @escaping () -> Void) throws {
        self.callback = callback
        guard let (keyCode, modifiers) = Self.parse(spec) else {
            throw Failure.invalidSpec(spec)
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
            throw Failure.registrationFailed(spec, status)
        }
        hotKeyRef = registered
    }

    /// Carbon key code + modifier mask for a spec, or nil when it has no key or no modifier.
    static func parse(_ spec: String) -> (keyCode: UInt32, modifiers: UInt32)? {
        var modifiers: UInt32 = 0
        var keyCode: UInt32?
        for part in parts(of: spec) {
            switch part {
            case "cmd", "command": modifiers |= UInt32(cmdKey)
            case "shift": modifiers |= UInt32(shiftKey)
            case "opt", "option", "alt": modifiers |= UInt32(optionKey)
            case "ctrl", "control": modifiers |= UInt32(controlKey)
            default:
                guard keyCode == nil, let code = keyCodes[part] else { return nil }
                keyCode = code
            }
        }
        guard let keyCode, modifiers != 0 else { return nil }
        return (keyCode, modifiers)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

// MARK: - Display helpers

extension HotKey {
    /// "cmd+shift+v" → "⇧⌘V", modifiers in canonical ⌃⌥⇧⌘ order.
    static func displaySymbols(for spec: String) -> String {
        var ctrl = false, opt = false, shift = false, cmd = false
        var key = ""
        for part in Self.parts(of: spec) {
            switch part {
            case "cmd", "command": cmd = true
            case "shift": shift = true
            case "opt", "option", "alt": opt = true
            case "ctrl", "control": ctrl = true
            default: key = part
            }
        }
        var result = ""
        if ctrl { result += "⌃" }
        if opt { result += "⌥" }
        if shift { result += "⇧" }
        if cmd { result += "⌘" }
        result += key == "space" ? "Space" : key.uppercased()
        return result
    }

    /// Key equivalent + modifier mask for showing the hotkey on an NSMenuItem.
    static func menuEquivalent(for spec: String) -> (key: String, modifiers: NSEvent.ModifierFlags)? {
        var modifiers: NSEvent.ModifierFlags = []
        var key: String?
        for part in Self.parts(of: spec) {
            switch part {
            case "cmd", "command": modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            case "opt", "option", "alt": modifiers.insert(.option)
            case "ctrl", "control": modifiers.insert(.control)
            default: key = part == "space" ? " " : part
            }
        }
        guard let key, !modifiers.isEmpty else { return nil }
        return (key, modifiers)
    }

    private static func parts(of spec: String) -> [String] {
        spec.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
