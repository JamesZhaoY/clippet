import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let store: ClipStore
    private let watcher: PasteboardWatcher
    private let hotkeySpec: String
    private let togglePanel: () -> Void
    private var pauseObserver: AnyCancellable?

    init(store: ClipStore, watcher: PasteboardWatcher, hotkeySpec: String, togglePanel: @escaping () -> Void) {
        self.store = store
        self.watcher = watcher
        self.hotkeySpec = hotkeySpec
        self.togglePanel = togglePanel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        // The icon is the only always-visible place to show that recording is off.
        pauseObserver = watcher.$isPaused.sink { [weak self] paused in
            self?.updateIcon(paused: paused)
        }
    }

    private func updateIcon(paused: Bool) {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: paused ? "paperclip.badge.ellipsis" : "paperclip",
                               accessibilityDescription: paused ? "Clippet (recording paused)" : "Clippet")
        button.appearsDisabled = paused
        button.toolTip = paused ? "Clippet — recording paused" : "Clippet"
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

        let show = NSMenuItem(title: "Show Panel",
                              action: #selector(showPanel),
                              keyEquivalent: "")
        show.target = self
        if let (key, modifiers) = HotKey.menuEquivalent(for: hotkeySpec) {
            show.keyEquivalent = key
            show.keyEquivalentModifierMask = modifiers
        }
        menu.addItem(show)

        let pause = NSMenuItem(title: watcher.isPaused ? "Resume Recording" : "Pause Recording",
                               action: #selector(togglePause),
                               keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        menu.addItem(.separator())

        let openConfig = NSMenuItem(title: "Open Config File…",
                                    action: #selector(openConfigFile),
                                    keyEquivalent: ",")
        openConfig.target = self
        menu.addItem(openConfig)

        let clear = NSMenuItem(title: "Clear History…",
                               action: #selector(clearHistory),
                               keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())

        let shortcuts = NSMenuItem(title: "Keyboard Shortcuts",
                                   action: #selector(showShortcuts),
                                   keyEquivalent: "/")
        shortcuts.target = self
        menu.addItem(shortcuts)

        let about = NSMenuItem(title: "About Clippet",
                               action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                               keyEquivalent: "")
        about.target = NSApp
        menu.addItem(about)

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

    // MARK: - Actions

    @objc private func showPanel() {
        togglePanel()
    }

    @objc private func togglePause() {
        watcher.isPaused.toggle()
    }

    @objc private func openConfigFile() {
        NSWorkspace.shared.open(Config.fileURL)
    }

    @objc private func showShortcuts() {
        showShortcutsAlert(hotkeySpec: hotkeySpec)
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
