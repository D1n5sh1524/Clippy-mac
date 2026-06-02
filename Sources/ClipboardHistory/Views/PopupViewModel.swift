import Foundation
import Combine

/// View model that bridges the HistoryStore (actor) with the PopupView (SwiftUI).
/// Publishes entries so the view reactively updates when entries are loaded or change.
@MainActor
class PopupViewModel: ObservableObject {
    /// The entries to display, published so SwiftUI observes changes.
    @Published var entries: [ClipboardEntry] = []

    /// Reference to the history store for fetching entries.
    private var historyStore: HistoryStore?

    /// Sets the history store reference. Called once during app setup.
    func configure(historyStore: HistoryStore) {
        self.historyStore = historyStore
    }

    /// Loads entries from the history store. Call this each time the panel is shown
    /// to ensure the displayed list is current.
    func loadEntries() {
        guard let store = historyStore else { return }
        Task {
            let allEntries = await store.getAllEntries()
            self.entries = allEntries
        }
    }

    /// Clears the displayed entries (e.g., when the panel is dismissed).
    func clearEntries() {
        entries = []
    }
}
