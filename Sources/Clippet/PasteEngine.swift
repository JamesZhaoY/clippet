import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
final class PasteEngine: NSObject {
    /// The last frontmost app that is not Clippet itself — the paste target.
    private var targetApp: NSRunningApplication?
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        super.init()
        targetApp = NSWorkspace.shared.frontmostApplication
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        targetApp = app
    }

    /// Every write is tagged with `.clippetOrigin`; the watcher skips tagged changes because
    /// the store already bumps the item itself, and re-capturing a pasted image would decode,
    /// re-encode and re-thumbnail it for nothing.
    func write(_ item: ClipItem, imageData: Data?) {
        pasteboard.clearContents()
        switch item.kind {
        case .text:
            pasteboard.setString(item.text, forType: .string)
        case .image:
            if let imageData {
                pasteboard.setData(imageData, forType: .png)
            }
        case .file:
            pasteboard.writeObjects(item.fileURLs as [NSURL])
        }
        pasteboard.setData(Data("1".utf8), forType: .clippetOrigin)
    }

    func paste(_ item: ClipItem, imageData: Data?) {
        write(item, imageData: imageData)
        guard AXIsProcessTrusted() else {
            promptForAccessibility()
            return
        }
        cancelPendingPaste()
        guard let target = targetApp, !target.isTerminated, !target.isActive else {
            // The panel never activated Clippet, so the target is still the active app; it
            // only needs a beat to get key focus back from the closing panel.
            schedulePostCmdV(after: 0.12)
            return
        }
        // Clippet itself was active (Dock click). Post ⌘V once the target has actually come
        // to the front — heavy apps take far longer than any fixed delay — with a timeout so
        // an activation that never reports still ends in a paste attempt.
        let pid = target.processIdentifier
        pendingActivation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier == pid else { return }
            MainActor.assumeIsolated {
                self?.cancelPendingPaste()
                self?.schedulePostCmdV(after: 0.08)
            }
        }
        let timeout = DispatchWorkItem { [weak self] in
            Log.paste.warning("target app did not activate within 1 s, posting ⌘V anyway")
            self?.cancelPendingPaste()
            Self.postCmdV()
        }
        pendingTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: timeout)
        target.activate(options: [])
    }

    private var pendingActivation: NSObjectProtocol?
    private var pendingTimeout: DispatchWorkItem?

    private func cancelPendingPaste() {
        if let pendingActivation {
            NSWorkspace.shared.notificationCenter.removeObserver(pendingActivation)
        }
        pendingActivation = nil
        pendingTimeout?.cancel()
        pendingTimeout = nil
    }

    private func schedulePostCmdV(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Self.postCmdV()
        }
    }

    private static func postCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func promptForAccessibility() {
        let alert = NSAlert()
        alert.messageText = "Accessibility permission needed"
        alert.informativeText = """
        Clippet simulates ⌘V to paste directly into the previous app. \
        Grant access in System Settings → Privacy & Security → Accessibility, then try again.

        Your selection is already on the clipboard — you can paste it manually with ⌘V.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
