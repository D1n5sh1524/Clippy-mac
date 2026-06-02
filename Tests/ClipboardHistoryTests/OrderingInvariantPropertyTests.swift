import Testing
import Foundation
import SwiftCheck
@testable import ClipboardHistory

// Feature: mac-clipboard-history, Property 5: Ordering invariant

/// **Validates: Requirements 2.6, 1.3**
///
/// Property: For any sequence of operations (additions, deletions, move-to-top) applied to
/// the HistoryStore, the resulting entry list SHALL always be ordered such that for any two
/// adjacent entries, the entry at the lower index has a more recent effective timestamp than
/// the entry at the higher index.

// MARK: - Generators

/// Generator for a lightweight ClipboardEntry with unique ID and text content.
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

/// Generator for a random operation type tag (0 = add, 1 = delete, 2 = moveToTop).
/// Weighted towards additions so the store has entries to operate on.
private let operationTypeGen: Gen<Int> = Gen<Int>.frequency([
    (5, Gen.pure(0)),  // add
    (2, Gen.pure(1)),  // delete
    (3, Gen.pure(2))   // moveToTop
])

/// Generator for a sequence of operation type tags with length between 10 and 60.
private let operationSequenceLengthGen: Gen<Int> = Gen<Int>.fromElements(in: 10...60)

/// Generator for an operation sequence: produces pairs of (operationType, entry).
/// The entry is used for additions; for delete/moveToTop, the index is computed at runtime
/// based on the current store state.
private struct OperationInput {
    let operationType: Int
    let entry: ClipboardEntry
    let indexSelector: Int  // Used to pick an index from current entries (mod count)
}

private let operationInputGen: Gen<OperationInput> = Gen<OperationInput>.compose { composer in
    let opType = composer.generate(using: operationTypeGen)
    let entry = composer.generate(using: entryGen)
    let indexSelector = composer.generate(using: Gen<Int>.fromElements(in: 0...999))
    return OperationInput(operationType: opType, entry: entry, indexSelector: indexSelector)
}

/// Generator for a sequence of operation inputs.
private func operationSequenceGen(count: Int) -> Gen<[OperationInput]> {
    Gen<[OperationInput]>.compose { composer in
        (0..<count).map { _ in
            composer.generate(using: operationInputGen)
        }
    }
}

/// Combined generator: produces a random-length sequence of operation inputs.
private let fullOperationSequenceGen: Gen<[OperationInput]> = operationSequenceLengthGen
    .flatMap { count in
        operationSequenceGen(count: count)
    }

// MARK: - Property Tests

@Suite("Ordering Invariant Property Tests")
struct OrderingInvariantPropertyTests {

    /// Verifies that entries are always ordered most recent first after each operation.
    /// "Most recent" means: the entry most recently added or moved-to-top appears at index 0,
    /// and each subsequent entry was added/moved before the one preceding it.
    ///
    /// We track insertion/move order via a logical clock (incrementing counter). After each
    /// operation, we verify that the store's entries match our expected ordering model.
    @Test("Entries are always ordered most recent first after any operation sequence")
    func entriesAlwaysOrderedMostRecentFirst() async {
        property("After any sequence of add/delete/moveToTop, entries are ordered most recent first")
            <- forAllNoShrink(fullOperationSequenceGen) { operations in
                let result = UnsafeSendableBox(value: true)
                let failureMessage = UnsafeSendableBox(value: "")
                let semaphore = DispatchSemaphore(value: 0)

                Task {
                    let store = HistoryStore(storageURL: URL(fileURLWithPath: "/dev/null"))

                    // Logical clock to track effective ordering
                    var clock: Int = 0
                    // Maps entry ID -> logical timestamp (higher = more recent)
                    var effectiveOrder: [UUID: Int] = [:]
                    // Track which IDs are currently in the store
                    var currentIds: [UUID] = []

                    for (opIndex, op) in operations.enumerated() {
                        switch op.operationType {
                        case 0:
                            // Add operation
                            clock += 1
                            await store.addEntry(op.entry)
                            effectiveOrder[op.entry.id] = clock

                            // Maintain our model of current IDs (most recent first)
                            currentIds.insert(op.entry.id, at: 0)
                            // If over capacity, remove the last (oldest by insertion order)
                            if currentIds.count > 50 {
                                let evictedId = currentIds.removeLast()
                                effectiveOrder.removeValue(forKey: evictedId)
                            }

                        case 1:
                            // Delete operation — only if store is non-empty
                            guard !currentIds.isEmpty else { continue }
                            let index = op.indexSelector % currentIds.count
                            let targetId = currentIds[index]
                            await store.deleteEntry(id: targetId)
                            currentIds.remove(at: index)
                            effectiveOrder.removeValue(forKey: targetId)

                        case 2:
                            // MoveToTop operation — only if store is non-empty
                            guard !currentIds.isEmpty else { continue }
                            let index = op.indexSelector % currentIds.count
                            let targetId = currentIds[index]
                            clock += 1
                            await store.moveToTop(id: targetId)
                            effectiveOrder[targetId] = clock

                            // Update our model: remove from current position, insert at front
                            currentIds.remove(at: index)
                            currentIds.insert(targetId, at: 0)

                        default:
                            break
                        }

                        // After each operation, verify ordering invariant
                        let entries = await store.getAllEntries()

                        // Verify count matches our model
                        if entries.count != currentIds.count {
                            result.value = false
                            failureMessage.value = "Count mismatch at operation \(opIndex): store has \(entries.count), model has \(currentIds.count)"
                            break
                        }

                        // Verify ordering: each entry at index i should have a higher
                        // effective order than the entry at index i+1
                        var orderingValid = true
                        for i in 0..<(entries.count - 1) {
                            let currentOrder = effectiveOrder[entries[i].id] ?? 0
                            let nextOrder = effectiveOrder[entries[i + 1].id] ?? 0
                            if currentOrder <= nextOrder {
                                orderingValid = false
                                result.value = false
                                failureMessage.value = "Ordering violation at operation \(opIndex), indices \(i)/\(i+1): entry[\(i)] order=\(currentOrder) <= entry[\(i+1)] order=\(nextOrder)"
                                break
                            }
                        }

                        if !orderingValid {
                            break
                        }

                        // Verify the entry IDs match our model order
                        let storeIds = entries.map { $0.id }
                        if storeIds != currentIds {
                            result.value = false
                            failureMessage.value = "ID order mismatch at operation \(opIndex): store order differs from model"
                            break
                        }
                    }

                    semaphore.signal()
                }

                semaphore.wait()
                if result.value {
                    return true <?> "Ordering invariant holds for all operations"
                } else {
                    return false <?> failureMessage.value
                }
            }
    }

    /// Verifies that additions always place the new entry at index 0.
    @Test("New entries are always placed at index 0 (most recent position)")
    func additionsAlwaysPlaceAtFront() async {
        let addSequenceGen = Gen<Int>.fromElements(in: 5...40).flatMap { count in
            operationSequenceGen(count: count)
        }

        property("Every addition results in the added entry at index 0")
            <- forAllNoShrink(addSequenceGen) { operations in
                let result = UnsafeSendableBox(value: true)
                let failureMessage = UnsafeSendableBox(value: "")
                let semaphore = DispatchSemaphore(value: 0)

                Task {
                    let store = HistoryStore(storageURL: URL(fileURLWithPath: "/dev/null"))

                    for (opIndex, op) in operations.enumerated() {
                        // Only perform additions for this test
                        await store.addEntry(op.entry)
                        let entries = await store.getAllEntries()

                        guard let first = entries.first else {
                            result.value = false
                            failureMessage.value = "Store is empty after addition at operation \(opIndex)"
                            break
                        }

                        if first.id != op.entry.id {
                            result.value = false
                            failureMessage.value = "Entry at index 0 is not the most recently added at operation \(opIndex)"
                            break
                        }
                    }

                    semaphore.signal()
                }

                semaphore.wait()
                if result.value {
                    return true <?> "All additions placed at index 0"
                } else {
                    return false <?> failureMessage.value
                }
            }
    }

    /// Verifies that moveToTop places the target entry at index 0 and the remaining
    /// entries maintain strict descending effective order.
    @Test("moveToTop makes target entry most recent while preserving order of others")
    func moveToTopPreservesOrderingInvariant() async {
        // First generate some entries to populate the store, then apply moveToTop operations
        let setupCountGen = Gen<Int>.fromElements(in: 5...30)
        let moveCountGen = Gen<Int>.fromElements(in: 3...15)

        let combinedGen: Gen<([ClipboardEntry], [Int])> = Gen<([ClipboardEntry], [Int])>.compose { composer in
            let setupCount = composer.generate(using: setupCountGen)
            let moveCount = composer.generate(using: moveCountGen)
            let entries = (0..<setupCount).map { _ in
                composer.generate(using: entryGen)
            }
            let moveSelectors = (0..<moveCount).map { _ in
                composer.generate(using: Gen<Int>.fromElements(in: 0...999))
            }
            return (entries, moveSelectors)
        }

        property("After moveToTop, entries remain in strict most-recent-first order")
            <- forAllNoShrink(combinedGen) { (entries, moveSelectors) in
                let result = UnsafeSendableBox(value: true)
                let failureMessage = UnsafeSendableBox(value: "")
                let semaphore = DispatchSemaphore(value: 0)

                Task {
                    let store = HistoryStore(storageURL: URL(fileURLWithPath: "/dev/null"))

                    // Populate the store
                    var currentIds: [UUID] = []
                    var clock = 0
                    var effectiveOrder: [UUID: Int] = [:]

                    for entry in entries {
                        clock += 1
                        await store.addEntry(entry)
                        effectiveOrder[entry.id] = clock
                        currentIds.insert(entry.id, at: 0)
                        if currentIds.count > 50 {
                            let evictedId = currentIds.removeLast()
                            effectiveOrder.removeValue(forKey: evictedId)
                        }
                    }

                    // Apply moveToTop operations
                    for (moveIndex, selector) in moveSelectors.enumerated() {
                        guard !currentIds.isEmpty else { break }
                        let index = selector % currentIds.count
                        let targetId = currentIds[index]
                        clock += 1
                        await store.moveToTop(id: targetId)
                        effectiveOrder[targetId] = clock
                        currentIds.remove(at: index)
                        currentIds.insert(targetId, at: 0)

                        // Verify ordering invariant
                        let storeEntries = await store.getAllEntries()

                        for i in 0..<(storeEntries.count - 1) {
                            let currentOrder = effectiveOrder[storeEntries[i].id] ?? 0
                            let nextOrder = effectiveOrder[storeEntries[i + 1].id] ?? 0
                            if currentOrder <= nextOrder {
                                result.value = false
                                failureMessage.value = "Ordering violation after moveToTop \(moveIndex), indices \(i)/\(i+1): order \(currentOrder) <= \(nextOrder)"
                                break
                            }
                        }

                        if !result.value { break }

                        // Also verify store matches our model
                        let storeIds = storeEntries.map { $0.id }
                        if storeIds != currentIds {
                            result.value = false
                            failureMessage.value = "ID order mismatch after moveToTop \(moveIndex)"
                            break
                        }
                    }

                    semaphore.signal()
                }

                semaphore.wait()
                if result.value {
                    return true <?> "moveToTop preserves ordering invariant"
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
