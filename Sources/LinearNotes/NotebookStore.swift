import SwiftUI
import AppKit
import Combine
import NotesCore

enum EditorMode: String, CaseIterable { case live, reading, source
    var title: String { switch self { case .live: "Live Preview"; case .reading: "Reading"; case .source: "Source" } }
    var icon: String { switch self { case .live: "pencil.line"; case .reading: "book"; case .source: "chevron.left.forwardslash.chevron.right" } }
}

struct NoteHeading: Identifiable { let id: Int; let level: Int; let text: String }

@MainActor final class NotebookStore: ObservableObject {
    @Published var items: [NoteItem] = []
    @Published var panes: [NotePane]
    @Published var layout: PaneLayout
    @Published var activePaneID: UUID
    var paneObservers: [AnyCancellable] = []
    var selected: String? { get { activeTab.selected } set { activeTab.selected = newValue } }
    var markdown: String { get { activeTab.markdown } set { activeTab.markdown = newValue } }
    var mode: EditorMode { get { activeTab.mode } set { activeTab.mode = newValue; saveWorkspace() } }
    @Published var sidebarVisible = true
    @Published var inspectorVisible = false
    var properties: String { get { activeTab.properties } set { activeTab.properties = newValue } }
    var propertyRows: [(name: String, value: String)] { get { activeTab.propertyRows } set { activeTab.propertyRows = newValue } }
    @Published var query = "" { didSet { refreshSearch() } }
    @Published var searchResults: [NoteSearchResult] = []
    @Published var searchError: String?
    @Published var searching = false
    @Published var quickOpenVisible = false { didSet { if quickOpenVisible { refreshSearch() } } }
    @Published var linearImportVisible = false
    var headings: [NoteHeading] { get { activeTab.headings } set { activeTab.headings = newValue } }
    var activeHeading: Int { get { activeTab.activeHeading } set { activeTab.activeHeading = newValue } }
    var documentVersion: Int { get { activeTab.documentVersion } set { activeTab.documentVersion = newValue } }
    @Published var metadataVersion = 0
    var status: String { get { activeTab.status } set { activeTab.status = newValue } }
    var error: String? { get { activeTab.error } set { activeTab.error = newValue } }
    var conflict: Bool { get { activeTab.conflict } set { activeTab.conflict = newValue } }
    var saveFailed: Bool { get { activeTab.saveFailed } set { activeTab.saveFailed = newValue } }
    @Published var textSize = UserDefaults.standard.integer(forKey: "documentTextSize") == 0 ? 15 : UserDefaults.standard.integer(forKey: "documentTextSize") { didSet { UserDefaults.standard.set(textSize, forKey: "documentTextSize"); allTabs.forEach { $0.bridge?.textSize(textSize) } } }
    var sessions: [String: NoteSession] = [:]
    var sessionSave: Task<Void, Never>?
    var pendingFind: String? { get { activeTab.pendingFind } set { activeTab.pendingFind = newValue } }
    var focusNewNote: Bool { get { activeTab.focusNewNote } set { activeTab.focusNewNote = newValue } }
    var words: Int { get { activeTab.words } set { activeTab.words = newValue } }
    @Published var rootName = "My notes"
    var library: NoteLibrary?
    var baseline: String { get { activeTab.baseline } set { activeTab.baseline = newValue } }
    var dirty: Bool { get { activeTab.dirty } set { activeTab.dirty = newValue } }
    var securityURL: URL?
    var autosave: Task<Void, Never>? { get { activeTab.autosave } set { activeTab.autosave = newValue } }
    var searchTask: Task<Void, Never>?
    var poller: Timer?
    var bridge: EditorBridge? { activeTab.bridge }
    var searchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    init(root: URL? = nil) {
        let pane = NotePane(tabs: [NoteTab()])
        panes = [pane]; layout = .pane(pane.id); activePaneID = pane.id; observePanes()
        let args = ProcessInfo.processInfo.arguments
        if let root { open(root, remember: false) }
        else if let index = args.firstIndex(of: "--library"), args.indices.contains(index + 1) {
            open(URL(fileURLWithPath: args[index + 1]), remember: false)
        } else if let data = UserDefaults.standard.data(forKey: "notesFolderBookmark") {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale) {
                open(url)
            }
        }
        poller = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshFromDisk() }
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Open notes folder"; panel.message = "Choose a folder containing your Markdown files."
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
    func refreshSearch() {
        searchTask?.cancel(); searchError = nil
        guard let library, !searchTerm.isEmpty || quickOpenVisible else { searchResults = []; searching = false; return }
        let root = library.root, term = query, notes = items
        let drafts = Dictionary(allTabs.compactMap { tab in tab.selected.map { ($0, tab.markdown) } }, uniquingKeysWith: { _, last in last })
        searching = true
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(180))
                let scan = Task.detached { try NoteLibrary(root: root).search(term, in: notes, drafts: drafts) }
                let results = try await withTaskCancellationHandler { try await scan.value } onCancel: { scan.cancel() }
                guard !Task.isCancelled, let self, self.library?.root == root, self.query == term else { return }
                self.searchResults = results; self.searching = false
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self?.searchError = error.localizedDescription; self?.searchResults = []; self?.searching = false } }
        }
    }
    func open(_ url: URL, remember: Bool = true) { afterSave { [self] in finishOpen(url, remember: remember) } }
    private func finishOpen(_ url: URL, remember: Bool) {
        do {
            let acquired = url.startAccessingSecurityScopedResource()
            let next: NoteLibrary, recovered: [String], nextSessions: [String: NoteSession]
            do { next = try NoteLibrary(root: url); _ = try next.scan(); recovered = try next.recoverDrafts(); nextSessions = try next.sessions() }
            catch { if acquired { url.stopAccessingSecurityScopedResource() }; throw error }
            securityURL?.stopAccessingSecurityScopedResource(); securityURL = acquired ? url : nil
            sessionSave?.cancel(); resetWorkspace(); sessions = nextSessions
            library = next; rootName = url.lastPathComponent; selected = nil; markdown = ""; baseline = ""; dirty = false
            error = nil; conflict = false; saveFailed = false; items = try next.scan(); documentVersion += 1
            headings = []; activeHeading = -1; refreshSearch()
            if remember, let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) { UserDefaults.standard.set(bookmark, forKey: "notesFolderBookmark") }
            let last = recovered.last ?? next.sidebar.lastSelected
            let restored = restoreWorkspace()
            if !restored || !recovered.isEmpty, let first = items.first(where: { !$0.isFolder && $0.path == last }) ?? next.children(of: "", in: items).first(where: { !$0.isFolder }) ?? items.first(where: { !$0.isFolder }) { select(first.path) }
            if !recovered.isEmpty { error = "Recovered \(recovered.count) unsaved draft(s) as separate notes. Your originals are unchanged." }
        } catch { self.error = error.localizedDescription }
    }

    func children(_ parent: String) -> [NoteItem] { library?.children(of: parent, in: items) ?? [] }
    var bookmarks: [NoteItem] { (library?.sidebar.bookmarks ?? []).compactMap { path in items.first { $0.path == path } } }
    func isPinned(_ path: String) -> Bool { library?.sidebar.pinned.contains(path) == true }
    func isBookmarked(_ path: String) -> Bool { library?.sidebar.bookmarks.contains(path) == true }
    func isExpanded(_ path: String) -> Bool { library?.sidebar.expanded.contains(path) == true }
    func mutateSidebar(_ mutation: (inout SidebarState) -> Void) {
        guard let library else { return }; mutation(&library.sidebar); metadataVersion += 1
        do { try library.saveSidebar() } catch { self.error = error.localizedDescription }
    }
    func toggleExpanded(_ path: String) { mutateSidebar { if !$0.expanded.insert(path).inserted { $0.expanded.remove(path) } } }
    func togglePin(_ path: String) { mutateSidebar { if !$0.pinned.insert(path).inserted { $0.pinned.remove(path) } } }
    func toggleBookmark(_ path: String) { mutateSidebar { if $0.bookmarks.contains(path) { $0.bookmarks.removeAll { $0 == path } } else { $0.bookmarks.append(path) } } }

    func select(_ path: String) {
        if let item = items.first(where: { $0.path == path }), item.isFolder { toggleExpanded(path); return }
        guard path != selected else { return }
        afterSave { [self] in finishSelection(path) }
    }
    func openSearchResult(_ path: String) {
        pendingFind = searchTerm
        if path == selected { bridge?.find(searchTerm); pendingFind = nil } else { select(path) }
    }
    func dropNote(_ path: String, in pane: NotePane, direction: SplitDirection?) {
        afterSave { [self] in
            guard panes.contains(where: { $0.id == pane.id }), items.contains(where: { $0.path == path && !$0.isFolder }), let library else { return }
            if let direction {
                do {
                    let tab = NoteTab(); tab.selected = path; tab.markdown = try library.read(path); tab.baseline = tab.markdown
                    tab.session = sessions[path]; tab.mode = EditorMode(rawValue: tab.session?.mode ?? "live") ?? .live
                    let next = NotePane(tabs: [tab]); insertPane(next, beside: pane, direction: direction)
                    observePanes(); activate(next)
                } catch { self.error = error.localizedDescription }
            } else { activate(pane); finishSelection(path) }
        }
    }
    private func finishSelection(_ path: String) {
        guard let library else { return }
        do {
            let text = try library.read(path), find = pendingFind
            pendingFind = nil
            if let existing = activePane.tabs.first(where: { $0.selected == path }) { activate(activePane, tab: existing); if let find { existing.bridge?.find(find) }; return }
            let tab = selected == nil ? activeTab : NoteTab()
            if tab !== activeTab { activePane.tabs.append(tab); activePane.selectedTabID = tab.id; observePanes() }
            tab.selected = path; tab.markdown = text; tab.baseline = text; tab.dirty = false
            tab.headings = []; tab.activeHeading = -1; tab.session = sessions[path]
            tab.mode = EditorMode(rawValue: tab.session?.mode ?? "live") ?? .live
            tab.status = "Saved locally"; tab.conflict = false; tab.saveFailed = false; tab.error = nil; tab.documentVersion += 1
            tab.pendingFind = find
            mutateSidebar { $0.lastSelected = path }; saveWorkspace()
        } catch { self.error = error.localizedDescription }
    }
    func changed(_ text: String, id: String, tab: NoteTab? = nil) {
        let tab = tab ?? activeTab
        guard allTabs.contains(where: { $0 === tab }), id == tab.selected, text != tab.markdown else { return }
        // ponytail: reload sibling views to share drafts; use incremental updates if large notes make this slow.
        for view in allTabs where view.selected == id {
            view.markdown = text; view.dirty = text != view.baseline; view.status = view.dirty ? "Saving…" : "Saved locally"
            if view !== tab { view.documentVersion += 1 }
        }
        do { try library?.recordDraft(tab.dirty ? text : nil, for: id) } catch { tab.error = "Draft recovery could not be saved: " + error.localizedDescription }
        refreshSearch()
        tab.autosave?.cancel(); tab.autosave = Task { [weak self, weak tab] in
            try? await Task.sleep(for: .milliseconds(350)); guard !Task.isCancelled, let tab else { return }; self?.save(tab: tab)
        }
    }
    @discardableResult func save(tab: NoteTab? = nil) -> Bool {
        let tab = tab ?? activeTab
        tab.autosave?.cancel()
        guard let library, let selected = tab.selected, tab.dirty || tab.saveFailed else { return true }
        do {
            if tab.dirty { try library.save(tab.markdown, to: selected, expected: tab.baseline) }
            for view in allTabs where view.selected == selected {
                view.baseline = tab.markdown; view.dirty = false; view.status = "Saved locally"; view.error = nil; view.conflict = false; view.saveFailed = false
            }
            try library.recordDraft(nil, for: selected)
            return true
        } catch {
            tab.error = error.localizedDescription; tab.status = tab.dirty ? "Draft not saved" : "Saved; recovery cleanup failed"; tab.saveFailed = true
            tab.conflict = (error as? LibraryError) == .conflict || !FileManager.default.fileExists(atPath: (try? library.url(for: selected).path) ?? "")
            return false
        }
    }
    func keepBoth() {
        if let bridge, bridge.ready { bridge.flush { [self] _ in finishKeepBoth() } } else { finishKeepBoth() }
    }
    private func finishKeepBoth() {
        guard let selected, let library else { return }
        let item = NoteItem(path: selected, isFolder: false)
        let parentExists = item.parent.isEmpty || items.contains { $0.isFolder && $0.path == item.parent }
        let draftParent = parentExists ? item.parent : ""
        var index = 1; var name = item.title + " — My draft"
        while items.contains(where: { $0.parent == draftParent && $0.title == name }) { index += 1; name = item.title + " — My draft \(index)" }
        do {
            let path = try library.create(name: name, parent: draftParent, content: markdown)
            try library.recordDraft(nil, for: selected)
            let external = try? library.read(selected)
            for tab in allTabs where tab.selected == selected {
                tab.autosave?.cancel(); tab.dirty = false; tab.conflict = false; tab.saveFailed = false; tab.error = nil
                tab.markdown = external ?? ""; tab.baseline = tab.markdown
                if external == nil { tab.selected = nil }
                tab.documentVersion += 1
            }
            dirty = false; items = try library.scan(); self.selected = nil; error = nil; conflict = false; saveFailed = false; finishSelection(path)
        } catch { self.error = error.localizedDescription }
    }
    func refreshFromDisk() {
        guard let library else { return }
        defer { if (!searchTerm.isEmpty || quickOpenVisible) && !searching { refreshSearch() } }
        do {
            let scanned = try library.scan(); if Set(scanned) != Set(items) { items = scanned }
            for tab in allTabs {
                guard let selected = tab.selected else { continue }
                guard items.contains(where: { $0.path == selected }) else {
                    if tab.dirty { tab.conflict = true; tab.error = "This file was moved or removed outside the app. Keep your draft as a new file." }
                    else { tab.selected = nil; tab.markdown = ""; tab.baseline = ""; tab.documentVersion += 1 }
                    continue
                }
                let disk = try library.read(selected)
                if disk != tab.baseline {
                    if tab.dirty { tab.conflict = true; tab.error = LibraryError.conflict.localizedDescription }
                    else { tab.markdown = disk; tab.baseline = disk; tab.documentVersion += 1; tab.status = "Updated from disk" }
                }
            }
        } catch { self.error = error.localizedDescription }
    }

    var insertionParent: String { selected.map { NoteItem(path: $0, isFolder: false).parent } ?? "" }
    func rememberSession(_ data: Any, id: String, immediately: Bool = false, tab: NoteTab? = nil) {
        let tab = tab ?? activeTab
        guard allTabs.contains(where: { $0 === tab }), id == tab.selected, let library, JSONSerialization.isValidJSONObject(data),
              let bytes = try? JSONSerialization.data(withJSONObject: data),
              let session = try? JSONDecoder().decode(NoteSession.self, from: bytes),
              EditorMode(rawValue: session.mode) != nil else { return }
        tab.session = session; tab.mode = EditorMode(rawValue: session.mode) ?? .live
        sessions[id] = session; sessionSave?.cancel()
        if immediately { do { try library.saveSessions(sessions); saveWorkspace() } catch { self.error = error.localizedDescription }; return }
        sessionSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self, self.library?.root == library.root else { return }
            do { try library.saveSessions(self.sessions); self.saveWorkspace() } catch { self.error = error.localizedDescription }
        }
    }
    func afterSave(_ action: @escaping () -> Void) { flushAll { success in if success { action() } } }
    func create(folder: Bool = false, parent: String? = nil) {
        guard library != nil else { chooseFolder(); return }
        afterSave { [self] in
            guard let library else { return }
            let destination = parent ?? insertionParent
            do {
                let path: String
                if folder {
                    let alert = NSAlert(); alert.messageText = "New folder"; alert.informativeText = "Give this folder a name."
                    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 310, height: 25)); input.placeholderString = "Folder name"
                    alert.accessoryView = input; alert.addButton(withTitle: "Create"); alert.addButton(withTitle: "Cancel"); alert.window.initialFirstResponder = input
                    guard alert.runModal() == .alertFirstButtonReturn else { return }
                    path = try library.create(name: input.stringValue, parent: destination, folder: true)
                } else { path = try library.createUnique(parent: destination) }
                items = try library.scan(); query = ""
                if !destination.isEmpty { mutateSidebar { $0.expanded.insert(destination) } }
                if !folder { finishSelection(path); focusNewNote = true }
            } catch { self.error = error.localizedDescription }
        }
    }
    func rename(_ item: NoteItem) { afterSave { [self] in finishRename(item) } }
    private func finishRename(_ item: NoteItem) {
        let alert = NSAlert(); alert.messageText = "Rename \(item.isFolder ? "folder" : "note")"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 310, height: 25)); input.stringValue = item.title
        alert.accessoryView = input; alert.addButton(withTitle: "Rename"); alert.addButton(withTitle: "Cancel"); alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let ext = (item.name as NSString).pathExtension
        move(item.path, parent: item.parent, newName: item.isFolder ? name : name + "." + ext)
    }
    func move(_ path: String, parent: String, before: String? = nil, newName: String? = nil) {
        afterSave { [self] in finishMove(path, parent: parent, before: before, newName: newName) }
    }
    private func finishMove(_ path: String, parent: String, before: String?, newName: String?) {
        guard let library else { return }
        do {
            // Seed order from what is actually visible, including previously unindexed files.
            library.sidebar.order[parent] = children(parent).map(\.path)
            let next = try library.move(path, to: parent, before: before, newName: newName)
            sessions = Dictionary(uniqueKeysWithValues: sessions.map { key, value in
                (key == path || key.hasPrefix(path + "/") ? next + key.dropFirst(path.count) : key, value)
            })
            try library.saveSessions(sessions)
            items = try library.scan(); metadataVersion += 1
            for tab in allTabs {
                if let selected = tab.selected, selected == path || selected.hasPrefix(path + "/") {
                    tab.selected = next + selected.dropFirst(path.count)
                }
                if let selected = tab.selected { tab.markdown = try library.read(selected); tab.baseline = tab.markdown; tab.documentVersion += 1 }
            }
            saveWorkspace()
            if !parent.isEmpty { mutateSidebar { $0.expanded.insert(parent) } }
        } catch { self.error = error.localizedDescription }
    }
    func bookmarkDrop(_ path: String, before: String? = nil) {
        guard items.contains(where: { $0.path == path }) else { return }
        mutateSidebar { state in
            state.bookmarks.removeAll { $0 == path }
            if let before, let index = state.bookmarks.firstIndex(of: before) { state.bookmarks.insert(path, at: index) }
            else { state.bookmarks.append(path) }
        }
    }
    func trash(_ item: NoteItem) { afterSave { [self] in finishTrash(item) } }
    private func finishTrash(_ item: NoteItem) {
        guard let library else { return }
        let alert = NSAlert(); alert.messageText = "Move “\(item.title)” to Trash?"; alert.informativeText = item.isFolder ? "The folder and its contents can be restored from Finder’s Trash." : "You can restore this note from Finder’s Trash."
        alert.addButton(withTitle: "Move to Trash"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.trashItem(at: library.url(for: item.path), resultingItemURL: nil)
            for tab in allTabs where tab.selected == item.path || tab.selected?.hasPrefix(item.path + "/") == true {
                tab.selected = nil; tab.markdown = ""; tab.baseline = ""; tab.documentVersion += 1
            }
            saveWorkspace()
            sessions = sessions.filter { $0.key != item.path && !$0.key.hasPrefix(item.path + "/") }; try library.saveSessions(sessions)
            mutateSidebar { $0.remove(item.path) }; items = try library.scan()
        } catch { self.error = error.localizedDescription }
    }
    func reveal(_ path: String? = nil) { if let url = try? library?.url(for: path ?? selected ?? "") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
}
