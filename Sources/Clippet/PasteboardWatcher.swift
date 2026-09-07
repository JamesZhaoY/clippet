import AppKit
import CryptoKit

extension NSPasteboard.PasteboardType {
    /// Attached to everything Clippet itself puts on the pasteboard, so the watcher can tell
    /// its own writes apart from user copies.
    static let clippetOrigin = NSPasteboard.PasteboardType("com.zhaozhanyang.clippet.origin")
}

struct PasteboardCapture {
    let kind: ClipKind
    /// Content identity used for deduplication.
    let hash: String
    let text: String
    /// Normalized PNG for images, nil otherwise.
    let imageData: Data?
    let imageSize: (width: Int, height: Int)
    let sourceBundleID: String?

    static func text(_ string: String, source: String?) -> PasteboardCapture {
        PasteboardCapture(kind: .text, hash: contentHash(kind: .text, text: string), text: string,
                          imageData: nil, imageSize: (0, 0), sourceBundleID: source)
    }

    static func files(_ urls: [URL], source: String?) -> PasteboardCapture {
        let text = urls.map(\.path).joined(separator: "\n")
        return PasteboardCapture(kind: .file, hash: contentHash(kind: .file, text: text), text: text,
                                 imageData: nil, imageSize: (0, 0), sourceBundleID: source)
    }

    /// Images are identified by their decoded pixels, not by the encoded file: PNG encoding
    /// is not byte-stable across passes, so hashing the bytes would make the same picture
    /// look new every time it is re-encoded.
    static func image(rep: NSBitmapImageRep, png: Data, source: String?) -> PasteboardCapture {
        PasteboardCapture(kind: .image, hash: pixelHash(rep) ?? sha256(png), text: "",
                          imageData: png, imageSize: (rep.pixelsWide, rep.pixelsHigh),
                          sourceBundleID: source)
    }

    static func contentHash(kind: ClipKind, text: String) -> String {
        sha256(Data("\(kind.rawValue):\(text)".utf8))
    }

    static func pixelHash(_ rep: NSBitmapImageRep) -> String? {
        guard !rep.isPlanar, let base = rep.bitmapData else { return nil }
        var hasher = SHA256()
        hasher.update(bufferPointer: UnsafeRawBufferPointer(start: base, count: rep.bytesPerRow * rep.pixelsHigh))
        hasher.update(data: Data("\(rep.pixelsWide)x\(rep.pixelsHigh)/\(rep.bitsPerPixel)".utf8))
        return hex(hasher.finalize())
    }

    private static func sha256(_ data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class PasteboardWatcher: NSObject {
    var onCapture: ((PasteboardCapture) -> Void)?
    /// While paused, copies are ignored; the change counter keeps tracking so nothing copied
    /// during the pause is recorded retroactively on resume.
    var isPaused = false

    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?
    private let maxImageBytes: Int

    private static let skippedTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        .clippetOrigin,
    ]

    init(pasteboard: NSPasteboard = .general, maxImageBytes: Int) {
        self.pasteboard = pasteboard
        self.maxImageBytes = maxImageBytes
        lastChangeCount = pasteboard.changeCount
        super.init()
    }

    func start(intervalMs: Int) {
        let interval = max(0.05, Double(intervalMs) / 1000)
        timer = Timer.scheduledTimer(timeInterval: interval,
                                     target: self,
                                     selector: #selector(tick),
                                     userInfo: nil,
                                     repeats: true)
    }

    @objc private func tick() {
        poll()
    }

    /// One polling step; exposed so tests can drive the watcher without a timer.
    func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard !isPaused else { return }

        let types = pasteboard.types ?? []
        guard !types.contains(where: { Self.skippedTypes.contains($0) }) else { return }

        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // File copies also carry an icon image and the file name as text, so files go first.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            onCapture?(.files(urls, source: source))
            return
        }

        let string = pasteboard.string(forType: .string)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let hasImage = types.contains(.png) || types.contains(.tiff)

        // Spreadsheets and word processors put a bitmap rendering next to the copied text; the
        // text is what the user meant. The exception is "Copy Image" in browsers, which ships
        // the image's URL as plain text — a lone URL next to an image means the image.
        if let string, !(hasImage && Self.isSingleURL(string)) {
            onCapture?(.text(string, source: source))
            return
        }
        if hasImage, let capture = imageCapture(source: source) {
            onCapture?(capture)
            return
        }
        if let string {
            onCapture?(.text(string, source: source))
        }
    }

    private func imageCapture(source: String?) -> PasteboardCapture? {
        guard let raw = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: raw),
              let png = rep.representation(using: .png, properties: [:]),
              png.count <= maxImageBytes else { return nil }
        return .image(rep: rep, png: png, source: source)
    }

    nonisolated static func isSingleURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: trimmed),
              url.scheme != nil else { return false }
        return url.host != nil || trimmed.lowercased().hasPrefix("data:")
    }
}
