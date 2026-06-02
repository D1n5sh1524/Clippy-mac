import Foundation
import UserNotifications

/// Manages the ordered list of clipboard entries and handles persistence.
/// Uses Swift actor isolation for thread-safe access to the entry store.
actor HistoryStore {
    /// The in-memory ordered list of clipboard entries (most recent first).
    private var entries: [ClipboardEntry] = []

    /// Maximum number of entries the store will hold before evicting the oldest.
    private let maxEntries = 50

    /// File URL for persisting entries as JSON.
    private let storageURL: URL

    /// Default storage URL: `~/Library/Application Support/ClipboardHistory/clipboard_history.json`
    static var defaultStorageURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("ClipboardHistory")
            .appendingPathComponent("clipboard_history.json")
    }

    /// Active debounced persistence task, if any.
    private var persistTask: Task<Void, Never>?

    /// Initialize the HistoryStore with a given storage URL.
    /// - Parameter storageURL: The file URL where entries are persisted.
    ///   Defaults to `~/Library/Application Support/ClipboardHistory/clipboard_history.json`.
    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL
    }

    // MARK: - Entry Management

    /// Adds a new entry to the history store.
    /// Inserts at the beginning (most recent first). If the store is at capacity,
    /// removes the oldest entry (last element) before inserting.
    /// - Parameter entry: The clipboard entry to add.
    func addEntry(_ entry: ClipboardEntry) {
        if entries.count >= maxEntries {
            entries.removeLast()
        }
        entries.insert(entry, at: 0)
        schedulePersist()
    }

    /// Removes a single entry from the history store by its unique identifier.
    /// If no entry with the given ID exists, does nothing.
    /// - Parameter id: The UUID of the entry to remove.
    func deleteEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        schedulePersist()
    }

    /// Removes all entries from the history store.
    /// The UI layer is responsible for showing a confirmation dialog before calling this method.
    func clearAll() {
        entries.removeAll()
        schedulePersist()
    }

    /// Moves the entry with the given ID to the most recent position (index 0).
    /// All other entries maintain their previous relative order.
    /// If no entry with the given ID exists, does nothing.
    /// - Parameter id: The UUID of the entry to move to the top.
    func moveToTop(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }
        let entry = entries.remove(at: index)
        entries.insert(entry, at: 0)
        schedulePersist()
    }

    /// Returns all entries ordered most recent first.
    /// Since entries are stored with the most recent at index 0,
    /// this simply returns the entries array as-is.
    /// - Returns: An array of all clipboard entries, most recent first.
    func getAllEntries() -> [ClipboardEntry] {
        return entries
    }

    /// Searches entries by case-insensitive substring matching on text content.
    /// Image entries are always excluded from search results.
    /// If the query is empty, returns all entries (including images).
    /// - Parameter query: The search string to match against text entries.
    /// - Returns: An array of matching clipboard entries, most recent first.
    func search(query: String) -> [ClipboardEntry] {
        if query.isEmpty {
            return entries
        }
        return entries.filter { entry in
            switch entry.content {
            case .text(let text):
                return text.localizedCaseInsensitiveContains(query)
            case .image:
                return false
            }
        }
    }

    // MARK: - Persistence

    /// Private wrapper struct for the persisted JSON format.
    private struct PersistedData: Codable {
        let version: Int
        let entries: [ClipboardEntry]
    }

    /// Loads entries from disk.
    /// If the file doesn't exist, starts with empty entries (no error).
    /// If decoding fails, throws the error.
    func load() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storageURL.path) else {
            entries = []
            return
        }

        let data = try Data(contentsOf: storageURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let persisted = try decoder.decode(PersistedData.self, from: data)
        entries = persisted.entries
    }

    /// Loads entries from disk with graceful corruption recovery.
    /// If the file is corrupted or unreadable:
    /// 1. Renames the corrupted file to `clipboard_history.json.corrupt`
    /// 2. Starts with an empty history
    /// 3. Posts a user notification indicating history could not be recovered
    func loadWithRecovery() {
        do {
            try load()
        } catch {
            let fileManager = FileManager.default
            // Rename corrupted file for potential manual recovery
            let corruptURL = URL(fileURLWithPath: storageURL.path + ".corrupt")
            // Remove any existing .corrupt file to avoid rename collision
            try? fileManager.removeItem(at: corruptURL)
            try? fileManager.moveItem(at: storageURL, to: corruptURL)

            // Start with empty history
            entries = []

            // Post user notification about the recovery failure
            postCorruptionNotification()
        }
    }

    /// Posts a user notification informing the user that clipboard history
    /// could not be recovered from a corrupted file.
    private func postCorruptionNotification() {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Clipboard History"
        content.body = "Previous clipboard history could not be recovered. The corrupted file has been preserved for manual recovery."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "clipboard-history-corruption",
            content: content,
            trigger: nil // Deliver immediately
        )

        center.add(request) { error in
            if let error = error {
                // Log but don't crash — notification is best-effort
                print("Failed to post corruption notification: \(error.localizedDescription)")
            }
        }
    }

    /// Schedules a debounced persist operation.
    /// Cancels any existing pending persist and schedules a new one after 1 second.
    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            guard !Task.isCancelled else { return }
            try? await persist()
        }
    }

    /// Immediately persists entries to disk, cancelling any pending debounced persist.
    /// Called on app quit to ensure no data is lost.
    func persistImmediately() async {
        persistTask?.cancel()
        persistTask = nil
        try? await persist()
    }

    /// Writes the current entries to disk as JSON.
    /// Creates the directory if it doesn't exist.
    /// Uses atomic write to prevent corruption.
    private func persist() async throws {
        let directory = storageURL.deletingLastPathComponent()
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        let persisted = PersistedData(version: 1, entries: entries)
        let data = try encoder.encode(persisted)
        try data.write(to: storageURL, options: .atomic)
    }
}
