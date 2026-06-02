import Foundation

/// Represents a single entry in the clipboard history.
/// Each entry has a unique identifier, the clipboard content, a creation timestamp,
/// and a content type indicator for persistence.
struct ClipboardEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let content: ClipboardContent
    let timestamp: Date
    let contentType: ContentType

    /// Indicates the type of content stored in this entry.
    enum ContentType: String, Codable {
        case text
        case image
    }
}
