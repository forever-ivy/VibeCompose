import AppKit
import Carbon
import Foundation

struct HotkeyBinding:
    Codable,
    Hashable,
    Sendable
{
    static let supportedModifierMask = UInt32(
        cmdKey | shiftKey | optionKey | controlKey
    )

    var keyCode: UInt32
    var modifiers: UInt32

    init(
        keyCode: UInt32,
        modifiers: UInt32 = 0
    ) {
        self.keyCode = keyCode
        self.modifiers =
            modifiers & Self.supportedModifierMask
    }

    static let f5 = HotkeyBinding(
        keyCode: UInt32(kVK_F5)
    )

    static let quickAdd = HotkeyBinding(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey | optionKey)
    )

    static let skillSwitcher = HotkeyBinding(
        keyCode: UInt32(kVK_ANSI_S),
        modifiers: UInt32(controlKey | optionKey)
    )

    /// Suggested binding when the user enables Result Preview reopen.
    /// Not applied automatically — Settings starts with no default.
    static let resultPreview = HotkeyBinding(
        keyCode: UInt32(kVK_ANSI_P),
        modifiers: UInt32(controlKey | optionKey)
    )

    var displayName: String {
        modifierDisplayPrefix + Self.keyDisplayName(
            keyCode: keyCode
        )
    }

    var isFunctionKey: Bool {
        Self.functionKeyNames[keyCode] != nil
    }

    func validated() throws -> HotkeyBinding {
        let normalized = HotkeyBinding(
            keyCode: keyCode,
            modifiers: modifiers
        )
        try HotkeyBindingValidator.validate(normalized)
        return normalized
    }

    static func from(event: NSEvent) -> HotkeyBinding {
        HotkeyBinding(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonModifiers(
                from: event.modifierFlags
            )
        )
    }

    static func carbonModifiers(
        from flags: NSEvent.ModifierFlags
    ) -> UInt32 {
        let normalized = flags.intersection(
            .deviceIndependentFlagsMask
        )
        var result: UInt32 = 0
        if normalized.contains(.command) {
            result |= UInt32(cmdKey)
        }
        if normalized.contains(.shift) {
            result |= UInt32(shiftKey)
        }
        if normalized.contains(.option) {
            result |= UInt32(optionKey)
        }
        if normalized.contains(.control) {
            result |= UInt32(controlKey)
        }
        return result
    }

    private var modifierDisplayPrefix: String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 {
            value += "⌃"
        }
        if modifiers & UInt32(optionKey) != 0 {
            value += "⌥"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            value += "⇧"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            value += "⌘"
        }
        return value
    }

    private static func keyDisplayName(
        keyCode: UInt32
    ) -> String {
        if let functionName = functionKeyNames[keyCode] {
            return functionName
        }
        if let specialName = specialKeyNames[keyCode] {
            return specialName
        }
        if let translated = translatedKeyName(
            keyCode: keyCode
        ) {
            return translated
        }
        if let fallback = fallbackKeyNames[keyCode] {
            return fallback
        }
        return L10n.format("Key %ld", Int(keyCode))
    }

    private static func translatedKeyName(
        keyCode: UInt32
    ) -> String? {
        guard
            let source = TISCopyCurrentKeyboardLayoutInputSource()?
                .takeRetainedValue(),
            let rawLayout = TISGetInputSourceProperty(
                source,
                kTISPropertyUnicodeKeyLayoutData
            )
        else {
            return nil
        }

        let layoutData = unsafeBitCast(
            rawLayout,
            to: CFData.self
        )
        guard let bytePointer = CFDataGetBytePtr(layoutData) else {
            return nil
        }
        let layout = UnsafeRawPointer(bytePointer)
            .assumingMemoryBound(
                to: UCKeyboardLayout.self
            )

        var deadKeyState: UInt32 = 0
        var characters = [UniChar](
            repeating: 0,
            count: 8
        )
        var actualLength = 0
        let status = UCKeyTranslate(
            layout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &actualLength,
            &characters
        )
        guard
            status == noErr,
            actualLength > 0
        else {
            return nil
        }

        let value = String(
            utf16CodeUnits: characters,
            count: actualLength
        ).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard
            !value.isEmpty,
            value.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters
                    .contains($0)
            })
        else {
            return nil
        }
        return value.uppercased()
    }

    private static let functionKeyNames: [UInt32: String] = [
        UInt32(kVK_F1): "F1",
        UInt32(kVK_F2): "F2",
        UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5",
        UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7",
        UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11",
        UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13",
        UInt32(kVK_F14): "F14",
        UInt32(kVK_F15): "F15",
        UInt32(kVK_F16): "F16",
        UInt32(kVK_F17): "F17",
        UInt32(kVK_F18): "F18",
        UInt32(kVK_F19): "F19",
        UInt32(kVK_F20): "F20",
    ]

    private static let specialKeyNames: [UInt32: String] = [
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Return): "Return",
        UInt32(kVK_ANSI_KeypadEnter): "Enter",
        UInt32(kVK_Escape): "Esc",
        UInt32(kVK_Delete): "Delete",
        UInt32(kVK_ForwardDelete): "Forward Delete",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "Home",
        UInt32(kVK_End): "End",
        UInt32(kVK_PageUp): "Page Up",
        UInt32(kVK_PageDown): "Page Down",
        UInt32(kVK_Help): "Help",
    ]

    private static let fallbackKeyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E",
        UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W",
        UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y",
        UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
    ]
}

enum HotkeyBindingValidationError:
    Error,
    Equatable,
    Sendable
{
    case unsupportedKey
    case escapeReserved
    case modifierRequired
    case systemShortcutReserved
    case quickAddConflict
}

extension HotkeyBindingValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedKey:
            return L10n.text(
                "This key cannot be registered as a stable global shortcut."
            )
        case .escapeReserved:
            return L10n.text(
                "Esc is reserved for cancelling the current dictation."
            )
        case .modifierRequired:
            return L10n.text(
                "Letters, numbers, punctuation, and navigation keys need Control, Option, or Command."
            )
        case .systemShortcutReserved:
            return L10n.text(
                "This common macOS or editing shortcut is reserved."
            )
        case .quickAddConflict:
            return L10n.text(
                "This shortcut is already used by VibeWhisper Quick Add."
            )
        }
    }
}

enum HotkeyBindingValidator {
    static func validate(
        _ binding: HotkeyBinding
    ) throws {
        guard binding.keyCode <= 127 else {
            throw HotkeyBindingValidationError.unsupportedKey
        }
        guard binding.keyCode != UInt32(kVK_Escape) else {
            throw HotkeyBindingValidationError.escapeReserved
        }
        guard binding != .quickAdd else {
            throw HotkeyBindingValidationError.quickAddConflict
        }

        if binding.modifiers == 0 {
            guard binding.isFunctionKey else {
                throw HotkeyBindingValidationError.modifierRequired
            }
            return
        }

        let hasSubstantiveModifier =
            binding.modifiers
                & UInt32(controlKey | optionKey | cmdKey)
                != 0
        if !binding.isFunctionKey && !hasSubstantiveModifier {
            throw HotkeyBindingValidationError.modifierRequired
        }

        if isReservedSystemShortcut(binding) {
            throw HotkeyBindingValidationError.systemShortcutReserved
        }
    }

    private static func isReservedSystemShortcut(
        _ binding: HotkeyBinding
    ) -> Bool {
        let hasCommand =
            binding.modifiers & UInt32(cmdKey) != 0
        let hasControlOrOption =
            binding.modifiers
                & UInt32(controlKey | optionKey)
                != 0
        guard hasCommand, !hasControlOrOption else {
            return false
        }

        let editingKeys: Set<UInt32> = [
            UInt32(kVK_ANSI_A),
            UInt32(kVK_ANSI_C),
            UInt32(kVK_ANSI_Q),
            UInt32(kVK_ANSI_V),
            UInt32(kVK_ANSI_W),
            UInt32(kVK_ANSI_X),
            UInt32(kVK_ANSI_Z),
            UInt32(kVK_Tab),
            UInt32(kVK_Space),
        ]
        return editingKeys.contains(binding.keyCode)
    }
}

enum VibeWhisperShortcutConflictError:
    Error,
    Equatable,
    Sendable,
    LocalizedError
{
    case dictationAndSkillSwitcherMatch
    case dictationAndResultPreviewMatch
    case skillSwitcherAndResultPreviewMatch

    var errorDescription: String? {
        switch self {
        case .dictationAndSkillSwitcherMatch:
            return L10n.text(
                "The Skill Switcher shortcut must be different from the dictation shortcut."
            )
        case .dictationAndResultPreviewMatch:
            return L10n.text(
                "The Result Preview shortcut must be different from the dictation shortcut."
            )
        case .skillSwitcherAndResultPreviewMatch:
            return L10n.text(
                "The Result Preview shortcut must be different from the Skill Switcher shortcut."
            )
        }
    }
}

enum VibeWhisperShortcutSetValidator {
    static func validate(
        dictation: HotkeyBinding,
        skillSwitcher: HotkeyBinding?,
        resultPreview: HotkeyBinding? = nil
    ) throws {
        _ = try dictation.validated()
        if let skillSwitcher {
            _ = try skillSwitcher.validated()
            guard skillSwitcher != dictation else {
                throw VibeWhisperShortcutConflictError
                    .dictationAndSkillSwitcherMatch
            }
        }
        if let resultPreview {
            _ = try resultPreview.validated()
            guard resultPreview != dictation else {
                throw VibeWhisperShortcutConflictError
                    .dictationAndResultPreviewMatch
            }
            if let skillSwitcher, resultPreview == skillSwitcher {
                throw VibeWhisperShortcutConflictError
                    .skillSwitcherAndResultPreviewMatch
            }
        }
    }
}
