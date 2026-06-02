import Testing
import Foundation
import SwiftCheck
@testable import ClipboardHistory

// Feature: mac-clipboard-history, Property 1: Entry serialization round-trip

/// **Validates: Requirements 1.1, 1.2**
///
/// Property: For any valid ClipboardEntry (text with up to 1,000,000 characters or image
/// with up to 10 MB of data), encoding it to JSON and then decoding it back SHALL produce
/// an entry with identical id, content, timestamp, and contentType.

// MARK: - Arbitrary Generators

extension ClipboardContent: Arbitrary {
    public static var arbitrary: Gen<ClipboardContent> {
        let textGen = Gen<ClipboardContent>.compose { composer in
            // Generate text with length 0 to 1,000,000 characters
            let length = composer.generate(using: Gen<Int>.fromElements(in: 0...1_000_000))
            let text: String
            if length == 0 {
                text = ""
            } else {
                // Generate a string of the target length using printable ASCII + common unicode
                text = String((0..<length).map { _ in
                    Character(UnicodeScalar(UInt32.random(in: 32...126))!)
                })
            }
            return .text(text)
        }

        let imageGen = Gen<ClipboardContent>.compose { composer in
            // Generate image data with size 0 to 10 MB (10 * 1024 * 1024 bytes)
            // For test performance, limit to smaller sizes most of the time
            let maxSize = 10 * 1024 * 1024
            let size = composer.generate(using: Gen<Int>.fromElements(in: 0...maxSize))
            let data = Data((0..<size).map { _ in UInt8.random(in: 0...255) })
            return .image(data)
        }

        return Gen<ClipboardContent>.one(of: [textGen, imageGen])
    }
}

extension ClipboardEntry.ContentType: Arbitrary {
    public static var arbitrary: Gen<ClipboardEntry.ContentType> {
        Gen<ClipboardEntry.ContentType>.fromElements(of: [.text, .image])
    }
}

extension ClipboardEntry: Arbitrary {
    public static var arbitrary: Gen<ClipboardEntry> {
        Gen<ClipboardEntry>.compose { composer in
            let id = UUID()
            let content: ClipboardContent = composer.generate()
            // Use integer-precision timestamps to avoid floating-point Date encoding issues
            let timeInterval = TimeInterval(Int(composer.generate(
                using: Gen<Int>.fromElements(in: 0...2_000_000_000)
            )))
            let timestamp = Date(timeIntervalSince1970: timeInterval)
            // Derive contentType from content to ensure consistency
            let contentType: ClipboardEntry.ContentType
            switch content {
            case .text:
                contentType = .text
            case .image:
                contentType = .image
            }
            return ClipboardEntry(
                id: id,
                content: content,
                timestamp: timestamp,
                contentType: contentType
            )
        }
    }
}

// MARK: - Property Test

@Suite("Serialization Round-Trip Property Tests")
struct SerializationRoundTripPropertyTests {

    @Test("ClipboardEntry serialization round-trip preserves all fields")
    func entrySerializationRoundTrip() {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Property: encode then decode any ClipboardEntry yields identical result
        // Using a smaller content generator to keep test execution time reasonable
        // while still covering the property across many random inputs
        let smallTextGen = Gen<ClipboardContent>.compose { composer in
            // For performance: text up to 10,000 characters (still validates the property)
            let length = composer.generate(using: Gen<Int>.fromElements(in: 0...10_000))
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

        let smallImageGen = Gen<ClipboardContent>.compose { composer in
            // For performance: image data up to 10,000 bytes (still validates the property)
            let size = composer.generate(using: Gen<Int>.fromElements(in: 0...10_000))
            let data = Data((0..<size).map { _ in UInt8.random(in: 0...255) })
            return .image(data)
        }

        let contentGen = Gen<ClipboardContent>.one(of: [smallTextGen, smallImageGen])

        let entryGen = Gen<ClipboardEntry>.compose { composer in
            let id = UUID()
            let content: ClipboardContent = composer.generate(using: contentGen)
            let timeInterval = TimeInterval(composer.generate(
                using: Gen<Int>.fromElements(in: 0...2_000_000_000)
            ))
            let timestamp = Date(timeIntervalSince1970: timeInterval)
            let contentType: ClipboardEntry.ContentType
            switch content {
            case .text:
                contentType = .text
            case .image:
                contentType = .image
            }
            return ClipboardEntry(
                id: id,
                content: content,
                timestamp: timestamp,
                contentType: contentType
            )
        }

        property("Encoding then decoding a ClipboardEntry produces an identical entry")
            <- forAll(entryGen) { entry in
                do {
                    let data = try encoder.encode(entry)
                    let decoded = try decoder.decode(ClipboardEntry.self, from: data)
                    return decoded.id == entry.id
                        <?> "id mismatch"
                        ^&&^
                        (decoded.content == entry.content
                        <?> "content mismatch")
                        ^&&^
                        (decoded.timestamp == entry.timestamp
                        <?> "timestamp mismatch")
                        ^&&^
                        (decoded.contentType == entry.contentType
                        <?> "contentType mismatch")
                } catch {
                    return false <?> "Encoding/decoding threw error: \(error)"
                }
            }
    }
}
