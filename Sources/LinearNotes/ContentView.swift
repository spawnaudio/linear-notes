import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NotesCore

enum Palette {
    static func adaptive(_ dark: UInt32, _ light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static let canvas = adaptive(0x1F2023, 0xFFFFFF)
    static let sidebar = adaptive(0x17181B, 0xF5F5F7)
    static let panel = adaptive(0x292A2E, 0xEAEAEE)
    static let control = adaptive(0x303138, 0xE2E3E8)
    static let hover = adaptive(0x35363C, 0xEDEEF2)
    static let boundary = adaptive(0x2B2C31, 0xDDDEE4)
    static let line = adaptive(0x383A40, 0xDDDEE4)
    static let primary = adaptive(0xF1F1F3, 0x292A2E)
    static let secondary = adaptive(0xC6C7CB, 0x555861)
    static let muted = adaptive(0x92949B, 0x636670)
    static let action = Color(red: 91 / 255, green: 110 / 255, blue: 225 / 255)
    static let accent = adaptive(0x8794F5, 0x5B6EE1)
}

struct ChromeButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 30, minHeight: 30)
            .background(configuration.isPressed ? Palette.control : hovering && enabled ? Palette.hover : .clear, in: RoundedRectangle(cornerRadius: 8))
            .opacity(enabled ? 1 : 0.5)
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(focused ? Palette.accent : .clear, lineWidth: 2) }
            .onHover { hovering = $0 }
    }
}

struct ContentView: View {
    @ObservedObject var store: NotebookStore
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 280).frame(width: store.sidebarVisible ? 280 : 0, alignment: .leading).clipped().opacity(store.sidebarVisible ? 1 : 0).allowsHitTesting(store.sidebarVisible).accessibilityHidden(!store.sidebarVisible)
            VStack(spacing: 0) {
                tabstrip
                VStack(spacing: 0) {
                    topbar
                    Rectangle().fill(Palette.line).frame(height: 1)
                    if let error = store.error {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                            Text(error).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if store.conflict { Button("Keep both", action: store.keepBoth).buttonStyle(.bordered) }
                            else if store.saveFailed { Button("Retry") { store.bridge?.flush { _ in } }.buttonStyle(.bordered) }
                            else { Button { store.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(ChromeButtonStyle()).accessibilityLabel("Dismiss error") }
                        }.padding(12).background(Color.orange.opacity(0.07))
                    }
                    ZStack {
                        MarkdownEditorView(store: store).opacity(store.selected == nil ? 0 : 1).allowsHitTesting(store.selected != nil)
                        if store.selected == nil { emptyState }
                    }
                }
                .background(Palette.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.boundary, lineWidth: 1) }
                .padding(.trailing, store.inspectorVisible ? 0 : 8)
                .padding(.leading, store.sidebarVisible ? 0 : 8)
                statusbar
            }
            if store.inspectorVisible { inspector.frame(width: 280) }
        }
        .background(Palette.sidebar)
        .foregroundStyle(Palette.primary)
        .tint(Palette.accent)
        .buttonStyle(ChromeButtonStyle())
        .frame(minWidth: store.inspectorVisible ? 1100 : 820, minHeight: 540)
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: store.sidebarVisible)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: store.inspectorVisible)
        .sheet(isPresented: $store.quickOpenVisible) { QuickOpenView(store: store) }
        .sheet(isPresented: $store.linearImportVisible) { LinearImportView(store: store) }
    }

    var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer().frame(width: 68)
                Text("Linear Notes").font(.system(size: 12, weight: .semibold)).offset(y: -9)
                Spacer()
            }.frame(height: 46)
            HStack(spacing: 9) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 15)).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.rootName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text("Local workspace").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Menu { Button("Import from Linear…") { store.linearImportVisible = true }; Divider(); Button("Open another folder…", action: store.chooseFolder); Button("Show in Finder") { store.reveal("") } } label: { Image(systemName: "chevron.down").font(.system(size: 9)) }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28, height: 28).accessibilityLabel("Workspace actions")
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 18)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Palette.muted)
                TextField("Find a note…", text: $store.query).textFieldStyle(.plain).font(.system(size: 13)).accessibilityLabel("Find a note")
                if !store.query.isEmpty { Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Palette.muted) }.buttonStyle(ChromeButtonStyle()).accessibilityLabel("Clear search") }
            }.padding(.horizontal, 10).padding(.vertical, 8).background(Palette.canvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line)).padding(.horizontal, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if store.searchTerm.isEmpty {
                        sectionLabel("Bookmarks")
                            .onDrop(of: [.text], isTargeted: nil) { loadDrop($0) { store.bookmarkDrop($0) } }
                        if store.bookmarks.isEmpty {
                            Text("Drag a note here to bookmark it.").font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.leading, 21).padding(.vertical, 8)
                        }
                        ForEach(store.bookmarks) { item in row(item, depth: 0, bookmark: true) }
                        sectionLabel("Notes")
                            .onDrop(of: [.text], isTargeted: nil) { loadDrop($0) { store.move($0, parent: "") } }
                        tree(parent: "", depth: 0)
                        if store.items.isEmpty {
                            Button { store.create() } label: { Label("Write your first note", systemImage: "plus").font(.system(size: 11)) }.buttonStyle(.plain).foregroundStyle(Palette.secondary).padding(20)
                        }
                        Color.clear.frame(height: 60).contentShape(Rectangle()).onDrop(of: [.text], isTargeted: nil) { loadDrop($0) { store.move($0, parent: "") } }
                    } else {
                        sectionLabel("Search results")
                        ForEach(store.searchResults) { result in
                            Button { store.openSearchResult(result.id) } label: { SearchResultRow(result: result, query: store.query) }.buttonStyle(.plain)
                                .background(store.selected == result.id ? Palette.control : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                        if let error = store.searchError { Text(error).font(.system(size: 12)).foregroundStyle(.orange).padding(10) }
                        if store.searchResults.isEmpty { Text(store.searching ? "Searching…" : "No notes found").font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(20) }
                    }
                }.padding(.horizontal, 8).padding(.top, 14)
            }
            Spacer(minLength: 0)
            HStack(spacing: 9) {
                Image(systemName: "internaldrive").font(.system(size: 11))
                Text("On your Mac").font(.system(size: 10))
                Spacer()
                Menu {
                    Button("New note") { store.create() }
                    Button("New folder…") { store.create(folder: true) }
                    Divider(); Button("Open folder…", action: store.chooseFolder)
                } label: { Image(systemName: "plus").font(.system(size: 14)) }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 30, height: 30).accessibilityLabel("New note or folder").help("New note or folder")
            }.foregroundStyle(Palette.secondary).padding(.horizontal, 19).frame(height: 43)
        }.background(Palette.sidebar)
    }

    func sectionLabel(_ title: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
            Spacer()
            if title == "Notes" {
                Button { store.quickOpenVisible = true } label: { Image(systemName: "magnifyingglass").font(.system(size: 11)) }.help("Search notes · ⌘P").accessibilityLabel("Search notes")
                Button { store.create() } label: { Image(systemName: "plus").font(.system(size: 12)).frame(width: 28, height: 28) }.buttonStyle(ChromeButtonStyle()).accessibilityLabel("New note").foregroundStyle(Palette.muted).help("New note")
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

    var tabstrip: some View {
        HStack(spacing: 8) {
            if !store.sidebarVisible { Spacer().frame(width: 68) }
            Button { store.sidebarVisible.toggle() } label: { Image(systemName: "sidebar.left") }
                .help("Toggle sidebar · ⌘\\").accessibilityLabel("Toggle sidebar")
            HStack(spacing: 8) {
                Image(systemName: store.selected == nil ? "square.stack" : "doc.text").foregroundStyle(Palette.muted)
                Text(store.selected.map { NoteItem(path: $0, isFolder: false).title } ?? "Notes")
                    .lineLimit(1).truncationMode(.middle)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12).frame(height: 32)
            .background(Palette.control, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line, lineWidth: 1))
            .frame(maxWidth: 260, alignment: .leading)
            Button { store.create() } label: { Image(systemName: "plus") }
                .help("New note · ⌘N").accessibilityLabel("New note")
            Spacer(minLength: 0)
        }
        .font(.system(size: 14)).foregroundStyle(Palette.secondary)
        .padding(.horizontal, 12).frame(height: 46).background(Palette.sidebar)
    }

    var topbar: some View {
        HStack(spacing: 13) {
            if let selected = store.selected {
                Image(systemName: "doc.text").foregroundStyle(Palette.muted)
                let item = NoteItem(path: selected, isFolder: false)
                Text(item.parent.isEmpty ? "Notes" : item.parent.replacingOccurrences(of: "/", with: "  /  ")).foregroundStyle(Palette.muted).lineLimit(1)
                Text("/").foregroundStyle(.quaternary)
                Text(item.title).foregroundStyle(Palette.secondary).lineLimit(1).truncationMode(.middle)
            } else { Text("Notes").foregroundStyle(Palette.muted) }
            Spacer(minLength: 10)
            if let selected = store.selected {
                HStack(spacing: 1) {
                    ForEach(EditorMode.allCases, id: \.self) { mode in
                        Button { store.mode = mode } label: {
                            HStack(spacing: 5) { Image(systemName: mode.icon).font(.system(size: 13)); if store.mode == mode { Text(mode.title).font(.system(size: 12, weight: .medium)) } }.padding(.horizontal, 8).frame(height: 30)
                                .background(store.mode == mode ? Palette.control : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(ChromeButtonStyle()).foregroundStyle(store.mode == mode ? Palette.primary : Palette.muted).help(mode.title).accessibilityLabel(mode.title).accessibilityAddTraits(store.mode == mode ? .isSelected : [])
                    }
                }.padding(2).accessibilityLabel("Document mode")
                Button { store.toggleBookmark(selected) } label: { Image(systemName: store.isBookmarked(selected) ? "bookmark.fill" : "bookmark").font(.system(size: 12)).foregroundStyle(store.isBookmarked(selected) ? Palette.accent : Palette.muted) }.buttonStyle(ChromeButtonStyle()).help("Bookmark note").accessibilityLabel("Bookmark note")
                Menu {
                    if let item = store.items.first(where: { $0.path == selected }) {
                        Button(store.isPinned(selected) ? "Unpin note" : "Pin note") { store.togglePin(selected) }
                        Button("Rename…") { store.rename(item) }
                        Button("Show in Finder") { store.reveal() }
                        Divider(); Button("Move to Trash…", role: .destructive) { store.trash(item) }
                    }
                } label: { Image(systemName: "ellipsis").font(.system(size: 13)) }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 30, height: 30).accessibilityLabel("Note actions")
            }
            Button { store.inspectorVisible.toggle() } label: {
                Image(systemName: "sidebar.right").foregroundStyle(store.inspectorVisible ? Palette.primary : Palette.muted)
            }.help("Toggle details · ⌘⌥\\").accessibilityLabel("Toggle details sidebar")
                .accessibilityValue(store.inspectorVisible ? "Open" : "Closed")
        }.font(.system(size: 13)).padding(.horizontal, 24).frame(height: 52)
    }
    var inspector: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Note details").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { store.inspectorVisible = false } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Close details sidebar").help("Close details")
            }.padding(.horizontal, 20).frame(height: 46)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let selected = store.selected {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Outline").foregroundStyle(Palette.muted)
                            if store.mode == .source { Text("View the outline in Live Preview or Reading.").font(.system(size: 12)).foregroundStyle(Palette.muted) }
                            else if store.headings.isEmpty { Text("Add headings to navigate this note.").font(.system(size: 12)).foregroundStyle(Palette.muted) }
                            else {
                                ForEach(store.headings) { heading in
                                    Button { store.bridge?.jumpToHeading(heading.id) } label: {
                                        Text(heading.text.isEmpty ? "Untitled heading" : heading.text).lineLimit(2).multilineTextAlignment(.leading)
                                            .padding(.leading, CGFloat(max(0, heading.level - 1) * 12)).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                    }.buttonStyle(.plain).background(store.activeHeading == heading.id ? Palette.control : .clear, in: RoundedRectangle(cornerRadius: 6))
                                        .accessibilityAddTraits(store.activeHeading == heading.id ? .isSelected : [])
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Properties").foregroundStyle(Palette.muted)
                                Spacer()
                                Button { store.bridge?.showProperties() } label: { Image(systemName: "square.and.pencil") }
                                    .disabled(store.mode == .reading).help("Edit properties").accessibilityLabel("Edit properties")
                            }
                            VStack(alignment: .leading, spacing: 14) {
                                if store.propertyRows.isEmpty {
                                    Text(store.properties.isEmpty ? "No properties yet" : store.properties)
                                        .foregroundStyle(Palette.muted)
                                } else {
                                    ForEach(Array(store.propertyRows.enumerated()), id: \.offset) { entry in
                                        HStack(alignment: .top, spacing: 12) {
                                            Text(entry.element.name).foregroundStyle(Palette.muted).frame(width: 76, alignment: .leading)
                                            Text(entry.element.value.isEmpty ? "—" : entry.element.value)
                                                .foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                            }.font(.system(size: 12)).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            if let source = store.propertyRows.first(where: { $0.name == "linearDocumentUrl" })?.value,
                               let url = URL(string: source.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))), url.scheme == "https", url.host == "linear.app" {
                                Link("Open original in Linear", destination: url)
                            }
                            Text("Document").foregroundStyle(Palette.muted)
                            HStack { Text("Mode"); Spacer(); Picker("Mode", selection: $store.mode) {
                                ForEach(EditorMode.allCases, id: \.self) { Text($0.title).tag($0) }
                            }.labelsHidden().frame(width: 140) }
                            HStack { Text("Words"); Spacer(); Text("\(store.words)").foregroundStyle(Palette.secondary) }
                            HStack { Text("Status"); Spacer(); Text(store.status).foregroundStyle(Palette.secondary) }
                            Text(selected).font(.system(size: 12)).foregroundStyle(Palette.muted)
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Options").foregroundStyle(Palette.muted).padding(.bottom, 4)
                            Button { store.toggleBookmark(selected) } label: {
                                Label(store.isBookmarked(selected) ? "Remove bookmark" : "Bookmark note", systemImage: "bookmark")
                            }
                            Button { store.togglePin(selected) } label: {
                                Label(store.isPinned(selected) ? "Unpin note" : "Pin to top of folder", systemImage: "pin")
                            }
                            Button { store.reveal() } label: { Label("Show in Finder", systemImage: "folder") }
                        }
                    } else {
                        Text("Select a note to see its properties and options.").foregroundStyle(Palette.muted)
                    }
                }.font(.system(size: 13)).padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }.background(Palette.sidebar)
    }

    var statusbar: some View {
        HStack(spacing: 6) {
            if store.selected != nil {
                Circle().fill(store.conflict || store.saveFailed ? Color.orange : Color.green).frame(width: 4, height: 4)
                Text(store.status)
                Spacer()
                Text("\(store.words) words"); Text("·").padding(.horizontal, 3); Text("Markdown")
            } else { Spacer(); Text("Markdown · Saved on your Mac"); Spacer() }
        }.font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.horizontal, 23).frame(height: 28).background(Palette.sidebar)
    }
    var emptyState: some View {
        VStack(spacing: 17) {
            Image(systemName: "doc.text").font(.system(size: 28, weight: .regular)).frame(width: 64, height: 64).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(Palette.accent.opacity(0.7)).padding(.bottom, 4)
            Text(store.library == nil ? "Your notes, on your Mac" : "Choose a note").font(.system(size: 28, weight: .semibold)).tracking(-0.6)
            Text(store.library == nil ? "Open a folder to start writing in Markdown." : "Select a note from the sidebar or create a new one.").font(.system(size: 13)).lineSpacing(5).multilineTextAlignment(.center).foregroundStyle(Palette.secondary)
            Button { if store.library == nil { store.chooseFolder() } else { store.create() } } label: {
                Label(store.library == nil ? "Choose a notes folder" : "New note", systemImage: store.library == nil ? "folder" : "plus").font(.system(size: 12, weight: .medium)).padding(.horizontal, 16).padding(.vertical, 10).background(Palette.action, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(.white)
            }.buttonStyle(.plain).padding(.top, 9)
            Text(store.library == nil ? "Works with any folder of .md files" : "⌘N to start writing").font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
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
        HStack(spacing: 7) {
            if item.isFolder && !bookmark {
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).rotationEffect(.degrees(store.isExpanded(item.path) ? 90 : 0)).frame(width: 9).foregroundStyle(Palette.muted)
            } else { Spacer().frame(width: 9) }
            Image(systemName: item.isFolder ? (store.isExpanded(item.path) ? "folder.fill" : "folder") : "doc.text").font(.system(size: 12, weight: .regular)).foregroundStyle(store.selected == item.path ? Palette.primary : Palette.muted).frame(width: 15)
            Text(item.title).font(.system(size: 13, weight: store.selected == item.path ? .medium : .regular)).lineLimit(1)
            Spacer(minLength: 3)
            if store.isPinned(item.path) && !bookmark { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(Palette.muted) }
        }.padding(.leading, CGFloat(depth * 14 + 8)).padding(.trailing, 11).frame(height: 34)
            .background(store.selected == item.path ? Palette.control : hovering ? Palette.panel : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: dropEdge == -1 ? .top : .bottom) { if let edge = dropEdge, edge != 0 { Rectangle().fill(Palette.accent).frame(height: 2) } }
            .overlay { if dropEdge == 0 { RoundedRectangle(cornerRadius: 8).stroke(Palette.accent, lineWidth: 1) } }
            .contentShape(Rectangle()).onTapGesture { store.select(item.path) }.onHover { hovering = $0 }
            .focusable().focused($focused).onKeyPress(.return) { store.select(item.path); return .handled }
            .onKeyPress(.space) { store.select(item.path); return .handled }
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(focused ? Palette.accent : .clear, lineWidth: 2) }
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
