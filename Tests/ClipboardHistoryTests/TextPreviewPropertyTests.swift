import Testing
import Foundation
import SwiftCheck
@testable import ClipboardHistory

// Feature: mac-clipboard-history, Property 9: Text preview formatting

/// **Validates: Requirements 4.2**
///
/// Property: For any text string, the preview function SHALL:
/// (a) replace all newline characters with spaces,
/// (b) if the resulting string exceeds 80 characters, truncate to 80 characters
///     and append an ellipsis character ("…"),
/// (c) if 80 characters or fewer, return the string unchanged after newline replacement.

// MARK: - Generators

/// Generator for strings that include newline characters and varying lengths around 80 chars.
/// Produces strings from 0 to 200+ characters with embedded newlines.
private let textWithNewlinesGen: Gen<String> = Gen<String>.compose { composer in
    // Generate length with focus around the 80-char boundary
    let length = composer.generate(using: Gen<Int>.frequency([
        // 40% near the boundary (70-90 chars)
        (4, Gen<Int>.fromElements(in: 70...90)),
        // 20% short strings (0-69 chars)
        (2, Gen<Int>.fromElements(in: 0...69)),
        // 20% longer strings (91-200 chars)
        (2, Gen<Int>.fromElements(in: 91...200)),
        // 20% much longer strings (201-300 chars)
        (2, Gen<Int>.fromElements(in: 201...300))
    ]))

    if length == 0 {
        return ""
    }

    // Build string with mix of printable characters and newlines
    let chars: [Character] = (0..<length).map { _ in
        // ~15% chance of newline
        let roll = Int.random(in: 0...99)
        if roll < 15 {
            return "\n"
        } else {
            return Character(UnicodeScalar(UInt32.random(in: 32...126))!)
        }
    }
    return String(chars)
}

/// Generator specifically for strings that are short (≤ 80 chars after newline replacement).
/// We generate strings where total length ≤ 80 (newlines count as 1 char each, replaced by space which is also 1 char).
private let shortTextGen: Gen<String> = Gen<String>.compose { composer in
    let length = composer.generate(using: Gen<Int>.fromElements(in: 0...80))

    if length == 0 {
        return ""
    }

    let chars: [Character] = (0..<length).map { _ in
        let roll = Int.random(in: 0...99)
        if roll < 15 {
            return "\n"
        } else {
            return Character(UnicodeScalar(UInt32.random(in: 32...126))!)
        }
    }
    return String(chars)
}

/// Generator specifically for strings that are long (> 80 chars after newline replacement).
/// Since newline→space is a 1-to-1 replacement, length is preserved.
private let longTextGen: Gen<String> = Gen<String>.compose { composer in
    let length = composer.generate(using: Gen<Int>.fromElements(in: 81...300))

    let chars: [Character] = (0..<length).map { _ in
        let roll = Int.random(in: 0...99)
        if roll < 15 {
            return "\n"
        } else {
            return Character(UnicodeScalar(UInt32.random(in: 32...126))!)
        }
    }
    return String(chars)
}

// MARK: - Property Tests

@Suite("Text Preview Formatting Property Tests")
struct TextPreviewPropertyTests {

    // MARK: - Property 9a: Newlines replaced with spaces

    @Test("Text preview never contains newline characters")
    func previewContainsNoNewlines() {
        property("textPreview never contains newline characters for any text input")
            <- forAll(textWithNewlinesGen) { text in
                let content = ClipboardContent.text(text)
                guard let preview = content.textPreview else {
                    return false <?> "textPreview returned nil for text content"
                }
                return !preview.contains("\n")
                    <?> "Preview contained newline for input of length \(text.count)"
            }
    }

    @Test("Newlines are replaced with spaces in text preview")
    func newlinesReplacedWithSpaces() {
        property("textPreview replaces all newlines with spaces")
            <- forAll(textWithNewlinesGen) { text in
                let content = ClipboardContent.text(text)
                guard let preview = content.textPreview else {
                    return false <?> "textPreview returned nil for text content"
                }
                let expectedAfterReplace = text.replacingOccurrences(of: "\n", with: " ")
                if expectedAfterReplace.count <= 80 {
                    // Short string: preview should match exactly
                    return (preview == expectedAfterReplace)
                        <?> "Short text preview mismatch: expected '\(expectedAfterReplace)', got '\(preview)'"
                } else {
                    // Long string: preview should start with the first 80 chars of replaced string
                    let expectedPrefix = String(expectedAfterReplace.prefix(80))
                    return preview.hasPrefix(expectedPrefix)
                        <?> "Long text preview prefix mismatch"
                }
            }
    }

    // MARK: - Property 9b: Strings > 80 chars truncated to 80 + ellipsis

    @Test("Text longer than 80 characters is truncated to 80 chars plus ellipsis")
    func longTextTruncatedWithEllipsis() {
        property("Strings > 80 chars (after newline replacement) are truncated to 81 chars total (80 + ellipsis)")
            <- forAll(longTextGen) { text in
                let content = ClipboardContent.text(text)
                guard let preview = content.textPreview else {
                    return false <?> "textPreview returned nil for text content"
                }

                // After newline replacement, string is > 80 chars, so preview should be 81 chars
                let correctLength = preview.count == 81
                let endsWithEllipsis = preview.hasSuffix("…")
                let expectedPrefix = String(text.replacingOccurrences(of: "\n", with: " ").prefix(80))
                let correctPrefix = preview.hasPrefix(expectedPrefix)

                return (correctLength <?> "Expected 81 chars, got \(preview.count)")
                    ^&&^
                    (endsWithEllipsis <?> "Preview does not end with ellipsis")
                    ^&&^
                    (correctPrefix <?> "Preview prefix does not match expected")
            }
    }

    // MARK: - Property 9c: Strings ≤ 80 chars returned unchanged after newline replacement

    @Test("Text of 80 or fewer characters returned unchanged after newline replacement")
    func shortTextReturnedUnchanged() {
        property("Strings <= 80 chars (after newline replacement) are returned as-is with newlines replaced")
            <- forAll(shortTextGen) { text in
                let content = ClipboardContent.text(text)
                guard let preview = content.textPreview else {
                    return false <?> "textPreview returned nil for text content"
                }

                let expected = text.replacingOccurrences(of: "\n", with: " ")
                return (preview == expected)
                    <?> "Expected '\(expected)', got '\(preview)'"
            }
    }

    // MARK: - Boundary: exactly 80 characters

    @Test("Text of exactly 80 characters is not truncated")
    func exactly80CharsNotTruncated() {
        // Generate strings of exactly 80 characters (some with newlines)
        let exactly80Gen = Gen<String>.compose { composer in
            let chars: [Character] = (0..<80).map { _ in
                let roll = Int.random(in: 0...99)
                if roll < 15 {
                    return "\n"
                } else {
                    return Character(UnicodeScalar(UInt32.random(in: 32...126))!)
                }
            }
            return String(chars)
        }

        property("Strings of exactly 80 chars are returned unchanged (with newlines replaced)")
            <- forAll(exactly80Gen) { text in
                let content = ClipboardContent.text(text)
                guard let preview = content.textPreview else {
                    return false <?> "textPreview returned nil for text content"
                }

                let expected = text.replacingOccurrences(of: "\n", with: " ")
                let correctContent = preview == expected
                let noEllipsis = !preview.hasSuffix("…")

                return (correctContent <?> "Content mismatch for 80-char string")
                    ^&&^
                    (noEllipsis <?> "80-char string should not have ellipsis")
            }
    }

    // MARK: - Image content returns nil

    @Test("Image content returns nil for textPreview")
    func imageContentReturnsNil() {
        let imageDataGen = Gen<Data>.compose { composer in
            let size = composer.generate(using: Gen<Int>.fromElements(in: 0...1000))
            return Data((0..<size).map { _ in UInt8.random(in: 0...255) })
        }

        property("Image content always returns nil for textPreview")
            <- forAll(imageDataGen) { data in
                let content = ClipboardContent.image(data)
                return (content.textPreview == nil)
                    <?> "Expected nil textPreview for image content, got non-nil"
            }
    }
}
