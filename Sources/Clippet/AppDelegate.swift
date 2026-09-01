import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config = Config()
    private var db: Database!
    private var store: ClipStore!
    private var watcher: PasteboardWatcher!
    private var engine: PasteEngine!
    private var panel: PanelController!
    private var statusItem: StatusItemController!
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        config = Config.load()
        db = Database(url: Config.directory.appendingPathComponent("clippet.sqlite3"))
        store = ClipStore(config: config, db: db)
        engine = PasteEngine()

        panel = PanelController(store: store)
        panel.onPaste = { [weak self] item in self?.deliver(item, simulatePaste: true) }
        panel.onCopyOnly = { [weak self] item in self?.deliver(item, simulatePaste: false) }

        watcher = PasteboardWatcher(maxImageBytes: config.maxImageBytes)
        watcher.onCapture = { [weak self] capture in self?.store.handle(capture) }
        watcher.start(intervalMs: config.pollIntervalMs)

        statusItem = StatusItemController(store: store, watcher: watcher, hotkeySpec: config.hotkey) { [weak self] in
            self?.panel.toggle()
        }

        hotKey = HotKey(spec: config.hotkey) { [weak self] in self?.panel.toggle() }
        if hotKey == nil, config.hotkey != "cmd+shift+v" {
            hotKey = HotKey(spec: "cmd+shift+v") { [weak self] in self?.panel.toggle() }
        }

        buildMainMenu()
        showAccessibilityOnboardingIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show()
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func deliver(_ item: ClipItem, simulatePaste: Bool) {
        let imageData = item.kind == .image ? store.imageData(for: item) : nil
        if simulatePaste {
            engine.paste(item, imageData: imageData)
        } else {
            engine.write(item, imageData: imageData)
        }
        store.touch(item)
    }

    /// Without a main menu, ⌘C/⌘V/⌘A would not work inside Clippet's own search field.
    private func buildMainMenu() {
        let main = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Clippet",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Clippet",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        main.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        main.addItem(editMenuItem)

        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        let shortcuts = NSMenuItem(title: "Keyboard Shortcuts",
                                   action: #selector(showShortcutsSheet),
                                   keyEquivalent: "/")
        shortcuts.target = self
        helpMenu.addItem(shortcuts)
        helpMenuItem.submenu = helpMenu
        main.addItem(helpMenuItem)

        NSApp.mainMenu = main
    }

    @objc private func showShortcutsSheet() {
        showShortcutsAlert(hotkeySpec: config.hotkey)
    }

    /// One-time system prompt; afterwards the paste path shows its own alert on demand.
    private func showAccessibilityOnboardingIfNeeded() {
        let key = "didShowAccessibilityOnboarding"
        guard !UserDefaults.standard.bool(forKey: key), !AXIsProcessTrusted() else { return }
        UserDefaults.standard.set(true, forKey: key)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
