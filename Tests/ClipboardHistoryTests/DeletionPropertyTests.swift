import Testing
import Foundation
import SwiftCheck
@testable import ClipboardHistory

// Feature: mac-clipboard-history, Property 6: Deletion removes exactly one entry

/// **Validates: Requirements 2.4**
///
/// Property: For any HistoryStore containing N entries and any valid entry ID present in the
/// store, deleting that entry SHALL result in a store containing exactly N-1 entries, with the
/// deleted entry absent and all other entries unchanged in their relative order.

// MARK: - Generators

/// Generator for a lightweight ClipboardEntry using short text content.
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

/// Generator for an array of entries with count between 1 and 50.
private func entrySequence(minCount: Int, maxCount: Int) -> Gen<[ClipboardEntry]> {
    Gen<Int>.fromElements(in: minCount...maxCount).flatMap { count in
        Gen<[ClipboardEntry]>.compose { composer in
            (0..<count).map { _ in
                composer.generate(using: entryGen)
            }
        }
    }
}

// MARK: - Property Tests

@Suite("Deletion Removes Exactly One Entry Property Tests")
struct DeletionPropertyTests {

    @Test("Deleting an entry results in exactly N-1 entries")
    func deletionDecreasesCountByOne() async {
        let storeEntriesGen = entrySequence(minCount: 1, maxCount: 50)

        property("Deleting any entry from a store of N entries results in N-1 entries")
            <- forAllNoShrink(storeEntriesGen) { entries in
                let result = UnsafeSendableBox(value: true)
                let failureMessage = UnsafeSendableBox(value: "")
                let semaphore = DispatchSemaphore(value: 0)

                Task {
                    let store = HistoryStore(storageURL: URL(fileURLWithPath: "/dev/null"))
                    for entry in entries {
                        await store.addEntry(entry)
                    }

                    let beforeEntries = await store.getAllEntries()
                    let n = beforeEntries.count

                    // Pick a random entry to delete
                    let randomIndex = Int.random(in: 0..<n)
                    let entryToDelete = beforeEntries[randomIndex]

                    await store.deleteEntry(id: entryToDelete.id)

                    let afterEntries = await store.getAllEntries()

                    if afterEntries.count != n - 1 {
                        result.value = false
                        failureMessage.value = "Expected \(n - 1) entries after deletion, got \(afterEntries.count)"
                    }

                    semaphore.signal()
                }

                semaphore.wait()
                if result.value {
                    return true <?> "Deletion correctly decreases count by one"
                } else {
                    return false <?> failureMessage.value
                }
            }
    }

    @Test("Deleted entry is absent from the store after deletion")
    func deletedEntryIsAbsent() async {
        let storeEntriesGen = entrySequence(minCount: 1, maxCount: 50)

        property("After deleting an entry, it is no longer present in the store")
            <- forAllNoShrink(storeEntriesGen) { entries in
                let result = UnsafeSendableBox(value: true)
                let failureMessage = UnsafeSendableBox(value: "")
                let semaphore = DispatchSemaphore(value: 0)

                Task {
                    let store = HistoryStore(storageURL: URL(fileURLWithPath: "/dev/null"))
                    for entry in entries {
                        await store.addEntry(entry)
                    }

                    let beforeEntries = await store.getAllEntries()
                    let n = beforeEntries.count

                    // Pick a random entry to delete
                    let randomIndex = Int.random(in: 0..<n)
                    let entryToDelete = beforeEntries[randomIndex]

                    await store.deleteEntry(id: entryToDelete.id)

                    let afterEntries = await store.getAllEntries()

                    let stillPresent = afterEntries.contains { $0.id == entryToDelete.id }
                    if stillPresent {
                        result.value = false
                        failureMessage.value = "Entry with id \(entryToDelete.id) should be absent after deletion"
                    }

                    semaphore.signal()
                }

                semaphore.wait()
                if result.value {
                    return true <?> "Deleted entry is absent from the store"
                } else {
                    return false <?> failureMessage.value
                }
            }
    }

    @Test("All other entries maintain their relative order after deletion")
    func otherEntriesPreserveOrder() async {
        let storeEntriesGen = entrySequence(minCount: 2, maxCount: 50)

        property("After deletion, all remaining entries maintain their previous relative order")
            <- forAllNoShrink(storeEntriesGen) { entries in
                let result = UnsafeSendableBox(value: true)
                let failureMessage = UnsafeSendableBox(value: "")
                let semaphore = DispatchSemaphore(value: 0)

                Task {
                    let store = HistoryStore(storageURL: URL(fileURLWithPath: "/dev/null"))
                    for entry in entries {
                        await store.addEntry(entry)
                    }

                    let beforeEntries = await store.getAllEntries()
                    let n = beforeEntries.count

                    // Pick a random entry to delete
                    let randomIndex = Int.random(in: 0..<n)
                    let entryToDelete = beforeEntries[randomIndex]

                    await store.deleteEntry(id: entryToDelete.id)

                    let afterEntries = await store.getAllEntries()

                    // Build expected list: beforeEntries with the deleted entry removed
                    let expectedEntries = beforeEntries.filter { $0.id != entryToDelete.id }

                    // Verify count matches
                    if afterEntries.count != expectedEntries.count {
                        result.value = false
                        failureMessage.value = "Count mismatch: expected \(expectedEntries.count), got \(afterEntries.count)"
                        semaphore.signal()
                        return
                    }

                    // Verify order preservation by comparing IDs in sequence
                    for i in 0..<expectedEntries.count {
                        if afterEntries[i].id != expectedEntries[i].id {
                            result.value = false
                            failureMessage.value = "Order mismatch at index \(i): expected id \(expectedEntries[i].id), got \(afterEntries[i].id)"
                            break
                        }
                    }

                    semaphore.signal()
                }

                semaphore.wait()
                if result.value {
                    return true <?> "Remaining entries preserve their relative order"
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
