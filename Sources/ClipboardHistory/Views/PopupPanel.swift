import AppKit
import SwiftUI

/// A floating, non-activating panel that hosts the clipboard history popup view.
/// This panel appears near the cursor when triggered and does not steal focus
/// from the previously active application.
class PopupPanel: NSPanel {

    /// The application that was focused before the panel appeared.
    /// Used to return focus on dismiss and to target paste operations.
    var previousApp: NSRunningApplication?

    /// Callback invoked when the user selects an entry to paste.
    var onPaste: ((ClipboardEntry) -> Void)?

    /// The view model shared with PopupView for providing entries.
    let viewModel = PopupViewModel()

    /// Creates a new PopupPanel configured as a floating, non-activating panel.
    /// Hosts a PopupView as the root SwiftUI content.
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: true
        )

        configurePanel()
        installPopupView()
    }

    // MARK: - SwiftUI Hosting

    /// Installs the PopupView as the panel's content using NSHostingView.
    private func installPopupView() {
        let popupView = PopupView(
            viewModel: viewModel,
            onPaste: { [weak self] entry in
                self?.onPaste?(entry)
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        let hostingView = NSHostingView(rootView: popupView)
        contentView = hostingView
    }

    // MARK: - Configuration

    /// Configures the panel with floating, non-activating behavior.
    private func configurePanel() {
        // Float above other windows
        level = .floating

        // Allow the panel to become key without activating the app
        // This enables keyboard input in the search field
        isFloatingPanel = true

        // Do not activate the owning application when shown
        // This preserves focus context for paste targeting
        hidesOnDeactivate = false

        // Make the panel transparent with no background by default
        // The SwiftUI content will provide its own background
        isOpaque = false
        backgroundColor = .clear

        // Allow the panel to gather mouse/keyboard events
        // without activating the application
        becomesKeyOnlyIfNeeded = true

        // Remove the panel from the window cycle (Cmd+` won't switch to it)
        isExcludedFromWindowsMenu = true

        // Ensure the panel can appear over full-screen spaces
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    // MARK: - Panel Behavior Overrides

    /// Allow the panel to become key window so it can receive keyboard events
    /// (search field input, arrow keys, Enter, Escape) without activating the app.
    override var canBecomeKey: Bool {
        return true
    }

    /// Prevent the panel from becoming the main window.
    override var canBecomeMain: Bool {
        return false
    }

    /// Dismiss the panel when it loses key window status (another window or
    /// application received focus). Satisfies Requirement 4.6.
    override func resignKey() {
        super.resignKey()
        dismiss()
    }

    // MARK: - Show and Dismiss

    /// Shows the panel positioned near the current cursor location.
    /// If the cursor is outside visible screen bounds, centers on the active screen.
    func showNearCursor() {
        // Store the previously active application before showing the panel
        previousApp = NSWorkspace.shared.frontmostApplication

        // Load current entries from the history store
        viewModel.loadEntries()

        let cursorPosition = NSEvent.mouseLocation
        let panelSize = frame.size

        if let targetScreen = screenContainingCursor(cursorPosition) {
            // Cursor is within a visible screen — position near cursor
            let origin = positionNearCursor(
                cursorPosition: cursorPosition,
                panelSize: panelSize,
                screenFrame: targetScreen.visibleFrame
            )
            setFrameOrigin(origin)
        } else {
            // Cursor is outside all visible screens — center on active/main screen
            let activeScreen = NSScreen.main ?? NSScreen.screens.first
            if let screen = activeScreen {
                let screenFrame = screen.visibleFrame
                let centeredX = screenFrame.midX - panelSize.width / 2
                let centeredY = screenFrame.midY - panelSize.height / 2
                setFrameOrigin(NSPoint(x: centeredX, y: centeredY))
            }
        }

        makeKeyAndOrderFront(nil)
    }

    // MARK: - Positioning Helpers

    /// Returns the screen that contains the given cursor position, or nil if
    /// the cursor is outside all visible screens.
    private func screenContainingCursor(_ cursorPosition: NSPoint) -> NSScreen? {
        let screens = NSScreen.screens
        let screenFrames = screens.map { $0.frame }
        if let index = screenIndexContainingCursor(cursorPosition: cursorPosition, screenBounds: screenFrames) {
            return screens[index]
        }
        return nil
    }

    /// Computes a panel origin near the cursor, with a small offset so the panel
    /// doesn't cover the cursor. The result is clamped to stay within the screen's
    /// visible frame.
    private func positionNearCursor(
        cursorPosition: NSPoint,
        panelSize: NSSize,
        screenFrame: NSRect
    ) -> NSPoint {
        return positionPanelNearCursor(
            cursorPosition: cursorPosition,
            panelSize: panelSize,
            screenFrame: screenFrame
        )
    }

    /// Dismisses the panel and returns focus to the previously active application.
    /// Per Requirement 5.2, this must complete within 200 milliseconds.
    func dismiss() {
        // Hide the panel
        orderOut(nil)

        // Return focus to the previously active application if available
        if let app = previousApp, !app.isTerminated {
            app.activate()
        }

        // Clear the reference to avoid stale state
        previousApp = nil
    }
}
