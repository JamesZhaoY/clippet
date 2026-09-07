import AppKit

/// Icon / display-name lookup by bundle id, cached — rows render on every selection change.
@MainActor
final class AppInfoCache {
    static let shared = AppInfoCache()

    private var icons: [String: NSImage?] = [:]
    private var names: [String: String?] = [:]

    func icon(forBundleID id: String?) -> NSImage? {
        guard let id else { return nil }
        if let cached = icons[id] { return cached }
        var icon: NSImage?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        }
        icons[id] = icon
        return icon
    }

    func name(forBundleID id: String?) -> String? {
        guard let id else { return nil }
        if let cached = names[id] { return cached }
        var name: String?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
           let bundle = Bundle(url: url) {
            name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        }
        let resolved = name ?? id.components(separatedBy: ".").last
        names[id] = resolved
        return resolved
    }
}

/// Decoded thumbnails and file icons, so scrolling does not re-decode JPEGs or hit the
/// disk for icons on every row render. Bounded by NSCache; entries are keyed by item id
/// (never reused) or file path.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let thumbnails: NSCache<NSNumber, NSImage> = {
        let cache = NSCache<NSNumber, NSImage>()
        cache.countLimit = 300
        return cache
    }()
    private let fileIcons: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()

    func thumbnail(for item: ClipItem) -> NSImage? {
        let key = NSNumber(value: item.id)
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let data = item.thumbnail, let image = NSImage(data: data) else { return nil }
        thumbnails.setObject(image, forKey: key)
        return image
    }

    func fileIcon(path: String) -> NSImage {
        let key = path as NSString
        if let cached = fileIcons.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        fileIcons.setObject(icon, forKey: key)
        return icon
    }
}

/// Compact relative time for list rows: "now", "5m", "3h", "2d", then "8/26".
func shortRelativeTime(from date: Date, to now: Date = Date()) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    if seconds < 60 { return "now" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h" }
    let days = hours / 24
    if days < 7 { return "\(days)d" }
    return date.formatted(.dateTime.month(.defaultDigits).day())
}

@MainActor
func showShortcutsAlert(hotkeySpec: String) {
    let symbols = HotKey.displaySymbols(for: hotkeySpec)
    let text = """
    Global
      \(symbols)  Open / close panel

    Panel
      Type          Search history
      ↑ ↓           Select item
      ⌘↑ ⌘↓         First / last item
      Page ↑ ↓      Move 8 items
      ↩             Paste into previous app
      ⌘↩            Copy to clipboard only
      ⌘1 … ⌘9       Paste the n-th listed item
      ⌘P            Pin / unpin
      ⌘⌫            Delete item
      Esc           Clear search, then close
      Double-click  Paste item
      Right-click   More actions
    """
    let label = NSTextField(labelWithString: text)
    label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    label.sizeToFit()

    let alert = NSAlert()
    alert.messageText = "Keyboard Shortcuts"
    alert.informativeText = "The global hotkey can be changed in config.json (restart to apply)."
    alert.accessoryView = label
    alert.addButton(withTitle: "OK")
    NSApp.activate()
    alert.runModal()
}
