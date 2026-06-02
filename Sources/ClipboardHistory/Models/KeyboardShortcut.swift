import Carbon

/// Represents a global keyboard shortcut with a key code and modifier flags.
/// Uses Carbon modifier flags for compatibility with the `RegisterEventHotKey` API.
struct KeyboardShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32  // Carbon modifier flags

    /// Default shortcut: Cmd+Shift+V
    static let `default` = KeyboardShortcut(
        keyCode: 0x09, // kVK_ANSI_V
        modifiers: UInt32(cmdKey | shiftKey)
    )

    /// Validates that the shortcut contains at least one modifier key
    /// (Cmd, Option, Control, or Shift) combined with a non-modifier key.
    var isValid: Bool {
        let hasModifier = modifiers & UInt32(cmdKey | optionKey | controlKey | shiftKey) != 0
        return hasModifier && keyCode != 0
    }
}
