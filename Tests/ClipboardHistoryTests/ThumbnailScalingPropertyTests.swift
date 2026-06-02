import Testing
import Foundation
import SwiftCheck
@testable import ClipboardHistory

// Feature: mac-clipboard-history, Property 10: Image thumbnail scaling preserves aspect ratio

/// **Validates: Requirements 4.3**
///
/// Property: For any image with width W and height H (both > 0), the thumbnail scaling
/// function SHALL produce dimensions that:
/// 1. Fit within 64×64 pixels (both output width ≤ 64 AND output height ≤ 64)
/// 2. Maintain the original aspect ratio (W/H) within a tolerance of ±1 pixel due to integer rounding
/// 3. At least one output dimension equals 64 when the input exceeds 64×64 (scaled to fill the bounding box)

// MARK: - Generators

/// Generator for positive image dimensions (1 to 10000) with emphasis on interesting ranges.
private let dimensionGen: Gen<Int> = Gen<Int>.frequency([
    // 20% very small (1-5) - edge cases
    (2, Gen<Int>.fromElements(in: 1...5)),
    // 20% near the boundary (50-80) - around the 64px threshold
    (2, Gen<Int>.fromElements(in: 50...80)),
    // 30% moderate (6-500) - typical small-to-medium images
    (3, Gen<Int>.fromElements(in: 6...500)),
    // 20% large (501-5000) - typical photos
    (2, Gen<Int>.fromElements(in: 501...5000)),
    // 10% very large (5001-10000) - high-res images
    (1, Gen<Int>.fromElements(in: 5001...10000))
])

/// Generator for a pair of (width, height) positive dimensions.
private let dimensionPairGen: Gen<(Int, Int)> = Gen<(Int, Int)>.compose { composer in
    let width = composer.generate(using: dimensionGen)
    let height = composer.generate(using: dimensionGen)
    return (width, height)
}

/// Generator for square dimensions to test the square case explicitly.
private let squareDimensionGen: Gen<Int> = Gen<Int>.frequency([
    (1, Gen<Int>.fromElements(in: 1...64)),
    (2, Gen<Int>.fromElements(in: 65...1000)),
    (1, Gen<Int>.fromElements(in: 1001...10000))
])

/// Generator for extreme aspect ratios (very wide or very tall).
private let extremeAspectGen: Gen<(Int, Int)> = Gen<(Int, Int)>.compose { composer in
    let isWide = composer.generate(using: Gen<Bool>.pure(true))
    let largerDim = composer.generate(using: Gen<Int>.fromElements(in: 100...10000))
    let smallerDim = composer.generate(using: Gen<Int>.fromElements(in: 1...10))
    if isWide {
        return (largerDim, smallerDim)
    } else {
        return (smallerDim, largerDim)
    }
}

// MARK: - Property Tests

@Suite("Image Thumbnail Scaling Property Tests")
struct ThumbnailScalingPropertyTests {

    // MARK: - Property 10a: Output fits within 64×64

    @Test("Scaled dimensions never exceed 64 in either axis")
    func outputFitsWithin64x64() {
        property("For any positive dimensions, scaled output width ≤ 64 AND height ≤ 64")
            <- forAll(dimensionPairGen) { (width, height) in
                let result = scaledThumbnailSize(width: width, height: height)
                let widthFits = result.width <= 64
                let heightFits = result.height <= 64
                return (widthFits <?> "Output width \(result.width) exceeds 64 for input (\(width), \(height))")
                    ^&&^
                    (heightFits <?> "Output height \(result.height) exceeds 64 for input (\(width), \(height))")
            }
    }

    @Test("Extreme aspect ratios still fit within 64×64")
    func extremeAspectRatiosFitWithin64x64() {
        property("Extreme aspect ratios produce output within 64×64")
            <- forAll(extremeAspectGen) { (width, height) in
                let result = scaledThumbnailSize(width: width, height: height)
                let widthFits = result.width <= 64
                let heightFits = result.height <= 64
                return (widthFits <?> "Width \(result.width) exceeds 64 for extreme input (\(width), \(height))")
                    ^&&^
                    (heightFits <?> "Height \(result.height) exceeds 64 for extreme input (\(width), \(height))")
            }
    }

    // MARK: - Property 10b: Aspect ratio preserved within ±1px tolerance

    @Test("Aspect ratio is preserved within ±1 pixel tolerance")
    func aspectRatioPreserved() {
        property("Output aspect ratio matches input aspect ratio within ±1px tolerance")
            <- forAll(dimensionPairGen) { (width, height) in
                let result = scaledThumbnailSize(width: width, height: height)

                // Guard against division by zero in verification
                guard result.height > 0 && result.width > 0 else {
                    return false <?> "Output has zero dimension: (\(result.width), \(result.height)) for input (\(width), \(height))"
                }

                // Verify aspect ratio preservation using cross-multiplication to avoid floating point:
                // If aspect ratio is preserved: outputW / outputH ≈ inputW / inputH
                // Which means: outputW * inputH ≈ outputH * inputW
                // The ±1px tolerance on output dimensions means the cross-product difference
                // should be bounded by: |outputW * inputH - outputH * inputW| ≤ max(inputH, inputW)
                //
                // Alternative approach: check that the output dimensions are consistent with
                // scaling by the same factor ± 1px rounding.
                let expectedWidth = Double(width) * Double(result.height) / Double(height)
                let expectedHeight = Double(height) * Double(result.width) / Double(width)

                // The actual output width should be within ±1 of the expected width given the output height
                let widthWithinTolerance = abs(Double(result.width) - expectedWidth) <= 1.0
                // OR the actual output height should be within ±1 of the expected height given the output width
                let heightWithinTolerance = abs(Double(result.height) - expectedHeight) <= 1.0

                return (widthWithinTolerance || heightWithinTolerance)
                    <?> "Aspect ratio not preserved: input (\(width), \(height)) -> output (\(result.width), \(result.height)), expectedW=\(expectedWidth), expectedH=\(expectedHeight)"
            }
    }

    // MARK: - Property 10c: At least one dimension reaches 64 when scaling is needed

    @Test("At least one dimension is 64 when input exceeds 64×64 bounding box")
    func atLeastOneDimensionReaches64WhenScaling() {
        // Generator for dimensions where at least one exceeds 64
        let needsScalingGen = Gen<(Int, Int)>.compose { composer in
            let width = composer.generate(using: Gen<Int>.fromElements(in: 65...10000))
            let height = composer.generate(using: Gen<Int>.fromElements(in: 1...10000))
            return (width, height)
        }

        property("When input exceeds 64 in at least one dimension, output has at least one dimension equal to 64")
            <- forAll(needsScalingGen) { (width, height) in
                let result = scaledThumbnailSize(width: width, height: height)

                // If the image needs scaling (width > 64 OR height > 64), then at least one
                // output dimension should be exactly 64
                if width > 64 || height > 64 {
                    let hasMax = result.width == 64 || result.height == 64
                    return hasMax
                        <?> "Neither dimension reached 64: output (\(result.width), \(result.height)) for input (\(width), \(height))"
                } else {
                    // Should not happen with this generator, but handle gracefully
                    return true <?> "Input fits within 64×64, no scaling needed"
                }
            }
    }

    // MARK: - Property 10d: Images that already fit are returned unchanged

    @Test("Images that already fit within 64×64 are returned with original dimensions")
    func imagesThatFitReturnedUnchanged() {
        let fittingGen = Gen<(Int, Int)>.compose { composer in
            let width = composer.generate(using: Gen<Int>.fromElements(in: 1...64))
            let height = composer.generate(using: Gen<Int>.fromElements(in: 1...64))
            return (width, height)
        }

        property("Images with both dimensions ≤ 64 are returned with original dimensions")
            <- forAll(fittingGen) { (width, height) in
                let result = scaledThumbnailSize(width: width, height: height)
                let widthPreserved = result.width == width
                let heightPreserved = result.height == height
                return (widthPreserved <?> "Width changed from \(width) to \(result.width)")
                    ^&&^
                    (heightPreserved <?> "Height changed from \(height) to \(result.height)")
            }
    }

    // MARK: - Property 10e: Output dimensions are always positive

    @Test("Output dimensions are always positive (> 0)")
    func outputDimensionsAlwaysPositive() {
        property("Scaled output always has positive width and height")
            <- forAll(dimensionPairGen) { (width, height) in
                let result = scaledThumbnailSize(width: width, height: height)
                let widthPositive = result.width > 0
                let heightPositive = result.height > 0
                return (widthPositive <?> "Output width is \(result.width) for input (\(width), \(height))")
                    ^&&^
                    (heightPositive <?> "Output height is \(result.height) for input (\(width), \(height))")
            }
    }

    // MARK: - Square images

    @Test("Square images produce square output when scaled")
    func squareImagesProduceSquareOutput() {
        property("Square images larger than 64×64 produce exactly 64×64 output")
            <- forAll(squareDimensionGen) { dimension in
                let result = scaledThumbnailSize(width: dimension, height: dimension)
                if dimension > 64 {
                    let isSquare64 = result.width == 64 && result.height == 64
                    return isSquare64
                        <?> "Square input \(dimension)×\(dimension) produced non-square output (\(result.width), \(result.height))"
                } else {
                    let unchanged = result.width == dimension && result.height == dimension
                    return unchanged
                        <?> "Square input \(dimension)×\(dimension) was unexpectedly changed to (\(result.width), \(result.height))"
                }
            }
    }
}
