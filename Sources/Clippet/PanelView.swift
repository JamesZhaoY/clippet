import SwiftUI

struct PanelView: View {
    @ObservedObject var store: ClipStore
    let onPaste: (ClipItem) -> Void
    let onCopyOnly: (ClipItem) -> Void
    @FocusState private var searchFocused: Bool

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

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard history…", text: $store.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($searchFocused)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    @ViewBuilder
    private var content: some View {
        if store.visibleItems.isEmpty {
            VStack(spacing: 6) {
                Spacer()
                Image(systemName: "clipboard")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text(store.query.isEmpty ? "Clipboard history is empty" : "No matches")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 0) {
                itemList.frame(width: 300)
                Divider()
                PreviewPane(store: store, item: store.selectedItem)
            }
        }
    }

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
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func row(_ item: ClipItem) -> some View {
        let selected = store.selectedItem?.id == item.id
        return HStack(spacing: 8) {
            Image(systemName: icon(for: item.kind))
                .frame(width: 16)
                .foregroundStyle(selected ? Color.white : Color.secondary)
            Text(item.listTitle.isEmpty ? " " : item.listTitle)
                .lineLimit(1)
                .foregroundStyle(selected ? Color.white : Color.primary)
            Spacer(minLength: 4)
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(selected ? Color.white : Color.orange)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(selected ? Color.accentColor : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .id(item.id)
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

    private func icon(for kind: ClipKind) -> String {
        switch kind {
        case .text: "doc.plaintext"
        case .image: "photo"
        case .file: "folder"
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↩", "Paste")
            hint("⌘↩", "Copy")
            hint("⌘P", "Pin")
            hint("⌘⌫", "Delete")
            hint("esc", "Close")
            Spacer()
            Text("\(store.visibleItems.count) items")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Text(label).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }
}

struct PreviewPane: View {
    @ObservedObject var store: ClipStore
    let item: ClipItem?
    @State private var fullImage: NSImage?

    var body: some View {
        Group {
            if let item {
                VStack(spacing: 0) {
                    previewBody(item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    metaBar(item)
                }
            } else {
                Text("Nothing selected")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { loadImageIfNeeded() }
        .onChange(of: item?.id) { loadImageIfNeeded() }
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
                if let image = fullImage ?? item.thumbnail.flatMap({ NSImage(data: $0) }) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo").foregroundStyle(.tertiary)
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
                                .frame(width: 16, height: 16)
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
        if let app = item.appBundleID { parts.append(app) }
        switch item.kind {
        case .text: parts.append("\(item.text.count) chars")
        case .image: parts.append("\(item.imageWidth)×\(item.imageHeight)")
        case .file: parts.append("\(item.fileURLs.count) file(s)")
        }
        return parts.joined(separator: " · ")
    }

    private func loadImageIfNeeded() {
        fullImage = nil
        guard let item, item.kind == .image else { return }
        if let data = store.imageData(for: item) {
            fullImage = NSImage(data: data)
        }
    }
}
