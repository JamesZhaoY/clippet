import AppKit

struct PasteboardCapture {
    let kind: ClipKind
    let text: String
    let imageData: Data?
    let imageSize: (width: Int, height: Int)
    let sourceBundleID: String?
}

@MainActor
final class PasteboardWatcher: NSObject {
    var onCapture: ((PasteboardCapture) -> Void)?
    /// While paused, copies are ignored; on resume the change counter is resynced
    /// so whatever was copied during the pause is not retroactively recorded.
    var isPaused = false {
        didSet {
            if !isPaused { lastChangeCount = NSPasteboard.general.changeCount }
        }
    }

    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let maxImageBytes: Int

    private static let skippedTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
    ]

    init(maxImageBytes: Int) {
        self.maxImageBytes = maxImageBytes
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
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard !isPaused else { return }

        let types = pasteboard.types ?? []
        guard !types.contains(where: { Self.skippedTypes.contains($0) }) else { return }

        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // File copies also carry an icon image, so files are checked before images.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let text = urls.map(\.path).joined(separator: "\n")
            onCapture?(PasteboardCapture(kind: .file, text: text, imageData: nil,
                                         imageSize: (0, 0), sourceBundleID: source))
            return
        }

        if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: imageData) {
            guard let png = rep.representation(using: .png, properties: [:]),
                  png.count <= maxImageBytes else { return }
            onCapture?(PasteboardCapture(kind: .image, text: "", imageData: png,
                                         imageSize: (rep.pixelsWide, rep.pixelsHigh),
                                         sourceBundleID: source))
            return
        }

        if let string = pasteboard.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onCapture?(PasteboardCapture(kind: .text, text: string, imageData: nil,
                                         imageSize: (0, 0), sourceBundleID: source))
        }
    }
}
