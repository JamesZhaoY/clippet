# Clippet 需求基线

2026-08-28 逐轮确认的 v0.1 需求。改动这份文件前先想清楚:这里的每一条都是当时有意的取舍,不是遗漏。

## 定位与红线

- 自用优先、完全可魔改的 macOS 剪贴板历史工具;作者本机 build 使用
- 原生 Swift:SwiftUI 负责面板 UI,AppKit 负责系统层(NSPasteboard / CGEvent / NSPanel / NSStatusItem)
- GitHub 开源,MIT License;不签名公证、不上架 App Store、不进 Homebrew、无自动更新
- **零网络功能,数据永不出本机**
- 系统要求 macOS 14+;SwiftPM 可执行目标 + 脚本打 .app(无 Xcode 工程)

## 核心闭环

- 全局快捷键 `⇧⌘V`(配置可改)唤出面板;菜单栏图标左键同效
- 面板出现在**键盘焦点所在屏幕**中央偏上(Spotlight 式):优先用辅助功能 API 取前台焦点窗口所在屏,退化到鼠标所在屏,再退化到主屏
- 布局:搜索框 + 左侧列表(约 8–10 行,PINNED 分区在顶部)+ 右侧选中项预览 + 底部快捷键提示条
- 输入即搜:子串匹配、不分大小写,匹配文本内容与文件路径;图片条目仅在空搜索时展示
- 键位:`↑↓` 选择,`↩` 切回原 App 模拟 ⌘V 直接粘贴,`⌘↩` 仅写入剪贴板,`⌘P` 固定/取消,`⌘⌫` 删除条目,`esc` 先清空搜索、再按关闭面板
- 直接粘贴需要辅助功能权限:首次启动触发一次系统引导;未授权时按 `↩` 弹说明框(内容此时已在剪贴板,可手动 ⌘V)

## 记录规则

- 轮询 `NSPasteboard.changeCount`(默认 300ms,可配)
- 记录三类:纯文本、图片(统一转 PNG 存储)、文件引用(存绝对路径);富文本降级为纯文本
- 自动跳过带 `org.nspasteboard.ConcealedType` / `TransientType` 标记的内容(密码管理器)
- **不做**排除 App 列表(v2;config 中 `excludedApps` 字段已预留,当前不生效)
- 图片单条超过 10MB(可配)不记录
- 重复内容(按 SHA-256 去重)不新增条目,原条目提升到最新;固定条目保持固定

## 存储与管理

- SQLite 存 `~/Library/Application Support/Clippet/clippet.sqlite3`,重启保留
- 上限 500 条(可配),超出淘汰最旧的未固定条目;固定条目永不被自动淘汰
- 图片全量数据只在库里,内存仅持缩略图(≤512px JPEG),预览/粘贴时按需读库
- 删除单条:`⌘⌫` 或右键菜单;清空全部(含固定):菜单栏右键「Clear History…」带确认框

## 常驻形态(用户特意拍板,勿"纠正")

- **保留 Dock 图标**(activation policy = regular),点 Dock 图标唤出面板
- **不做开机自启**
- 菜单栏图标:左键弹面板;右键菜单 = Pause Recording / Open Config File / Clear History… / Quit

## 配置

- 单个 JSON:`~/Library/Application Support/Clippet/config.json`,首次启动自动生成默认值
- 字段:`hotkey`、`maxItems`、`maxImageBytes`、`pollIntervalMs`、`excludedApps`(预留)
- 改动**重启生效**;v0.1 无设置界面、无热加载
- 界面文案英文,不做 i18n;README 英文为主 + 中文段落

## v2 停车场(明确不进 v0.1)

排除 App 列表生效、粘贴队列、跨设备同步、文本处理动作(去格式/大小写/trim)、
智能分类与类型筛选 tab、模糊搜索(fzf 式)、设置 UI 与改键 UI、富文本保真、开机自启选项。
