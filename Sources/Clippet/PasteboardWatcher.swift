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
    let thumbnail: Data?
    let sourceBundleID: String?
    /// When the change was noticed. Image captures finish processing later and must still
    /// take their place in history by the moment they were copied.
    let capturedAt: Date

    static func text(_ string: String, source: String?, at date: Date = Date()) -> PasteboardCapture {
        PasteboardCapture(kind: .text, hash: contentHash(kind: .text, text: string), text: string,
                          imageData: nil, imageSize: (0, 0), thumbnail: nil,
                          sourceBundleID: source, capturedAt: date)
    }

    static func files(_ urls: [URL], source: String?, at date: Date = Date()) -> PasteboardCapture {
        let text = urls.map(\.path).joined(separator: "\n")
        return PasteboardCapture(kind: .file, hash: contentHash(kind: .file, text: text), text: text,
                                 imageData: nil, imageSize: (0, 0), thumbnail: nil,
                                 sourceBundleID: source, capturedAt: date)
    }

    static func image(_ processed: ImageCodec.Processed, source: String?, at date: Date = Date()) -> PasteboardCapture {
        PasteboardCapture(kind: .image, hash: processed.hash, text: "",
                          imageData: processed.png, imageSize: (processed.width, processed.height),
                          thumbnail: processed.thumbnail, sourceBundleID: source, capturedAt: date)
    }

    static func contentHash(kind: ClipKind, text: String) -> String {
        SHA256.hash(data: Data("\(kind.rawValue):\(text)".utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Runs the decode → PNG → hash → thumbnail chain for one image at a time, off the main
/// thread. Being an actor, a burst of copies queues up instead of fanning out across cores.
actor ImageProcessor {
    func process(_ raw: Data, maxBytes: Int) -> ImageCodec.Processed? {
        ImageCodec.process(raw, maxBytes: maxBytes)
    }
}

@MainActor
final class PasteboardWatcher: NSObject, ObservableObject {
    var onCapture: ((PasteboardCapture) -> Void)?
    /// While paused, copies are ignored; the change counter keeps tracking so nothing copied
    /// during the pause is recorded retroactively on resume.
    @Published var isPaused = false
    /// The most recent image still being processed; tests await it.
    private(set) var pendingImageWork: Task<Void, Never>?

    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?
    private let maxImageBytes: Int
    private let maxTextBytes: Int
    private let processor = ImageProcessor()

    private static let skippedTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        .clippetOrigin,
    ]

    init(pasteboard: NSPasteboard = .general, maxImageBytes: Int, maxTextBytes: Int) {
        self.pasteboard = pasteboard
        self.maxImageBytes = maxImageBytes
        self.maxTextBytes = maxTextBytes
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
        let capturedAt = Date()

        // File copies also carry an icon image and the file name as text, so files go first.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            onCapture?(.files(urls, source: source, at: capturedAt))
            return
        }

        let text = usableText()
        let hasImage = types.contains(.png) || types.contains(.tiff)

        // Spreadsheets and word processors put a bitmap rendering next to the copied text; the
        // text is what the user meant. The exception is "Copy Image" in browsers, which ships
        // the image's URL as plain text — a lone URL next to an image means the image.
        if let text, !(hasImage && Self.isSingleURL(text)) {
            onCapture?(.text(text, source: source, at: capturedAt))
            return
        }
        if hasImage, let raw = imageData() {
            // Decoding, re-encoding, hashing and thumbnailing run off the main thread; an
            // image that turns out too large falls back to the URL text, if any.
            pendingImageWork = Task { [processor, maxImageBytes] in
                if let processed = await processor.process(raw, maxBytes: maxImageBytes) {
                    onCapture?(.image(processed, source: source, at: capturedAt))
                } else if let text {
                    onCapture?(.text(text, source: source, at: capturedAt))
                } else {
                    Log.pasteboard.info("image of \(raw.count) raw bytes skipped (undecodable or over maxImageBytes)")
                }
            }
            return
        }
        if let text {
            onCapture?(.text(text, source: source, at: capturedAt))
        }
    }

    private func usableText() -> String? {
        guard let string = pasteboard.string(forType: .string),
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let bytes = string.utf8.count
        guard bytes <= maxTextBytes else {
            Log.pasteboard.info("text copy of \(bytes) bytes exceeds maxTextBytes, skipped")
            return nil
        }
        return string
    }

    /// Raw PNG/TIFF bytes, or nil when images are disabled or the payload is absurdly large
    /// for the configured limit (a TIFF of that size cannot compress below it).
    private func imageData() -> Data? {
        guard maxImageBytes > 0,
              let raw = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) else { return nil }
        guard raw.count <= 32 * maxImageBytes else {
            Log.pasteboard.info("image of \(raw.count) raw bytes skipped before decoding")
            return nil
        }
        return raw
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
