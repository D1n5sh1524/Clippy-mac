import SwiftUI
import AppKit

/// A SwiftUI view that displays a single clipboard entry row in the popup list.
/// Shows content type icon, text preview or image thumbnail, and relative timestamp.
struct EntryRowView: View {

    // MARK: - Properties

    /// The clipboard entry to display.
    let entry: ClipboardEntry

    /// Whether this row is currently highlighted (keyboard navigation).
    let isHighlighted: Bool

    /// Callback when the row is tapped.
    let onTap: () -> Void

    /// Callback when the copy button is tapped.
    var onCopy: (() -> Void)? = nil

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            // Content type icon
            contentTypeIcon

            // Content preview (text or image thumbnail)
            contentPreview

            Spacer()

            // Copy button
            Button(action: {
                onCopy?()
            }) {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .help("Copy to clipboard")

            // Relative timestamp
            timestampLabel
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isHighlighted
                ? Color.accentColor.opacity(0.2)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .id(entry.id)
    }

    // MARK: - Subviews

    /// Icon indicating content type (text or image).
    private var contentTypeIcon: some View {
        Image(systemName: entry.contentType == .text ? "doc.text" : "photo")
            .foregroundColor(.secondary)
            .frame(width: 20)
    }

    /// Content preview: text preview for text entries, thumbnail for image entries.
    @ViewBuilder
    private var contentPreview: some View {
        switch entry.content {
        case .text:
            if let preview = entry.content.textPreview {
                Text(preview)
                    .lineLimit(1)
                    .font(.system(size: 13))
            }
        case .image(let data):
            imageThumbnail(data: data)
        }
    }

    /// Relative timestamp label displayed on the right side of the row.
    private var timestampLabel: some View {
        Text(RelativeTimestampFormatter().format(entry.timestamp))
            .font(.system(size: 11))
            .foregroundColor(.secondary)
    }

    /// Creates a thumbnail image view scaled to fit within 64x64 pixels preserving aspect ratio.
    @ViewBuilder
    private func imageThumbnail(data: Data) -> some View {
        if let nsImage = NSImage(data: data),
           let rep = nsImage.representations.first {
            let originalWidth = rep.pixelsWide > 0 ? rep.pixelsWide : Int(nsImage.size.width)
            let originalHeight = rep.pixelsHigh > 0 ? rep.pixelsHigh : Int(nsImage.size.height)
            let scaled = scaledThumbnailSize(
                width: max(originalWidth, 1),
                height: max(originalHeight, 1)
            )
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: CGFloat(scaled.width), height: CGFloat(scaled.height))
        } else {
            // Fallback if image data cannot be loaded
            Image(systemName: "photo")
                .foregroundColor(.secondary)
                .frame(width: 64, height: 64)
        }
    }
}
