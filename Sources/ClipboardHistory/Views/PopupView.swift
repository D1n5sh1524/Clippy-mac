import SwiftUI

/// The root SwiftUI view hosted in the PopupPanel.
/// Contains a search area at the top and a scrollable list of clipboard entries below.
/// Manages search state, highlighted selection, and entry filtering.
struct PopupView: View {

    // MARK: - State

    /// The current search query entered by the user.
    @State private var searchQuery: String = ""

    /// The index of the currently highlighted entry (keyboard navigation).
    @State private var highlightedIndex: Int? = nil

    /// View model providing entries from the HistoryStore.
    @ObservedObject var viewModel: PopupViewModel

    // MARK: - Callbacks

    /// Called when the user selects an entry to paste.
    var onPaste: (ClipboardEntry) -> Void

    /// Called when the popup should be dismissed.
    var onDismiss: () -> Void

    /// Called when the user copies an entry to clipboard (without pasting).
    var onCopy: ((ClipboardEntry) -> Void)?

    // MARK: - Computed Properties

    /// Entries filtered by the current search query.
    /// When the query is empty, returns all entries.
    /// When non-empty, returns only text entries containing the query (case-insensitive).
    private var filteredEntries: [ClipboardEntry] {
        guard !searchQuery.isEmpty else {
            return viewModel.entries
        }
        return viewModel.entries.filter { entry in
            switch entry.content {
            case .text(let text):
                return text.localizedCaseInsensitiveContains(searchQuery)
            case .image:
                return false
            }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Search area and Clear All button
            HStack {
                searchArea

                // Clear All button
                if !viewModel.entries.isEmpty {
                    Button(action: {
                        viewModel.showClearConfirmation = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Clear all history")
                    .padding(.trailing, 8)
                }
            }

            // Divider between search and list
            Divider()

            // Scrollable list of entries
            entryList
        }
        .frame(width: 320, height: 400)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .alert("Clear All History", isPresented: $viewModel.showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                viewModel.clearAll()
            }
        } message: {
            Text("Are you sure you want to clear all clipboard history? This cannot be undone.")
        }
        .onKeyPress(.escape) {
            handleEscape()
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveHighlight(direction: .down)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveHighlight(direction: .up)
            return .handled
        }
        .onKeyPress(.return) {
            handleReturn()
            return .handled
        }
    }

    // MARK: - Subviews

    /// Search input field using SearchView with auto-focus support.
    private var searchArea: some View {
        SearchView(searchQuery: $searchQuery)
    }

    /// Scrollable list of filtered clipboard entries.
    private var entryList: some View {
        Group {
            if filteredEntries.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                                entryRow(entry: entry, index: index)
                            }
                        }
                    }
                    .onChange(of: highlightedIndex) { _, newValue in
                        if let index = newValue, index < filteredEntries.count {
                            proxy.scrollTo(filteredEntries[index].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    /// Entry row view using EntryRowView component.
    private func entryRow(entry: ClipboardEntry, index: Int) -> some View {
        EntryRowView(
            entry: entry,
            isHighlighted: highlightedIndex == index,
            onTap: { onPaste(entry) },
            onCopy: { viewModel.copyToClipboard(entry: entry) }
        )
    }

    /// Empty state displayed when no entries match the filter or history is empty.
    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            if searchQuery.isEmpty {
                Text("No clipboard history")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            } else {
                Text("No matching entries")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Keyboard Navigation

    private enum Direction {
        case up, down
    }

    /// Moves the highlight in the given direction, respecting list bounds.
    private func moveHighlight(direction: Direction) {
        let count = filteredEntries.count
        guard count > 0 else { return }

        switch direction {
        case .down:
            if let current = highlightedIndex {
                if current < count - 1 {
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

    /// Handles the Escape key: clears search if non-empty, dismisses otherwise.
    private func handleEscape() {
        if !searchQuery.isEmpty {
            searchQuery = ""
            highlightedIndex = nil
        } else {
            onDismiss()
        }
    }

    /// Handles the Return key: pastes the highlighted entry if one is selected.
    private func handleReturn() {
        guard let index = highlightedIndex,
              index < filteredEntries.count else {
            return
        }
        onPaste(filteredEntries[index])
    }

}
