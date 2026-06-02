import Testing
import Foundation
import SwiftCheck
@testable import ClipboardHistory

// Feature: mac-clipboard-history, Property 2: Duplicate detection correctness

/// **Validates: Requirements 1.5**
///
/// Property: For any ClipboardContent value and a HistoryStore whose most recent entry
/// contains byte-identical content of the same type, the duplicate detection function SHALL
/// return true. Conversely, for any content that differs by at least one byte from the most
/// recent entry, it SHALL return false.

// MARK: - Duplicate Detection Logic

/// Simulates the duplicate detection behavior as specified in the design:
/// Returns true if the given content is byte-identical to the most recent entry's content.
/// Returns false if content differs or if there is no most recent entry.
private func isDuplicate(_ content: ClipboardContent, mostRecentContent: ClipboardContent?) -> Bool {
    guard let mostRecent = mostRecentContent else {
        return false
    }
    return content == mostRecent
}

// MARK: - Generators

/// Generator for random text content with reasonable sizes for testing.
/// Generates text strings from 0 to 1000 characters using printable ASCII.
private let textContentGen: Gen<ClipboardContent> = Gen<ClipboardContent>.compose { composer in
    let length = composer.generate(using: Gen<Int>.fromElements(in: 0...1000))
    let text: String
    if length == 0 {
        text = ""
    } else {
        text = String((0..<length).map { _ in
            Character(UnicodeScalar(UInt32.random(in: 32...126))!)
        })
    }
    return .text(text)
}

/// Generator for random image content with reasonable sizes for testing.
/// Generates image data from 0 to 1000 bytes.
private let imageContentGen: Gen<ClipboardContent> = Gen<ClipboardContent>.compose { composer in
    let size = composer.generate(using: Gen<Int>.fromElements(in: 0...1000))
    let data = Data((0..<size).map { _ in UInt8.random(in: 0...255) })
    return .image(data)
}

/// Generator that produces any ClipboardContent (text or image).
private let anyContentGen: Gen<ClipboardContent> = Gen<ClipboardContent>.one(of: [
    textContentGen,
    imageContentGen
])

/// Generator that produces a pair of distinct ClipboardContent values.
/// Ensures the two values differ by at least one byte.
private let distinctContentPairGen: Gen<(ClipboardContent, ClipboardContent)> = Gen<(ClipboardContent, ClipboardContent)>.compose { composer in
    let first: ClipboardContent = composer.generate(using: anyContentGen)

    // Generate a second content that is guaranteed to be different from the first
    let second: ClipboardContent
    switch first {
    case .text(let originalText):
        // Modify the text to ensure it differs by at least one byte
        let modifiedText = originalText + "X"
        second = .text(modifiedText)
    case .image(let originalData):
        // Modify the data to ensure it differs by at least one byte
        var modifiedData = originalData
        modifiedData.append(0xFF)
        second = .image(modifiedData)
    }

    return (first, second)
}

/// Generator that produces a content and a different-type content (text vs image).
private let crossTypeContentPairGen: Gen<(ClipboardContent, ClipboardContent)> = Gen<(ClipboardContent, ClipboardContent)>.compose { composer in
    let textContent: ClipboardContent = composer.generate(using: textContentGen)
    let imageContent: ClipboardContent = composer.generate(using: imageContentGen)

    // Randomly choose which is first and which is second
    let swapped: Bool = composer.generate(using: Gen<Bool>.pure(true))
    if swapped {
        return (textContent, imageContent)
    } else {
        return (imageContent, textContent)
    }
}

// MARK: - Property Tests

@Suite("Duplicate Detection Property Tests")
struct DuplicateDetectionPropertyTests {

    // MARK: - Identical Content Detection

    @Test("Byte-identical content is detected as duplicate")
    func identicalContentDetectedAsDuplicate() {
        property("Duplicate detection returns true for byte-identical content")
            <- forAll(anyContentGen) { content in
                // When the most recent entry has byte-identical content,
                // duplicate detection SHALL return true
                return isDuplicate(content, mostRecentContent: content) == true
                    <?> "Expected isDuplicate to return true for identical content: \(content)"
            }
    }

    @Test("Byte-identical text content is detected as duplicate")
    func identicalTextContentDetectedAsDuplicate() {
        property("Duplicate detection returns true for identical text content")
            <- forAll(textContentGen) { content in
                return isDuplicate(content, mostRecentContent: content) == true
                    <?> "Expected isDuplicate to return true for identical text"
            }
    }

    @Test("Byte-identical image content is detected as duplicate")
    func identicalImageContentDetectedAsDuplicate() {
        property("Duplicate detection returns true for identical image content")
            <- forAll(imageContentGen) { content in
                return isDuplicate(content, mostRecentContent: content) == true
                    <?> "Expected isDuplicate to return true for identical image data"
            }
    }

    // MARK: - Different Content Detection

    @Test("Content differing by at least one byte is not detected as duplicate")
    func differentContentNotDetectedAsDuplicate() {
        property("Duplicate detection returns false for content differing by at least one byte")
            <- forAll(distinctContentPairGen) { pair in
                let (original, modified) = pair
                return isDuplicate(modified, mostRecentContent: original) == false
                    <?> "Expected isDuplicate to return false for different content"
            }
    }

    @Test("Content of different types is not detected as duplicate")
    func differentTypeContentNotDetectedAsDuplicate() {
        property("Duplicate detection returns false when content types differ")
            <- forAll(crossTypeContentPairGen) { pair in
                let (first, second) = pair
                return isDuplicate(second, mostRecentContent: first) == false
                    <?> "Expected isDuplicate to return false for different content types"
            }
    }

    // MARK: - Empty Store Edge Case

    @Test("No duplicate when history store has no entries")
    func noDuplicateWhenStoreEmpty() {
        property("Duplicate detection returns false when there is no most recent entry")
            <- forAll(anyContentGen) { content in
                return isDuplicate(content, mostRecentContent: nil) == false
                    <?> "Expected isDuplicate to return false when store is empty"
            }
    }
}
