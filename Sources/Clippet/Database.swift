import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class Database {
    private var db: OpaquePointer?

    init(url: URL) {
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            NSLog("Clippet: cannot open database at \(url.path)")
        }
        exec("""
        CREATE TABLE IF NOT EXISTS items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            hash TEXT NOT NULL UNIQUE,
            text TEXT NOT NULL DEFAULT '',
            data BLOB,
            thumb BLOB,
            img_w INTEGER NOT NULL DEFAULT 0,
            img_h INTEGER NOT NULL DEFAULT 0,
            pinned INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            last_used_at REAL NOT NULL,
            app_bundle_id TEXT
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_items_last_used ON items(last_used_at);")
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Queries

    /// Full image payloads stay on disk; rows carry only thumbnails.
    func loadAll() -> [ClipItem] {
        guard let stmt = prepare("""
        SELECT id, kind, hash, text, thumb, img_w, img_h, pinned, created_at, last_used_at, app_bundle_id
        FROM items ORDER BY last_used_at DESC;
        """) else { return [] }
        defer { sqlite3_finalize(stmt) }
        var items: [ClipItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var thumb: Data?
            if let blob = sqlite3_column_blob(stmt, 4) {
                thumb = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 4)))
            }
            var bundleID: String?
            if let cString = sqlite3_column_text(stmt, 10) {
                bundleID = String(cString: cString)
            }
            items.append(ClipItem(
                id: sqlite3_column_int64(stmt, 0),
                kind: ClipKind(rawValue: String(cString: sqlite3_column_text(stmt, 1))) ?? .text,
                hash: String(cString: sqlite3_column_text(stmt, 2)),
                text: String(cString: sqlite3_column_text(stmt, 3)),
                pinned: sqlite3_column_int(stmt, 7) != 0,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8)),
                lastUsedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9)),
                appBundleID: bundleID,
                thumbnail: thumb,
                imageWidth: Int(sqlite3_column_int(stmt, 5)),
                imageHeight: Int(sqlite3_column_int(stmt, 6))
            ))
        }
        return items
    }

    func imageData(id: Int64) -> Data? {
        guard let stmt = prepare("SELECT data FROM items WHERE id = ?;") else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_ROW, let blob = sqlite3_column_blob(stmt, 0) else { return nil }
        return Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 0)))
    }

    // MARK: - Mutations

    /// Inserts a new item, or bumps last_used_at when the same hash already exists
    /// (pinned state is preserved).
    func upsert(kind: ClipKind, hash: String, text: String, data: Data?, thumb: Data?,
                imageWidth: Int, imageHeight: Int, appBundleID: String?, now: Date) {
        if let existing = rowID(forHash: hash) {
            touch(id: existing, at: now)
            return
        }
        guard let stmt = prepare("""
        INSERT INTO items(kind, hash, text, data, thumb, img_w, img_h, pinned, created_at, last_used_at, app_bundle_id)
        VALUES(?,?,?,?,?,?,?,0,?,?,?);
        """) else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, kind.rawValue, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, hash, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 3, text, -1, sqliteTransient)
        bindBlob(stmt, 4, data)
        bindBlob(stmt, 5, thumb)
        sqlite3_bind_int(stmt, 6, Int32(imageWidth))
        sqlite3_bind_int(stmt, 7, Int32(imageHeight))
        sqlite3_bind_double(stmt, 8, now.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 9, now.timeIntervalSince1970)
        if let appBundleID {
            sqlite3_bind_text(stmt, 10, appBundleID, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, 10)
        }
        sqlite3_step(stmt)
    }

    func touch(id: Int64, at date: Date) {
        guard let stmt = prepare("UPDATE items SET last_used_at = ? WHERE id = ?;") else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, date.timeIntervalSince1970)
        sqlite3_bind_int64(stmt, 2, id)
        sqlite3_step(stmt)
    }

    func setPinned(_ pinned: Bool, id: Int64) {
        guard let stmt = prepare("UPDATE items SET pinned = ? WHERE id = ?;") else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, pinned ? 1 : 0)
        sqlite3_bind_int64(stmt, 2, id)
        sqlite3_step(stmt)
    }

    func delete(id: Int64) {
        guard let stmt = prepare("DELETE FROM items WHERE id = ?;") else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        sqlite3_step(stmt)
    }

    func clearAll() {
        exec("DELETE FROM items;")
    }

    /// Deletes the oldest unpinned items until the total row count is back under `cap`.
    /// Pinned items never count as eviction candidates, so the total can exceed `cap`
    /// when more than `cap` items are pinned.
    func evict(keeping cap: Int) {
        guard cap > 0 else { return }
        let overflow = count() - cap
        guard overflow > 0 else { return }
        guard let stmt = prepare("""
        DELETE FROM items WHERE id IN (
            SELECT id FROM items WHERE pinned = 0 ORDER BY last_used_at ASC LIMIT ?
        );
        """) else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(overflow))
        sqlite3_step(stmt)
    }

    // MARK: - Helpers

    private func rowID(forHash hash: String) -> Int64? {
        guard let stmt = prepare("SELECT id FROM items WHERE hash = ?;") else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, hash, -1, sqliteTransient)
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : nil
    }

    private func count() -> Int {
        guard let stmt = prepare("SELECT COUNT(*) FROM items;") else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    private func bindBlob(_ stmt: OpaquePointer?, _ index: Int32, _ data: Data?) {
        if let data, !data.isEmpty {
            _ = data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(stmt, index, bytes.baseAddress, Int32(bytes.count), sqliteTransient)
            }
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("Clippet: cannot prepare statement: \(sql)")
            return nil
        }
        return stmt
    }

    private func exec(_ sql: String) {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK, let error {
            NSLog("Clippet: sqlite error: \(String(cString: error))")
            sqlite3_free(error)
        }
    }
}
