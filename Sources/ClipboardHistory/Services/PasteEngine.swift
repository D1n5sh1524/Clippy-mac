import AppKit
import Foundation

/// Handles placing clipboard content onto the system pasteboard and simulating paste actions.
///
/// `PasteEngine` orchestrates the paste workflow: it writes content to `NSPasteboard.general`
/// and can simulate a Cmd+V keystroke to paste into the target application.
class PasteEngine {
    // MARK: - Properties

    /// The system pasteboard used for writing content.
    private let pasteboard: NSPasteboard

    // MARK: - Initialization

    /// Creates a new PasteEngine.
    /// - Parameter pasteboard: The pasteboard to write to. Defaults to `NSPasteboard.general`.
    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    // MARK: - Public Methods

    /// Paste the given entry: places content on the pasteboard, then simulates Cmd+V.
    /// - Parameters:
    ///   - entry: The clipboard entry to paste.
    ///   - targetApp: The previously focused application (optional). If the target app
    ///     is no longer running, Cmd+V simulation is skipped (Requirement 5.7).
    func paste(entry: ClipboardEntry, targetApp: NSRunningApplication?) {
        placeOnPasteboard(entry.content)

        // Only simulate paste if target app is still available (Req 5.7)
        guard isAppAvailable(targetApp) else {
            return
        }

        simulatePaste()
    }

    // MARK: - Pasteboard Writing

    /// Places the given content onto the system pasteboard.
    ///
    /// For text content, writes the string using the `.string` pasteboard type.
    /// For image content, writes the PNG data using the `.png` pasteboard type.
    ///
    /// - Parameter content: The clipboard content to place on the pasteboard.
    func placeOnPasteboard(_ content: ClipboardContent) {
        // Clear existing pasteboard contents before writing new data
        pasteboard.clearContents()

        switch content {
        case .text(let string):
            pasteboard.setString(string, forType: .string)

        case .image(let data):
            pasteboard.setData(data, forType: .png)
        }
    }

    // MARK: - Paste Simulation

    /// Simulates a Cmd+V keystroke using the `CGEvent` API.
    /// Requires Accessibility permission at runtime.
    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key code for 'V' is 0x09
        let keyCodeV: CGKeyCode = 0x09

        // Create key down event with Cmd modifier
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: true) else {
            return
        }
        keyDown.flags = .maskCommand

        // Create key up event with Cmd modifier
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: false) else {
            return
        }
        keyUp.flags = .maskCommand

        // Post events to the HID event tap
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Target App Validation

    /// Checks whether the target application is still available (running and not terminated).
    /// - Parameter app: The target application to check.
    /// - Returns: `true` if the app is non-nil and not terminated, `false` otherwise.
    private func isAppAvailable(_ app: NSRunningApplication?) -> Bool {
        guard let app = app else {
            return false
        }
        return !app.isTerminated
    }
}
