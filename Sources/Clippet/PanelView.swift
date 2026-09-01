import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var store: ClipStore
    let onPaste: (ClipItem) -> Void
    let onCopyOnly: (ClipItem) -> Void
    @FocusState private var searchFocused: Bool
    @State private var hoveredID: Int64?

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 680, height: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
        .onAppear { searchFocused = true }
        .onChange(of: store.focusToken) { searchFocused = true }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search clipboard history...", text: $store.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
            if !store.query.isEmpty {
                Button {
                    store.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.visibleItems.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 0) {
                itemList.frame(width: 312)
                Divider()
                PreviewPane(store: store, item: store.selectedItem)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.quaternary.opacity(0.35))
                    .frame(width: 58, height: 58)
                Image(systemName: store.query.isEmpty ? "clipboard" : "magnifyingglass")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 4) {
                Text(store.query.isEmpty ? "Clipboard History Is Empty" : "No Matches")
                    .font(.system(size: 13, weight: .semibold))
                Text(store.query.isEmpty
                     ? "Copy anything and it will appear here."
                     : "Try a different search term.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Item list

    private var itemList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !store.pinnedFiltered.isEmpty {
                        sectionHeader("PINNED")
                        ForEach(store.pinnedFiltered) { item in
                            row(item)
                        }
                    }
                    if !store.recentFiltered.isEmpty {
                        sectionHeader("HISTORY")
                        ForEach(store.recentFiltered) { item in
                            row(item)
                        }
                    }
                }
                .padding(6)
            }
            .onChange(of: store.selectedID) {
                if let id = store.selectedID { proxy.scrollTo(id) }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, 7)
            .padding(.bottom, 3)
    }

    private func row(_ item: ClipItem) -> some View {
        let selected = store.selectedItem?.id == item.id
        return HStack(spacing: 9) {
            rowIcon(item, selected: selected)
                .frame(width: 26, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(item.listTitle.isEmpty ? " " : item.listTitle)
                .lineLimit(1)
                .font(.system(size: 12.5, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? Color.white : Color.primary)
            Spacer(minLength: 4)
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(selected ? Color.white.opacity(0.9) : Color.orange)
            }
            Text(shortRelativeTime(from: item.lastUsedAt))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
            Image(systemName: "chevron.left")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(selected ? Color.white.opacity(0.5) : Color.clear)
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(rowBackground(selected: selected, itemID: item.id),
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .id(item.id)
        .onHover { hovering in
            hoveredID = hovering ? item.id : nil
        }
        .gesture(TapGesture(count: 2).onEnded { onPaste(item) })
        .simultaneousGesture(TapGesture().onEnded { store.selectedID = item.id })
        .contextMenu {
            Button(item.pinned ? "Unpin" : "Pin") { store.togglePin(item) }
            Button("Copy") { onCopyOnly(item) }
            Button("Paste") { onPaste(item) }
            Divider()
            Button("Delete", role: .destructive) { store.delete(item) }
        }
    }

    private func rowBackground(selected: Bool, itemID: Int64) -> Color {
        if selected { return .accentColor }
        if hoveredID == itemID { return Color.primary.opacity(0.07) }
        return .clear
    }

    @ViewBuilder
    private func rowIcon(_ item: ClipItem, selected: Bool) -> some View {
        switch item.kind {
        case .text:
            if let id = item.appBundleID, let icon = AppInfoCache.shared.icon(forBundleID: id) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "doc.plaintext")
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.white : Color.secondary)
            }
        case .image:
            if let data = item.thumbnail, let thumb = NSImage(data: data) {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.white : Color.secondary)
            }
        case .file:
            if let url = item.fileURLs.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "folder")
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.white : Color.secondary)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            hint("↩", "Paste")
            hint("⌘↩", "Copy")
            hint("⌘P", "Pin")
            hint("⌘⌫", "Delete")
            hint("esc", "Close")
            Spacer()
            Text("\(store.visibleItems.count) item\(store.visibleItems.count == 1 ? "" : "s")")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            keycap(keys)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.quaternary.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.quaternary, lineWidth: 0.5))
    }
}

// MARK: - Preview

struct PreviewPane: View {
    @ObservedObject var store: ClipStore
    let item: ClipItem?
    @State private var fullImage: NSImage?
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let item {
                VStack(spacing: 0) {
                    previewHeader(item)
                    Divider().opacity(0.5)
                    previewBody(item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    metaBar(item)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                    Text("Nothing selected")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { load() }
        .onChange(of: item?.id) { load() }
    }

    private func previewHeader(_ item: ClipItem) -> some View {
        HStack(spacing: 6) {
            if let id = item.appBundleID, let icon = AppInfoCache.shared.icon(forBundleID: id) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 15, height: 15)
            } else {
                Image(systemName: kindSymbol(item.kind))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Text(previewTitle(item))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Spacer()
            Text(kindLabel(item.kind).uppercased())
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.5), in: Capsule())
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(.primary.opacity(0.03))
    }

    @ViewBuilder
    private func previewBody(_ item: ClipItem) -> some View {
        switch item.kind {
        case .text:
            ScrollView {
                Text(item.text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        case .image:
            Group {
                if let image = fullImage ?? thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(10)
        case .file:
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item.fileURLs, id: \.path) { url in
                        HStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 15, height: 15)
                                        Text(url.path)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
        }
    }

    private func metaBar(_ item: ClipItem) -> some View {
        HStack {
            Text(metaText(item))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 22)
    }

    private func metaText(_ item: ClipItem) -> String {
        var parts = [item.lastUsedAt.formatted(.relative(presentation: .named))]
        if let app = AppInfoCache.shared.name(forBundleID: item.appBundleID) { parts.append(app) }
        switch item.kind {
        case .text: parts.append("\(item.text.count) chars")
        case .image: parts.append("\(item.imageWidth)×\(item.imageHeight)")
        case .file: parts.append("\(item.fileURLs.count) file\(item.fileURLs.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    private func previewTitle(_ item: ClipItem) -> String {
        if item.kind == .text,
           let app = item.appBundleID.flatMap({ AppInfoCache.shared.name(forBundleID: $0) }) {
            return app
        }
        return kindLabel(item.kind)
    }

    private func kindLabel(_ kind: ClipKind) -> String {
        switch kind {
        case .text: return "Text"
        case .image: return "Image"
        case .file: return "Files"
        }
    }

    private func kindSymbol(_ kind: ClipKind) -> String {
        switch kind {
        case .text: return "doc.plaintext"
        case .image: return "photo"
        case .file: return "folder"
        }
    }

    private func load() {
        fullImage = nil
        thumbnail = nil
        guard let item, item.kind == .image else { return }
        thumbnail = item.thumbnail.flatMap { NSImage(data: $0) }
        if let data = store.imageData(for: item) {
            fullImage = NSImage(data: data)
        }
    }
}
