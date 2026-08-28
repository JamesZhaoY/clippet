import Foundation

struct Config {
    var hotkey = "cmd+shift+v"
    var maxItems = 500
    var maxImageBytes = 10 * 1024 * 1024
    var pollIntervalMs = 300
    /// Reserved for v2; not enforced yet.
    var excludedApps: [String] = []

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clippet", isDirectory: true)
    }

    static var fileURL: URL {
        directory.appendingPathComponent("config.json")
    }

    /// Missing file: defaults are written out so the user has something to edit.
    /// Missing keys fall back to defaults so a partial file stays valid.
    static func load() -> Config {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var config = Config()
        guard let data = try? Data(contentsOf: fileURL) else {
            config.writeDefaultFile()
            return config
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            NSLog("Clippet: config.json is not valid JSON, using defaults")
            return config
        }
        if let value = json["hotkey"] as? String { config.hotkey = value }
        if let value = json["maxItems"] as? Int { config.maxItems = value }
        if let value = json["maxImageBytes"] as? Int { config.maxImageBytes = value }
        if let value = json["pollIntervalMs"] as? Int { config.pollIntervalMs = value }
        if let value = json["excludedApps"] as? [String] { config.excludedApps = value }
        return config
    }

    private func writeDefaultFile() {
        let json: [String: Any] = [
            "hotkey": hotkey,
            "maxItems": maxItems,
            "maxImageBytes": maxImageBytes,
            "pollIntervalMs": pollIntervalMs,
            "excludedApps": excludedApps,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: Config.fileURL)
    }
}
