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
- Deduplicates by content hash — recopying something just moves it to the top
- SQLite persistence (default cap: 500 items, images over 10 MB are not recorded)
- Menu bar icon: left-click opens the panel; right-click → pause recording, open config, clear history, quit

## Build & Install

Requires macOS 14+ and a Swift 5.9+ toolchain (Command Line Tools are enough).

```bash
git clone https://github.com/JamesZhaoY/clippet.git
cd clippet
bash Scripts/package-app.sh
cp -R .build/package/Clippet.app /Applications/
open /Applications/Clippet.app
```

No notarization, no auto-update: this is a build-it-yourself tool. To upgrade, `git pull` and run the script again.

> Note: rebuilding produces a new binary, so macOS may ask you to re-grant Accessibility after an upgrade. Remove and re-add Clippet in the Accessibility list if pasting stops working.

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
| `maxItems` | `500` | History cap; oldest unpinned items are evicted |
| `maxImageBytes` | `10485760` | Images larger than this are not recorded |
| `pollIntervalMs` | `300` | Pasteboard polling interval |
| `excludedApps` | `[]` | Reserved for v2, not enforced yet |

## Privacy

- No network code at all. Nothing is uploaded, synced, or phoned home.
- History is stored unencrypted in `~/Library/Application Support/Clippet/` — same trust model as your Downloads folder.
- Password-manager copies are skipped automatically (concealed/transient pasteboard types).
- Pause recording any time from the menu bar icon.

---

## 中文说明

Clippet 是一个自用优先、可随意魔改的 macOS 剪贴板历史工具:原生 Swift 编写,零依赖、零网络,数据永远只在本机。

**构建安装**:装好 Command Line Tools 后执行 `bash Scripts/package-app.sh`,把 `.build/package/Clippet.app` 拖进「应用程序」即可。升级 = `git pull` 后重跑脚本(重编译后二进制变了,系统可能要求在「辅助功能」里移除再重新添加 Clippet)。

**权限**:按 ↩ 直接粘贴依赖「辅助功能」权限(系统设置 → 隐私与安全性 → 辅助功能);不授权也能用,只是要自己 ⌘V。

**日常使用**:⇧⌘V 唤出面板,输入即搜索,↑↓ 选择,↩ 粘贴到之前的应用,⌘↩ 仅复制,⌘P 固定常用条目,⌘⌫ 删除。菜单栏回形针图标:左键开面板,右键可暂停记录、打开配置文件、清空历史。

配置在 `~/Library/Application Support/Clippet/config.json`,改完重启应用生效。

## License

[MIT](LICENSE) © 2026 JamesZhao
