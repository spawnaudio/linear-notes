import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NotesCore

struct ContentView: View {
    @ObservedObject var store: NotebookStore
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    static let sidebarWidth: CGFloat = 244
    static let titlebarHeight: CGFloat = 40
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: Self.sidebarWidth).frame(width: store.sidebarVisible ? Self.sidebarWidth : 0, alignment: .leading).clipped().opacity(store.sidebarVisible ? 1 : 0).allowsHitTesting(store.sidebarVisible).accessibilityHidden(!store.sidebarVisible)
            paneTree(store.layout)
                .padding(.leading, store.sidebarVisible ? 0 : 8)
                .padding(.trailing, 8)
            if store.inspectorVisible { inspector.frame(width: 280).padding(.trailing, 8) }
        }
        .padding(.bottom, 8)
        .background(Palette.shell)
        .foregroundStyle(Palette.secondary)
        .font(Typeface.ui(13, 500))
        .tint(Palette.accent)
        .buttonStyle(ChromeButtonStyle())
        .frame(minWidth: store.inspectorVisible ? 1100 : 820, minHeight: 540)
        .ignoresSafeArea(edges: [.leading, .trailing, .bottom])
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: store.sidebarVisible)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: store.inspectorVisible)
        .sheet(isPresented: $store.quickOpenVisible) { QuickOpenView(store: store) }
        .sheet(isPresented: $store.linearImportVisible) { LinearImportView(store: store) }
        .sheet(isPresented: $store.linearRefreshVisible) { LinearRefreshView(store: store) }
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Spacer()
                NavigationButtons(store: store)
            }.padding(.horizontal, 8).frame(height: Self.titlebarHeight)
            HStack(spacing: 6) {
                Menu {
                    Button("Import from Linear…") { store.linearImportVisible = true }
                    Divider()
                    Button("Open another folder…", action: store.chooseFolder)
                    Button("Show in Finder") { store.reveal("") }
                } label: {
                    HStack(spacing: 8) {
                        IdentityTile(name: store.rootName)
                        Text(store.rootName).font(Typeface.ui(13, 600)).foregroundStyle(Palette.primary).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Palette.muted)
                    }.padding(.horizontal, 4).frame(height: 28).contentShape(Rectangle())
                }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().accessibilityLabel("Notebook: \(store.rootName)")
                Spacer(minLength: 4)
                Button { store.quickOpenVisible = true } label: { ChromeIcon("magnifyingglass", size: 13, color: Palette.secondary) }
                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 6))
                    .help("Search · ⌘K").accessibilityLabel("Search")
                Button { store.create() } label: { ChromeIcon("square.and.pencil", size: 13, color: Palette.primary) }
                    .background(Palette.control, in: RoundedRectangle(cornerRadius: 6))
                    .help("New note · ⌘N").accessibilityLabel("New note")
            }.padding(.horizontal, 10).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    NavigationRow(title: "Recent", icon: "clock", selected: store.library != nil && store.selected == nil) { store.showRecent() }
                        .disabled(store.library == nil)
                    SectionHeader(title: "Favorites", expanded: !store.favoritesCollapsed) { store.favoritesCollapsed.toggle() }
                        .onDrop(of: [.text], isTargeted: nil) { loadDrop($0) { store.bookmarkDrop($0) } }
                    if !store.favoritesCollapsed {
                        if store.bookmarks.isEmpty {
                            Text("Star a note or drag it here.").font(Typeface.ui(12)).foregroundStyle(Palette.faint).padding(.leading, 32).frame(height: 28)
                        }
                        ForEach(store.bookmarks) { item in row(item, depth: 0, bookmark: true) }
                    }
                    SectionHeader(title: "Notes", expanded: !store.notesCollapsed, add: { store.create() }, addLabel: "New note") { store.notesCollapsed.toggle() }
                        .onDrop(of: [.text], isTargeted: nil) { loadDrop($0) { store.move($0, parent: "") } }
                    if !store.notesCollapsed {
                        tree(parent: "", depth: 0)
                        if store.library == nil {
                            NavigationRow(title: "Open a notes folder…", icon: "folder", selected: false, action: store.chooseFolder)
                        } else if store.items.isEmpty {
                            NavigationRow(title: "Write your first note", icon: "plus", selected: false) { store.create() }
                        }
                    }
                    Color.clear.frame(height: 60).contentShape(Rectangle()).onDrop(of: [.text], isTargeted: nil) { loadDrop($0) { store.move($0, parent: "") } }
                }.padding(.horizontal, 8)
            }.scrollIndicators(.never)
            HStack {
                Menu {
                    Button("Keyboard shortcuts") { showShortcuts() }
                    Button("Backing up and recovering notes") { showBackupHelp() }
                } label: {
                    Image(systemName: "questionmark").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
                        .frame(width: 24, height: 24).background(Palette.raised, in: Circle()).overlay { Circle().stroke(Palette.border) }
                }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().accessibilityLabel("Help")
                Spacer()
            }.padding(.horizontal, 14).frame(height: 44)
        }.background(Palette.shell)
    }

    func tree(parent: String, depth: Int) -> AnyView {
        AnyView(ForEach(store.children(parent)) { item in
            row(item, depth: depth)
            if item.isFolder && store.isExpanded(item.path) { tree(parent: item.path, depth: depth + 1) }
        })
    }
    func row(_ item: NoteItem, depth: Int, bookmark: Bool = false) -> some View {
        SidebarRow(store: store, item: item, depth: depth, bookmark: bookmark)
    }
    func loadDrop(_ providers: [NSItemProvider], action: @escaping @MainActor (String) -> Void) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: String.self) { value, _ in if let value { Task { @MainActor in action(value) } } }
        return true
    }

    func paneTree(_ layout: PaneLayout) -> AnyView {
        switch layout {
        case .pane(let id):
            if let pane = store.panes.first(where: { $0.id == id }) {
                return AnyView(NotePaneView(store: store, pane: pane).id(id))
            }
            return AnyView(EmptyView())
        case .split(let id, let horizontal, let fraction, let first, let second):
            return AnyView(PaneSplitView(horizontal: horizontal, fraction: fraction, resize: { value in
                store.layout = store.layout.resizing(id, to: value)
            }, finish: store.saveWorkspace, first: paneTree(first), second: paneTree(second)))
        }
    }

    var inspector: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Details").font(Typeface.ui(13, 500)).foregroundStyle(Palette.primary)
                Spacer()
                Button { store.inspectorVisible = false } label: { ChromeIcon("xmark", size: 11) }
                    .accessibilityLabel("Close details").help("Close details · ⌘⌥\\")
            }.padding(.leading, 16).padding(.trailing, 8).frame(height: 44)
            Rectangle().fill(Palette.divider).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let selected = store.selected {
                        railSection("Properties", action: store.mode == .reading ? nil : { store.bridge?.showProperties() }, actionIcon: "plus", actionLabel: "Edit properties") {
                            if store.propertyRows.isEmpty {
                                Text(store.properties.isEmpty ? "No properties" : store.properties).foregroundStyle(Palette.faint)
                            } else {
                                ForEach(Array(store.propertyRows.enumerated()), id: \.offset) { entry in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(entry.element.name).foregroundStyle(Palette.muted).frame(width: 84, alignment: .leading).lineLimit(1)
                                        Text(entry.element.value.isEmpty ? "—" : entry.element.value).foregroundStyle(Palette.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                                    }.frame(minHeight: 30)
                                }
                            }
                        }
                        if !store.headings.isEmpty && store.mode != .source {
                            railSection("Outline") {
                                ForEach(store.headings) { heading in
                                    Button { store.bridge?.jumpToHeading(heading.id) } label: {
                                        Text(heading.text.isEmpty ? "Untitled heading" : heading.text).lineLimit(1)
                                            .foregroundStyle(store.activeHeading == heading.id ? Palette.primary : Palette.secondary)
                                            .padding(.leading, CGFloat(max(0, heading.level - 1) * 12) + 8).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                                            .background(store.activeHeading == heading.id ? Palette.selected : .clear, in: RoundedRectangle(cornerRadius: 6))
                                    }.buttonStyle(.plain).accessibilityAddTraits(store.activeHeading == heading.id ? .isSelected : [])
                                }
                            }
                        }
                        railSection("Note") {
                            railRow("textformat.size", "\(store.words) words")
                            railRow("clock", store.editedLabel(selected).isEmpty ? store.status : store.editedLabel(selected))
                            railRow(store.mode.icon, store.mode.title)
                        }
                        if let source = store.propertyRows.first(where: { $0.name == "linearDocumentUrl" })?.value,
                           let url = URL(string: source.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))), url.scheme == "https", url.host == "linear.app" {
                            railSection("Linear") {
                                Link(destination: url) { railRow("arrow.up.right", "Open original") }
                                if NoteLibrary.linearSource(in: store.markdown) != nil {
                                    Button { store.linearRefreshVisible = true } label: { railRow("arrow.clockwise", "Refresh from Linear…") }.buttonStyle(.plain)
                                }
                            }
                        } else if NoteLibrary.linearSource(in: store.markdown) != nil {
                            railSection("Linear") {
                                Button { store.linearRefreshVisible = true } label: { railRow("arrow.clockwise", "Refresh from Linear…") }.buttonStyle(.plain)
                            }
                        }
                        railSection("File") {
                            Text(selected).foregroundStyle(Palette.muted).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            if !NoteLibrary.remoteImageURLs(in: store.markdown).isEmpty {
                                Button { store.saveImagesLocally() } label: { railRow("photo", store.savingImages ? "Saving images…" : "Save images locally") }
                                    .buttonStyle(.plain).disabled(store.savingImages)
                            }
                            Button { store.togglePin(selected) } label: { railRow(store.isPinned(selected) ? "pin.slash" : "pin", store.isPinned(selected) ? "Unpin from folder" : "Pin to top of folder") }.buttonStyle(.plain)
                            Button { store.reveal() } label: { railRow("folder", "Show in Finder") }.buttonStyle(.plain)
                        }
                    } else {
                        Text("Open a note to see its details.").foregroundStyle(Palette.faint)
                    }
                }.font(Typeface.ui(13)).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Palette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.border, lineWidth: 1) }
        .padding(.top, Self.titlebarHeight)
    }

    func railSection<Content: View>(_ title: String, action: (() -> Void)? = nil, actionIcon: String = "plus", actionLabel: String = "", @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(Typeface.ui(12, 500)).foregroundStyle(Palette.muted)
                Spacer()
                if let action { Button(action: action) { ChromeIcon(actionIcon, size: 11) }.buttonStyle(ChromeButtonStyle(size: 22)).accessibilityLabel(actionLabel).help(actionLabel) }
            }.frame(height: 22)
            content()
        }
    }
    func railRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            ChromeIcon(icon, size: 12)
            Text(text).foregroundStyle(Palette.secondary).lineLimit(1)
            Spacer(minLength: 0)
        }.frame(height: 30).contentShape(Rectangle())
    }
}

struct SidebarRow: View {
    @ObservedObject var store: NotebookStore
    let item: NoteItem
    let depth: Int
    let bookmark: Bool
    @State private var hovering = false
    @State private var dropEdge: Int? = nil
    @FocusState private var focused: Bool
    var body: some View {
        let isSelected = store.selected == item.path
        let expanded = store.isExpanded(item.path)
        HStack(spacing: 8) {
            ChromeIcon(item.isFolder ? (expanded && !bookmark ? "folder.fill" : "folder") : "doc.text", size: 13, color: isSelected ? Palette.primary : Palette.muted)
            Text(item.title).font(Typeface.ui(13, 500)).foregroundStyle(isSelected ? Palette.primary : Palette.secondary).lineLimit(1)
            if item.isFolder && !bookmark {
                Image(systemName: "triangle.fill").font(.system(size: 5)).foregroundStyle(Palette.muted).rotationEffect(.degrees(expanded ? 180 : 90))
            }
            Spacer(minLength: 3)
            if store.isPinned(item.path) && !bookmark { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(Palette.faint) }
        }.padding(.leading, CGFloat(depth * 20 + 8)).padding(.trailing, 8).frame(height: 30)
            .background(isSelected ? Palette.selected : hovering ? Palette.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: dropEdge == -1 ? .top : .bottom) { if let edge = dropEdge, edge != 0 { Rectangle().fill(Palette.accent).frame(height: 2) } }
            .overlay { if dropEdge == 0 { RoundedRectangle(cornerRadius: 6).stroke(Palette.accent, lineWidth: 1) } }
            .contentShape(Rectangle()).onTapGesture { store.select(item.path) }.onHover { hovering = $0 }
            .focusable().focused($focused).onKeyPress(.return) { store.select(item.path); return .handled }
            .onKeyPress(.space) { store.select(item.path); return .handled }
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(focused ? Palette.accent : .clear, lineWidth: 2) }
            .accessibilityAction { store.select(item.path) }
            .accessibilityAddTraits(store.selected == item.path ? .isSelected : [])
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
            .accessibilityLabel(item.title).accessibilityValue(item.isFolder ? (store.isExpanded(item.path) ? "Expanded folder" : "Collapsed folder") : (store.selected == item.path ? "Selected note" : "Note"))
            .help(item.path)
            .onDrag { NSItemProvider(object: item.path as NSString) }
            .onDrop(of: [.text], delegate: NoteDropDelegate(store: store, item: item, bookmark: bookmark, edge: $dropEdge))
            .contextMenu {
                if item.isFolder { Button("New note here") { store.create(parent: item.path) }; Button("New folder here…") { store.create(folder: true, parent: item.path) }; Divider() }
                Button(store.isPinned(item.path) ? "Unpin" : "Pin to top of folder") { store.togglePin(item.path) }
                Button(store.isBookmarked(item.path) ? "Remove from Favorites" : "Add to Favorites") { store.toggleBookmark(item.path) }
                Divider(); Button("Rename…") { store.rename(item) }; Button("Show in Finder") { store.reveal(item.path) }
                Divider(); Button("Move to Trash…", role: .destructive) { store.trash(item) }
            }
    }
}

struct NoteDropDelegate: DropDelegate {
    let store: NotebookStore
    let item: NoteItem
    let bookmark: Bool
    @Binding var edge: Int?
    func dropUpdated(info: DropInfo) -> DropProposal? {
        edge = info.location.y < 8 ? -1 : (item.isFolder && !bookmark && info.location.y < 24 ? 0 : 1)
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { edge = nil }
    func performDrop(info: DropInfo) -> Bool {
        let placement = edge ?? -1; edge = nil
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        _ = provider.loadObject(ofClass: String.self) { value, _ in
            guard let path = value else { return }
            Task { @MainActor in
                guard path != item.path, store.items.contains(where: { $0.path == path }) else { return }
                if bookmark {
                    let list = store.bookmarks.map(\.path)
                    let index = list.firstIndex(of: item.path) ?? 0
                    let before = placement < 0 ? item.path : (list.indices.contains(index + 1) ? list[index + 1] : nil)
                    store.bookmarkDrop(path, before: before)
                } else if placement == 0 { store.move(path, parent: item.path) }
                else {
                    let siblings = store.children(item.parent).map(\.path); let index = siblings.firstIndex(of: item.path) ?? 0
                    let before = placement < 0 ? item.path : (siblings.indices.contains(index + 1) ? siblings[index + 1] : nil)
                    store.move(path, parent: item.parent, before: before)
                }
            }
        }
        return true
    }
}
