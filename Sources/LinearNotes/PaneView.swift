import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NotesCore

let tabType = UTType(exportedAs: "local.linearnotes.tab", conformingTo: .data)

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
                    topbar
                    Rectangle().fill(Palette.line).frame(height: 1)
                    if let error = tab.error {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                            Text(error).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if tab.conflict { Button("Keep both") { store.activate(pane); store.keepBoth() }.buttonStyle(.bordered) }
                            else if tab.saveFailed { Button("Retry") { tab.bridge?.flush { _ in } }.buttonStyle(.bordered) }
                            else { Button { tab.error = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss error") }
                        }.padding(12).background(Color.orange.opacity(0.07))
                    }
                    ZStack {
                        MarkdownEditorView(store: store, tab: tab, tabDragChanged: { hovering, edge in
                            dropping = hovering; dropDirection = edge
                        }, tabDropped: { id, edge in store.moveTab(id, to: pane.id, direction: edge) }).id(tab.id)
                            .opacity(tab.selected == nil ? 0 : 1).allowsHitTesting(tab.selected != nil)
                        if tab.selected == nil { emptyState }
                    }
                }
                .background(Palette.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(store.panes.count > 1 && store.activePaneID == pane.id ? Palette.accent.opacity(0.65) : Palette.boundary, lineWidth: 1) }
                statusbar
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
    var tabstrip: some View {
        HStack(spacing: 4) {
            if pane.id == store.layout.paneIDs.first {
                if !store.sidebarVisible { Spacer().frame(width: 68) }
                Button { store.sidebarVisible.toggle() } label: { Image(systemName: "sidebar.left") }
                    .help("Toggle sidebar · ⌘\\").accessibilityLabel("Toggle sidebar")
            }
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(pane.tabs) { item in
                        let title = item.selected.map { NoteItem(path: $0, isFolder: false).title } ?? "New tab"
                        let width = min(150, (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width) + 65
                        HStack(spacing: 5) {
                            TabDragButton(title: title, id: item.id) { store.selectTab(item, in: pane) }
                                .frame(width: width - 35, height: 30)
                                .accessibilityAddTraits(item.id == pane.selectedTabID ? .isSelected : [])
                            Button { store.closeTab(item, in: pane) } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                                .accessibilityLabel("Close \(item.selected.map { NoteItem(path: $0, isFolder: false).title } ?? "tab")")
                        }
                        .frame(width: width, height: 30)
                        .background(item.id == pane.selectedTabID ? Palette.control : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).stroke(item.id == pane.selectedTabID ? Palette.line : .clear) }
                        .contentShape(Rectangle())
                        .overlay(alignment: dropAfter ? .trailing : .leading) {
                            if dropTabID == item.id { Rectangle().fill(Palette.accent).frame(width: 2).allowsHitTesting(false) }
                        }
                        .onDrop(of: [tabType], delegate: TabDropDelegate(store: store, pane: pane, tabID: item.id, width: width, target: $dropTabID, after: $dropAfter))
                        .contextMenu {
                            ForEach(SplitDirection.allCases, id: \.self) { direction in
                                Button(direction.title) { store.split(direction, paneID: pane.id, tabID: item.id) }
                            }
                            Divider()
                            Button("Close tab") { store.closeTab(item, in: pane) }
                        }
                    }
                }
            }.scrollIndicators(.hidden)
            Button { store.activate(pane); store.newTab() } label: { Image(systemName: "plus") }
                .help("New tab · ⌘T").accessibilityLabel("New tab")
            Menu {
                ForEach(SplitDirection.allCases, id: \.self) { direction in
                    Button(direction.title) { store.split(direction, paneID: pane.id) }
                }
                Divider(); Button("Close pane") { store.closePane(pane) }
            } label: { Image(systemName: "rectangle.split.2x1") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
                .help("Split pane").accessibilityLabel("Split pane")
        }
        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
        .padding(.horizontal, 8).frame(height: 46).background(Palette.sidebar)
    }
    var topbar: some View {
        ViewThatFits(in: .horizontal) {
            fullTopbar
            HStack(spacing: 4) {
                Text(tab.selected.map { NoteItem(path: $0, isFolder: false).title } ?? "Notes").lineLimit(1)
                Spacer(minLength: 0)
                Menu {
                    ForEach(EditorMode.allCases, id: \.self) { mode in
                        Button(mode.title) { store.activate(pane); tab.mode = mode; store.saveWorkspace() }
                    }
                    Divider()
                    ForEach(SplitDirection.allCases, id: \.self) { direction in
                        Button(direction.title) { store.split(direction, paneID: pane.id) }
                    }
                    Button("New tab") { store.activate(pane); store.newTab() }
                    Button("Close pane") { store.closePane(pane) }
                    Button("Note details") { store.activate(pane); store.inspectorVisible = true }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28).accessibilityLabel("Pane actions")
            }.padding(.horizontal, 8).frame(height: 52).font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }.simultaneousGesture(TapGesture().onEnded { store.activate(pane) })
    }
    var fullTopbar: some View {
        HStack(spacing: 13) {
            if let selected = tab.selected {
                Image(systemName: "doc.text").foregroundStyle(Palette.muted)
                let item = NoteItem(path: selected, isFolder: false)
                Text(item.parent.isEmpty ? "Notes" : item.parent.replacingOccurrences(of: "/", with: "  /  ")).foregroundStyle(Palette.muted).lineLimit(1)
                Text("/").foregroundStyle(.quaternary)
                Text(item.title).foregroundStyle(Palette.secondary).lineLimit(1).truncationMode(.middle)
            } else { Text("Notes").foregroundStyle(Palette.muted) }
            Spacer(minLength: 10)
            if let selected = tab.selected {
                HStack(spacing: 1) {
                    ForEach(EditorMode.allCases, id: \.self) { mode in
                        Button { store.activate(pane); tab.mode = mode; store.saveWorkspace() } label: {
                            HStack(spacing: 5) { Image(systemName: mode.icon).font(.system(size: 13)); if tab.mode == mode && store.panes.count == 1 { Text(mode.title).font(.system(size: 12, weight: .medium)) } }.padding(.horizontal, 8).frame(height: 30)
                                .background(tab.mode == mode ? Palette.control : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(ChromeButtonStyle()).foregroundStyle(tab.mode == mode ? Palette.primary : Palette.muted).help(mode.title).accessibilityLabel(mode.title).accessibilityAddTraits(tab.mode == mode ? .isSelected : [])
                    }
                }.padding(2).accessibilityLabel("Document mode")
                Button { store.toggleBookmark(selected) } label: { Image(systemName: store.isBookmarked(selected) ? "bookmark.fill" : "bookmark").font(.system(size: 12)).foregroundStyle(store.isBookmarked(selected) ? Palette.accent : Palette.muted) }.buttonStyle(ChromeButtonStyle()).help("Bookmark note").accessibilityLabel("Bookmark note")
                Menu {
                    ForEach(SplitDirection.allCases, id: \.self) { direction in
                        Button(direction.title) { store.split(direction, paneID: pane.id) }
                    }
                    Button("Close pane") { store.closePane(pane) }
                    Divider()
                    if let item = store.items.first(where: { $0.path == selected }) {
                        Button(store.isPinned(selected) ? "Unpin note" : "Pin note") { store.togglePin(selected) }
                        Button("Rename…") { store.activate(pane); store.rename(item) }
                        Button("Show in Finder") { store.reveal(tab.selected) }
                        Divider(); Button("Move to Trash…", role: .destructive) { store.activate(pane); store.trash(item) }
                    }
                } label: { Image(systemName: "ellipsis").font(.system(size: 13)) }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 30, height: 30).accessibilityLabel("Note actions")
            }
            Button { store.inspectorVisible.toggle() } label: {
                Image(systemName: "sidebar.right").foregroundStyle(store.inspectorVisible ? Palette.primary : Palette.muted)
            }.help("Toggle details · ⌘⌥\\").accessibilityLabel("Toggle details sidebar")
                .accessibilityValue(store.inspectorVisible ? "Open" : "Closed")
        }.font(.system(size: 13)).padding(.horizontal, store.panes.count == 1 ? 24 : 12).frame(height: 52)
    }
    var statusbar: some View {
        HStack(spacing: 6) {
            if tab.selected != nil {
                Circle().fill(tab.conflict || tab.saveFailed ? Color.orange : Color.green).frame(width: 4, height: 4)
                Text(tab.status)
                Spacer()
                Text("\(tab.words) words"); Text("·").padding(.horizontal, 3); Text("Markdown")
            } else { Spacer(); Text("Markdown · Saved on your Mac"); Spacer() }
        }.font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.horizontal, 23).frame(height: 28).background(Palette.sidebar)
    }
    var emptyState: some View {
        VStack(spacing: 17) {
            Image(systemName: "doc.text").font(.system(size: 28, weight: .regular)).frame(width: 64, height: 64).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(Palette.accent.opacity(0.7)).padding(.bottom, 4)
            Text(store.library == nil ? "Your notes, on your Mac" : "Choose a note").font(.system(size: 28, weight: .semibold)).tracking(-0.6)
            Text(store.library == nil ? "Open a folder to start writing in Markdown." : "Select a note from the sidebar or create a new one.").font(.system(size: 13)).lineSpacing(5).multilineTextAlignment(.center).foregroundStyle(Palette.secondary)
            Button { if store.library == nil { store.chooseFolder() } else { store.activate(pane); store.create() } } label: {
                Label(store.library == nil ? "Choose a notes folder" : "New note", systemImage: store.library == nil ? "folder" : "plus").font(.system(size: 12, weight: .medium)).padding(.horizontal, 16).padding(.vertical, 10).background(Palette.action, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(.white)
            }.buttonStyle(.plain).padding(.top, 9)
            Text(store.library == nil ? "Works with any folder of .md files" : "⌘N to start writing").font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
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
    let select: () -> Void
    func makeNSView(context: Context) -> TabButton {
        let button = TabButton()
        button.isBordered = false; button.font = .systemFont(ofSize: 12)
        button.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        button.imagePosition = .imageLeft; button.lineBreakMode = .byTruncatingTail
        button.target = button; button.action = #selector(TabButton.selectTab)
        return button
    }
    func updateNSView(_ button: TabButton, context: Context) {
        button.title = title; button.tabID = id; button.select = select
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
        direction = paneDropDirection(at: info.location, in: size, header: 46)
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
            .contentShape(Rectangle())
            .onHover { hover in if hover { (horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                if dragStart == nil { dragStart = fraction }
                resize((dragStart ?? fraction) + (horizontal ? value.translation.width : value.translation.height) / length)
            }.onEnded { _ in dragStart = nil; finish() })
            .accessibilityLabel(horizontal ? "Resize panes horizontally" : "Resize panes vertically")
            .accessibilityValue("\(Int(fraction * 100)) percent")
            .accessibilityAdjustableAction { direction in resize(fraction + (direction == .increment ? 0.05 : -0.05)); finish() }
    }
}
