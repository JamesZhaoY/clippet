import AppKit
import Combine
import CryptoKit

@MainActor
final class ClipStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []
    @Published var query = "" {
        didSet { resetSelection() }
    }
    @Published var selectedID: Int64?
    /// Bumped by the panel controller on every show; PanelView watches it to grab search focus.
    @Published var focusToken = 0

    let config: Config
    private let db: Database

    init(config: Config, db: Database) {
        self.config = config
        self.db = db
        items = db.loadAll()
    }

    // MARK: - Filtering

    var pinnedFiltered: [ClipItem] { filtered.filter(\.pinned) }
    var recentFiltered: [ClipItem] { filtered.filter { !$0.pinned } }
    /// Flat navigation order: pinned section first, then history.
    var visibleItems: [ClipItem] { pinnedFiltered + recentFiltered }

    var selectedItem: ClipItem? {
        visibleItems.first { $0.id == selectedID } ?? visibleItems.first
    }

    private var filtered: [ClipItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        // Images carry no searchable text, so they only show up on an empty query.
        return items.filter { $0.kind != .image && $0.text.localizedCaseInsensitiveContains(trimmed) }
    }

    // MARK: - Selection

    func resetSelection() {
        selectedID = visibleItems.first?.id
    }

    func moveSelection(by delta: Int) {
        let list = visibleItems
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + delta, 0), list.count - 1)
        selectedID = list[next].id
    }

    // MARK: - Capture

    func handle(_ capture: PasteboardCapture) {
        let hash: String
        switch capture.kind {
        case .image:
            hash = sha256(capture.imageData ?? Data())
        case .text, .file:
            hash = sha256(Data("\(capture.kind.rawValue):\(capture.text)".utf8))
        }
        var thumb: Data?
        if capture.kind == .image, let data = capture.imageData {
            thumb = makeThumbnail(png: data)
        }
        db.upsert(kind: capture.kind,
                  hash: hash,
                  text: capture.text,
                  data: capture.kind == .image ? capture.imageData : nil,
                  thumb: thumb,
                  imageWidth: capture.imageSize.width,
                  imageHeight: capture.imageSize.height,
                  appBundleID: capture.sourceBundleID,
                  now: Date())
        db.evict(keeping: config.maxItems)
        items = db.loadAll()
        if selectedID == nil { resetSelection() }
    }

    // MARK: - Item actions

    func togglePin(_ item: ClipItem) {
        db.setPinned(!item.pinned, id: item.id)
        items = db.loadAll()
        selectedID = item.id
    }

    func delete(_ item: ClipItem) {
        let previousIndex = visibleItems.firstIndex { $0.id == item.id }
        db.delete(id: item.id)
        items = db.loadAll()
        let list = visibleItems
        if let previousIndex {
            selectedID = list.indices.contains(previousIndex) ? list[previousIndex].id : list.last?.id
        }
    }

    func clearAll() {
        db.clearAll()
        items = []
        selectedID = nil
    }

    func touch(_ item: ClipItem) {
        db.touch(id: item.id, at: Date())
        items = db.loadAll()
    }

    func imageData(for item: ClipItem) -> Data? {
        db.imageData(id: item.id)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
