import os

/// Unified logging, one category per subsystem area. Follow along with:
///   log stream --predicate 'subsystem == "com.zhaozhanyang.Clippet"' --level info
enum Log {
    private static let subsystem = "com.zhaozhanyang.Clippet"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let database = Logger(subsystem: subsystem, category: "database")
    static let pasteboard = Logger(subsystem: subsystem, category: "pasteboard")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let paste = Logger(subsystem: subsystem, category: "paste")
}
