import Testing
import Foundation
@testable import ClipboardHistory

@Suite("ThumbnailScaling Tests")
struct ThumbnailScalingTests {

    // MARK: - Images that already fit within 64x64

    @Test("Image that already fits returns original dimensions")
    func alreadyFitsReturnsOriginal() {
        let result = scaledThumbnailSize(width: 32, height: 32)
        #expect(result.width == 32)
        #expect(result.height == 32)
    }

    @Test("Image exactly 64x64 returns original dimensions")
    func exactly64x64ReturnsOriginal() {
        let result = scaledThumbnailSize(width: 64, height: 64)
        #expect(result.width == 64)
        #expect(result.height == 64)
    }

    @Test("Small 1x1 image returns original dimensions")
    func tinyImageReturnsOriginal() {
        let result = scaledThumbnailSize(width: 1, height: 1)
        #expect(result.width == 1)
        #expect(result.height == 1)
    }

    @Test("Image 64x32 returns original dimensions")
    func wideFittingImageReturnsOriginal() {
        let result = scaledThumbnailSize(width: 64, height: 32)
        #expect(result.width == 64)
        #expect(result.height == 32)
    }

    @Test("Image 32x64 returns original dimensions")
    func tallFittingImageReturnsOriginal() {
        let result = scaledThumbnailSize(width: 32, height: 64)
        #expect(result.width == 32)
        #expect(result.height == 64)
    }

    // MARK: - Landscape images (width > height)

    @Test("Landscape image scales width to 64")
    func landscapeScalesCorrectly() {
        let result = scaledThumbnailSize(width: 128, height: 64)
        #expect(result.width == 64)
        #expect(result.height == 32)
    }

    @Test("Wide landscape image scales correctly")
    func wideLandscapeScalesCorrectly() {
        let result = scaledThumbnailSize(width: 1920, height: 1080)
        #expect(result.width == 64)
        #expect(result.height == 36)
    }

    @Test("2:1 landscape ratio scales correctly")
    func twoToOneLandscape() {
        let result = scaledThumbnailSize(width: 200, height: 100)
        #expect(result.width == 64)
        #expect(result.height == 32)
    }

    // MARK: - Portrait images (height > width)

    @Test("Portrait image scales height to 64")
    func portraitScalesCorrectly() {
        let result = scaledThumbnailSize(width: 64, height: 128)
        #expect(result.width == 32)
        #expect(result.height == 64)
    }

    @Test("Tall portrait image scales correctly")
    func tallPortraitScalesCorrectly() {
        let result = scaledThumbnailSize(width: 1080, height: 1920)
        #expect(result.width == 36)
        #expect(result.height == 64)
    }

    @Test("1:2 portrait ratio scales correctly")
    func oneToTwoPortrait() {
        let result = scaledThumbnailSize(width: 100, height: 200)
        #expect(result.width == 32)
        #expect(result.height == 64)
    }

    // MARK: - Square images

    @Test("Square image larger than 64 scales to 64x64")
    func squareScalesTo64() {
        let result = scaledThumbnailSize(width: 256, height: 256)
        #expect(result.width == 64)
        #expect(result.height == 64)
    }

    @Test("Large square image scales to 64x64")
    func largeSquareScalesTo64() {
        let result = scaledThumbnailSize(width: 4096, height: 4096)
        #expect(result.width == 64)
        #expect(result.height == 64)
    }

    // MARK: - Output constraints

    @Test("Output width never exceeds 64")
    func widthNeverExceeds64() {
        let result = scaledThumbnailSize(width: 10000, height: 1)
        #expect(result.width <= 64)
    }

    @Test("Output height never exceeds 64")
    func heightNeverExceeds64() {
        let result = scaledThumbnailSize(width: 1, height: 10000)
        #expect(result.height <= 64)
    }

    @Test("At least one dimension is 64 when scaling down")
    func atLeastOneDimensionIs64WhenScaling() {
        // For an image that needs scaling, at least one dimension should be 64
        let result = scaledThumbnailSize(width: 1920, height: 1080)
        #expect(result.width == 64 || result.height == 64)
    }

    // MARK: - Aspect ratio preservation

    @Test("Aspect ratio preserved for 16:9 image")
    func aspectRatioPreserved16by9() {
        let result = scaledThumbnailSize(width: 1600, height: 900)
        // Original ratio: 1600/900 = 1.778
        // Expected: 64x36 -> ratio 64/36 = 1.778
        let originalRatio = Double(1600) / Double(900)
        let scaledRatio = Double(result.width) / Double(result.height)
        // Within ±1 pixel tolerance means the ratio difference should be small
        #expect(abs(originalRatio - scaledRatio) < 0.1)
    }

    @Test("Aspect ratio preserved for 4:3 image")
    func aspectRatioPreserved4by3() {
        let result = scaledThumbnailSize(width: 800, height: 600)
        // 800/600 = 1.333, scaled should be 64/48 = 1.333
        #expect(result.width == 64)
        #expect(result.height == 48)
    }

    // MARK: - Edge cases with one dimension already at or below 64

    @Test("Only width exceeds 64, height stays proportional")
    func onlyWidthExceeds() {
        let result = scaledThumbnailSize(width: 128, height: 32)
        #expect(result.width == 64)
        #expect(result.height == 16)
    }

    @Test("Only height exceeds 64, width stays proportional")
    func onlyHeightExceeds() {
        let result = scaledThumbnailSize(width: 32, height: 128)
        #expect(result.width == 16)
        #expect(result.height == 64)
    }
}
