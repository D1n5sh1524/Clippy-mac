import AppKit
import Foundation

/// Monitors the macOS system pasteboard for new clipboard content.
/// Polls `NSPasteboard.general` at 500ms intervals, extracting text or image content,
/// checking for duplicates and size limits, and storing valid entries in HistoryStore.
///
/// Uses Swift actor isolation for thread-safe access to internal state.
actor ClipboardMonitor {
    // MARK: - Properties

    /// Reference to the system general pasteboard.
    private let pasteboard: NSPasteboard

    /// Tracks the last observed pasteboard change count to detect new content.
    private var lastChangeCount: Int

    /// Timer used to poll the pasteboard at regular intervals.
    private var pollingTimer: Timer?

    /// The history store to persist valid clipboard entries.
    private let historyStore: HistoryStore

    /// The polling interval in seconds (500ms).
    private static let pollingInterval: TimeInterval = 0.5

    /// Maximum allowed text length (1,000,000 characters).
    private static let maxTextLength = 1_000_000

    /// Maximum allowed image data size (10 MB).
    private static let maxImageSize = 10 * 1024 * 1024

    // MARK: - Initialization

    /// Creates a new ClipboardMonitor.
    /// - Parameters:
    ///   - historyStore: The history store for persisting clipboard entries.
    ///   - pasteboard: The pasteboard to monitor. Defaults to `NSPasteboard.general`.
    init(historyStore: HistoryStore, pasteboard: NSPasteboard = .general) {
        self.historyStore = historyStore
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    // MARK: - Monitoring Control

    /// Starts monitoring the pasteboard by scheduling a timer that fires every 500ms.
    /// Each tick calls `checkForChanges()` to detect and process new clipboard content.
    func startMonitoring() {
        // Avoid creating duplicate timers
        stopMonitoring()

        // Timer must be scheduled on the main run loop since actors don't own a run loop.
        // We dispatch to the main thread to create and schedule the timer.
        let interval = Self.pollingInterval
        Task { @MainActor in
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.checkForChanges()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            await self.setPollingTimer(timer)
        }
    }

    /// Stops monitoring the pasteboard by invalidating and releasing the timer.
    func stopMonitoring() {
        if let timer = pollingTimer {
            // Invalidate must happen on the main thread where the timer was scheduled.
            let timerToInvalidate = timer
            Task { @MainActor in
                timerToInvalidate.invalidate()
            }
        }
        pollingTimer = nil
    }

    // MARK: - Private Helpers

    /// Sets the polling timer reference. Called from the MainActor context after timer creation.
    private func setPollingTimer(_ timer: Timer) {
        pollingTimer = timer
    }

    /// Checks the pasteboard for changes and processes new content if detected.
    /// Compares the current `changeCount` to `lastChangeCount`. If different,
    /// attempts to extract text or image content, validates size limits and duplicates,
    /// and stores valid entries in the history store.
    ///
    /// Error handling: any failure during pasteboard access or processing is caught
    /// and silently skipped, allowing the next polling cycle to retry (Requirement 1.7).
    private func checkForChanges() async {
        do {
            let currentChangeCount = pasteboard.changeCount

            // No change detected — nothing to do
            guard currentChangeCount != lastChangeCount else {
                return
            }

            // Update the change count regardless of whether we successfully process content.
            // This prevents repeatedly processing the same change on failure.
            lastChangeCount = currentChangeCount

            // Attempt to extract text content first, then image content.
            // If neither is available, the content is non-text/non-image and is ignored (Req 1.6).
            if let text = try extractText() {
                let content = ClipboardContent.text(text)

                // Size limit check (Req 1.8)
                guard !content.exceedsSizeLimit else {
                    return
                }

                // Duplicate check (Req 1.5)
                let duplicate = await isDuplicate(content)
                guard !duplicate else {
                    return
                }

                // Create and store entry (Req 1.1, 1.3)
                let entry = ClipboardEntry(
                    id: UUID(),
                    content: content,
                    timestamp: Date(),
                    contentType: .text
                )
                await historyStore.addEntry(entry)

            } else if let imageData = try extractImage() {
                let content = ClipboardContent.image(imageData)

                // Size limit check (Req 1.8)
                guard !content.exceedsSizeLimit else {
                    return
                }

                // Duplicate check (Req 1.5)
                let duplicate = await isDuplicate(content)
                guard !duplicate else {
                    return
                }

                // Create and store entry (Req 1.2, 1.3)
                let entry = ClipboardEntry(
                    id: UUID(),
                    content: content,
                    timestamp: Date(),
                    contentType: .image
                )
                await historyStore.addEntry(entry)
            }
            // If neither text nor image was extracted, content is ignored (Req 1.6)

        } catch {
            // Pasteboard access failure: skip this cycle silently (Req 1.7).
            // Monitoring continues on the next polling interval.
            return
        }
    }

    // MARK: - Content Extraction

    /// Extracts text content from the pasteboard.
    /// Checks for plain text (`NSPasteboardTypeString`) or rich text (RTF/RTFD),
    /// converting rich text to plain text if necessary.
    /// - Returns: The extracted text string, or `nil` if no text content is available.
    /// - Throws: An error if pasteboard access fails.
    private func extractText() throws -> String? {
        // Check for plain text first (most common case)
        if let plainText = pasteboard.string(forType: .string), !plainText.isEmpty {
            return plainText
        }

        // Check for RTF content and convert to plain text
        if let rtfData = pasteboard.data(forType: .rtf) {
            let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil)
            if let text = attributedString?.string, !text.isEmpty {
                return text
            }
        }

        // Check for RTFD content and convert to plain text
        if let rtfdData = pasteboard.data(forType: .rtfd) {
            let attributedString = NSAttributedString(rtfd: rtfdData, documentAttributes: nil)
            if let text = attributedString?.string, !text.isEmpty {
                return text
            }
        }

        return nil
    }

    /// Extracts image data from the pasteboard.
    /// Checks for PNG data first, then TIFF data. Returns raw PNG or TIFF bytes.
    /// - Returns: The image data (PNG or TIFF format), or `nil` if no image content is available.
    /// - Throws: An error if pasteboard access fails.
    private func extractImage() throws -> Data? {
        // Check for PNG data first (preferred format)
        if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty {
            return pngData
        }

        // Check for TIFF data
        if let tiffData = pasteboard.data(forType: .tiff), !tiffData.isEmpty {
            return tiffData
        }

        return nil
    }

    // MARK: - Validation

    /// Determines whether the given content is a duplicate of the most recent entry
    /// in the history store. Comparison is byte-identical for the same content type.
    /// - Parameter content: The clipboard content to check for duplicates.
    /// - Returns: `true` if the content is byte-identical to the most recent entry, `false` otherwise.
    private func isDuplicate(_ content: ClipboardContent) async -> Bool {
        let entries = await historyStore.getAllEntries()
        guard let mostRecent = entries.first else {
            return false
        }
        return mostRecent.content == content
    }
}
