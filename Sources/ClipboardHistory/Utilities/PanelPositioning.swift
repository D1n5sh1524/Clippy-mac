import Foundation

/// Represents the result of panel position computation.
enum PanelPlacement: Equatable {
    /// Panel should be positioned near the cursor, with computed origin.
    case nearCursor(origin: CGPoint)
    /// Panel should be centered on the active screen.
    case centeredOnScreen(origin: CGPoint)
}

/// Determines whether the cursor is within any of the provided screen bounds.
///
/// - Parameters:
///   - cursorPosition: The current cursor position (x, y).
///   - screenBounds: An array of screen rectangles representing visible screens.
/// - Returns: The index of the screen containing the cursor, or nil if outside all screens.
func screenIndexContainingCursor(
    cursorPosition: CGPoint,
    screenBounds: [CGRect]
) -> Int? {
    for (index, bounds) in screenBounds.enumerated() {
        if bounds.contains(cursorPosition) {
            return index
        }
    }
    return nil
}

/// Computes the panel placement given a cursor position, panel size, and screen configuration.
///
/// - Parameters:
///   - cursorPosition: The current cursor position (x, y).
///   - panelSize: The size of the panel to position.
///   - screenBounds: An array of screen rectangles representing all visible screens.
///   - activeScreenIndex: The index of the active/main screen (used for centering fallback).
/// - Returns: A `PanelPlacement` indicating where the panel should be positioned.
///
/// Behavior (Requirement 4.5):
/// - If the cursor is within the bounds of a visible screen, the panel is positioned near the cursor.
/// - If the cursor is outside all screen bounds, the panel is centered on the active screen.
func computePanelPlacement(
    cursorPosition: CGPoint,
    panelSize: CGSize,
    screenBounds: [CGRect],
    activeScreenIndex: Int
) -> PanelPlacement {
    guard !screenBounds.isEmpty else {
        // Fallback: no screens available, center at origin
        return .centeredOnScreen(origin: .zero)
    }

    let clampedActiveIndex = min(max(activeScreenIndex, 0), screenBounds.count - 1)

    if let screenIndex = screenIndexContainingCursor(cursorPosition: cursorPosition, screenBounds: screenBounds) {
        // Cursor is within a visible screen — position near cursor
        let screenFrame = screenBounds[screenIndex]
        let origin = positionPanelNearCursor(
            cursorPosition: cursorPosition,
            panelSize: panelSize,
            screenFrame: screenFrame
        )
        return .nearCursor(origin: origin)
    } else {
        // Cursor is outside all visible screens — center on active screen
        let activeScreen = screenBounds[clampedActiveIndex]
        let centeredX = activeScreen.midX - panelSize.width / 2
        let centeredY = activeScreen.midY - panelSize.height / 2
        return .centeredOnScreen(origin: CGPoint(x: centeredX, y: centeredY))
    }
}

/// Computes a panel origin near the cursor, with a small offset so the panel
/// doesn't cover the cursor. The result is clamped to stay within the screen's
/// visible frame.
///
/// - Parameters:
///   - cursorPosition: The cursor location.
///   - panelSize: The panel dimensions.
///   - screenFrame: The visible bounds of the target screen.
/// - Returns: The computed origin point for the panel.
func positionPanelNearCursor(
    cursorPosition: CGPoint,
    panelSize: CGSize,
    screenFrame: CGRect
) -> CGPoint {
    // Offset the panel slightly below-right of the cursor
    let cursorOffset: CGFloat = 8

    var x = cursorPosition.x + cursorOffset
    var y = cursorPosition.y - panelSize.height - cursorOffset

    // Clamp horizontal: ensure the panel doesn't extend past the right edge
    if x + panelSize.width > screenFrame.maxX {
        x = cursorPosition.x - panelSize.width - cursorOffset
    }
    // Ensure it doesn't extend past the left edge
    if x < screenFrame.minX {
        x = screenFrame.minX
    }

    // Clamp vertical: ensure the panel doesn't extend below the bottom edge
    if y < screenFrame.minY {
        y = cursorPosition.y + cursorOffset
    }
    // Ensure it doesn't extend above the top edge
    if y + panelSize.height > screenFrame.maxY {
        y = screenFrame.maxY - panelSize.height
    }

    return CGPoint(x: x, y: y)
}
