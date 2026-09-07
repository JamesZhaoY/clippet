import AppKit
import XCTest
@testable import Clippet

final class ConfigTests: XCTestCase {
    func testMissingKeysKeepDefaults() {
        let config = Config(json: ["maxItems": 42])
        XCTAssertEqual(config.maxItems, 42)
        XCTAssertEqual(config.hotkey, Config.defaultHotkey)
        XCTAssertEqual(config.pollIntervalMs, 300)
        XCTAssertEqual(config.maxImageBytes, 10 * 1024 * 1024)
    }

    func testOutOfRangeValuesAreClamped() {
        let low = Config(json: ["maxItems": 0, "pollIntervalMs": 1, "maxImageBytes": -5, "hotkey": ""])
        XCTAssertEqual(low.maxItems, 1, "0 would disable eviction")
        XCTAssertEqual(low.pollIntervalMs, 50)
        XCTAssertEqual(low.maxImageBytes, 0)
        XCTAssertEqual(low.hotkey, Config.defaultHotkey)

        let high = Config(json: ["maxItems": 10_000_000, "pollIntervalMs": 60_000])
        XCTAssertEqual(high.maxItems, 100_000)
        XCTAssertEqual(high.pollIntervalMs, 5_000)
    }

    func testWrongTypesAreIgnored() {
        let config = Config(json: ["maxItems": "lots", "excludedApps": "com.example"])
        XCTAssertEqual(config.maxItems, 500)
        XCTAssertEqual(config.excludedApps, [])
    }
}

final class HotKeyTests: XCTestCase {
    func testDisplaySymbolsUseCanonicalModifierOrder() {
        XCTAssertEqual(HotKey.displaySymbols(for: "cmd+shift+v"), "⇧⌘V")
        XCTAssertEqual(HotKey.displaySymbols(for: "shift+ctrl+alt+command+space"), "⌃⌥⇧⌘Space")
        XCTAssertEqual(HotKey.displaySymbols(for: "Opt+Cmd+V"), "⌥⌘V")
    }

    func testMenuEquivalentRequiresAModifier() {
        let equivalent = HotKey.menuEquivalent(for: "cmd+shift+v")
        XCTAssertEqual(equivalent?.key, "v")
        XCTAssertEqual(equivalent?.modifiers, [.command, .shift])
        XCTAssertNil(HotKey.menuEquivalent(for: "v"))
    }
}
