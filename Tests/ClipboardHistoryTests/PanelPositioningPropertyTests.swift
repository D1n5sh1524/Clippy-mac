import Testing
import Foundation
import SwiftCheck
@testable import ClipboardHistory

// Feature: mac-clipboard-history, Property 12: Panel positioning

/// **Validates: Requirements 4.5**
///
/// Property: For any cursor position (x, y) and screen bounds rectangle, if the cursor is
/// within the screen bounds, the panel SHALL be positioned near the cursor. If the cursor
/// is outside all screen bounds, the panel SHALL be centered on the active screen.

// MARK: - Generators

/// Generator for CGFloat values in a typical screen coordinate range.
private let coordinateGen: Gen<CGFloat> = Gen<CGFloat>.compose { composer in
    let intVal = composer.generate(using: Gen<Int>.fromElements(in: -2000...5000))
    return CGFloat(intVal)
}

/// Generator for positive dimension values (typical screen/panel sizes).
private let positiveDimensionGen: Gen<CGFloat> = Gen<CGFloat>.compose { composer in
    let intVal = composer.generate(using: Gen<Int>.fromElements(in: 100...3000))
    return CGFloat(intVal)
}

/// Generator for panel size dimensions (reasonable panel sizes).
private let panelDimensionGen: Gen<CGFloat> = Gen<CGFloat>.compose { composer in
    let intVal = composer.generate(using: Gen<Int>.fromElements(in: 200...600))
    return CGFloat(intVal)
}

/// Generator for a cursor position (CGPoint).
private let cursorPositionGen: Gen<CGPoint> = Gen<CGPoint>.compose { composer in
    let x = composer.generate(using: coordinateGen)
    let y = composer.generate(using: coordinateGen)
    return CGPoint(x: x, y: y)
}

/// Generator for a screen bounds rectangle with positive dimensions.
/// Screens have a position (origin) and positive width/height.
private let screenBoundsGen: Gen<CGRect> = Gen<CGRect>.compose { composer in
    let x = composer.generate(using: Gen<CGFloat>.compose { c in
        CGFloat(c.generate(using: Gen<Int>.fromElements(in: -1000...3000)))
    })
    let y = composer.generate(using: Gen<CGFloat>.compose { c in
        CGFloat(c.generate(using: Gen<Int>.fromElements(in: -1000...3000)))
    })
    let width = composer.generate(using: positiveDimensionGen)
    let height = composer.generate(using: positiveDimensionGen)
    return CGRect(x: x, y: y, width: width, height: height)
}

/// Generator for panel size.
private let panelSizeGen: Gen<CGSize> = Gen<CGSize>.compose { composer in
    let width = composer.generate(using: panelDimensionGen)
    let height = composer.generate(using: panelDimensionGen)
    return CGSize(width: width, height: height)
}

/// Generator for a list of 1-4 screen bounds (multi-monitor setups).
private let screenBoundsListGen: Gen<[CGRect]> = Gen<[CGRect]>.compose { composer in
    let count = composer.generate(using: Gen<Int>.fromElements(in: 1...4))
    var screens: [CGRect] = []
    for _ in 0..<count {
        screens.append(composer.generate(using: screenBoundsGen))
    }
    return screens
}

/// Generator for a cursor position guaranteed to be INSIDE a given screen bounds.
private func cursorInsideScreenGen(screen: CGRect) -> Gen<CGPoint> {
    return Gen<CGPoint>.compose { composer in
        // Generate a point strictly inside the screen bounds
        let xOffset = composer.generate(using: Gen<CGFloat>.compose { c in
            CGFloat(c.generate(using: Gen<Int>.fromElements(in: 1...Int(max(1, screen.width - 1)))))
        })
        let yOffset = composer.generate(using: Gen<CGFloat>.compose { c in
            CGFloat(c.generate(using: Gen<Int>.fromElements(in: 1...Int(max(1, screen.height - 1)))))
        })
        return CGPoint(x: screen.origin.x + xOffset, y: screen.origin.y + yOffset)
    }
}

/// Generator for a cursor position guaranteed to be OUTSIDE all given screen bounds.
private func cursorOutsideAllScreensGen(screens: [CGRect]) -> Gen<CGPoint> {
    return Gen<CGPoint>.compose { composer in
        // Place cursor far outside any reasonable screen area
        let direction = composer.generate(using: Gen<Int>.fromElements(in: 0...3))
        let offset = composer.generate(using: Gen<CGFloat>.compose { c in
            CGFloat(c.generate(using: Gen<Int>.fromElements(in: 100...2000)))
        })

        // Find bounding box of all screens
        let minX = screens.map { $0.minX }.min() ?? 0
        let minY = screens.map { $0.minY }.min() ?? 0
        let maxX = screens.map { $0.maxX }.max() ?? 1920
        let maxY = screens.map { $0.maxY }.max() ?? 1080

        switch direction {
        case 0: return CGPoint(x: minX - offset, y: (minY + maxY) / 2)  // Far left
        case 1: return CGPoint(x: maxX + offset, y: (minY + maxY) / 2)  // Far right
        case 2: return CGPoint(x: (minX + maxX) / 2, y: minY - offset)  // Far below
        default: return CGPoint(x: (minX + maxX) / 2, y: maxY + offset) // Far above
        }
    }
}

// MARK: - Property Tests

@Suite("Panel Positioning Property Tests")
struct PanelPositioningPropertyTests {

    // MARK: - Property 12a: Cursor inside screen bounds → panel positioned near cursor

    @Test("When cursor is within screen bounds, panel is positioned near cursor")
    func cursorInsideScreenPositionsNearCursor() {
        property("Cursor within screen bounds produces nearCursor placement")
            <- forAll(screenBoundsGen, panelSizeGen) { (screen, panelSize) in
                // Generate a cursor position inside the screen
                let xOffset = CGFloat(Int.random(in: 1...Int(max(1, screen.width - 1))))
                let yOffset = CGFloat(Int.random(in: 1...Int(max(1, screen.height - 1))))
                let cursor = CGPoint(x: screen.origin.x + xOffset, y: screen.origin.y + yOffset)

                let placement = computePanelPlacement(
                    cursorPosition: cursor,
                    panelSize: panelSize,
                    screenBounds: [screen],
                    activeScreenIndex: 0
                )

                switch placement {
                case .nearCursor:
                    return true <?> "Correctly placed near cursor"
                case .centeredOnScreen:
                    return false <?> "Expected nearCursor but got centeredOnScreen for cursor (\(cursor.x), \(cursor.y)) in screen \(screen)"
                }
            }
    }

    // MARK: - Property 12b: Cursor outside all screens → panel centered on active screen

    @Test("When cursor is outside all screen bounds, panel is centered on active screen")
    func cursorOutsideScreensCentersOnActiveScreen() {
        property("Cursor outside all screens produces centeredOnScreen placement")
            <- forAll(screenBoundsListGen, panelSizeGen) { (screens, panelSize) in
                // Place cursor far outside all screens
                let minX = screens.map { $0.minX }.min()!
                let maxX = screens.map { $0.maxX }.max()!
                let maxY = screens.map { $0.maxY }.max()!

                // Cursor well outside any screen
                let cursor = CGPoint(x: maxX + 5000, y: maxY + 5000)
                let activeIndex = 0

                let placement = computePanelPlacement(
                    cursorPosition: cursor,
                    panelSize: panelSize,
                    screenBounds: screens,
                    activeScreenIndex: activeIndex
                )

                switch placement {
                case .nearCursor:
                    return false <?> "Expected centeredOnScreen but got nearCursor for cursor (\(cursor.x), \(cursor.y)) outside all screens"
                case .centeredOnScreen(let origin):
                    // Verify it is centered on the active screen
                    let activeScreen = screens[activeIndex]
                    let expectedX = activeScreen.midX - panelSize.width / 2
                    let expectedY = activeScreen.midY - panelSize.height / 2
                    let xMatch = abs(origin.x - expectedX) < 1.0
                    let yMatch = abs(origin.y - expectedY) < 1.0
                    return (xMatch && yMatch)
                        <?> "Centered position (\(origin.x), \(origin.y)) doesn't match expected (\(expectedX), \(expectedY)) for active screen \(activeScreen)"
                }
            }
    }

    // MARK: - Property 12c: Panel positioned near cursor stays within screen bounds

    @Test("Panel positioned near cursor is clamped within screen visible frame")
    func panelNearCursorStaysWithinScreen() {
        property("Panel origin near cursor keeps the panel within screen bounds")
            <- forAll(screenBoundsGen, panelSizeGen) { (screen, panelSize) in
                // Generate a cursor position inside the screen
                let xOffset = CGFloat(Int.random(in: 1...Int(max(1, screen.width - 1))))
                let yOffset = CGFloat(Int.random(in: 1...Int(max(1, screen.height - 1))))
                let cursor = CGPoint(x: screen.origin.x + xOffset, y: screen.origin.y + yOffset)

                let placement = computePanelPlacement(
                    cursorPosition: cursor,
                    panelSize: panelSize,
                    screenBounds: [screen],
                    activeScreenIndex: 0
                )

                switch placement {
                case .nearCursor(let origin):
                    // Panel must fit within the screen bounds
                    let panelRect = CGRect(origin: origin, size: panelSize)

                    // Allow 1px tolerance for floating point
                    let fitsHorizontally = panelRect.minX >= screen.minX - 1.0 &&
                                           panelRect.maxX <= screen.maxX + 1.0
                    let fitsVertically = panelRect.minY >= screen.minY - 1.0 &&
                                         panelRect.maxY <= screen.maxY + 1.0

                    return (fitsHorizontally <?> "Panel extends outside screen horizontally: panel=\(panelRect), screen=\(screen)")
                        ^&&^
                        (fitsVertically <?> "Panel extends outside screen vertically: panel=\(panelRect), screen=\(screen)")
                case .centeredOnScreen:
                    return false <?> "Expected nearCursor but got centeredOnScreen"
                }
            }
    }

    // MARK: - Property 12d: Panel positioned near cursor has proximity to cursor

    @Test("Panel positioned near cursor is within reasonable proximity of cursor position")
    func panelIsProximateToCursor() {
        property("Panel near cursor is within panelSize + offset distance of cursor")
            <- forAll(screenBoundsGen, panelSizeGen) { (screen, panelSize) in
                // Generate a cursor position inside the screen, away from edges
                let margin: CGFloat = 50
                guard screen.width > margin * 2 && screen.height > margin * 2 else {
                    return true <?> "Screen too small for meaningful proximity test"
                }

                let xOffset = CGFloat(Int.random(in: Int(margin)...Int(screen.width - margin)))
                let yOffset = CGFloat(Int.random(in: Int(margin)...Int(screen.height - margin)))
                let cursor = CGPoint(x: screen.origin.x + xOffset, y: screen.origin.y + yOffset)

                let placement = computePanelPlacement(
                    cursorPosition: cursor,
                    panelSize: panelSize,
                    screenBounds: [screen],
                    activeScreenIndex: 0
                )

                switch placement {
                case .nearCursor(let origin):
                    // The panel origin should be within (panelSize + cursorOffset) distance
                    // from the cursor in each axis. The cursorOffset is 8.
                    let maxDistanceX = panelSize.width + 8
                    let maxDistanceY = panelSize.height + 8
                    let dx = abs(origin.x - cursor.x)
                    let dy = abs(origin.y - cursor.y)

                    return (dx <= maxDistanceX <?> "Horizontal distance \(dx) exceeds max \(maxDistanceX)")
                        ^&&^
                        (dy <= maxDistanceY <?> "Vertical distance \(dy) exceeds max \(maxDistanceY)")
                case .centeredOnScreen:
                    return false <?> "Expected nearCursor but got centeredOnScreen"
                }
            }
    }

    // MARK: - Property 12e: Centered placement is exactly at screen center

    @Test("Centered panel placement computes exact center of active screen")
    func centeredPlacementIsExactCenter() {
        property("Centered placement origin equals midpoint minus half panel size")
            <- forAll(screenBoundsListGen, panelSizeGen) { (screens, panelSize) in
                // Cursor outside all screens
                let maxX = screens.map { $0.maxX }.max()! + 1000
                let maxY = screens.map { $0.maxY }.max()! + 1000
                let cursor = CGPoint(x: maxX, y: maxY)

                let activeIndex = Int.random(in: 0..<screens.count)

                let placement = computePanelPlacement(
                    cursorPosition: cursor,
                    panelSize: panelSize,
                    screenBounds: screens,
                    activeScreenIndex: activeIndex
                )

                switch placement {
                case .centeredOnScreen(let origin):
                    let activeScreen = screens[activeIndex]
                    let expectedX = activeScreen.midX - panelSize.width / 2
                    let expectedY = activeScreen.midY - panelSize.height / 2

                    let xMatch = abs(origin.x - expectedX) < 0.001
                    let yMatch = abs(origin.y - expectedY) < 0.001

                    return (xMatch <?> "X mismatch: got \(origin.x), expected \(expectedX)")
                        ^&&^
                        (yMatch <?> "Y mismatch: got \(origin.y), expected \(expectedY)")
                case .nearCursor:
                    return false <?> "Expected centeredOnScreen but got nearCursor for cursor outside all screens"
                }
            }
    }

    // MARK: - Property 12f: Multi-monitor - correct screen selection

    @Test("Cursor is assigned to the correct screen in multi-monitor setups")
    func correctScreenSelectionMultiMonitor() {
        property("screenIndexContainingCursor returns correct index for cursor within a specific screen")
            <- forAll(screenBoundsListGen) { screens in
                // Pick a random screen and place cursor inside it
                let targetIndex = Int.random(in: 0..<screens.count)
                let targetScreen = screens[targetIndex]

                let xOff = CGFloat(Int.random(in: 1...Int(max(1, targetScreen.width - 1))))
                let yOff = CGFloat(Int.random(in: 1...Int(max(1, targetScreen.height - 1))))
                let cursor = CGPoint(x: targetScreen.origin.x + xOff, y: targetScreen.origin.y + yOff)

                let foundIndex = screenIndexContainingCursor(cursorPosition: cursor, screenBounds: screens)

                // The cursor should be found in at least one screen (could be overlapping screens)
                guard let idx = foundIndex else {
                    return false <?> "Cursor (\(cursor.x), \(cursor.y)) not found in any screen, expected index \(targetIndex) in screen \(targetScreen)"
                }

                // The found screen should actually contain the cursor
                let foundScreen = screens[idx]
                return foundScreen.contains(cursor)
                    <?> "Found screen \(foundScreen) at index \(idx) doesn't contain cursor (\(cursor.x), \(cursor.y))"
            }
    }
}
