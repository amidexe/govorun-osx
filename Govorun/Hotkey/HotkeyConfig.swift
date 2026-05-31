import AppKit
import Carbon.HIToolbox
import CoreGraphics

struct HotkeyConfig: Equatable {
    enum Kind { case key, modifierOnly }

    var kind:          Kind
    var keyCode:       UInt16
    var modifierFlags: NSEvent.ModifierFlags

    // MARK: - Convenience constructors

    static func key(_ keyCode: UInt16, _ mods: NSEvent.ModifierFlags) -> Self {
        Self(kind: .key, keyCode: keyCode, modifierFlags: mods)
    }
    static func modifierOnly(_ keyCode: UInt16, _ mods: NSEvent.ModifierFlags) -> Self {
        Self(kind: .modifierOnly, keyCode: keyCode, modifierFlags: mods)
    }

    static let `default`     = HotkeyConfig.key(UInt16(kVK_Space),  [.option])
    static let defaultCancel = HotkeyConfig.key(UInt16(kVK_Escape), [])

    // MARK: - UserDefaults

    // Cancel hotkey — optional, nil = disabled
    static var cancelStored: HotkeyConfig? {
        get {
            let kc = UserDefaults.standard.integer(forKey: "cancelHotkeyKeyCode")
            guard kc != 0 else { return nil }
            let mod  = UserDefaults.standard.integer(forKey: "cancelHotkeyModifiers")
            let kind = UserDefaults.standard.string(forKey: "cancelHotkeyKind") ?? "key"
            let k: Kind = kind == "modifierOnly" ? .modifierOnly : .key
            return HotkeyConfig(kind: k, keyCode: UInt16(kc),
                                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(mod)))
        }
        set {
            if let cfg = newValue {
                UserDefaults.standard.set(Int(cfg.keyCode),                forKey: "cancelHotkeyKeyCode")
                UserDefaults.standard.set(Int(cfg.modifierFlags.rawValue), forKey: "cancelHotkeyModifiers")
                UserDefaults.standard.set(cfg.kind == .modifierOnly ? "modifierOnly" : "key",
                                          forKey: "cancelHotkeyKind")
            } else {
                UserDefaults.standard.removeObject(forKey: "cancelHotkeyKeyCode")
                UserDefaults.standard.removeObject(forKey: "cancelHotkeyModifiers")
                UserDefaults.standard.removeObject(forKey: "cancelHotkeyKind")
            }
        }
    }

    static var stored: HotkeyConfig {
        get {
            let kc   = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
            let mod  = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
            let kind = UserDefaults.standard.string(forKey: "hotkeyKind") ?? "key"
            guard kc != 0 else { return .default }
            let k: Kind = kind == "modifierOnly" ? .modifierOnly : .key
            return HotkeyConfig(kind: k, keyCode: UInt16(kc),
                                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(mod)))
        }
        set {
            UserDefaults.standard.set(Int(newValue.keyCode),                forKey: "hotkeyKeyCode")
            UserDefaults.standard.set(Int(newValue.modifierFlags.rawValue), forKey: "hotkeyModifiers")
            UserDefaults.standard.set(newValue.kind == .modifierOnly ? "modifierOnly" : "key",
                                      forKey: "hotkeyKind")
        }
    }

    // MARK: - CGEventFlags (for HotkeyManager)

    var cgModifiers: CGEventFlags {
        var f: CGEventFlags = []
        if modifierFlags.contains(.control)  { f.insert(.maskControl) }
        if modifierFlags.contains(.option)   { f.insert(.maskAlternate) }
        if modifierFlags.contains(.shift)    { f.insert(.maskShift) }
        if modifierFlags.contains(.command)  { f.insert(.maskCommand) }
        return f
    }

    // MARK: - Display

    var displayString: String { displayTokens.joined(separator: " ") }

    var displayTokens: [String] {
        switch kind {
        case .key:
            return modifierFlags.shortcutDisplayTokens + [Self.keyName(for: keyCode)]
        case .modifierOnly:
            if let name = sideSpecificName { return [name] }
            return modifierFlags.shortcutDisplayTokens
        }
    }

    private var sideSpecificName: String? {
        switch keyCode {
        case UInt16(kVK_Option):       return "Left ⌥"
        case UInt16(kVK_RightOption):  return "Right ⌥"
        case UInt16(kVK_Command):      return "Left ⌘"
        case UInt16(kVK_RightCommand): return "Right ⌘"
        case UInt16(kVK_Control):      return "Left ⌃"
        case UInt16(kVK_RightControl): return "Right ⌃"
        case UInt16(kVK_Shift):        return "Left ⇧"
        case UInt16(kVK_RightShift):   return "Right ⇧"
        default: return nil
        }
    }

    // MARK: - Validation

    var isValid: Bool {
        switch kind {
        case .modifierOnly:
            return Self.isModifierKeyCode(keyCode)
        case .key:
            guard !Self.isModifierKeyCode(keyCode) else { return false }
            if Self.isSpecialKeyCode(keyCode) { return true }
            return !modifierFlags.intersection([.control, .option, .shift, .command]).isEmpty
        }
    }

    static func isModifierKeyCode(_ kc: UInt16) -> Bool { modifierKeyCodes.contains(kc) }
    static func isSpecialKeyCode(_ kc: UInt16) -> Bool  { specialKeyCodes.contains(kc) }

    private static let modifierKeyCodes: Set<UInt16> = [
        UInt16(kVK_Shift), UInt16(kVK_RightShift),
        UInt16(kVK_Control), UInt16(kVK_RightControl),
        UInt16(kVK_Option), UInt16(kVK_RightOption),
        UInt16(kVK_Command), UInt16(kVK_RightCommand),
        UInt16(kVK_Function)
    ]

    private static let specialKeyCodes: Set<UInt16> = [
        UInt16(kVK_F1),  UInt16(kVK_F2),  UInt16(kVK_F3),  UInt16(kVK_F4),
        UInt16(kVK_F5),  UInt16(kVK_F6),  UInt16(kVK_F7),  UInt16(kVK_F8),
        UInt16(kVK_F9),  UInt16(kVK_F10), UInt16(kVK_F11), UInt16(kVK_F12),
        UInt16(kVK_F13), UInt16(kVK_F14), UInt16(kVK_F15), UInt16(kVK_F16),
        UInt16(kVK_F17), UInt16(kVK_F18), UInt16(kVK_F19), UInt16(kVK_F20),
    ]

    // MARK: - Key name

    static func keyName(for kc: UInt16) -> String {
        if let s = specialKeyNames[kc] { return s }
        if let s = characterForLayout(kc) { return s.uppercased() }
        return qwertyFallback[kc] ?? "Key\(kc)"
    }

    private static func characterForLayout(_ kc: UInt16) -> String? {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = unsafeBitCast(ptr, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        return bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var len = 0
            let ok = UCKeyTranslate(layout, kc, UInt16(kUCKeyActionDisplay), 0,
                                    UInt32(LMGetKbdType()),
                                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                    &dead, 4, &len, &chars)
            guard ok == noErr, len > 0 else { return nil }
            let s = String(utf16CodeUnits: Array(chars.prefix(len)), count: len)
            return s.unicodeScalars.allSatisfy({ CharacterSet.controlCharacters.contains($0) }) ? nil : s
        }
    }

    private static let specialKeyNames: [UInt16: String] = [
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "Return",
        UInt16(kVK_Tab): "Tab", UInt16(kVK_Escape): "Esc",
        UInt16(kVK_Delete): "Delete", UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→", UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4", UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8", UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
    ]

    private static let qwertyFallback: [UInt16: String] = [
        UInt16(kVK_ANSI_A):"A", UInt16(kVK_ANSI_B):"B", UInt16(kVK_ANSI_C):"C",
        UInt16(kVK_ANSI_D):"D", UInt16(kVK_ANSI_E):"E", UInt16(kVK_ANSI_F):"F",
        UInt16(kVK_ANSI_G):"G", UInt16(kVK_ANSI_H):"H", UInt16(kVK_ANSI_I):"I",
        UInt16(kVK_ANSI_J):"J", UInt16(kVK_ANSI_K):"K", UInt16(kVK_ANSI_L):"L",
        UInt16(kVK_ANSI_M):"M", UInt16(kVK_ANSI_N):"N", UInt16(kVK_ANSI_O):"O",
        UInt16(kVK_ANSI_P):"P", UInt16(kVK_ANSI_Q):"Q", UInt16(kVK_ANSI_R):"R",
        UInt16(kVK_ANSI_S):"S", UInt16(kVK_ANSI_T):"T", UInt16(kVK_ANSI_U):"U",
        UInt16(kVK_ANSI_V):"V", UInt16(kVK_ANSI_W):"W", UInt16(kVK_ANSI_X):"X",
        UInt16(kVK_ANSI_Y):"Y", UInt16(kVK_ANSI_Z):"Z",
    ]
}

extension NSEvent.ModifierFlags {
    var shortcutDisplayTokens: [String] {
        var t: [String] = []
        if contains(.control) { t.append("⌃") }
        if contains(.option)  { t.append("⌥") }
        if contains(.shift)   { t.append("⇧") }
        if contains(.command) { t.append("⌘") }
        return t
    }
}
