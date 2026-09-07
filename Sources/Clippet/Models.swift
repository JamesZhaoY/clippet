import AppKit

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
    }

    var fileURLs: [URL] {
        guard kind == .file else { return [] }
        return text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }

    var listTitle: String {
        switch kind {
        case .text:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        case .image:
            return "Image \(imageWidth)×\(imageHeight)"
        case .file:
            return fileURLs.map(\.lastPathComponent).joined(separator: ", ")
        }
    }
}

/// Downscales PNG data to a JPEG thumbnail capped at `maxDimension` on the long edge.
/// Returns the original data when it is already small enough.
func makeThumbnail(png: Data, maxDimension: CGFloat = 512) -> Data? {
    guard let source = NSImage(data: png) else { return nil }
    let size = source.size
    guard size.width > 0, size.height > 0 else { return nil }
    let scale = min(1, maxDimension / max(size.width, size.height))
    if scale >= 1 { return png }
    let target = NSSize(width: max(1, floor(size.width * scale)),
                        height: max(1, floor(size.height * scale)))
    let scaled = NSImage(size: target, flipped: false) { rect in
        source.draw(in: rect)
        return true
    }
    guard let tiff = scaled.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
}
