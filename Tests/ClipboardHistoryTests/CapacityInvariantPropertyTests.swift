import Testing
import Foundation
import SwiftCheck
@testable import ClipboardHistory

// Feature: mac-clipboard-history, Property 4: Capacity invariant with FIFO eviction

/// **Validates: Requirements 2.2, 2.3**
///
/// Property: For any sequence of entry additions to the HistoryStore, the store SHALL never
/// contain more than 50 entries, and when the 51st entry is added, the entry with the oldest
/// timestamp (earliest insertion) SHALL be the one removed.

// MARK: - Generators

/// Generator for a lightweight ClipboardEntry using short text content.
/// Uses small text to keep tests fast while still exercising the capacity logic.
private let entryGen: Gen<ClipboardEntry> = Gen<ClipboardEntry>.compose { composer in
    let id = UUID()
    let length = composer.generate(using: Gen<Int>.fromElements(in: 1...100))
    let text = String((0..<length).map { _ in
        Character(UnicodeScalar(UInt32.random(in: 32...126))!)
    })
    let content = ClipboardContent.text(text)
    let timeInterval = TimeInterval(composer.generate(
        using: Gen<Int>.fromElements(in: 0...2_000_000_000)
    ))
    let timestamp = Date(timeIntervalSince1970: timeInterval)
    return ClipboardEntry(
        id: id,
        content: content,
        timestamp: timestamp,
        contentType: .text
    )
}

/// Generator for a sequence of entries with count between 51 and 120.
/// This ensures we always exceed the maxEntries capacity of 50.
private let entrySequenceGen: Gen<[ClipboardEntry]> = Gen<Int>.fromElements(in: 51...120)
    .flatMap { count in
        sequence(count: count, of: entryGen)
    }

/// Helper to generate an array of a given count from a generator.
private func sequence(count: Int, of gen: Gen<ClipboardEntry>) -> Gen<[ClipboardEntry]> {
    Gen<[ClipboardEntry]>.compose { composer in
        (0..<count).map { _ in
            composer.generate(using: gen)
        }
    }
}

// MARK: - Property Tests

@Suite("Capacity Invariant with FIFO Eviction Property Tests")
struct CapacityInvariantPropertyTests {

    @Test("Store never exceeds 50 entries after any sequence of additions")
    func storeNeverExceedsMaxEntries() async {
        // Generate sequences of entries that exceed the capacity
        let sequenceGen = Gen<Int>.fromElements(in: 51...120).flatMap { count in
            sequence(count: count, of: entryGen)
        }

        property("HistoryStore count never exceeds maxEntries (50) after any additions")
            <- forAllNoShrink(sequenceGen) { entries in
                // We must run async code in a blocking manner for SwiftCheck
                let result = UnsafeSendableBox(value: true)
                let semaphore = DispatchSemaphore(value: 0)

                Task {
                    let store = HistoryStore(storageURL: URL(fileURLWithPath: "/dev/null"))
                    for entry in entries {
                        await store.addEntry(entry)
                        let allEntries = await store.getAllEntries()
                        if allEntries.count > 50 {
                            result.value = false
                            break
                        }
                    }
                    semaphore.signal()
                }

                semaphore.wait()
                return result.value <?> "Store exceeded 50 entries during sequence of \(entries.count) additions"
            }
    }

    @Test("FIFO eviction removes the oldest inserted entry when capacity is reached")
    func fifoEvictionRemovesOldestEntry() async {
        // Generate sequences that exceed capacity
        let sequenceGen = Gen<Int>.fromElements(in: 51...100).flatMap { count in
            sequence(count: count, of: entryGen)
        }

        property("When the 51st entry is added, the entry with the oldest insertion order is evicted")
            <- forAllNoShrink(sequenceGen) { entries in
                let result = UnsafeSendableBox(value: true)
                let failureMessage = UnsafeSendableBox(value: "")
                let semaphore = DispatchSemaphore(value: 0)

                Task {
                    let store = HistoryStore(storageURL: URL(fileURLWithPath: "/dev/null"))

                    // Add first 50 entries (fills to capacity)
                    for i in 0..<50 {
                        await store.addEntry(entries[i])
                    }

                    let entriesAtCapacity = await store.getAllEntries()
                    guard entriesAtCapacity.count == 50 else {
                        result.value = false
                        failureMessage.value = "Expected 50 entries after adding 50, got \(entriesAtCapacity.count)"
                        semaphore.signal()
                        return
                    }

                    // The oldest entry by insertion order is the first one added (entries[0])
                    // which is at the last position in the store (most recent first ordering)
                    let oldestEntryId = entries[0].id

                    // Add the 51st entry
                    await store.addEntry(entries[50])
                    let entriesAfterEviction = await store.getAllEntries()

                    // Verify count is still 50
                    if entriesAfterEviction.count != 50 {
                        result.value = false
                        failureMessage.value = "Expected 50 entries after adding 51st, got \(entriesAfterEviction.count)"
                        semaphore.signal()
                        return
                    }

                    // Verify the oldest entry (first added) was evicted
                    let oldestStillPresent = entriesAfterEviction.contains { $0.id == oldestEntryId }
                    if oldestStillPresent {
                        result.value = false
                        failureMessage.value = "Oldest entry (first inserted) should have been evicted but is still present"
                        semaphore.signal()
                        return
                    }

                    // Verify the 51st entry (newest) is present at index 0
                    if entriesAfterEviction[0].id != entries[50].id {
                        result.value = false
                        failureMessage.value = "Newest entry (51st) should be at index 0"
                        semaphore.signal()
                        return
                    }

                    // Continue adding remaining entries and verify FIFO eviction for each
                    for i in 51..<entries.count {
                        // Before adding: the oldest remaining entry is entries[i - 50]
                        let expectedEvictedId = entries[i - 50].id
                        await store.addEntry(entries[i])

                        let currentEntries = await store.getAllEntries()

                        if currentEntries.count > 50 {
                            result.value = false
                            failureMessage.value = "Store exceeded 50 entries at addition \(i + 1)"
                            break
                        }

                        let evictedStillPresent = currentEntries.contains { $0.id == expectedEvictedId }
                        if evictedStillPresent {
                            result.value = false
                            failureMessage.value = "Entry \(i - 50) should have been evicted when entry \(i) was added"
                            break
                        }
                    }

                    semaphore.signal()
                }

                semaphore.wait()
                if result.value {
                    return true <?> "FIFO eviction works correctly"
                } else {
                    return false <?> failureMessage.value
                }
            }
    }

    @Test("Store maintains exactly 50 entries when continuously adding beyond capacity")
    func storeCountStabilizesAtMaxEntries() async {
        let sequenceGen = Gen<Int>.fromElements(in: 60...120).flatMap { count in
            sequence(count: count, of: entryGen)
        }

        property("After reaching capacity, store count remains exactly 50 for all subsequent additions")
            <- forAllNoShrink(sequenceGen) { entries in
                let result = UnsafeSendableBox(value: true)
                let failureMessage = UnsafeSendableBox(value: "")
                let semaphore = DispatchSemaphore(value: 0)

                Task {
                    let store = HistoryStore(storageURL: URL(fileURLWithPath: "/dev/null"))

                    for (index, entry) in entries.enumerated() {
                        await store.addEntry(entry)
                        let currentEntries = await store.getAllEntries()
                        let expectedCount = min(index + 1, 50)

                        if currentEntries.count != expectedCount {
                            result.value = false
                            failureMessage.value = "After adding entry \(index + 1), expected count \(expectedCount) but got \(currentEntries.count)"
                            break
                        }
                    }

                    semaphore.signal()
                }

                semaphore.wait()
                if result.value {
                    return true <?> "Store count matches expected value at each step"
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
