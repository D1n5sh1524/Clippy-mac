import Testing
import Foundation
import SwiftCheck
@testable import ClipboardHistory

// Feature: mac-clipboard-history, Property 3: Size limit enforcement

/// **Validates: Requirements 1.8**
///
/// Property: For any text string longer than 1,000,000 characters or image data larger than
/// 10 MB, the `exceedsSizeLimit` check SHALL return true. For any text with 1,000,000 or
/// fewer characters or image data of 10 MB or less, it SHALL return false.

// MARK: - Boundary-Focused Generators

/// Generator for text lengths focused around the 1,000,000 character boundary.
/// Produces lengths in the range [999_990, 1_000_010] to densely test around the boundary,
/// as well as values from the broader range [0, 1_100_000] for general coverage.
private let textLengthBoundaryGen: Gen<Int> = Gen<Int>.frequency([
    // 60% of values near the boundary (within ±10 of 1,000,000)
    (6, Gen<Int>.fromElements(in: 999_990...1_000_010)),
    // 20% below the boundary (general within-limit values)
    (2, Gen<Int>.fromElements(in: 0...999_989)),
    // 20% above the boundary (general over-limit values)
    (2, Gen<Int>.fromElements(in: 1_000_011...1_100_000))
])

/// Generator for image data sizes focused around the 10 MB boundary.
/// 10 MB = 10 * 1024 * 1024 = 10_485_760 bytes.
/// Produces sizes in the range [10_485_750, 10_485_770] for boundary testing,
/// plus broader ranges for general coverage.
private let imageSizeBoundaryGen: Gen<Int> = Gen<Int>.frequency([
    // 60% near the boundary (within ±10 of 10 MB)
    (6, Gen<Int>.fromElements(in: 10_485_750...10_485_770)),
    // 20% below the boundary (general within-limit values)
    (2, Gen<Int>.fromElements(in: 0...10_485_749)),
    // 20% above the boundary (general over-limit values)
    (2, Gen<Int>.fromElements(in: 10_485_771...11_000_000))
])

// MARK: - Property Tests

@Suite("Size Limit Enforcement Property Tests")
struct SizeLimitPropertyTests {

    // MARK: - Text Size Limit

    @Test("Text exceeding 1,000,000 characters returns exceedsSizeLimit == true")
    func textOverLimitExceedsSize() {
        // Generate text lengths strictly above 1,000,000
        let overLimitGen = Gen<Int>.frequency([
            (7, Gen<Int>.fromElements(in: 1_000_001...1_000_010)),
            (3, Gen<Int>.fromElements(in: 1_000_011...1_100_000))
        ])

        property("Text with more than 1,000,000 characters exceeds size limit")
            <- forAllNoShrink(overLimitGen) { length in
                // Use a repeating character to efficiently create a string of the target length
                let text = String(repeating: "a", count: length)
                let content = ClipboardContent.text(text)
                return content.exceedsSizeLimit == true
                    <?> "Expected exceedsSizeLimit == true for text of length \(length)"
            }
    }

    @Test("Text with 1,000,000 or fewer characters returns exceedsSizeLimit == false")
    func textWithinLimitDoesNotExceedSize() {
        // Generate text lengths at or below 1,000,000
        let withinLimitGen = Gen<Int>.frequency([
            (7, Gen<Int>.fromElements(in: 999_990...1_000_000)),
            (3, Gen<Int>.fromElements(in: 0...999_989))
        ])

        property("Text with 1,000,000 or fewer characters does not exceed size limit")
            <- forAllNoShrink(withinLimitGen) { length in
                let text = String(repeating: "a", count: length)
                let content = ClipboardContent.text(text)
                return content.exceedsSizeLimit == false
                    <?> "Expected exceedsSizeLimit == false for text of length \(length)"
            }
    }

    @Test("Text size limit boundary is exactly at 1,000,000 characters")
    func textBoundaryExact() {
        // Combined property: for any length, exceedsSizeLimit should be (length > 1_000_000)
        property("Text exceedsSizeLimit matches (count > 1_000_000) for any length near boundary")
            <- forAllNoShrink(textLengthBoundaryGen) { length in
                let text = String(repeating: "x", count: length)
                let content = ClipboardContent.text(text)
                let expected = length > 1_000_000
                return content.exceedsSizeLimit == expected
                    <?> "For text length \(length): expected exceedsSizeLimit == \(expected), got \(!expected)"
            }
    }

    // MARK: - Image Size Limit

    @Test("Image data exceeding 10 MB returns exceedsSizeLimit == true")
    func imageOverLimitExceedsSize() {
        // Generate image sizes strictly above 10 MB (10_485_760 bytes)
        let overLimitGen = Gen<Int>.frequency([
            (7, Gen<Int>.fromElements(in: 10_485_761...10_485_770)),
            (3, Gen<Int>.fromElements(in: 10_485_771...11_000_000))
        ])

        property("Image data larger than 10 MB exceeds size limit")
            <- forAllNoShrink(overLimitGen) { size in
                // Use Data(count:) for efficient zero-filled allocation
                let data = Data(count: size)
                let content = ClipboardContent.image(data)
                return content.exceedsSizeLimit == true
                    <?> "Expected exceedsSizeLimit == true for image of size \(size) bytes"
            }
    }

    @Test("Image data of 10 MB or less returns exceedsSizeLimit == false")
    func imageWithinLimitDoesNotExceedSize() {
        // Generate image sizes at or below 10 MB (10_485_760 bytes)
        let withinLimitGen = Gen<Int>.frequency([
            (7, Gen<Int>.fromElements(in: 10_485_750...10_485_760)),
            (3, Gen<Int>.fromElements(in: 0...10_485_749))
        ])

        property("Image data of 10 MB or less does not exceed size limit")
            <- forAllNoShrink(withinLimitGen) { size in
                let data = Data(count: size)
                let content = ClipboardContent.image(data)
                return content.exceedsSizeLimit == false
                    <?> "Expected exceedsSizeLimit == false for image of size \(size) bytes"
            }
    }

    @Test("Image size limit boundary is exactly at 10 MB (10,485,760 bytes)")
    func imageBoundaryExact() {
        // Combined property: for any size, exceedsSizeLimit should be (size > 10 * 1024 * 1024)
        let tenMB = 10 * 1024 * 1024 // 10_485_760

        property("Image exceedsSizeLimit matches (count > 10 MB) for any size near boundary")
            <- forAllNoShrink(imageSizeBoundaryGen) { size in
                let data = Data(count: size)
                let content = ClipboardContent.image(data)
                let expected = size > tenMB
                return content.exceedsSizeLimit == expected
                    <?> "For image size \(size): expected exceedsSizeLimit == \(expected), got \(!expected)"
            }
    }
}
