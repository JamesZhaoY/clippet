# Clippet

A small, hackable clipboard history manager for macOS. Native Swift, zero dependencies, zero network — your clipboard never leaves your machine.

Press **⇧⌘V**, type to search, hit **↩** — the item is pasted straight into the app you were using.

## Features

- Clipboard history for plain text, images, and copied files (rich text is stored as plain text — on purpose)
- Spotlight-style panel on the screen you're working on: search, arrow keys, paste
- **↩** pastes directly into the previous app (simulated ⌘V), **⌘↩** only puts the item on the clipboard
- **⌘P** pins items to a PINNED section that never gets evicted
- **⌘⌫** deletes an item; menu-bar right-click → *Clear History…* wipes everything
- Skips content marked `org.nspasteboard.ConcealedType` / `TransientType` (password managers)
- Deduplicates by content hash — recopying something just moves it to the top; images are identified by their pixels, so re-encoded copies of the same picture don't pile up
- When one copy carries both text and a bitmap rendering of it (Numbers, Excel, Word…), the text is recorded — unless the text is just an image URL (browser "Copy Image"), then the image is
- Items pasted from Clippet itself are not re-recorded as new copies
- SQLite persistence in WAL mode with incremental vacuum (default cap: 500 items, images over 10 MB are not recorded)
- Menu bar icon: left-click opens the panel; right-click → pause recording, open config, clear history, quit

## Build & Install

Requires macOS 14+ and a Swift 5.9+ toolchain (Command Line Tools are enough).

```bash
git clone https://github.com/JamesZhaoY/clippet.git
cd clippet
bash Scripts/package-app.sh   # build + assemble + sign .build/package/Clippet.app
bash Scripts/install.sh       # quit the old copy, replace it in /Applications, relaunch
```

No notarization, no auto-update: this is a build-it-yourself tool. To upgrade, `git pull` and run both scripts again. `install.sh` replaces the old bundle instead of copying over it (which would leave the Dock showing a stale icon); pass a directory to install elsewhere, or `-n` for a dry run.

### Code signing and the Accessibility grant

macOS ties the Accessibility permission to the app's *designated requirement*. With an ad-hoc signature that requirement is the hash of the binary, so every rebuild silently loses the grant. `package-app.sh` therefore signs with a real identity when it finds one — an *Apple Development* certificate from Xcode, or any *Code Signing* certificate you create yourself in Keychain Access (Certificate Assistant → Create a Certificate → type "Code Signing") — and only falls back to ad-hoc when there is none. Override the choice with `CLIPPET_SIGN_IDENTITY="Your Cert Name" bash Scripts/package-app.sh`.

You re-grant Accessibility once when the identity changes (e.g. the first install after switching from ad-hoc); after that rebuilds keep it.

### Tests

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

XCTest ships with Xcode, not with the Command Line Tools, hence the `DEVELOPER_DIR`. The tests exercise the store, the database (including the v0.1 → v1 migration) and the pasteboard rules against a private named pasteboard — your real clipboard is never touched.

## Permissions

Direct paste works by simulating ⌘V, which needs **Accessibility** access:
*System Settings → Privacy & Security → Accessibility → enable Clippet.*

Everything else (recording history, searching, copy-only mode) works without it.

## Keyboard

| Key | Action |
| --- | --- |
| ⇧⌘V | Open / close the panel (global) |
| type | Search (case-insensitive substring) |
| ↑ ↓ | Select |
| ↩ | Paste into the previous app |
| ⌘↩ | Copy to clipboard only |
| ⌘P | Pin / unpin |
| ⌘⌫ | Delete item |
| esc | Clear search, then close |

## Configuration

`~/Library/Application Support/Clippet/config.json` (created on first launch, changes apply after restart):

| Key | Default | Meaning |
| --- | --- | --- |
| `hotkey` | `"cmd+shift+v"` | Global hotkey, e.g. `"opt+cmd+v"` |
| `maxItems` | `500` | History cap (1–100000); oldest unpinned items are evicted |
| `maxImageBytes` | `10485760` | Images larger than this are not recorded; `0` disables image capture |
| `pollIntervalMs` | `300` | Pasteboard polling interval (50–5000) |
| `excludedApps` | `[]` | Reserved for v2, not enforced yet |

Out-of-range values are clamped to the ranges above. The environment variable `CLIPPET_DATA_DIR` relocates both `config.json` and the database — handy for running a development build next to the installed one.

## Privacy

- No network code at all. Nothing is uploaded, synced, or phoned home.
- History is stored unencrypted in `~/Library/Application Support/Clippet/` — same trust model as your Downloads folder.
- Password-manager copies are skipped automatically (concealed/transient pasteboard types).
- Pause recording any time from the menu bar icon.

---

## 中文说明

Clippet 是一个自用优先、可随意魔改的 macOS 剪贴板历史工具:原生 Swift 编写,零依赖、零网络,数据永远只在本机。

**构建安装**:装好 Command Line Tools 后执行 `bash Scripts/package-app.sh` 打包,再执行 `bash Scripts/install.sh` 安装(会先退出旧实例、整体替换旧包、刷新图标缓存、重新启动)。升级 = `git pull` 后重跑这两个脚本。

**签名与权限**:打包脚本会自动使用钥匙串里已有的签名证书(Xcode 装的 Apple Development,或你在「钥匙串访问」里自建的「代码签名」证书),这样辅助功能授权不会随每次重编译丢失;只有在换签名身份时需要重新勾选一次。找不到证书时退回 ad-hoc 签名。

**权限**:按 ↩ 直接粘贴依赖「辅助功能」权限(系统设置 → 隐私与安全性 → 辅助功能);不授权也能用,只是要自己 ⌘V。

**日常使用**:⇧⌘V 唤出面板,输入即搜索,↑↓ 选择,↩ 粘贴到之前的应用,⌘↩ 仅复制,⌘P 固定常用条目,⌘⌫ 删除。菜单栏回形针图标:左键开面板,右键可暂停记录、打开配置文件、清空历史。

配置在 `~/Library/Application Support/Clippet/config.json`,改完重启应用生效。

## License

[MIT](LICENSE) © 2026 JamesZhao
