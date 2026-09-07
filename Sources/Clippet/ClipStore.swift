import AppKit
import Combine

@MainActor
final class ClipStore: ObservableObject {
    /// Newest first (by last use); every mutation updates this in place instead of
    /// re-reading the whole table, which would drag every thumbnail back from disk.
    @Published private(set) var items: [ClipItem] = [] {
        didSet { refilter() }
    }
    @Published var query = "" {
        didSet {
            refilter()
            resetSelection()
        }
    }
    @Published var selectedID: Int64?
    /// Bumped by the panel controller on every show; PanelView watches it to grab search focus.
    @Published var focusToken = 0
    /// True while ⌘ is down with the panel open; rows then show their ⌘1–⌘9 shortcut.
    @Published var commandHeld = false

    /// Filtered views, recomputed only when `items` or `query` change — never per row render.
    private(set) var pinnedFiltered: [ClipItem] = []
    private(set) var recentFiltered: [ClipItem] = []
    /// Flat navigation order: pinned section first, then history.
    private(set) var visibleItems: [ClipItem] = []

    let config: Config
    private let db: Database

    init(config: Config, db: Database) {
        self.config = config
        self.db = db
        items = db.loadAll()
        refilter()
    }

    // MARK: - Filtering

    var selectedItem: ClipItem? {
        visibleItems.first { $0.id == selectedID } ?? visibleItems.first
    }

    private func refilter() {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [ClipItem]
        if needle.isEmpty {
            filtered = items
        } else {
            // Images carry no searchable text, so they only show up on an empty query.
            filtered = items.filter { $0.kind != .image && $0.searchKey.contains(needle) }
        }
        pinnedFiltered = filtered.filter(\.pinned)
        recentFiltered = filtered.filter { !$0.pinned }
        visibleItems = pinnedFiltered + recentFiltered
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
        let now = capture.capturedAt
        guard let result = db.upsert(kind: capture.kind,
                                     hash: capture.hash,
                                     text: capture.text,
                                     data: capture.kind == .image ? capture.imageData : nil,
                                     thumb: capture.thumbnail,
                                     imageWidth: capture.imageSize.width,
                                     imageHeight: capture.imageSize.height,
                                     appBundleID: capture.sourceBundleID,
                                     now: now) else { return }

        var updated = items
        switch result {
        case .touched(let id):
            if let index = updated.firstIndex(where: { $0.id == id }) {
                var moved = updated.remove(at: index)
                moved.lastUsedAt = max(moved.lastUsedAt, now)
                Self.insert(moved, into: &updated)
            } else {
                // Memory drifted from disk (e.g. a second instance wrote to the same file).
                updated = db.loadAll()
            }
        case .inserted(let id):
            Self.insert(ClipItem(id: id,
                                 kind: capture.kind,
                                 hash: capture.hash,
                                 text: capture.text,
                                 pinned: false,
                                 createdAt: now,
                                 lastUsedAt: now,
                                 appBundleID: capture.sourceBundleID,
                                 thumbnail: capture.thumbnail,
                                 imageWidth: capture.imageSize.width,
                                 imageHeight: capture.imageSize.height), into: &updated)
            let evicted = Set(db.evict(keeping: config.maxItems))
            if !evicted.isEmpty {
                updated.removeAll { evicted.contains($0.id) }
            }
        }
        items = updated
        if selectedID == nil { resetSelection() }
    }

    /// Keeps `items` ordered newest-first. Image captures arrive after background processing,
    /// so a text copied in the meantime may already sit above them.
    private static func insert(_ item: ClipItem, into list: inout [ClipItem]) {
        let index = list.firstIndex { $0.lastUsedAt <= item.lastUsedAt } ?? list.endIndex
        list.insert(item, at: index)
    }

    // MARK: - Item actions

    func togglePin(_ item: ClipItem) {
        db.setPinned(!item.pinned, id: item.id)
        update(id: item.id) { $0.pinned.toggle() }
        selectedID = item.id
    }

    func delete(_ item: ClipItem) {
        let previousIndex = visibleItems.firstIndex { $0.id == item.id }
        db.delete(id: item.id)
        items.removeAll { $0.id == item.id }
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
        let now = Date()
        db.touch(id: item.id, at: now)
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items
        var moved = updated.remove(at: index)
        moved.lastUsedAt = now
        updated.insert(moved, at: 0)
        items = updated
    }

    func imageData(for item: ClipItem) -> Data? {
        db.imageData(id: item.id)
    }

    private func update(id: Int64, _ change: (inout ClipItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var updated = items
        change(&updated[index])
        items = updated
    }
}
