import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let store: ClipStore
    private let watcher: PasteboardWatcher
    private let togglePanel: () -> Void

    init(store: ClipStore, watcher: PasteboardWatcher, togglePanel: @escaping () -> Void) {
        self.store = store
        self.watcher = watcher
        self.togglePanel = togglePanel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Clippet")
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePanel()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let pause = NSMenuItem(title: "Pause Recording", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.state = watcher.isPaused ? .on : .off
        menu.addItem(pause)

        let openConfig = NSMenuItem(title: "Open Config File", action: #selector(openConfigFile), keyEquivalent: "")
        openConfig.target = self
        menu.addItem(openConfig)

        let clear = NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Clippet",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        // Transient menu assignment: the status item shows a menu on this click only,
        // so the left click keeps toggling the panel instead of opening the menu.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func togglePause() {
        watcher.isPaused.toggle()
    }

    @objc private func openConfigFile() {
        NSWorkspace.shared.open(Config.fileURL)
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear all clipboard history?"
        alert.informativeText = "This removes every item, including pinned ones. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearAll()
        }
    }
}
