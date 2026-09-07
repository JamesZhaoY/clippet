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
    /// The hotkey actually registered — the configured one, or the default after a fallback.
    private var effectiveHotkey = Config.defaultHotkey

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        guard !yieldToRunningInstance() else { return }

        config = Config.load()
        db = openDatabase()
        store = ClipStore(config: config, db: db)
        engine = PasteEngine()

        panel = PanelController(store: store)
        panel.onPaste = { [weak self] item in self?.deliver(item, simulatePaste: true) }
        panel.onCopyOnly = { [weak self] item in self?.deliver(item, simulatePaste: false) }

        watcher = PasteboardWatcher(maxImageBytes: config.maxImageBytes, maxTextBytes: config.maxTextBytes)
        watcher.onCapture = { [weak self] capture in self?.store.handle(capture) }
        watcher.start(intervalMs: config.pollIntervalMs)

        registerHotkey()
        statusItem = StatusItemController(store: store, watcher: watcher, hotkeySpec: effectiveHotkey) { [weak self] in
            self?.panel.toggle()
        }

        buildMainMenu()
        showAccessibilityOnboardingIfNeeded()
    }

    /// A second copy would poll the same pasteboard and lose the hotkey race. Hand off to
    /// the running one (it opens its panel) and quit — unless this run has its own data
    /// directory, which is how a development build is meant to run alongside the install.
    private func yieldToRunningInstance() -> Bool {
        guard ProcessInfo.processInfo.environment["CLIPPET_DATA_DIR"] == nil,
              let bundleID = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard let other = others.first else { return false }
        Log.app.notice("another instance is running (pid \(other.processIdentifier)); quitting")
        if let url = other.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        NSApp.terminate(nil)
        return true
    }

    /// Registers the configured hotkey, falling back to the default. Either failure is
    /// reported once: a silently missing hotkey looks exactly like a broken app.
    private func registerHotkey() {
        let toggle: () -> Void = { [weak self] in self?.panel.toggle() }
        do {
            hotKey = try HotKey(spec: config.hotkey, callback: toggle)
            effectiveHotkey = config.hotkey
            return
        } catch {
            Log.hotkey.error("\(String(describing: error), privacy: .public)")
            var message = "\(error)."
            if config.hotkey != Config.defaultHotkey {
                do {
                    hotKey = try HotKey(spec: Config.defaultHotkey, callback: toggle)
                    effectiveHotkey = Config.defaultHotkey
                    message += " Using \(HotKey.displaySymbols(for: Config.defaultHotkey)) instead."
                } catch let fallbackError {
                    Log.hotkey.error("\(String(describing: fallbackError), privacy: .public)")
                    message += " The default \(HotKey.displaySymbols(for: Config.defaultHotkey)) failed too: \(fallbackError)."
                }
            }
            if hotKey == nil {
                message += " The panel is still available from the menu bar icon."
            }
            let alert = NSAlert()
            alert.messageText = "Global hotkey problem"
            alert.informativeText = message + "\n\nEdit \"hotkey\" in config.json and restart Clippet."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate()
            alert.runModal()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show()
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        db?.close()
    }

    /// A database that cannot be opened must not turn into a silent, history-less session:
    /// say so, then fall back to an in-memory store so the panel still works until quit.
    private func openDatabase() -> Database {
        let url = Config.directory.appendingPathComponent("clippet.sqlite3")
        do {
            return try Database(url: url)
        } catch {
            Log.database.error("\(String(describing: error), privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "Clippet can't open its history database"
            alert.informativeText = """
            \(error)

            History will not be saved during this session. Check the permissions of \
            \(Config.directory.path), or move the file away to start fresh.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Continue Without Saving")
            NSApp.activate()
            alert.runModal()
            // ":memory:" cannot fail to open.
            return try! Database(path: ":memory:")
        }
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
        showShortcutsAlert(hotkeySpec: effectiveHotkey)
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
