import Foundation

/// Represents the content of a clipboard entry.
/// Supports text strings and PNG-encoded image data.
enum ClipboardContent: Codable, Equatable {
    case text(String)
    case image(Data)  // PNG-encoded image data

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case text
        case image
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let textValue = try container.decodeIfPresent(String.self, forKey: .text) {
            self = .text(textValue)
        } else if let imageValue = try container.decodeIfPresent(Data.self, forKey: .image) {
            self = .image(imageValue)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "ClipboardContent must contain either 'text' or 'image' key"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let str):
            try container.encode(str, forKey: .text)
        case .image(let data):
            try container.encode(data, forKey: .image)
        }
    }

    // MARK: - Computed Properties

    /// Text preview for display (truncated, single-line).
    /// Returns nil for image content.
    var textPreview: String? {
        switch self {
        case .text(let str):
            let singleLine = str.replacingOccurrences(of: "\n", with: " ")
            return singleLine.count > 80
                ? String(singleLine.prefix(80)) + "…"
                : singleLine
        case .image:
            return nil
        }
    }

    /// Check if content exceeds size limits.
    /// Text: max 1,000,000 characters. Image: max 10 MB.
    var exceedsSizeLimit: Bool {
        switch self {
        case .text(let str): return str.count > 1_000_000
        case .image(let data): return data.count > 10 * 1024 * 1024
        }
    }
}
