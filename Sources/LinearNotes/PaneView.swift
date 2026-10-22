import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NotesCore

// The overhaul experiment has its own identifiers so it can run beside the shipped app (spec §15).
let tabType = UTType(exportedAs: "local.linearnotes.overhaul.tab", conformingTo: .data)

struct NotePaneView: View {
    @ObservedObject var store: NotebookStore
    @ObservedObject var pane: NotePane
    var body: some View { NotePaneContent(store: store, pane: pane, tab: pane.tab) }
}

private struct NotePaneContent: View {
    @ObservedObject var store: NotebookStore
    @ObservedObject var pane: NotePane
    @ObservedObject var tab: NoteTab
    @State private var dropping = false
    @State private var dropDirection: SplitDirection?
    @State private var dropTabID: UUID?
    @State private var dropAfter = false
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                tabstrip
                VStack(spacing: 0) {
                    header
                    Rectangle().fill(Palette.divider).frame(height: 1)
                    if let error = tab.error {
                        HStack(spacing: 10) {
                            ChromeIcon("exclamationmark.circle", size: 13, color: Palette.warning)
                            Text(error).font(Typeface.ui(12)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if tab.conflict { Button("Keep both") { store.activate(pane); store.keepBoth() }.buttonStyle(.bordered) }
                            else if tab.saveFailed { Button("Retry") { tab.bridge?.flush { _ in } }.buttonStyle(.bordered) }
                            else { Button { tab.error = nil } label: { ChromeIcon("xmark", size: 11) }.accessibilityLabel("Dismiss error") }
                        }.padding(.horizontal, 16).padding(.vertical, 10).background(Palette.warning.opacity(0.08))
                    }
                    ZStack {
                        MarkdownEditorView(store: store, tab: tab, tabDragChanged: { hovering, edge in
                            dropping = hovering; dropDirection = edge
                        }, tabDropped: { id, edge in store.moveTab(id, to: pane.id, direction: edge) }).id(tab.id)
                            .opacity(tab.selected == nil ? 0 : 1).allowsHitTesting(tab.selected != nil)
                        if tab.selected == nil { if store.library == nil { emptyState } else { RecentView(store: store, pane: pane) } }
                    }
                }
                .background(Palette.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(store.panes.count > 1 && store.activePaneID == pane.id ? Palette.accent.opacity(0.55) : Palette.border, lineWidth: 1) }
            }
            .overlay {
                if dropping {
                    GeometryReader { bounds in
                        let horizontal = dropDirection?.horizontal == true
                        let width = dropDirection == nil || !horizontal ? bounds.size.width : bounds.size.width / 2
                        let height = dropDirection == nil || horizontal ? bounds.size.height : bounds.size.height / 2
                        RoundedRectangle(cornerRadius: 12).fill(Palette.accent.opacity(0.12))
                            .overlay { RoundedRectangle(cornerRadius: 12).stroke(Palette.accent, lineWidth: 2) }
                            .frame(width: width, height: height)
                            .offset(x: dropDirection == .right ? width : 0, y: dropDirection == .down ? height : 0)
                    }.allowsHitTesting(false)
                }
            }
            .onDrop(of: [tabType, .text], delegate: PaneDropDelegate(store: store, pane: pane, size: geometry.size, dropping: $dropping, direction: $dropDirection))
        }
        .clipped()
        .onChange(of: tab.mode) { store.saveWorkspace() }
    }

    /// Linear's tab strip: shell background, quiet inactive tabs, one filled active tab, `+` after the last tab.
    var tabstrip: some View {
        HStack(spacing: 2) {
            if pane.id == store.layout.paneIDs.first && !store.sidebarVisible {
                Spacer().frame(width: 68)
                NavigationButtons(store: store)
                Spacer().frame(width: 6)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(pane.tabs) { item in
                        let title = item.selected.map { NoteItem(path: $0, isFolder: false).title } ?? "Recent"
                        let active = item.id == pane.selectedTabID
                        let width = min(160, (title as NSString).size(withAttributes: [.font: Typeface.nsFont(13, 500)]).width) + 54
                        TabChip(store: store, pane: pane, tab: item, title: title, active: active, width: width, dropTabID: $dropTabID, dropAfter: $dropAfter)
                    }
                    Button { store.activate(pane); store.newTab() } label: { ChromeIcon("plus", size: 12) }
                        .help("New tab · ⌘T").accessibilityLabel("New tab")
                }.padding(.vertical, 6)
            }.scrollIndicators(.hidden)
            Menu {
                ForEach(SplitDirection.allCases, id: \.self) { direction in
                    Button(direction.title) { store.split(direction, paneID: pane.id) }
                }
                Divider(); Button("Close pane") { store.closePane(pane) }
            } label: { ChromeIcon("rectangle.split.2x1", size: 12) }
                .menuStyle(.button).buttonStyle(ChromeButtonStyle()).menuIndicator(.hidden)
                .help("Split pane").accessibilityLabel("Split pane")
        }
        .padding(.horizontal, 2).frame(height: ContentView.titlebarHeight).background(Palette.shell)
    }

    /// The page header: breadcrumbs, more, favourite on the left; edited time, link, details on the right.
    var header: some View {
        HStack(spacing: 4) {
            if !store.sidebarVisible && pane.id == store.layout.paneIDs.first {
                Button { store.sidebarVisible = true } label: { ChromeIcon("sidebar.left", size: 13) }
                    .help("Show sidebar · ⌘\\").accessibilityLabel("Show sidebar")
            }
            if let selected = tab.selected {
                let item = NoteItem(path: selected, isFolder: false)
                Breadcrumbs(store: store, path: selected)
                Menu { noteMenu(selected, item: item) } label: { ChromeIcon("ellipsis", size: 13) }
                    .menuStyle(.button).buttonStyle(ChromeButtonStyle()).menuIndicator(.hidden).accessibilityLabel("Note actions")
                Button { store.toggleBookmark(selected) } label: {
                    ChromeIcon(store.isBookmarked(selected) ? "star.fill" : "star", size: 13, color: store.isBookmarked(selected) ? Palette.star : Palette.muted)
                }.help(store.isBookmarked(selected) ? "Remove from Favorites · ⌥F" : "Add to Favorites · ⌥F")
                    .accessibilityLabel(store.isBookmarked(selected) ? "Remove from Favorites" : "Add to Favorites")
                Spacer(minLength: 12)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let saved = tab.status == "Saved locally"
                    Text(saved ? store.editedLabel(selected, now: context.date) : tab.status)
                        .font(Typeface.ui(12)).foregroundStyle(tab.conflict || tab.saveFailed ? Palette.warning : Palette.faint).lineLimit(1)
                }.padding(.trailing, 6).layoutPriority(-1)
                Button { store.copyLink(selected) } label: { ChromeIcon("link", size: 13) }
                    .help("Copy file link").accessibilityLabel("Copy file link")
                Rectangle().fill(Palette.border).frame(width: 1, height: 16).padding(.horizontal, 4)
            } else {
                HStack(spacing: 8) {
                    ChromeIcon("clock", size: 13)
                    Text(store.library == nil ? "Linear Notes" : "Recent").font(Typeface.ui(13, 500)).foregroundStyle(Palette.primary)
                }.padding(.leading, 4)
                Spacer()
            }
            Button { store.activate(pane); store.inspectorVisible.toggle() } label: {
                ChromeIcon("sidebar.right", size: 13, color: store.inspectorVisible ? Palette.primary : Palette.muted)
            }.help("Toggle details · ⌘⌥\\").accessibilityLabel("Toggle details")
                .accessibilityValue(store.inspectorVisible ? "Open" : "Closed")
        }
        .padding(.horizontal, 10).frame(height: 44)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { store.activate(pane) })
    }

    @ViewBuilder func noteMenu(_ selected: String, item: NoteItem) -> some View {
        if let note = store.items.first(where: { $0.path == selected }) {
            Button("Rename…") { store.activate(pane); store.rename(note) }
        }
        Button("Copy file link") { store.copyLink(selected) }
        Menu("Mode") {
            ForEach(EditorMode.allCases, id: \.self) { mode in
                Toggle(mode.title, isOn: Binding(get: { tab.mode == mode }, set: { if $0 { store.activate(pane); tab.mode = mode; store.saveWorkspace() } }))
            }
        }
        Divider()
        ForEach(SplitDirection.allCases, id: \.self) { direction in
            Button(direction.title) { store.split(direction, paneID: pane.id) }
        }
        if store.panes.count > 1 { Button("Close pane") { store.closePane(pane) } }
        Divider()
        Button(store.isPinned(selected) ? "Unpin from folder" : "Pin to top of folder") { store.togglePin(selected) }
        Button("Print / Save as PDF…") { store.activate(pane); tab.bridge?.printDocument() }
        if NoteLibrary.linearSource(in: tab.markdown) != nil {
            Button("Refresh from Linear…") { store.activate(pane); store.linearRefreshVisible = true }
        }
        Button("Show in Finder") { store.reveal(selected) }
        if let note = store.items.first(where: { $0.path == selected }) {
            Divider(); Button("Move to Trash…", role: .destructive) { store.activate(pane); store.trash(note) }
        }
    }

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.fill").font(.system(size: 18)).foregroundStyle(Palette.accent)
                .frame(width: 32, height: 32).background(Palette.accentTint, in: RoundedRectangle(cornerRadius: 6))
            Text("Your notes, on your Mac").font(Typeface.ui(28, 600)).foregroundStyle(Palette.primary)
            Text("Open a folder of Markdown files to start writing.").font(Typeface.ui(15)).foregroundStyle(Palette.muted)
            Button { store.chooseFolder() } label: {
                Text("Open notes folder").font(Typeface.ui(13, 500)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 32).background(Palette.accent, in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(.plain).padding(.top, 8)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
    }
}

/// One tab in the strip. The title is an AppKit button so tabs can start native drags.
private struct TabChip: View {
    @ObservedObject var store: NotebookStore
    @ObservedObject var pane: NotePane
    let tab: NoteTab
    let title: String
    let active: Bool
    let width: CGFloat
    @Binding var dropTabID: UUID?
    @Binding var dropAfter: Bool
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 2) {
            TabDragButton(title: title, id: tab.id, active: active, symbol: tab.selected == nil ? "clock" : "doc.text") { store.selectTab(tab, in: pane) }
                .frame(width: width - 30, height: 28)
                .accessibilityAddTraits(active ? .isSelected : [])
            Button { store.closeTab(tab, in: pane) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.muted) }
                .buttonStyle(ChromeButtonStyle(size: 20)).opacity(active || hovering ? 1 : 0)
                .accessibilityLabel("Close \(title)")
        }
        .padding(.leading, 4).padding(.trailing, 4)
        .frame(width: width, height: 28)
        .background(active ? Palette.control : hovering ? Palette.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(active ? Palette.border : .clear) }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .overlay(alignment: dropAfter ? .trailing : .leading) {
            if dropTabID == tab.id { Rectangle().fill(Palette.accent).frame(width: 2).allowsHitTesting(false) }
        }
        .onDrop(of: [tabType], delegate: TabDropDelegate(store: store, pane: pane, tabID: tab.id, width: width, target: $dropTabID, after: $dropAfter))
        .contextMenu {
            ForEach(SplitDirection.allCases, id: \.self) { direction in
                Button(direction.title) { store.split(direction, paneID: pane.id, tabID: tab.id) }
            }
            Divider()
            Button("Close tab") { store.closeTab(tab, in: pane) }
        }
    }
}

/// Breadcrumbs from the notebook root to the note, with the final crumb brightest.
private struct Breadcrumbs: View {
    @ObservedObject var store: NotebookStore
    let path: String
    struct Crumb { let name: String; let path: String? }
    var crumbs: [Crumb] {
        let folders = path.split(separator: "/").dropLast().map(String.init)
        let all = folders.indices.map { Crumb(name: folders[$0], path: folders[...$0].joined(separator: "/")) }
        guard all.count > 3 else { return all }
        return [all[0], Crumb(name: "…", path: nil), all[all.count - 1]]
    }
    var body: some View {
        let shown = crumbs.map { (name: $0.name, path: $0.path) }
        HStack(spacing: 4) {
            ForEach(Array(shown.enumerated()), id: \.offset) { entry in
                Button {
                    if let folder = entry.element.path, !store.isExpanded(folder) { store.toggleExpanded(folder) }
                    store.sidebarVisible = true
                } label: {
                    HStack(spacing: 6) {
                        if entry.element.path != nil { ChromeIcon("folder", size: 12) }
                        Text(entry.element.name).font(Typeface.ui(13, 500)).foregroundStyle(Palette.secondary).lineLimit(1)
                    }.padding(.horizontal, 4).frame(height: 26).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(entry.element.path == nil)
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(Palette.faint)
            }
            HStack(spacing: 6) {
                ChromeIcon("doc.text", size: 12)
                Text(NoteItem(path: path, isFolder: false).title).font(Typeface.ui(13, 500)).foregroundStyle(Palette.primary).lineLimit(1).truncationMode(.middle)
            }.padding(.horizontal, 4)
        }.accessibilityElement(children: .contain).accessibilityLabel("Location")
    }
}

/// The Recent page: a Linear-style list of recently opened notes, shown in a tab with no note.
private struct RecentView: View {
    @ObservedObject var store: NotebookStore
    @ObservedObject var pane: NotePane
    var body: some View {
        let notes = store.recentItems.isEmpty ? Array(store.items.filter { !$0.isFolder }.prefix(20)) : store.recentItems
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(notes) { item in
                    Button { store.activate(pane); store.select(item.path) } label: { RecentRow(store: store, item: item) }.buttonStyle(.plain)
                    Rectangle().fill(Palette.divider).frame(height: 1).padding(.leading, 44)
                }
                if notes.isEmpty {
                    Text("Notes you open appear here.").font(Typeface.ui(13)).foregroundStyle(Palette.faint).padding(24)
                }
            }.padding(.vertical, 8)
        }.background(Palette.canvas)
    }
}

private struct RecentRow: View {
    @ObservedObject var store: NotebookStore
    let item: NoteItem
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 12) {
            ChromeIcon("doc.text", size: 13)
            Text(item.title).font(Typeface.ui(13, 500)).foregroundStyle(Palette.primary).lineLimit(1)
            if !item.parent.isEmpty { Text(item.parent).font(Typeface.ui(12)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.head) }
            Spacer(minLength: 12)
            if store.isBookmarked(item.path) { ChromeIcon("star.fill", size: 10, color: Palette.star) }
            Text(store.editedLabel(item.path).replacingOccurrences(of: "Edited ", with: "")).font(Typeface.ui(12)).foregroundStyle(Palette.faint)
        }.padding(.horizontal, 16).frame(height: 44).contentShape(Rectangle())
            .background(hovering ? Palette.hover : .clear)
            .onHover { hovering = $0 }
    }
}

func paneDropDirection(at point: CGPoint, in size: CGSize, header: CGFloat) -> SplitDirection? {
    if point.y < header { return nil }
    if point.x < min(60, size.width / 4) { return .left }
    if point.x > size.width - min(60, size.width / 4) { return .right }
    if point.y < header + min(60, size.height / 4) { return .up }
    if point.y > size.height - min(60, size.height / 4) { return .down }
    return nil
}

private struct TabDragButton: NSViewRepresentable {
    let title: String
    let id: UUID
    let active: Bool
    let symbol: String
    let select: () -> Void
    func makeNSView(context: Context) -> TabButton {
        let button = TabButton()
        button.isBordered = false
        button.imagePosition = .imageLeft; button.imageHugsTitle = true; button.alignment = .left
        button.lineBreakMode = .byTruncatingTail
        button.target = button; button.action = #selector(TabButton.selectTab)
        return button
    }
    func updateNSView(_ button: TabButton, context: Context) {
        let color = active ? Palette.nsPrimary : Palette.nsMuted
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        button.contentTintColor = color
        button.attributedTitle = NSAttributedString(string: " " + title, attributes: [.font: Typeface.nsFont(13, 500), .foregroundColor: color])
        button.setAccessibilityLabel(title)
        button.tabID = id; button.select = select
    }
}

private final class TabButton: NSButton, NSDraggingSource {
    var tabID = UUID()
    var select: (() -> Void)?
    override var mouseDownCanMoveWindow: Bool { false }
    @objc func selectTab() { select?() }
    override func mouseDown(with event: NSEvent) {
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { selectTab(); return }
            guard hypot(next.locationInWindow.x - event.locationInWindow.x, next.locationInWindow.y - event.locationInWindow.y) > 4 else { continue }
            let data = NSPasteboardItem(); data.setString(tabID.uuidString, forType: .init(tabType.identifier))
            let item = NSDraggingItem(pasteboardWriter: data)
            let image = NSImage(size: bounds.size)
            image.lockFocus(); draw(bounds); image.unlockFocus()
            item.setDraggingFrame(bounds, contents: image)
            beginDraggingSession(with: [item], event: next, source: self)
            return
        }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
}

private func loadTab(_ provider: NSItemProvider, perform: @escaping @MainActor (UUID) -> Void) {
    _ = provider.loadDataRepresentation(forTypeIdentifier: tabType.identifier) { data, _ in
        guard let data, let value = String(data: data, encoding: .utf8), let id = UUID(uuidString: value) else { return }
        Task { @MainActor in perform(id) }
    }
}

private struct TabDropDelegate: DropDelegate {
    let store: NotebookStore
    let pane: NotePane
    let tabID: UUID
    let width: CGFloat
    @Binding var target: UUID?
    @Binding var after: Bool
    func dropUpdated(info: DropInfo) -> DropProposal? {
        target = tabID; after = info.location.x > width / 2
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { target = nil }
    func performDrop(info: DropInfo) -> Bool {
        target = nil
        guard let provider = info.itemProviders(for: [tabType]).first,
              let index = pane.tabs.firstIndex(where: { $0.id == tabID }) else { return false }
        let insertion = index + (info.location.x > width / 2 ? 1 : 0)
        let before = insertion < pane.tabs.count ? pane.tabs[insertion].id : nil
        loadTab(provider) { store.moveTab($0, to: pane.id, before: before) }
        return true
    }
}

private struct PaneDropDelegate: DropDelegate {
    let store: NotebookStore
    let pane: NotePane
    let size: CGSize
    @Binding var dropping: Bool
    @Binding var direction: SplitDirection?
    func dropUpdated(info: DropInfo) -> DropProposal? {
        dropping = true
        direction = paneDropDirection(at: info.location, in: size, header: ContentView.titlebarHeight)
        return DropProposal(operation: info.hasItemsConforming(to: [tabType]) ? .move : .copy)
    }
    func dropExited(info: DropInfo) { dropping = false; direction = nil }
    func performDrop(info: DropInfo) -> Bool {
        let edge = direction; dropping = false; direction = nil
        if let provider = info.itemProviders(for: [tabType]).first {
            loadTab(provider) { store.moveTab($0, to: pane.id, direction: edge) }
        } else if let provider = info.itemProviders(for: [.text]).first {
            _ = provider.loadObject(ofClass: String.self) { path, _ in
                guard let path else { return }
                Task { @MainActor in
                    guard store.items.contains(where: { $0.path == path && !$0.isFolder }) else { return }
                    store.dropNote(path, in: pane, direction: edge)
                }
            }
        } else { return false }
        return true
    }
}

struct PaneSplitView: View {
    let horizontal: Bool
    let fraction: Double
    let resize: (Double) -> Void
    let finish: () -> Void
    let first: AnyView
    let second: AnyView
    @State private var dragStart: Double?
    @FocusState private var dividerFocused: Bool
    var body: some View {
        GeometryReader { geometry in
            let length = max(1, (horizontal ? geometry.size.width : geometry.size.height) - 7)
            let ratio = min(0.9, max(0.1, fraction.isFinite ? fraction : 0.5))
            if horizontal {
                HStack(spacing: 0) { first.frame(width: length * ratio); divider(length); second.frame(width: length * (1 - ratio)) }
            } else {
                VStack(spacing: 0) { first.frame(height: length * ratio); divider(length); second.frame(height: length * (1 - ratio)) }
            }
        }
    }
    func divider(_ length: CGFloat) -> some View {
        Rectangle().fill(Palette.sidebar)
            .frame(width: horizontal ? 7 : nil, height: horizontal ? nil : 7)
            .overlay { Rectangle().fill(Palette.line).frame(width: horizontal ? 1 : nil, height: horizontal ? nil : 1) }
            .overlay { Rectangle().stroke(dividerFocused ? Palette.accent : .clear, lineWidth: 2) }
            .contentShape(Rectangle())
            .focusable().focused($dividerFocused)
            .onKeyPress(keys: horizontal ? [.leftArrow, .rightArrow] : [.upArrow, .downArrow]) { press in
                resize(fraction + (press.key == .rightArrow || press.key == .downArrow ? 0.05 : -0.05)); finish()
                return .handled
            }
            .onHover { hover in if hover { (horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                if dragStart == nil { dragStart = fraction }
                resize((dragStart ?? fraction) + (horizontal ? value.translation.width : value.translation.height) / length)
            }.onEnded { _ in dragStart = nil; finish() })
            .accessibilityLabel(horizontal ? "Resize panes horizontally" : "Resize panes vertically")
            .accessibilityValue("\(Int(fraction * 100)) percent")
            .accessibilityHint(horizontal ? "Use Left and Right Arrow to resize by 5 percent." : "Use Up and Down Arrow to resize by 5 percent.")
            .accessibilityAdjustableAction { direction in resize(fraction + (direction == .increment ? 0.05 : -0.05)); finish() }
    }
}
