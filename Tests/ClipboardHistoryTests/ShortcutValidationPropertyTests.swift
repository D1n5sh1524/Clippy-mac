import Testing
import Foundation
import SwiftCheck
@testable import ClipboardHistory

// Feature: mac-clipboard-history, Property 8: Shortcut validation

/// **Validates: Requirements 3.5**
///
/// Property: For any key combination, the validation function SHALL return true if and only
/// if the combination contains at least one modifier key (Cmd, Option, Control, or Shift)
/// AND a non-modifier key (keyCode != 0). Combinations with only modifiers or only
/// non-modifiers SHALL be rejected.

// MARK: - Generators

/// Carbon modifier flag constants used for generating modifier combinations.
/// These match the Carbon framework values used by KeyboardShortcut.
private let carbonCmdKey: UInt32 = 256      // cmdKey
private let carbonShiftKey: UInt32 = 512    // shiftKey
private let carbonOptionKey: UInt32 = 2048  // optionKey
private let carbonControlKey: UInt32 = 4096 // controlKey

/// All individual modifier flags that are recognized by the validation logic.
private let allModifierFlags: [UInt32] = [
    carbonCmdKey, carbonShiftKey, carbonOptionKey, carbonControlKey
]

/// Generator for a non-zero keyCode (valid non-modifier key) in the typical key range 1-127.
private let nonZeroKeyCodeGen: Gen<UInt32> = Gen<UInt32>.fromElements(in: 1...127)

/// Generator for a keyCode in the full typical range 0-127 (includes invalid keyCode 0).
private let anyKeyCodeGen: Gen<UInt32> = Gen<UInt32>.fromElements(in: 0...127)

/// Generator for a non-zero modifier combination (at least one modifier flag set).
/// Randomly selects a subset of modifier flags and bitwise ORs them together.
private let nonZeroModifiersGen: Gen<UInt32> = Gen<UInt32>.compose { composer in
    // Each modifier is independently included or excluded
    let includeCmd = composer.generate(using: Gen<Bool>.arbitrary)
    let includeShift = composer.generate(using: Gen<Bool>.arbitrary)
    let includeOption = composer.generate(using: Gen<Bool>.arbitrary)
    let includeControl = composer.generate(using: Gen<Bool>.arbitrary)

    var modifiers: UInt32 = 0
    if includeCmd { modifiers |= carbonCmdKey }
    if includeShift { modifiers |= carbonShiftKey }
    if includeOption { modifiers |= carbonOptionKey }
    if includeControl { modifiers |= carbonControlKey }

    // Ensure at least one modifier is set
    if modifiers == 0 {
        // Default to Cmd if nothing was selected
        modifiers = carbonCmdKey
    }
    return modifiers
}

/// Generator for a random modifier value (may be zero or any combination of flags,
/// including values that don't correspond to known modifiers).
private let anyModifiersGen: Gen<UInt32> = Gen<UInt32>.compose { composer in
    let includeCmd = composer.generate(using: Gen<Bool>.arbitrary)
    let includeShift = composer.generate(using: Gen<Bool>.arbitrary)
    let includeOption = composer.generate(using: Gen<Bool>.arbitrary)
    let includeControl = composer.generate(using: Gen<Bool>.arbitrary)

    var modifiers: UInt32 = 0
    if includeCmd { modifiers |= carbonCmdKey }
    if includeShift { modifiers |= carbonShiftKey }
    if includeOption { modifiers |= carbonOptionKey }
    if includeControl { modifiers |= carbonControlKey }
    return modifiers
}

// MARK: - Property Tests

@Suite("Shortcut Validation Property Tests")
struct ShortcutValidationPropertyTests {

    // MARK: - Valid shortcuts: modifiers AND non-zero keyCode

    @Test("Shortcuts with at least one modifier AND a non-zero keyCode are valid")
    func validShortcutsAccepted() {
        property("A shortcut with modifiers != 0 (containing recognized flags) and keyCode != 0 is valid")
            <- forAll(nonZeroModifiersGen, nonZeroKeyCodeGen) { (modifiers, keyCode) in
                let shortcut = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
                return shortcut.isValid
                    <?> "Expected valid for keyCode=\(keyCode), modifiers=\(modifiers)"
            }
    }

    // MARK: - Invalid shortcuts: no modifiers

    @Test("Shortcuts with no modifiers are invalid regardless of keyCode")
    func noModifiersInvalid() {
        property("A shortcut with modifiers == 0 is always invalid")
            <- forAll(anyKeyCodeGen) { keyCode in
                let shortcut = KeyboardShortcut(keyCode: keyCode, modifiers: 0)
                return (!shortcut.isValid)
                    <?> "Expected invalid for keyCode=\(keyCode) with no modifiers"
            }
    }

    // MARK: - Invalid shortcuts: keyCode == 0

    @Test("Shortcuts with keyCode == 0 are invalid even with modifiers")
    func zeroKeyCodeInvalid() {
        property("A shortcut with keyCode == 0 is always invalid regardless of modifiers")
            <- forAll(nonZeroModifiersGen) { modifiers in
                let shortcut = KeyboardShortcut(keyCode: 0, modifiers: modifiers)
                return (!shortcut.isValid)
                    <?> "Expected invalid for keyCode=0, modifiers=\(modifiers)"
            }
    }

    // MARK: - Invalid shortcuts: both keyCode == 0 AND no modifiers

    @Test("Shortcuts with both keyCode == 0 and no modifiers are invalid")
    func zeroKeyCodeAndNoModifiersInvalid() {
        let shortcut = KeyboardShortcut(keyCode: 0, modifiers: 0)
        #expect(!shortcut.isValid, "Expected invalid for keyCode=0, modifiers=0")
    }

    // MARK: - Biconditional property: isValid iff (hasModifier AND keyCode != 0)

    @Test("isValid is true if and only if modifiers contain a recognized flag AND keyCode != 0")
    func validationBiconditional() {
        property("isValid == (hasRecognizedModifier && keyCode != 0) for any combination")
            <- forAll(anyKeyCodeGen, anyModifiersGen) { (keyCode, modifiers) in
                let shortcut = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)

                // Compute expected validity using the same logic as the model
                let recognizedModifierMask = carbonCmdKey | carbonOptionKey | carbonControlKey | carbonShiftKey
                let hasModifier = (modifiers & recognizedModifierMask) != 0
                let expectedValid = hasModifier && keyCode != 0

                return (shortcut.isValid == expectedValid)
                    <?> "Mismatch: keyCode=\(keyCode), modifiers=\(modifiers), isValid=\(shortcut.isValid), expected=\(expectedValid)"
            }
    }

    // MARK: - Modifiers without recognized flags are treated as no-modifier

    @Test("Modifier values without recognized flags (Cmd/Shift/Option/Control) are invalid")
    func unrecognizedModifierFlagsInvalid() {
        // Generate modifier values that have bits set but NOT in the recognized modifier positions
        let recognizedMask = carbonCmdKey | carbonShiftKey | carbonOptionKey | carbonControlKey
        let unrecognizedModGen = Gen<UInt32>.compose { composer in
            // Generate a random value that has no recognized modifier bits
            var value = composer.generate(using: Gen<UInt32>.fromElements(in: 1...65535))
            // Clear all recognized modifier bits
            value = value & ~recognizedMask
            // Ensure it's not zero (so we actually have bits set, just not recognized ones)
            if value == 0 { value = 1 } // bit 0 is not a recognized modifier
            return value
        }

        property("Modifiers with only unrecognized bits set produce an invalid shortcut")
            <- forAll(unrecognizedModGen, nonZeroKeyCodeGen) { (modifiers, keyCode) in
                let shortcut = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
                return (!shortcut.isValid)
                    <?> "Expected invalid for unrecognized modifiers=\(modifiers), keyCode=\(keyCode)"
            }
    }
}
