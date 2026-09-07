import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Clippet

final class ImageCodecTests: XCTestCase {
    func testSamePixelsHashTheSameAcrossContainersAndReencodes() {
        let png = makePNG(width: 40, height: 30)
        let fromPNG = ImageCodec.decode(png)!
        let fromTIFF = ImageCodec.decode(tiffData(fromPNG: png))!
        let reencoded = ImageCodec.decode(ImageCodec.pngData(fromPNG)!)!

        let reference = ImageCodec.pixelHash(fromPNG)
        XCTAssertEqual(ImageCodec.pixelHash(fromTIFF), reference)
        XCTAssertEqual(ImageCodec.pixelHash(reencoded), reference)
        XCTAssertNotEqual(ImageCodec.pixelHash(ImageCodec.decode(makePNG(width: 40, height: 30, seed: 0x99))!), reference)
        XCTAssertNotEqual(ImageCodec.pixelHash(ImageCodec.decode(makePNG(width: 30, height: 40))!), reference,
                          "same bytes in a different shape are a different picture")
    }

    func testProcessRejectsOversizedAndNonImages() {
        let png = makePNG(width: 64, height: 64)
        XCTAssertNil(ImageCodec.process(png, maxBytes: 16))
        XCTAssertNil(ImageCodec.process(Data("not an image".utf8), maxBytes: .max))
        let processed = ImageCodec.process(png, maxBytes: .max)
        XCTAssertEqual(processed?.width, 64)
        XCTAssertEqual(processed?.height, 64)
        XCTAssertLessThanOrEqual(processed!.png.count, .max)
    }

    func testThumbnailsAreBoundedAndKeepTransparencyOnlyWhenNeeded() {
        let opaque = ImageCodec.decode(makePNG(width: 2_000, height: 500))!
        let opaqueThumb = ImageCodec.decode(ImageCodec.thumbnail(of: opaque)!)!
        XCTAssertEqual(opaqueThumb.width, ImageCodec.thumbnailMaxPixels)
        XCTAssertEqual(opaqueThumb.height, 128)
        XCTAssertEqual(opaqueThumb.utType as String?, "public.jpeg")

        let translucent = ImageCodec.decode(makePNG(width: 100, height: 300, alpha: 128))!
        let translucentThumb = ImageCodec.decode(ImageCodec.thumbnail(of: translucent)!)!
        XCTAssertEqual(translucentThumb.width, 100, "small images are not upscaled")
        XCTAssertEqual(translucentThumb.utType as String?, "public.png", "alpha would be lost in JPEG")
    }
}

final class ClipItemTests: XCTestCase {
    private func item(_ text: String, kind: ClipKind = .text) -> ClipItem {
        ClipItem(id: 1, kind: kind, hash: "h", text: text, pinned: false, createdAt: Date(),
                 lastUsedAt: Date(), appBundleID: nil, thumbnail: nil, imageWidth: 0, imageHeight: 0)
    }

    func testTitleIsFirstLineWithWhitespaceCollapsed() {
        let code = item("\n\n    if let x  =\tfoo() {\n        bar()\n    }\n")
        XCTAssertEqual(code.listTitle, "if let x = foo() {")
        XCTAssertEqual(code.lineCount, 3, "surrounding blank lines do not count")
        XCTAssertEqual(item("single").lineCount, 1)
        XCTAssertEqual(item("/tmp/a.txt\n/tmp/b.txt", kind: .file).listTitle, "a.txt, b.txt")
        XCTAssertEqual(item("/tmp/a.txt\n/tmp/b.txt", kind: .file).lineCount, 1)
    }

    func testSearchKeyIsLowercasedText() {
        XCTAssertEqual(item("Hello Wörld").searchKey, "hello wörld")
    }
}

final class HotKeyParseTests: XCTestCase {
    func testParseAcceptsModifiersPlusOneKey() {
        let parsed = HotKey.parse("cmd+shift+v")
        XCTAssertEqual(parsed?.keyCode, 9)
        XCTAssertEqual(parsed?.modifiers, UInt32(cmdKey | shiftKey))
        XCTAssertNil(HotKey.parse("v"), "a bare key would fire on every keystroke")
        XCTAssertNil(HotKey.parse("cmd+shift"), "no key")
        XCTAssertNil(HotKey.parse("cmd+v+c"), "two keys")
        XCTAssertNil(HotKey.parse("cmd+f13"), "unknown key name")
    }

    func testFailureMessagesNameTheProblem() {
        XCTAssertTrue("\(HotKey.Failure.invalidSpec("zz"))".contains("zz"))
        XCTAssertTrue("\(HotKey.Failure.registrationFailed("cmd+shift+v", -9878))".contains("⇧⌘V"))
    }
}
