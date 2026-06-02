import SwiftUI

/// A search text field view for filtering clipboard history entries.
/// Uses @FocusState to automatically receive focus when the popup panel is activated.
/// Displays a magnifying glass icon on the left and a clear button on the right when text is present.
struct SearchView: View {

    // MARK: - Bindings

    /// Binding to the search query text managed by the parent view.
    @Binding var searchQuery: String

    // MARK: - Focus State

    /// Controls whether the search text field has keyboard focus.
    @FocusState private var isSearchFieldFocused: Bool

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            // Magnifying glass icon on the left
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14))

            // Search text field
            TextField("Search clipboard history…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isSearchFieldFocused)

            // Clear button (X) shown only when text is present
            if !searchQuery.isEmpty {
                Button(action: {
                    searchQuery = ""
                    isSearchFieldFocused = true
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onAppear {
            // Automatically focus the search field when the view appears
            // (i.e., when the popup panel is activated)
            isSearchFieldFocused = true
        }
    }
}
