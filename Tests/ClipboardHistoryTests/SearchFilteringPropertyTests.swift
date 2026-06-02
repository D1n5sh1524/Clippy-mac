import Testing
import Foundation
import SwiftCheck
@testable import ClipboardHistory

// Feature: mac-clipboard-history, Property 13: Search filtering correctness

/// **Validates: Requirements 7.3, 7.4**
///
/// Property: For any set of ClipboardEntries and any non-empty query string, the search function
/// SHALL return only text entries whose content contains the query as a case-insensitive substring,
/// and SHALL return zero image entries regardless of the query.

// MARK: - Generators

/// Generator for a random non-empty text string (1 to 100 printable ASCII characters).
private let textContentGen: Gen<String> = Gen<Int>.fromElements(in: 1...100)
    .flatMap { length in
        Gen<String>.compose { composer in
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
/// Uses a shorter length range to increase the chance of substring matches.
private let queryGen: Gen<String> = Gen<Int>.fromElements(in: 1...10)
    .flatMap { length in
        Gen<String>.compose { composer in
            String((0..<length).map { _ in
                Character(UnicodeScalar(UInt32.random(in: 32...126))!)
            })
        }
    }

// MARK: - Property Tests

@Suite("Search Filtering Correctness Property Tests")
struct SearchFilteringPropertyTests {

    @Test("Search returns only text entries containing the query (case-insensitive)")
    func searchReturnsOnlyMatchingTextEntries() async {
        property("Search results contain only text entries whose content matches the query case-insensitively")
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

                    // Perform the search
                    let searchResults = await store.search(query: query)

                    // Verify: every result must be a text entry containing the query
                    for resultEntry in searchResults {
                        switch resultEntry.content {
                        case .text(let text):
                            if !text.localizedCaseInsensitiveContains(query) {
                                result.value = false
                                failureMessage.value = "Search returned text entry that does NOT contain query '\(query)': '\(text.prefix(50))'"
                                break
                            }
                        case .image:
                            result.value = false
                            failureMessage.value = "Search returned an image entry for query '\(query)'"
                            break
                        }
                    }

                    semaphore.signal()
                }

                semaphore.wait()
                if result.value {
                    return true <?> "All search results are matching text entries"
                } else {
                    return false <?> failureMessage.value
                }
            }
    }

    @Test("Search never returns image entries regardless of query")
    func searchNeverReturnsImageEntries() async {
        property("Search results contain zero image entries for any non-empty query")
            <- forAllNoShrink(mixedEntriesGen, queryGen) { entries, query in
                let result = UnsafeSendableBox(value: true)
                let failureMessage = UnsafeSendableBox(value: "")
                let semaphore = DispatchSemaphore(value: 0)

                Task {
                    let store = HistoryStore(storageURL: URL(fileURLWithPath: "/dev/null"))

                    for entry in entries {
                        await store.addEntry(entry)
                    }

                    let searchResults = await store.search(query: query)

                    // Verify: no image entries in results
                    let imageResults = searchResults.filter { $0.contentType == .image }
                    if !imageResults.isEmpty {
                        result.value = false
                        failureMessage.value = "Search returned \(imageResults.count) image entries for query '\(query)'"
                    }

                    semaphore.signal()
                }

                semaphore.wait()
                if result.value {
                    return true <?> "Zero image entries in search results"
                } else {
                    return false <?> failureMessage.value
                }
            }
    }

    @Test("Search includes all matching text entries (no false negatives)")
    func searchIncludesAllMatchingTextEntries() async {
        property("All text entries containing the query are present in the search results (no false negatives)")
            <- forAllNoShrink(mixedEntriesGen, queryGen) { entries, query in
                let result = UnsafeSendableBox(value: true)
                let failureMessage = UnsafeSendableBox(value: "")
                let semaphore = DispatchSemaphore(value: 0)

                Task {
                    let store = HistoryStore(storageURL: URL(fileURLWithPath: "/dev/null"))

                    for entry in entries {
                        await store.addEntry(entry)
                    }

                    let searchResults = await store.search(query: query)
                    let allEntries = await store.getAllEntries()

                    // Compute expected matches: text entries containing the query
                    let expectedMatches = allEntries.filter { entry in
                        switch entry.content {
                        case .text(let text):
                            return text.localizedCaseInsensitiveContains(query)
                        case .image:
                            return false
                        }
                    }

                    // Verify: every expected match is in the results
                    let resultIds = Set(searchResults.map { $0.id })
                    for expected in expectedMatches {
                        if !resultIds.contains(expected.id) {
                            result.value = false
                            failureMessage.value = "Matching text entry with id \(expected.id) not found in search results for query '\(query)'"
                            break
                        }
                    }

                    // Also verify result count matches expected count
                    if result.value && searchResults.count != expectedMatches.count {
                        result.value = false
                        failureMessage.value = "Expected \(expectedMatches.count) results but got \(searchResults.count) for query '\(query)'"
                    }

                    semaphore.signal()
                }

                semaphore.wait()
                if result.value {
                    return true <?> "All matching text entries included in results"
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
