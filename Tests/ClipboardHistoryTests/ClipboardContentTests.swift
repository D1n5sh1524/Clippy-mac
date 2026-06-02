import Testing
import Foundation
@testable import ClipboardHistory

@Suite("ClipboardContent Tests")
struct ClipboardContentTests {

    // MARK: - Codable Round-Trip Tests

    @Test("Text content encodes and decodes correctly")
    func textCodableRoundTrip() throws {
        let original = ClipboardContent.text("Hello, World!")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ClipboardContent.self, from: data)
        #expect(decoded == original)
    }

    @Test("Image content encodes and decodes correctly")
    func imageCodableRoundTrip() throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let original = ClipboardContent.image(imageData)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ClipboardContent.self, from: data)
        #expect(decoded == original)
    }

    @Test("Empty text encodes and decodes correctly")
    func emptyTextCodableRoundTrip() throws {
        let original = ClipboardContent.text("")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ClipboardContent.self, from: data)
        #expect(decoded == original)
    }

    @Test("Empty image data encodes and decodes correctly")
    func emptyImageCodableRoundTrip() throws {
        let original = ClipboardContent.image(Data())
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ClipboardContent.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Equatable Tests

    @Test("Same text content is equal")
    func textEquality() {
        let a = ClipboardContent.text("hello")
        let b = ClipboardContent.text("hello")
        #expect(a == b)
    }

    @Test("Different text content is not equal")
    func textInequality() {
        let a = ClipboardContent.text("hello")
        let b = ClipboardContent.text("world")
        #expect(a != b)
    }

    @Test("Same image content is equal")
    func imageEquality() {
        let data = Data([1, 2, 3, 4])
        let a = ClipboardContent.image(data)
        let b = ClipboardContent.image(data)
        #expect(a == b)
    }

    @Test("Different image content is not equal")
    func imageInequality() {
        let a = ClipboardContent.image(Data([1, 2, 3]))
        let b = ClipboardContent.image(Data([4, 5, 6]))
        #expect(a != b)
    }

    @Test("Text and image content are not equal")
    func textImageInequality() {
        let a = ClipboardContent.text("hello")
        let b = ClipboardContent.image(Data([1, 2, 3]))
        #expect(a != b)
    }

    // MARK: - Text Preview Tests

    @Test("Short text returns unchanged preview")
    func shortTextPreview() {
        let content = ClipboardContent.text("Hello, World!")
        #expect(content.textPreview == "Hello, World!")
    }

    @Test("Text with newlines has them replaced with spaces")
    func newlinesReplacedInPreview() {
        let content = ClipboardContent.text("Hello\nWorld\nFoo")
        #expect(content.textPreview == "Hello World Foo")
    }

    @Test("Text exactly 80 characters is not truncated")
    func exactly80CharsNotTruncated() {
        let text = String(repeating: "a", count: 80)
        let content = ClipboardContent.text(text)
        #expect(content.textPreview == text)
        #expect(content.textPreview?.count == 80)
    }

    @Test("Text over 80 characters is truncated with ellipsis")
    func over80CharsTruncated() {
        let text = String(repeating: "a", count: 100)
        let content = ClipboardContent.text(text)
        let expected = String(repeating: "a", count: 80) + "…"
        #expect(content.textPreview == expected)
    }

    @Test("Text with newlines counted after replacement for truncation")
    func newlinesAndTruncation() {
        // 79 chars + newline + 10 chars = after replacement: 90 chars (spaces replace newlines)
        let text = String(repeating: "a", count: 79) + "\n" + String(repeating: "b", count: 10)
        let content = ClipboardContent.text(text)
        let afterReplace = String(repeating: "a", count: 79) + " " + String(repeating: "b", count: 10)
        // afterReplace is 90 chars, so should be truncated
        let expected = String(afterReplace.prefix(80)) + "…"
        #expect(content.textPreview == expected)
    }

    @Test("Empty text returns empty string preview")
    func emptyTextPreview() {
        let content = ClipboardContent.text("")
        #expect(content.textPreview == "")
    }

    @Test("Image content returns nil preview")
    func imagePreviewIsNil() {
        let content = ClipboardContent.image(Data([1, 2, 3]))
        #expect(content.textPreview == nil)
    }

    // MARK: - Size Limit Tests

    @Test("Text at exactly 1,000,000 characters does not exceed limit")
    func textAtLimitDoesNotExceed() {
        let text = String(repeating: "x", count: 1_000_000)
        let content = ClipboardContent.text(text)
        #expect(content.exceedsSizeLimit == false)
    }

    @Test("Text over 1,000,000 characters exceeds limit")
    func textOverLimitExceeds() {
        let text = String(repeating: "x", count: 1_000_001)
        let content = ClipboardContent.text(text)
        #expect(content.exceedsSizeLimit == true)
    }

    @Test("Image at exactly 10 MB does not exceed limit")
    func imageAtLimitDoesNotExceed() {
        let data = Data(count: 10 * 1024 * 1024)
        let content = ClipboardContent.image(data)
        #expect(content.exceedsSizeLimit == false)
    }

    @Test("Image over 10 MB exceeds limit")
    func imageOverLimitExceeds() {
        let data = Data(count: 10 * 1024 * 1024 + 1)
        let content = ClipboardContent.image(data)
        #expect(content.exceedsSizeLimit == true)
    }

    @Test("Small text does not exceed limit")
    func smallTextDoesNotExceed() {
        let content = ClipboardContent.text("hello")
        #expect(content.exceedsSizeLimit == false)
    }

    @Test("Small image does not exceed limit")
    func smallImageDoesNotExceed() {
        let content = ClipboardContent.image(Data([1, 2, 3]))
        #expect(content.exceedsSizeLimit == false)
    }
}
