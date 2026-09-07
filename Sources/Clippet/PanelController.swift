import AppKit
import ApplicationServices
import SwiftUI

enum PanelLayout {
    static let size = NSSize(width: 680, height: 440)
    static let listWidth: CGFloat = 312
}

/// Borderless nonactivating panels refuse key status unless this is overridden.
final class ClippetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    var onPaste: ((ClipItem) -> Void)?
    var onCopyOnly: ((ClipItem) -> Void)?

    private let store: ClipStore
    private let panel: ClippetPanel
    private var keyMonitor: Any?
    private var flagsMonitor: Any?

    /// Rows moved by Page Up / Page Down.
    private static let pageSize = 8

    init(store: ClipStore) {
        self.store = store
        panel = ClippetPanel(
            contentRect: NSRect(origin: .zero, size: PanelLayout.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self

        let host = NSHostingView(rootView: PanelView(
            store: store,
            onPaste: { [weak self] item in self?.paste(item) },
            onCopyOnly: { [weak self] item in self?.copyOnly(item) }
        ))
        host.frame = NSRect(origin: .zero, size: PanelLayout.size)
        panel.contentView = host
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let frame = targetScreen().visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - PanelLayout.size.width / 2,
            y: frame.minY + frame.height * 0.62 - PanelLayout.size.height / 2
        ))
        store.query = ""
        store.resetSelection()
        store.commandHeld = NSEvent.modifierFlags.contains(.command)
        store.focusToken += 1
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        store.commandHeld = false
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: - Actions

    private func paste(_ item: ClipItem) {
        hide()
        onPaste?(item)
    }

    private func copyOnly(_ item: ClipItem) {
        hide()
        onCopyOnly?(item)
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            return self.handle(event) ? nil : event
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.store.commandHeld = event.modifierFlags.contains(.command)
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        keyMonitor = nil
        flagsMonitor = nil
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let cmd = event.modifierFlags.contains(.command)
        let count = store.visibleItems.count
        switch event.keyCode {
        case 53: // esc — clear the query first, close on the second press
            if store.query.isEmpty {
                hide()
            } else {
                store.query = ""
            }
            return true
        case 126: // up (⌘↑ jumps to the first item)
            store.moveSelection(by: cmd ? -count : -1)
            return true
        case 125: // down (⌘↓ jumps to the last item)
            store.moveSelection(by: cmd ? count : 1)
            return true
        case 116: // page up
            store.moveSelection(by: -Self.pageSize)
            return true
        case 121: // page down
            store.moveSelection(by: Self.pageSize)
            return true
        case 115: // home
            store.moveSelection(by: -count)
            return true
        case 119: // end
            store.moveSelection(by: count)
            return true
        case 36, 76: // return / keypad enter
            if let item = store.selectedItem {
                cmd ? copyOnly(item) : paste(item)
            }
            return true
        case 51 where cmd: // ⌘⌫
            if let item = store.selectedItem { store.delete(item) }
            return true
        default:
            guard cmd, let chars = event.charactersIgnoringModifiers?.lowercased() else { return false }
            if chars == "p" {
                if let item = store.selectedItem { store.togglePin(item) }
                return true
            }
            // ⌘1–⌘9 paste the n-th visible item straight away.
            if let digit = Int(chars), (1...9).contains(digit) {
                if digit <= count { paste(store.visibleItems[digit - 1]) }
                return true
            }
            return false
        }
    }

    // MARK: - Screen placement

    private func targetScreen() -> NSScreen {
        if let screen = Self.focusedWindowScreen() { return screen }
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) { return screen }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    /// Screen hosting the focused window of the frontmost app. Needs Accessibility;
    /// callers fall back to the mouse screen when unavailable.
    private static func focusedWindowScreen() -> NSScreen? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return nil }
        let window = windowRef as! AXUIElement

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)

        // AX coordinates are top-left based; NSScreen frames are bottom-left based.
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let center = CGPoint(x: position.x + size.width / 2,
                             y: primaryHeight - (position.y + size.height / 2))
        return NSScreen.screens.first { $0.frame.contains(center) }
    }
}
