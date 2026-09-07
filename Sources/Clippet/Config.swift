import Foundation

struct Config {
    var hotkey = Config.defaultHotkey
    var maxItems = 500
    var maxImageBytes = 10 * 1024 * 1024
    /// Text copies above this many UTF-8 bytes are not recorded: a pasted log file would
    /// otherwise be hashed, searched and laid out in full on every keystroke.
    var maxTextBytes = 1_000_000
    var pollIntervalMs = 300
    /// Reserved for v2; not enforced yet.
    var excludedApps: [String] = []

    static let defaultHotkey = "cmd+shift+v"

    /// `CLIPPET_DATA_DIR` relocates config and database, so a test build can run next to the
    /// installed app without touching its history.
    static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["CLIPPET_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clippet", isDirectory: true)
    }

    static var fileURL: URL {
        directory.appendingPathComponent("config.json")
    }

    /// Missing file: defaults are written out so the user has something to edit.
    static func load() -> Config {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: fileURL) else {
            let config = Config()
            config.writeDefaultFile()
            return config
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            Log.app.error("config.json is not valid JSON, using defaults")
            return Config()
        }
        return Config(json: json)
    }

    /// Missing keys fall back to defaults so a partial file stays valid; out-of-range values
    /// are clamped so a typo cannot switch eviction off or spin the poller.
    init(json: [String: Any]) {
        self.init()
        if let value = json["hotkey"] as? String, !value.isEmpty { hotkey = value }
        if let value = json["maxItems"] as? Int { maxItems = value.clamped(to: 1...100_000) }
        if let value = json["maxImageBytes"] as? Int { maxImageBytes = max(0, value) }
        if let value = json["maxTextBytes"] as? Int { maxTextBytes = value.clamped(to: 1_000...100_000_000) }
        if let value = json["pollIntervalMs"] as? Int { pollIntervalMs = value.clamped(to: 50...5_000) }
        if let value = json["excludedApps"] as? [String] { excludedApps = value }
    }

    init() {}

    private func writeDefaultFile() {
        let json: [String: Any] = [
            "hotkey": hotkey,
            "maxItems": maxItems,
            "maxImageBytes": maxImageBytes,
            "maxTextBytes": maxTextBytes,
            "pollIntervalMs": pollIntervalMs,
            "excludedApps": excludedApps,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: Config.fileURL)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
