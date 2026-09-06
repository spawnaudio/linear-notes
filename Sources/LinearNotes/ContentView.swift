import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NotesCore

enum Palette {
    static let canvas = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.098, green: 0.102, blue: 0.118, alpha: 1) : .white })
    static let sidebar = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.079, green: 0.083, blue: 0.097, alpha: 1) : NSColor(red: 0.969, green: 0.969, blue: 0.976, alpha: 1) })
    static let line = Color.primary.opacity(0.075)
    static let accent = Color(red: 0.46, green: 0.44, blue: 0.85)
}

struct ContentView: View {
    @ObservedObject var store: NotebookStore
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var dragged: String?
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 244).frame(width: store.sidebarVisible ? 244 : 0, alignment: .leading).clipped().opacity(store.sidebarVisible ? 1 : 0)
            VStack(spacing: 0) {
                topbar
                Rectangle().fill(Palette.line).frame(height: 1)
                if let error = store.error {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                        Text(error).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if store.conflict { Button("Keep both", action: store.keepBoth).buttonStyle(.bordered) }
                        else { Button { store.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                    }.padding(12).background(Color.orange.opacity(0.07))
                }
                ZStack {
                    MarkdownEditorView(store: store).opacity(store.selected == nil ? 0 : 1).allowsHitTesting(store.selected != nil)
                    if store.selected == nil { emptyState }
                }
                statusbar
            }.background(Palette.canvas)
        }
        .background(Palette.canvas)
        .frame(minWidth: 740, minHeight: 540)
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9), value: store.sidebarVisible)
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer().frame(width: 68)
                Text("Linear Notes").font(.system(size: 12, weight: .semibold))
                Spacer()
            }.frame(height: 51)
            HStack(spacing: 9) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 15)).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.rootName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text("Your personal workspace").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                Menu { Button("Open another folder…", action: store.chooseFolder); Button("Show in Finder") { store.reveal("") } } label: { Image(systemName: "chevron.down").font(.system(size: 9)) }.menuStyle(.borderlessButton).frame(width: 18)
            }.padding(.horizontal, 18).padding(.top, 13).padding(.bottom, 22)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.tertiary)
                TextField("Find a note…", text: $store.query).textFieldStyle(.plain).font(.system(size: 12))
                if !store.query.isEmpty { Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.tertiary) }.buttonStyle(.plain) }
            }.padding(.horizontal, 10).padding(.vertical, 8).background(Palette.canvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.line)).padding(.horizontal, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if store.query.isEmpty {
                        sectionLabel("Bookmarks", icon: "bookmark")
                            .onDrop(of: [.text], isTargeted: nil) { loadDrop($0) { store.bookmarkDrop($0) } }
                        if store.bookmarks.isEmpty {
                            Text("Keep something close.").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.leading, 21).padding(.vertical, 8)
                        }
                        ForEach(store.bookmarks) { item in row(item, depth: 0, bookmark: true) }
                        sectionLabel("Notes", icon: nil)
                            .onDrop(of: [.text], isTargeted: nil) { loadDrop($0) { store.move($0, parent: "") } }
                        tree(parent: "", depth: 0)
                        if store.items.isEmpty {
                            Button { store.create() } label: { Label("Write your first note", systemImage: "plus").font(.system(size: 11)) }.buttonStyle(.plain).foregroundStyle(.secondary).padding(20)
                        }
                        Color.clear.frame(height: 60).contentShape(Rectangle()).onDrop(of: [.text], isTargeted: nil) { loadDrop($0) { store.move($0, parent: "") } }
                    } else {
                        sectionLabel("Search results", icon: nil)
                        let matches = store.items.filter { $0.path.localizedCaseInsensitiveContains(store.query) }
                        ForEach(matches) { item in row(item, depth: 0) }
                        if matches.isEmpty { Text("No notes found").font(.system(size: 12)).foregroundStyle(.secondary).padding(20) }
                    }
                }.padding(.horizontal, 8).padding(.top, 14)
            }
            Spacer(minLength: 0)
            HStack(spacing: 9) {
                Image(systemName: "internaldrive").font(.system(size: 11))
                Text("On your Mac").font(.system(size: 10))
                Spacer()
                Menu {
                    Button("New note…") { store.create() }
                    Button("New folder…") { store.create(folder: true) }
                    Divider(); Button("Open folder…", action: store.chooseFolder)
                } label: { Image(systemName: "plus").font(.system(size: 14)) }.menuStyle(.borderlessButton).frame(width: 23).help("New note or folder")
            }.foregroundStyle(.secondary).padding(.horizontal, 19).frame(height: 43).overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        }.background(Palette.sidebar).overlay(alignment: .trailing) { Rectangle().fill(Palette.line).frame(width: 1) }
    }

    func sectionLabel(_ title: String, icon: String?) -> some View {
        HStack {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
            Spacer()
            if title == "Notes" {
                Button { store.create() } label: { Image(systemName: "plus").font(.system(size: 10)) }.buttonStyle(.plain).foregroundStyle(.tertiary).help("New note")
            }
        }.padding(.horizontal, 12).padding(.top, title == "Notes" ? 23 : 7).padding(.bottom, 9)
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

    var topbar: some View {
        HStack(spacing: 13) {
            if !store.sidebarVisible { Spacer().frame(width: 63) }
            Button { store.sidebarVisible.toggle() } label: { Image(systemName: "sidebar.left").font(.system(size: 14)).foregroundStyle(.secondary) }.buttonStyle(.plain).help("Toggle sidebar · ⌘\\")
            if let selected = store.selected {
                let item = NoteItem(path: selected, isFolder: false)
                Text(item.parent.isEmpty ? "Notes" : item.parent.replacingOccurrences(of: "/", with: "  /  ")).foregroundStyle(.tertiary).lineLimit(1)
                Text("/").foregroundStyle(.quaternary)
                Text(item.title).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            } else { Text("A place for your thoughts").foregroundStyle(.tertiary) }
            Spacer(minLength: 10)
            if let selected = store.selected {
                HStack(spacing: 1) {
                    ForEach(EditorMode.allCases, id: \.self) { mode in
                        Button { store.mode = mode } label: {
                            HStack(spacing: 5) { Image(systemName: mode.icon).font(.system(size: 10)); if store.mode == mode { Text(mode.title).font(.system(size: 10, weight: .medium)) } }.padding(.horizontal, 8).frame(height: 25)
                                .background(store.mode == mode ? Palette.canvas : .clear, in: RoundedRectangle(cornerRadius: 5))
                                .shadow(color: .black.opacity(store.mode == mode ? 0.05 : 0), radius: 1, y: 1)
                        }.buttonStyle(.plain).foregroundStyle(store.mode == mode ? .primary : .tertiary).help(mode.title)
                    }
                }.padding(3).background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 7)).accessibilityLabel("Document mode")
                Button { store.toggleBookmark(selected) } label: { Image(systemName: store.isBookmarked(selected) ? "bookmark.fill" : "bookmark").font(.system(size: 12)).foregroundStyle(store.isBookmarked(selected) ? Palette.accent : Color.secondary) }.buttonStyle(.plain).help("Bookmark note")
                Menu {
                    if let item = store.items.first(where: { $0.path == selected }) {
                        Button(store.isPinned(selected) ? "Unpin note" : "Pin note") { store.togglePin(selected) }
                        Button("Rename…") { store.rename(item) }
                        Button("Show in Finder") { store.reveal() }
                        Divider(); Button("Move to Trash…", role: .destructive) { store.trash(item) }
                    }
                } label: { Image(systemName: "ellipsis").font(.system(size: 13)) }.menuStyle(.borderlessButton).frame(width: 20)
            }
        }.font(.system(size: 11)).padding(.horizontal, 21).frame(height: 51)
    }
    var statusbar: some View {
        HStack(spacing: 6) {
            if store.selected != nil {
                Circle().fill(store.conflict ? Color.orange : Color.green.opacity(0.65)).frame(width: 4, height: 4)
                Text(store.status)
                Spacer()
                Text("\(store.words) words"); Text("·").padding(.horizontal, 3); Text("Markdown")
            } else { Spacer(); Text("Local files. A little room to think."); Spacer() }
        }.font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 23).frame(height: 28).overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
    var emptyState: some View {
        VStack(spacing: 17) {
            Image(systemName: "doc.text").font(.system(size: 34, weight: .ultraLight)).foregroundStyle(Palette.accent.opacity(0.7)).padding(.bottom, 4)
            Text(store.library == nil ? "A little room to think." : "Make yourself a little space.").font(.system(size: 25, weight: .semibold)).tracking(-0.6)
            Text(store.library == nil ? "Notes, ideas, and the things worth keeping.\nBeautifully simple. Saved on your Mac." : "Choose a note from the sidebar,\nor start something new.").font(.system(size: 13)).lineSpacing(5).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button { if store.library == nil { store.chooseFolder() } else { store.create() } } label: {
                Label(store.library == nil ? "Choose a notes folder" : "New note", systemImage: store.library == nil ? "folder" : "plus").font(.system(size: 12, weight: .medium)).padding(.horizontal, 16).padding(.vertical, 10).background(Palette.accent, in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(.white)
            }.buttonStyle(.plain).padding(.top, 9)
            Text(store.library == nil ? "Works with any folder of .md files" : "⌘N to start writing").font(.system(size: 10)).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
    }
}

struct SidebarRow: View {
    @ObservedObject var store: NotebookStore
    let item: NoteItem
    let depth: Int
    let bookmark: Bool
    @State private var hovering = false
    @State private var dropEdge: Int? = nil
    var body: some View {
        HStack(spacing: 7) {
            if item.isFolder && !bookmark {
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).rotationEffect(.degrees(store.isExpanded(item.path) ? 90 : 0)).frame(width: 9).foregroundStyle(.tertiary)
            } else { Spacer().frame(width: 9) }
            Image(systemName: item.isFolder ? (store.isExpanded(item.path) ? "folder.fill" : "folder") : "doc.text").font(.system(size: 12, weight: .regular)).foregroundStyle(store.selected == item.path ? Palette.accent : Color.secondary.opacity(0.65)).frame(width: 15)
            Text(item.title).font(.system(size: 12, weight: store.selected == item.path ? .medium : .regular)).lineLimit(1)
            Spacer(minLength: 3)
            if store.isPinned(item.path) && !bookmark { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.tertiary) }
        }.padding(.leading, CGFloat(depth * 14 + 8)).padding(.trailing, 11).frame(height: 31)
            .background(store.selected == item.path ? Palette.accent.opacity(0.10) : hovering ? Color.primary.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: dropEdge == -1 ? .top : .bottom) { if let edge = dropEdge, edge != 0 { Rectangle().fill(Palette.accent).frame(height: 2) } }
            .overlay { if dropEdge == 0 { RoundedRectangle(cornerRadius: 5).stroke(Palette.accent, lineWidth: 1) } }
            .contentShape(Rectangle()).onTapGesture { store.select(item.path) }.onHover { hovering = $0 }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
            .help(item.path)
            .onDrag { NSItemProvider(object: item.path as NSString) }
            .onDrop(of: [.text], delegate: NoteDropDelegate(store: store, item: item, bookmark: bookmark, edge: $dropEdge))
            .contextMenu {
                if item.isFolder { Button("New note here…") { store.create(parent: item.path) }; Button("New folder here…") { store.create(folder: true, parent: item.path) }; Divider() }
                Button(store.isPinned(item.path) ? "Unpin" : "Pin to top of folder") { store.togglePin(item.path) }
                Button(store.isBookmarked(item.path) ? "Remove bookmark" : "Bookmark") { store.toggleBookmark(item.path) }
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
