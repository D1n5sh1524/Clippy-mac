import Testing
import Foundation
import SwiftCheck
@testable import ClipboardHistory

// Feature: mac-clipboard-history, Property 14: Search clear restores full list

/// **Validates: Requirements 7.6**
///
/// Property: For any HistoryStore state, applying a non-empty search filter and then clearing it
/// SHALL produce a result identical to the original unfiltered entry list (including all image entries).

// MARK: - Generators

/// Generator for a random non-empty text string (1 to 100 printable ASCII characters).
private let textContentGen: Gen<String> = Gen<Int>.fromElements(in: 1...100)
    .flatMap { length in
        Gen<String>.compose { _ in
            String((0..<length).map { _ in
                Character(UnicodeScalar(UInt32.random(in: 32...126))!)
            })
        }
    }

/// Generator for a random image entry (small random Data payload).
private let imageDataGen: Gen<Data> = Gen<Int>.fromElements(in: 1...64)
    .flatMap { length in
        Gen<Data>.compose { _ in
            Data((0..<length).map { _ in UInt8.random(in: 0...255) })
        }
    }

/// Generator for a ClipboardEntry with text content.
private let textEntryGen: Gen<ClipboardEntry> = textContentGen.flatMap { text in
    Gen<ClipboardEntry>.compose { composer in
        let timeInterval = TimeInterval(composer.generate(
            using: Gen<Int>.fromElements(in: 0...2_000_000_000)
        ))
        return ClipboardEntry(
            id: UUID(),
            content: .text(text),
            timestamp: Date(timeIntervalSince1970: timeInterval),
            contentType: .text
        )
    }
}

/// Generator for a ClipboardEntry with image content.
private let imageEntryGen: Gen<ClipboardEntry> = imageDataGen.flatMap { data in
    Gen<ClipboardEntry>.compose { composer in
        let timeInterval = TimeInterval(composer.generate(
            using: Gen<Int>.fromElements(in: 0...2_000_000_000)
        ))
        return ClipboardEntry(
            id: UUID(),
            content: .image(data),
            timestamp: Date(timeIntervalSince1970: timeInterval),
            contentType: .image
        )
    }
}

/// Generator for a mixed set of ClipboardEntries (both text and image).
/// Produces between 1 and 30 entries (staying well under the 50 capacity limit).
private let mixedEntriesGen: Gen<[ClipboardEntry]> = Gen<Int>.fromElements(in: 1...30)
    .flatMap { count in
        Gen<[ClipboardEntry]>.compose { composer in
            (0..<count).map { _ in
                let isText = composer.generate(using: Gen<Bool>.pure(Bool.random()))
                if isText {
                    return composer.generate(using: textEntryGen)
                } else {
                    return composer.generate(using: imageEntryGen)
                }
            }
        }
    }

/// Generator for a non-empty query string (1 to 10 printable ASCII characters).
private let queryGen: Gen<String> = Gen<Int>.fromElements(in: 1...10)
    .flatMap { length in
        Gen<String>.compose { _ in
            String((0..<length).map { _ in
                Character(UnicodeScalar(UInt32.random(in: 32...126))!)
            })
        }
    }

// MARK: - Property Tests

@Suite("Search Clear Restores Full List Property Tests")
struct SearchClearPropertyTests {

    @Test("Clearing search filter restores the full unfiltered entry list including images")
    func searchClearRestoresFullList() async {
        property("Applying a non-empty search and then getting all entries produces the original unfiltered list")
            <- forAllNoShrink(mixedEntriesGen, queryGen) { entries, query in
                let result = UnsafeSendableBox(value: true)
                let failureMessage = UnsafeSendableBox(value: "")
                let semaphore = DispatchSemaphore(value: 0)

                Task {
                    let store = HistoryStore(storageURL: URL(fileURLWithPath: "/dev/null"))

                    // Add all entries to the store
                    for entry in entries {
                        await store.addEntry(entry)
                    }

                    // Get the full unfiltered list before searching
                    let originalList = await store.getAllEntries()

                    // Apply a non-empty search filter
                    let _ = await store.search(query: query)

                    // Clear the search by getting the full list again (simulates UI clearing search)
                    let restoredList = await store.getAllEntries()

                    // Verify the restored list matches the original exactly
                    if restoredList.count != originalList.count {
                        result.value = false
                        failureMessage.value = "After search clear, entry count changed: expected \(originalList.count), got \(restoredList.count)"
                        semaphore.signal()
                        return
                    }

                    // Verify same entries in same order
                    for i in 0..<originalList.count {
                        if restoredList[i].id != originalList[i].id {
                            result.value = false
                            failureMessage.value = "Entry at index \(i) differs: expected id \(originalList[i].id), got \(restoredList[i].id)"
                            break
                        }
                        if restoredList[i].content != originalList[i].content {
                            result.value = false
                            failureMessage.value = "Entry content at index \(i) differs after search clear"
                            break
                        }
                        if restoredList[i].contentType != originalList[i].contentType {
                            result.value = false
                            failureMessage.value = "Entry contentType at index \(i) differs: expected \(originalList[i].contentType), got \(restoredList[i].contentType)"
                            break
                        }
                    }

                    // Verify image entries are included in the restored list
                    let originalImageCount = originalList.filter { $0.contentType == .image }.count
                    let restoredImageCount = restoredList.filter { $0.contentType == .image }.count
                    if result.value && originalImageCount != restoredImageCount {
                        result.value = false
                        failureMessage.value = "Image entry count changed after search clear: expected \(originalImageCount), got \(restoredImageCount)"
                    }

                    semaphore.signal()
                }

                semaphore.wait()
                if result.value {
                    return true <?> "Full list restored after clearing search"
                } else {
                    return false <?> failureMessage.value
                }
            }
    }
}

// MARK: - Helper

/// A simple wrapper to allow mutation of a value across Task boundaries in tests.
/// Used only in test code where we need to pass results back from async contexts
/// to the synchronous SwiftCheck property evaluation.
private final class UnsafeSendableBox<T>: @unchecked Sendable {
    var value: T
    init(value: T) { self.value = value }
}
