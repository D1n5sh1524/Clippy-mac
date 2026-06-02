import Testing
import Foundation
import SwiftCheck
@testable import ClipboardHistory

// Feature: mac-clipboard-history, Property 15: Arrow key navigation respects bounds

/// **Validates: Requirements 5.4**
///
/// Property: For any list of N entries (N ≥ 1) and any current highlight index, pressing Down
/// SHALL move the highlight to index+1 unless already at N-1, and pressing Up SHALL move to
/// index-1 unless already at 0. The highlight SHALL never go below 0 or above N-1.

// MARK: - Navigation Model

/// A pure-logic model of the PopupView's arrow key navigation behavior.
/// This replicates the exact logic from PopupView.moveHighlight(direction:)
/// to enable property-based testing without SwiftUI dependencies.
private struct NavigationModel {
    let listSize: Int
    var highlightedIndex: Int?

    enum Direction {
        case up, down
    }

    /// Moves the highlight in the given direction, respecting list bounds.
    /// Mirrors PopupView.moveHighlight(direction:) exactly.
    mutating func moveHighlight(direction: Direction) {
        guard listSize > 0 else { return }

        switch direction {
        case .down:
            if let current = highlightedIndex {
                if current < listSize - 1 {
                    highlightedIndex = current + 1
                }
            } else {
                highlightedIndex = 0
            }
        case .up:
            if let current = highlightedIndex {
                if current > 0 {
                    highlightedIndex = current - 1
                }
            }
        }
    }
}

// MARK: - Generators

/// Generator for list sizes N where N >= 1, with emphasis on interesting ranges.
private let listSizeGen: Gen<Int> = Gen<Int>.frequency([
    // 20% tiny lists (1-3) - boundary cases
    (2, Gen<Int>.fromElements(in: 1...3)),
    // 30% small lists (4-20) - typical usage
    (3, Gen<Int>.fromElements(in: 4...20)),
    // 30% medium lists (21-50) - full capacity
    (3, Gen<Int>.fromElements(in: 21...50)),
    // 20% edge cases at exact capacity
    (2, Gen.pure(50))
])

/// Combined generator: (listSize, startIndex, sequence of directions).
private let navigationScenarioGen: Gen<(Int, Int, [Bool])> = Gen<(Int, Int, [Bool])>.compose { composer in
    let size = composer.generate(using: listSizeGen)
    let startIndex = composer.generate(using: Gen<Int>.fromElements(in: 0...(size - 1)))
    let seqLength = composer.generate(using: Gen<Int>.fromElements(in: 1...100))
    let directions = (0..<seqLength).map { _ -> Bool in
        let val = composer.generate(using: Gen<Int>.fromElements(in: 0...1))
        return val == 1  // true = down, false = up
    }
    return (size, startIndex, directions)
}

// MARK: - Property Tests

@Suite("Arrow Key Navigation Bounds Property Tests")
struct ArrowKeyNavigationPropertyTests {

    // MARK: - Property 15a: Down moves to index+1 when not at end

    @Test("Down arrow moves highlight to index+1 when current index < N-1")
    func downMovesToNextWhenNotAtEnd() {
        property("Pressing Down at index < N-1 moves to index+1")
            <- forAll(listSizeGen.suchThat { $0 >= 2 }) { size in
                // Generate an index that is NOT at the end (0..<size-1)
                let indexGen = Gen<Int>.fromElements(in: 0...(size - 2))

                return forAll(indexGen) { index in
                    var model = NavigationModel(listSize: size, highlightedIndex: index)
                    model.moveHighlight(direction: .down)

                    let movedCorrectly = model.highlightedIndex == index + 1
                    return movedCorrectly
                        <?> "Down at index \(index) in list of \(size) should move to \(index + 1), got \(String(describing: model.highlightedIndex))"
                }
            }
    }

    // MARK: - Property 15b: Down stays at N-1 when already at end

    @Test("Down arrow stays at N-1 when already at the last position")
    func downStaysAtEndWhenAtLastPosition() {
        property("Pressing Down at index N-1 stays at N-1 (no wrapping)")
            <- forAll(listSizeGen) { size in
                let lastIndex = size - 1
                var model = NavigationModel(listSize: size, highlightedIndex: lastIndex)
                model.moveHighlight(direction: .down)

                let staysAtEnd = model.highlightedIndex == lastIndex
                return staysAtEnd
                    <?> "Down at last index \(lastIndex) in list of \(size) should stay at \(lastIndex), got \(String(describing: model.highlightedIndex))"
            }
    }

    // MARK: - Property 15c: Up moves to index-1 when not at start

    @Test("Up arrow moves highlight to index-1 when current index > 0")
    func upMovesToPreviousWhenNotAtStart() {
        property("Pressing Up at index > 0 moves to index-1")
            <- forAll(listSizeGen.suchThat { $0 >= 2 }) { size in
                // Generate an index that is NOT at the start (1..<size)
                let indexGen = Gen<Int>.fromElements(in: 1...(size - 1))

                return forAll(indexGen) { index in
                    var model = NavigationModel(listSize: size, highlightedIndex: index)
                    model.moveHighlight(direction: .up)

                    let movedCorrectly = model.highlightedIndex == index - 1
                    return movedCorrectly
                        <?> "Up at index \(index) in list of \(size) should move to \(index - 1), got \(String(describing: model.highlightedIndex))"
                }
            }
    }

    // MARK: - Property 15d: Up stays at 0 when already at start

    @Test("Up arrow stays at 0 when already at the first position")
    func upStaysAtStartWhenAtFirstPosition() {
        property("Pressing Up at index 0 stays at 0 (no wrapping)")
            <- forAll(listSizeGen) { size in
                var model = NavigationModel(listSize: size, highlightedIndex: 0)
                model.moveHighlight(direction: .up)

                let staysAtStart = model.highlightedIndex == 0
                return staysAtStart
                    <?> "Up at index 0 in list of \(size) should stay at 0, got \(String(describing: model.highlightedIndex))"
            }
    }

    // MARK: - Property 15e: Highlight never goes below 0 or above N-1

    @Test("Highlight never goes below 0 or above N-1 after any sequence of arrow presses")
    func highlightNeverExceedsBoundsAfterAnySequence() {
        property("After any sequence of Up/Down presses, highlight stays within [0, N-1]")
            <- forAll(navigationScenarioGen) { (size, startIndex, directions) in
                var model = NavigationModel(listSize: size, highlightedIndex: startIndex)

                for isDown in directions {
                    model.moveHighlight(direction: isDown ? .down : .up)

                    // Check bounds after every single key press
                    guard let current = model.highlightedIndex else {
                        return false <?> "Highlight became nil during navigation in list of \(size)"
                    }
                    if current < 0 {
                        return false <?> "Highlight went below 0: \(current) in list of \(size)"
                    }
                    if current > size - 1 {
                        return false <?> "Highlight went above N-1 (\(size - 1)): \(current) in list of \(size)"
                    }
                }

                return true <?> "Bounds maintained for list of \(size) after \(directions.count) key presses"
            }
    }

    // MARK: - Property 15f: Down from nil initializes to 0

    @Test("Down arrow from nil highlight initializes to index 0")
    func downFromNilInitializesToZero() {
        property("Pressing Down with no current highlight sets highlight to 0")
            <- forAll(listSizeGen) { size in
                var model = NavigationModel(listSize: size, highlightedIndex: nil)
                model.moveHighlight(direction: .down)

                let initializesToZero = model.highlightedIndex == 0
                return initializesToZero
                    <?> "Down from nil in list of \(size) should set highlight to 0, got \(String(describing: model.highlightedIndex))"
            }
    }

    // MARK: - Property 15g: Up from nil leaves highlight as nil

    @Test("Up arrow from nil highlight leaves highlight unchanged (nil)")
    func upFromNilLeavesNil() {
        property("Pressing Up with no current highlight leaves highlight as nil")
            <- forAll(listSizeGen) { size in
                var model = NavigationModel(listSize: size, highlightedIndex: nil)
                model.moveHighlight(direction: .up)

                let remainsNil = model.highlightedIndex == nil
                return remainsNil
                    <?> "Up from nil in list of \(size) should leave highlight nil, got \(String(describing: model.highlightedIndex))"
            }
    }

    // MARK: - Property 15h: Consecutive downs from 0 reach exactly N-1 and stop

    @Test("Pressing Down N-1 times from index 0 reaches index N-1 and further presses stay")
    func consecutiveDownsReachEndAndStop() {
        property("N-1 consecutive Down presses from index 0 reach N-1, then stay")
            <- forAll(listSizeGen) { size in
                var model = NavigationModel(listSize: size, highlightedIndex: 0)

                // Press Down (size - 1) times to reach the end
                for _ in 0..<(size - 1) {
                    model.moveHighlight(direction: .down)
                }

                let reachedEnd = model.highlightedIndex == size - 1
                guard reachedEnd else {
                    return false <?> "After \(size - 1) Down presses from 0, expected index \(size - 1), got \(String(describing: model.highlightedIndex))"
                }

                // Press Down 5 more times — should stay at N-1
                for _ in 0..<5 {
                    model.moveHighlight(direction: .down)
                }

                let staysAtEnd = model.highlightedIndex == size - 1
                return staysAtEnd
                    <?> "After reaching end and pressing Down 5 more times, should stay at \(size - 1), got \(String(describing: model.highlightedIndex))"
            }
    }

    // MARK: - Property 15i: Consecutive ups from N-1 reach exactly 0 and stop

    @Test("Pressing Up N-1 times from index N-1 reaches index 0 and further presses stay")
    func consecutiveUpsReachStartAndStop() {
        property("N-1 consecutive Up presses from index N-1 reach 0, then stay")
            <- forAll(listSizeGen) { size in
                let lastIndex = size - 1
                var model = NavigationModel(listSize: size, highlightedIndex: lastIndex)

                // Press Up (size - 1) times to reach the start
                for _ in 0..<(size - 1) {
                    model.moveHighlight(direction: .up)
                }

                let reachedStart = model.highlightedIndex == 0
                guard reachedStart else {
                    return false <?> "After \(size - 1) Up presses from \(lastIndex), expected index 0, got \(String(describing: model.highlightedIndex))"
                }

                // Press Up 5 more times — should stay at 0
                for _ in 0..<5 {
                    model.moveHighlight(direction: .up)
                }

                let staysAtStart = model.highlightedIndex == 0
                return staysAtStart
                    <?> "After reaching start and pressing Up 5 more times, should stay at 0, got \(String(describing: model.highlightedIndex))"
            }
    }
}
