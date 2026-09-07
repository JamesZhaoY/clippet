import AppKit
import XCTest
@testable import Clippet

/// Drives the watcher against a private named pasteboard, so the user's real clipboard is
/// never touched.
final class PasteboardWatcherTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var tmp: TempDir!

    override func setUp() {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.zhaozhanyang.clippet.tests.\(UUID().uuidString)"))
        tmp = TempDir()
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
        tmp = nil
    }

    @MainActor
    private func captureAfterWriting(maxImageBytes: Int = 10 * 1024 * 1024,
                                     maxTextBytes: Int = 1_000_000,
                                     _ write: (NSPasteboard) -> Void) async -> PasteboardCapture? {
        let watcher = PasteboardWatcher(pasteboard: pasteboard, maxImageBytes: maxImageBytes, maxTextBytes: maxTextBytes)
        var captured: PasteboardCapture?
        watcher.onCapture = { captured = $0 }
        pasteboard.clearContents()
        write(pasteboard)
        watcher.poll()
        await watcher.pendingImageWork?.value
        return captured
    }

    @MainActor
    func testPlainTextIsCaptured() async {
        let capture = await captureAfterWriting { $0.setString("hello", forType: .string) }
        XCTAssertEqual(capture?.kind, .text)
        XCTAssertEqual(capture?.text, "hello")
        XCTAssertEqual(capture?.hash, PasteboardCapture.contentHash(kind: .text, text: "hello"))
    }

    @MainActor
    func testWhitespaceOnlyTextIsIgnored() async {
        let capture = await captureAfterWriting { $0.setString("  \n\t ", forType: .string) }
        XCTAssertNil(capture)
    }

    @MainActor
    func testOversizedTextIsSkipped() async {
        let big = String(repeating: "x", count: 5_000)
        let skipped = await captureAfterWriting(maxTextBytes: 1_000) { $0.setString(big, forType: .string) }
        XCTAssertNil(skipped)
        let kept = await captureAfterWriting(maxTextBytes: 5_000) { $0.setString(big, forType: .string) }
        XCTAssertEqual(kept?.text.count, 5_000, "the limit is inclusive")
    }

    @MainActor
    func testTextWinsOverBitmapRenderingOfTheSameCopy() async {
        // Numbers / Excel / Word put a TIFF snapshot of the selection next to the text.
        let capture = await captureAfterWriting {
            $0.setString("=SUM(A1:A3)", forType: .string)
            $0.setData(tiffData(fromPNG: makePNG(width: 20, height: 10)), forType: .tiff)
        }
        XCTAssertEqual(capture?.kind, .text)
        XCTAssertEqual(capture?.text, "=SUM(A1:A3)")
    }

    @MainActor
    func testImageIsProcessedOffTheMainThreadIntoNormalizedPNG() async {
        let png = makePNG(width: 20, height: 10)
        let capture = await captureAfterWriting {
            $0.setData(tiffData(fromPNG: png), forType: .tiff)
        }
        XCTAssertEqual(capture?.kind, .image)
        XCTAssertEqual(capture?.imageSize.width, 20)
        XCTAssertEqual(capture?.imageSize.height, 10)
        XCTAssertNotNil(capture?.thumbnail, "thumbnails are prepared with the capture, not by the store")
        XCTAssertNotNil(capture?.imageData.flatMap { ImageCodec.decode($0) })
        XCTAssertEqual(capture?.hash, ImageCodec.pixelHash(ImageCodec.decode(png)!),
                       "TIFF and PNG of the same pixels must share an identity")
    }

    @MainActor
    func testImageCaptureKeepsTheTimeOfTheCopyNotOfTheProcessing() async {
        let before = Date()
        let capture = await captureAfterWriting { $0.setData(makePNG(width: 4, height: 4), forType: .png) }
        let after = Date()
        XCTAssertNotNil(capture)
        XCTAssertGreaterThanOrEqual(capture!.capturedAt, before)
        XCTAssertLessThanOrEqual(capture!.capturedAt, after)
    }

    @MainActor
    func testLoneURLNextToAnImageMeansTheImage() async {
        // Safari "Copy Image" ships the image URL as plain text.
        let capture = await captureAfterWriting {
            $0.setString("https://example.com/cat.png", forType: .string)
            $0.setData(makePNG(width: 4, height: 4), forType: .png)
        }
        XCTAssertEqual(capture?.kind, .image)
    }

    @MainActor
    func testOversizedImageFallsBackToItsURLText() async {
        let capture = await captureAfterWriting(maxImageBytes: 10) {
            $0.setString("https://example.com/huge.png", forType: .string)
            $0.setData(makePNG(width: 64, height: 64), forType: .png)
        }
        XCTAssertEqual(capture?.kind, .text)
        let dropped = await captureAfterWriting(maxImageBytes: 10) { $0.setData(makePNG(width: 64, height: 64), forType: .png) }
        XCTAssertNil(dropped, "an oversized image with nothing else is dropped")
    }

    @MainActor
    func testImagesCanBeDisabled() async {
        let capture = await captureAfterWriting(maxImageBytes: 0) {
            $0.setString("https://example.com/cat.png", forType: .string)
            $0.setData(makePNG(width: 4, height: 4), forType: .png)
        }
        XCTAssertEqual(capture?.kind, .text, "with images off, the URL text is still worth keeping")
        let none = await captureAfterWriting(maxImageBytes: 0) { $0.setData(makePNG(width: 4, height: 4), forType: .png) }
        XCTAssertNil(none)
    }

    @MainActor
    func testFileURLsBeatTheirFinderNameText() async {
        let file = URL(fileURLWithPath: tmp.path("report.pdf"))
        FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
        let capture = await captureAfterWriting {
            $0.writeObjects([file as NSURL])
            $0.setString("report.pdf", forType: .string)
        }
        XCTAssertEqual(capture?.kind, .file)
        XCTAssertEqual(capture?.text, file.path)
    }

    @MainActor
    func testConcealedContentIsSkipped() async {
        let capture = await captureAfterWriting {
            $0.setString("hunter2", forType: .string)
            $0.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        }
        XCTAssertNil(capture)
    }

    @MainActor
    func testClippetsOwnWritesAreSkipped() async {
        let engine = PasteEngine(pasteboard: pasteboard)
        let item = ClipItem(id: 1, kind: .text, hash: "h", text: "from history", pinned: false,
                            createdAt: Date(), lastUsedAt: Date(), appBundleID: nil,
                            thumbnail: nil, imageWidth: 0, imageHeight: 0)
        let capture = await captureAfterWriting { _ in engine.write(item, imageData: nil) }
        XCTAssertNil(capture, "the store already bumped the item; re-capturing it is wasted work")
        XCTAssertEqual(pasteboard.string(forType: .string), "from history", "the tag must not disturb the payload")

        let file = URL(fileURLWithPath: tmp.path("a.txt"))
        FileManager.default.createFile(atPath: file.path, contents: Data())
        let fileItem = ClipItem(id: 2, kind: .file, hash: "f", text: file.path, pinned: false,
                                createdAt: Date(), lastUsedAt: Date(), appBundleID: nil,
                                thumbnail: nil, imageWidth: 0, imageHeight: 0)
        let fileCapture = await captureAfterWriting { _ in engine.write(fileItem, imageData: nil) }
        XCTAssertNil(fileCapture)
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        XCTAssertEqual(urls?.map(\.path), [file.path], "file URLs survive alongside the tag")
    }

    @MainActor
    func testPausedChangesAreNeverRecordedRetroactively() {
        let watcher = PasteboardWatcher(pasteboard: pasteboard, maxImageBytes: 1 << 20, maxTextBytes: 1 << 20)
        var captured: [String] = []
        watcher.onCapture = { captured.append($0.text) }

        watcher.isPaused = true
        pasteboard.clearContents()
        pasteboard.setString("secret while paused", forType: .string)
        watcher.poll()
        watcher.isPaused = false
        watcher.poll()
        XCTAssertEqual(captured, [])

        pasteboard.clearContents()
        pasteboard.setString("after resume", forType: .string)
        watcher.poll()
        XCTAssertEqual(captured, ["after resume"])
    }

    func testSingleURLDetection() {
        XCTAssertTrue(PasteboardWatcher.isSingleURL("https://example.com/a.png"))
        XCTAssertTrue(PasteboardWatcher.isSingleURL("  data:image/png;base64,AAAA  "))
        XCTAssertFalse(PasteboardWatcher.isSingleURL("see https://example.com"))
        XCTAssertFalse(PasteboardWatcher.isSingleURL("plain words"))
        XCTAssertFalse(PasteboardWatcher.isSingleURL("mailto:"))
    }
}
