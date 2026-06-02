import Foundation

/// Maximum dimension for thumbnail previews.
let thumbnailMaxSize: Int = 64

/// Computes scaled dimensions that fit within 64×64 pixels while preserving the original aspect ratio.
///
/// - Parameters:
///   - width: The original image width (must be > 0).
///   - height: The original image height (must be > 0).
/// - Returns: A tuple of (scaledWidth, scaledHeight) that fits within 64×64.
///
/// Behavior:
/// - If both dimensions already fit within 64×64, returns the original dimensions.
/// - Otherwise, scales down so the larger dimension becomes exactly 64 and the other is scaled
///   proportionally, preserving the aspect ratio (within ±1 pixel due to integer rounding).
func scaledThumbnailSize(width: Int, height: Int) -> (width: Int, height: Int) {
    precondition(width > 0 && height > 0, "Width and height must be positive")

    // If the image already fits within the max thumbnail size, return original dimensions
    if width <= thumbnailMaxSize && height <= thumbnailMaxSize {
        return (width: width, height: height)
    }

    // Determine the scale factor based on the larger dimension
    let scaleFactor: Double
    if width >= height {
        scaleFactor = Double(thumbnailMaxSize) / Double(width)
    } else {
        scaleFactor = Double(thumbnailMaxSize) / Double(height)
    }

    let scaledWidth = Int(round(Double(width) * scaleFactor))
    let scaledHeight = Int(round(Double(height) * scaleFactor))

    // Clamp to ensure we never exceed the max size due to rounding
    let clampedWidth = min(scaledWidth, thumbnailMaxSize)
    let clampedHeight = min(scaledHeight, thumbnailMaxSize)

    return (width: clampedWidth, height: clampedHeight)
}
