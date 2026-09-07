import SQLite3
import XCTest
@testable import Clippet

final class DatabaseTests: XCTestCase {
    private var tmp: TempDir!

    override func setUp() {
        tmp = TempDir()
    }

    override func tearDown() {
        tmp = nil
    }

    private func insert(_ db: Database, _ text: String, at date: Date = Date(),
                        data: Data? = nil) -> Int64 {
        let result = db.upsert(kind: .text, hash: PasteboardCapture.contentHash(kind: .text, text: text),
                               text: text, data: data, thumb: nil, imageWidth: 0, imageHeight: 0,
                               appBundleID: nil, now: date)
        guard case .inserted(let id)? = result else {
            XCTFail("expected insert for \(text), got \(String(describing: result))")
            return -1
        }
        return id
    }

    func testFreshDatabaseIsVersionedWithWALAndIncrementalVacuum() throws {
        let path = tmp.path("fresh.sqlite3")
        let db = try Database(path: path)
        XCTAssertEqual(db.scalarInt("PRAGMA user_version;"), Int(Database.schemaVersion))
        XCTAssertEqual(db.scalarInt("PRAGMA auto_vacuum;"), 2, "2 = INCREMENTAL")

        _ = insert(db, "hello")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path + "-wal"), "writes should go through a WAL")
    }

    func testUpsertTouchesDuplicatesInsteadOfInserting() throws {
        let db = try Database(path: tmp.path("dup.sqlite3"))
        let first = insert(db, "same", at: Date(timeIntervalSince1970: 1_000))

        let later = Date(timeIntervalSince1970: 2_000)
        let result = db.upsert(kind: .text, hash: PasteboardCapture.contentHash(kind: .text, text: "same"),
                               text: "same", data: nil, thumb: nil, imageWidth: 0, imageHeight: 0,
                               appBundleID: nil, now: later)
        guard case .touched(let id)? = result else { return XCTFail("expected touch, got \(String(describing: result))") }
        XCTAssertEqual(id, first)
        XCTAssertEqual(db.count(), 1)
        XCTAssertEqual(db.loadAll().first?.lastUsedAt, later)
    }

    func testEvictReturnsOldestUnpinnedIds() throws {
        let db = try Database(path: tmp.path("evict.sqlite3"))
        var ids: [Int64] = []
        for i in 0..<5 {
            ids.append(insert(db, "item \(i)", at: Date(timeIntervalSince1970: Double(i))))
        }
        db.setPinned(true, id: ids[0]) // oldest, but pinned: must survive

        let evicted = db.evict(keeping: 3)
        XCTAssertEqual(Set(evicted), Set([ids[1], ids[2]]))
        XCTAssertEqual(db.count(), 3)
        XCTAssertEqual(Set(db.loadAll().map(\.id)), Set([ids[0], ids[3], ids[4]]))
        XCTAssertEqual(db.evict(keeping: 3), [], "nothing to evict once under the cap")
    }

    func testDeletingLargeRowsShrinksTheFile() throws {
        let path = tmp.path("shrink.sqlite3")
        let db = try Database(path: path)
        let blob = Data(repeating: 0xAB, count: 2 * 1024 * 1024)
        let id = insert(db, "big", data: blob)
        db.close()
        let populated = fileSize(path)
        XCTAssertGreaterThan(populated, 2 * 1024 * 1024)

        let reopened = try Database(path: path)
        reopened.delete(id: id)
        XCTAssertEqual(reopened.scalarInt("PRAGMA freelist_count;"), 0, "incremental_vacuum should reclaim freed pages")
        reopened.close() // checkpoint applies the truncation to the main file
        XCTAssertLessThan(fileSize(path), 200 * 1024)
    }

    func testLegacyUnversionedDatabaseIsMigratedAndCompacted() throws {
        let path = tmp.path("legacy.sqlite3")
        createLegacyDatabase(at: path)
        XCTAssertGreaterThan(fileSize(path), 1024 * 1024, "legacy file keeps its high-water mark")

        let db = try Database(path: path)
        XCTAssertEqual(db.scalarInt("PRAGMA user_version;"), 1)
        XCTAssertEqual(db.scalarInt("PRAGMA auto_vacuum;"), 2)
        XCTAssertEqual(db.scalarInt("PRAGMA freelist_count;"), 0, "VACUUM should have compacted the file")
        let items = db.loadAll()
        XCTAssertEqual(items.map(\.text), ["kept"], "existing rows survive the migration")
        db.close()
        XCTAssertLessThan(fileSize(path), 200 * 1024)
    }

    /// Reproduces a v0.1 file: default journal, no auto_vacuum, no user_version, and a pile
    /// of free pages left behind by a cleared history.
    private func createLegacyDatabase(at path: String) {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &handle), SQLITE_OK)
        let sql = """
        CREATE TABLE items(
            id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, hash TEXT NOT NULL UNIQUE,
            text TEXT NOT NULL DEFAULT '', data BLOB, thumb BLOB,
            img_w INTEGER NOT NULL DEFAULT 0, img_h INTEGER NOT NULL DEFAULT 0,
            pinned INTEGER NOT NULL DEFAULT 0, created_at REAL NOT NULL, last_used_at REAL NOT NULL,
            app_bundle_id TEXT);
        CREATE INDEX idx_items_last_used ON items(last_used_at);
        INSERT INTO items(kind, hash, text, data, created_at, last_used_at)
            VALUES('image', 'h1', '', zeroblob(1500000), 1, 1);
        INSERT INTO items(kind, hash, text, created_at, last_used_at) VALUES('text', 'h2', 'kept', 2, 2);
        DELETE FROM items WHERE hash = 'h1';
        """
        XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)
    }
}
