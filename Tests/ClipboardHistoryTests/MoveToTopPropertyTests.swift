import Testing
import Foundation
import SwiftCheck
@testable import ClipboardHistory

// Feature: mac-clipboard-history, Property 7: Move-to-top preserves relative order

/// **Validates: Requirements 5.3**
///
/// Property: For any HistoryStore and any entry within it, moving that entry to the top
/// SHALL make it the first entry, and all other entries SHALL maintain their previous
/// relative order.

// MARK: - Generators

/// Generator for a lightweight ClipboardEntry using short text content.
private let entryGen: Gen<ClipboardEntry> = Gen<ClipboardEntry>.compose { composer in
    let id = UUID()
    let length = composer.generate(using: Gen<Int>.fromElements(in: 1...80))
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

/// Generator for a list of entries with count between 2 and 50.
private let storeEntriesGen: Gen<[ClipboardEntry]> = Gen<Int>.fromElements(in: 2...50)
    .flatMap { count in
        sequenceGen(count: count, of: entryGen)
    }

/// Helper to generate an array of a given count from a generator.
private func sequenceGen(count: Int, of gen: Gen<ClipboardEntry>) -> Gen<[ClipboardEntry]> {
    Gen<[ClipboardEntry]>.compose { composer in
        (0..<count).map { _ in
            composer.generate(using: gen)
        }
    }
}

// MARK: - Property Tests

@Suite("Move-to-Top Preserves Relative Order Property Tests")
struct MoveToTopPropertyTests {

    @Test("Moving an entry to top makes it the first entry")
    func movedEntryIsAtIndexZero() async {
        property("After moveToTop, the moved entry is at index 0")
            <- forAllNoShrink(storeEntriesGen) { entries in
                // Pick a random index to move to top
                let indexToMove = Int.random(in: 0..<entries.count)
                let entryToMove = entries[indexToMove]

                let result = UnsafeSendableBox(value: true)
                let failureMessage = UnsafeSendableBox(value: "")
                let semaphore = DispatchSemaphore(value: 0)

                Task {
                    let store = HistoryStore(storageURL: URL(fileURLWithPath: "/dev/null"))

                    // Add all entries to the store
                    for entry in entries {
                        await store.addEntry(entry)
                    }

                    // Move the selected entry to top
                    await store.moveToTop(id: entryToMove.id)

                    let allEntries = await store.getAllEntries()

                    // Verify the moved entry is at index 0
                    if allEntries.isEmpty {
                        result.value = false
                        failureMessage.value = "Store is empty after adding entries"
                    } else if allEntries[0].id != entryToMove.id {
                        result.value = false
                        failureMessage.value = "Moved entry (id: \(entryToMove.id)) is not at index 0; found \(allEntries[0].id) instead"
                    }

                    semaphore.signal()
                }

                semaphore.wait()
                if result.value {
                    return true <?> "Moved entry is at index 0"
                } else {
                    return false <?> failureMessage.value
                }
            }
    }

    @Test("Other entries maintain their previous relative order after moveToTop")
    func otherEntriesMaintainRelativeOrder() async {
        property("After moveToTop, all other entries maintain their previous relative order")
            <- forAllNoShrink(storeEntriesGen) { entries in
                // Pick a random index to move to top
                let indexToMove = Int.random(in: 0..<entries.count)
                let entryToMove = entries[indexToMove]

                let result = UnsafeSendableBox(value: true)
                let failureMessage = UnsafeSendableBox(value: "")
                let semaphore = DispatchSemaphore(value: 0)

                Task {
                    let store = HistoryStore(storageURL: URL(fileURLWithPath: "/dev/null"))

                    // Add all entries to the store
                    for entry in entries {
                        await store.addEntry(entry)
                    }

                    // Capture the order before moveToTop
                    let entriesBefore = await store.getAllEntries()

                    // Move the selected entry to top
                    await store.moveToTop(id: entryToMove.id)

                    let entriesAfter = await store.getAllEntries()

                    // The other entries (excluding the moved one) should maintain
                    // their previous relative order
                    let othersBefore = entriesBefore.filter { $0.id != entryToMove.id }
                    let othersAfter = entriesAfter.filter { $0.id != entryToMove.id }

                    if othersBefore.count != othersAfter.count {
                        result.value = false
                        failureMessage.value = "Other entries count changed: before=\(othersBefore.count), after=\(othersAfter.count)"
                    } else {
                        for i in 0..<othersBefore.count {
                            if othersBefore[i].id != othersAfter[i].id {
                                result.value = false
                                failureMessage.value = "Relative order violated at position \(i): expected \(othersBefore[i].id), got \(othersAfter[i].id)"
                                break
                            }
                        }
                    }

                    semaphore.signal()
                }

                semaphore.wait()
                if result.value {
                    return true <?> "Other entries maintain relative order"
                } else {
                    return false <?> failureMessage.value
                }
            }
    }

    @Test("Move-to-top preserves total entry count")
    func moveToTopPreservesCount() async {
        property("After moveToTop, the total number of entries is unchanged")
            <- forAllNoShrink(storeEntriesGen) { entries in
                let indexToMove = Int.random(in: 0..<entries.count)
                let entryToMove = entries[indexToMove]

                let result = UnsafeSendableBox(value: true)
                let failureMessage = UnsafeSendableBox(value: "")
                let semaphore = DispatchSemaphore(value: 0)

                Task {
                    let store = HistoryStore(storageURL: URL(fileURLWithPath: "/dev/null"))

                    for entry in entries {
                        await store.addEntry(entry)
                    }

                    let countBefore = await store.getAllEntries().count

                    await store.moveToTop(id: entryToMove.id)

                    let countAfter = await store.getAllEntries().count

                    if countBefore != countAfter {
                        result.value = false
                        failureMessage.value = "Entry count changed: before=\(countBefore), after=\(countAfter)"
                    }

                    semaphore.signal()
                }

                semaphore.wait()
                if result.value {
                    return true <?> "Entry count is preserved after moveToTop"
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
