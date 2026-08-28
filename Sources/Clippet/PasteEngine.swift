import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
final class PasteEngine: NSObject {
    /// The last frontmost app that is not Clippet itself — the paste target.
    private var targetApp: NSRunningApplication?

    override init() {
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

    func write(_ item: ClipItem, imageData: Data?) {
        let pasteboard = NSPasteboard.general
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
    }

    func paste(_ item: ClipItem, imageData: Data?) {
        write(item, imageData: imageData)
        guard AXIsProcessTrusted() else {
            promptForAccessibility()
            return
        }
        if let target = targetApp, !target.isActive {
            target.activate(options: [])
        }
        // Give the target app a beat to regain key focus before ⌘V lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
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
