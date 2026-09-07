import Foundation

enum ClipKind: String {
    case text
    case image
    case file
}

struct ClipItem: Identifiable {
    let id: Int64
    let kind: ClipKind
    let hash: String
    /// Text content; for .file, newline-joined absolute paths; empty for .image.
    var text: String
    var pinned: Bool
    let createdAt: Date
    var lastUsedAt: Date
    let appBundleID: String?
    var thumbnail: Data?
    var imageWidth: Int
    var imageHeight: Int
    /// Lowercased `text`, computed once so filtering does not re-fold every item per keystroke.
    let searchKey: String
    /// One-line label for the list, computed once: first non-empty line with runs of
    /// whitespace collapsed, so indented code does not show as a blank row.
    let listTitle: String
    /// Number of lines in a text item (1 for anything else).
    let lineCount: Int

    init(id: Int64, kind: ClipKind, hash: String, text: String, pinned: Bool,
         createdAt: Date, lastUsedAt: Date, appBundleID: String?,
         thumbnail: Data?, imageWidth: Int, imageHeight: Int) {
        self.id = id
        self.kind = kind
        self.hash = hash
        self.text = text
        self.pinned = pinned
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.appBundleID = appBundleID
        self.thumbnail = thumbnail
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.searchKey = kind == .image ? "" : text.lowercased()
        switch kind {
        case .text:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            listTitle = Self.collapseWhitespace(trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? "")
            lineCount = trimmed.utf8.lazy.filter { $0 == UInt8(ascii: "\n") }.count + 1
        case .image:
            listTitle = "Image \(imageWidth)×\(imageHeight)"
            lineCount = 1
        case .file:
            listTitle = text.split(separator: "\n").map { URL(fileURLWithPath: String($0)).lastPathComponent }
                .joined(separator: ", ")
            lineCount = 1
        }
    }

    var fileURLs: [URL] {
        guard kind == .file else { return [] }
        return text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }

    private static func collapseWhitespace(_ line: String) -> String {
        line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
