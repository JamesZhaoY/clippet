import AppKit
import XCTest
@testable import Clippet

final class ClipStoreTests: XCTestCase {
    private var tmp: TempDir!
    private var db: Database!

    override func setUpWithError() throws {
        tmp = TempDir()
        db = try Database(path: tmp.path("store.sqlite3"))
    }

    override func tearDown() {
        db = nil
        tmp = nil
    }

    @MainActor
    private func makeStore(maxItems: Int = 500) -> ClipStore {
        var config = Config()
        config.maxItems = maxItems
        return ClipStore(config: config, db: db)
    }

    /// The in-memory list must always equal what a cold start would load.
    @MainActor
    private func assertMatchesDisk(_ store: ClipStore, file: StaticString = #filePath, line: UInt = #line) {
        let memory = store.items
        let disk = db.loadAll()
        XCTAssertEqual(memory.map(\.id), disk.map(\.id), "memory drifted from disk", file: file, line: line)
        XCTAssertEqual(memory.map(\.pinned), disk.map(\.pinned), file: file, line: line)
    }

    @MainActor
    func testCapturesInsertNewestFirstAndDedupeByBumping() {
        let store = makeStore()
        store.handle(textCapture("alpha"))
        store.handle(textCapture("beta"))
        store.handle(textCapture("alpha"))

        XCTAssertEqual(store.items.map(\.text), ["alpha", "beta"])
        XCTAssertEqual(db.count(), 2)
        assertMatchesDisk(store)
    }

    @MainActor
    func testEvictionRemovesFromMemoryAndDisk() {
        let store = makeStore(maxItems: 3)
        for i in 0..<5 { store.handle(textCapture("item \(i)")) }

        XCTAssertEqual(store.items.map(\.text), ["item 4", "item 3", "item 2"])
        XCTAssertEqual(db.count(), 3)
        assertMatchesDisk(store)
    }

    @MainActor
    func testPinDeleteAndTouchStayInSyncWithDisk() {
        let store = makeStore()
        store.handle(textCapture("one"))
        store.handle(textCapture("two"))
        store.handle(textCapture("three"))
        let two = store.items.first { $0.text == "two" }!

        store.togglePin(two)
        XCTAssertEqual(store.pinnedFiltered.map(\.text), ["two"])
        XCTAssertEqual(store.recentFiltered.map(\.text), ["three", "one"])
        XCTAssertEqual(store.visibleItems.map(\.text), ["two", "three", "one"])
        assertMatchesDisk(store)

        store.touch(store.items.first { $0.text == "one" }!)
        XCTAssertEqual(store.items.map(\.text), ["one", "three", "two"], "touched item jumps to the top; the rest keep their order")
        assertMatchesDisk(store)

        store.delete(store.items.first { $0.text == "three" }!)
        XCTAssertEqual(store.items.map(\.text), ["one", "two"])
        assertMatchesDisk(store)

        store.clearAll()
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(db.count(), 0)
    }

    @MainActor
    func testFilterIsCaseInsensitiveAndHidesImagesWhileSearching() {
        let store = makeStore()
        store.handle(textCapture("Hello World"))
        store.handle(imageCapture(makePNG(width: 8, height: 8)))
        store.handle(textCapture("other"))

        store.query = "hello"
        XCTAssertEqual(store.visibleItems.map(\.text), ["Hello World"])
        XCTAssertEqual(store.selectedItem?.text, "Hello World")

        store.query = "  WORLD "
        XCTAssertEqual(store.visibleItems.map(\.text), ["Hello World"])

        store.query = ""
        XCTAssertEqual(store.visibleItems.count, 3)
        XCTAssertEqual(store.visibleItems.first?.text, "other")
    }

    @MainActor
    func testLateImageCaptureIsPlacedByItsCopyTimeNotArrival() {
        let store = makeStore()
        let t0 = Date(timeIntervalSince1970: 1_000)
        store.handle(textCapture("first", at: t0))
        store.handle(textCapture("typed while the screenshot was processing", at: t0 + 2))
        // The screenshot was copied between the two texts but finishes processing last.
        store.handle(imageCapture(makePNG(width: 8, height: 8), at: t0 + 1))

        XCTAssertEqual(store.items.map(\.kind), [.text, .image, .text])
        assertMatchesDisk(store)

        // Re-copying an item never moves it backwards in time.
        store.handle(textCapture("first", at: t0 - 100))
        XCTAssertEqual(store.items.last?.text, "first")
        XCTAssertEqual(store.items.last?.lastUsedAt, t0)
        assertMatchesDisk(store)
    }

    @MainActor
    func testImageIdentityIgnoresEncodingDifferences() {
        let store = makeStore()
        let original = makePNG(width: 32, height: 16)
        // What Clippet would find on the pasteboard after pasting the stored PNG and having it
        // re-encoded: different bytes, same pixels.
        let reencoded = NSBitmapImageRep(data: original)!.representation(using: .png, properties: [:])!

        store.handle(imageCapture(original))
        store.handle(imageCapture(reencoded))

        XCTAssertEqual(store.items.count, 1, "same pixels must dedupe even when bytes differ")
        XCTAssertNotEqual(
            imageCapture(original).hash,
            imageCapture(makePNG(width: 32, height: 16, seed: 0x90)).hash,
            "different pixels must not collide"
        )
        XCTAssertEqual(store.items.first?.imageWidth, 32)
        XCTAssertEqual(store.items.first?.imageHeight, 16)
        XCTAssertNotNil(store.items.first?.thumbnail)
        XCTAssertNotNil(store.imageData(for: store.items.first!))
    }
}
