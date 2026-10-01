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
    @Published var selected: String?
    @Published var markdown = ""
    @Published var mode: EditorMode = .live
    @Published var sidebarVisible = true
    @Published var inspectorVisible = false
    @Published var properties = ""
    @Published var propertyRows: [(name: String, value: String)] = []
    @Published var query = "" { didSet { refreshSearch() } }
    @Published var searchResults: [NoteSearchResult] = []
    @Published var searchError: String?
    @Published var searching = false
    @Published var quickOpenVisible = false { didSet { if quickOpenVisible { refreshSearch() } } }
    @Published var linearImportVisible = false
    @Published var headings: [NoteHeading] = []
    @Published var activeHeading = -1
    @Published var documentVersion = 0
    @Published var metadataVersion = 0
    @Published var status = "Saved locally"
    @Published var error: String?
    @Published var conflict = false
    @Published var saveFailed = false
    @Published var textSize = UserDefaults.standard.integer(forKey: "documentTextSize") == 0 ? 15 : UserDefaults.standard.integer(forKey: "documentTextSize") { didSet { UserDefaults.standard.set(textSize, forKey: "documentTextSize"); bridge?.textSize(textSize) } }
    var sessions: [String: NoteSession] = [:]
    var sessionSave: Task<Void, Never>?
    var pendingFind: String?
    var focusNewNote = false
    @Published var words = 0
    @Published var rootName = "My notes"
    var library: NoteLibrary?
    var baseline = ""
    var dirty = false
    var securityURL: URL?
    var autosave: Task<Void, Never>?
    var searchTask: Task<Void, Never>?
    var poller: Timer?
    weak var bridge: EditorBridge?
    var searchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    init(root: URL? = nil) {
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
        let drafts = selected.map { [$0: markdown] } ?? [:]
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
            sessions = nextSessions
            library = next; rootName = url.lastPathComponent; selected = nil; markdown = ""; baseline = ""; dirty = false
            error = nil; conflict = false; saveFailed = false; items = try next.scan(); documentVersion += 1
            headings = []; activeHeading = -1; refreshSearch()
            if remember, let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) { UserDefaults.standard.set(bookmark, forKey: "notesFolderBookmark") }
            let last = recovered.last ?? next.sidebar.lastSelected
            if let first = items.first(where: { !$0.isFolder && $0.path == last }) ?? next.children(of: "", in: items).first(where: { !$0.isFolder }) ?? items.first(where: { !$0.isFolder }) { select(first.path) }
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
        if let bridge, bridge.ready {
            bridge.flush { [weak self] success in if success { self?.finishSelection(path) } }
        } else { finishSelection(path) }
    }
    func openSearchResult(_ path: String) {
        pendingFind = searchTerm
        if path == selected { bridge?.find(searchTerm); pendingFind = nil } else { select(path) }
    }
    private func finishSelection(_ path: String) {
        guard path != selected, save(), let library else { return }
        do {
            let text = try library.read(path); selected = path; markdown = text; baseline = text; dirty = false
            headings = []; activeHeading = -1; mode = EditorMode(rawValue: sessions[path]?.mode ?? "live") ?? .live
            status = "Saved locally"; conflict = false; saveFailed = false; error = nil; documentVersion += 1
            mutateSidebar { $0.lastSelected = path }
        } catch { self.error = error.localizedDescription }
    }
    func changed(_ text: String, id: String) {
        guard id == selected, text != markdown else { return }
        markdown = text; dirty = text != baseline; status = dirty ? "Saving…" : "Saved locally"
        do { try library?.recordDraft(dirty ? text : nil, for: id) } catch { self.error = "Draft recovery could not be saved: " + error.localizedDescription }
        refreshSearch()
        autosave?.cancel(); autosave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350)); guard !Task.isCancelled else { return }; self?.save()
        }
    }
    @discardableResult func save() -> Bool {
        autosave?.cancel()
        guard let library, let selected, dirty || saveFailed else { return true }
        do {
            if dirty { try library.save(markdown, to: selected, expected: baseline) }
            baseline = markdown; dirty = false; status = "Saved locally"; error = nil; conflict = false; saveFailed = false
            try library.recordDraft(nil, for: selected)
            return true
        } catch {
            self.error = error.localizedDescription; status = dirty ? "Draft not saved" : "Saved; recovery cleanup failed"; saveFailed = true
            conflict = (error as? LibraryError) == .conflict || !FileManager.default.fileExists(atPath: (try? library.url(for: selected).path) ?? "")
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
            dirty = false; items = try library.scan(); self.selected = nil; error = nil; conflict = false; saveFailed = false; select(path)
        } catch { self.error = error.localizedDescription }
    }
    func refreshFromDisk() {
        guard let library else { return }
        defer { if (!searchTerm.isEmpty || quickOpenVisible) && !searching { refreshSearch() } }
        do {
            let scanned = try library.scan(); if Set(scanned) != Set(items) { items = scanned }
            guard let selected else { return }
            guard items.contains(where: { $0.path == selected }) else {
                if dirty { conflict = true; error = "This file was moved or removed outside the app. Keep your draft as a new file." }
                else { self.selected = nil; markdown = ""; baseline = ""; documentVersion += 1 }
                return
            }
            let disk = try library.read(selected)
            if disk != baseline {
                if dirty { conflict = true; error = LibraryError.conflict.localizedDescription }
                else { markdown = disk; baseline = disk; documentVersion += 1; status = "Updated from disk" }
            }
        } catch { self.error = error.localizedDescription }
    }

    var insertionParent: String { selected.map { NoteItem(path: $0, isFolder: false).parent } ?? "" }
    func rememberSession(_ data: Any, id: String, immediately: Bool = false) {
        guard id == selected, let library, JSONSerialization.isValidJSONObject(data),
              let bytes = try? JSONSerialization.data(withJSONObject: data),
              let session = try? JSONDecoder().decode(NoteSession.self, from: bytes),
              EditorMode(rawValue: session.mode) != nil else { return }
        sessions[id] = session; sessionSave?.cancel()
        if immediately { do { try library.saveSessions(sessions) } catch { self.error = error.localizedDescription }; return }
        sessionSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self, self.library?.root == library.root else { return }
            do { try library.saveSessions(self.sessions) } catch { self.error = error.localizedDescription }
        }
    }
    private func afterSave(_ action: @escaping () -> Void) {
        if let bridge, bridge.ready { bridge.flush { success in if success { action() } } }
        else if save() { action() }
    }
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
                if !folder { focusNewNote = true; finishSelection(path) }
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
            let oldSelected = selected
            let next = try library.move(path, to: parent, before: before, newName: newName)
            sessions = Dictionary(uniqueKeysWithValues: sessions.map { key, value in
                (key == path || key.hasPrefix(path + "/") ? next + key.dropFirst(path.count) : key, value)
            })
            try library.saveSessions(sessions)
            items = try library.scan(); metadataVersion += 1
            if let oldSelected, oldSelected == path || oldSelected.hasPrefix(path + "/") {
                selected = next + oldSelected.dropFirst(path.count)
            }
            if let selected { markdown = try library.read(selected); baseline = markdown; documentVersion += 1 }
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
            if selected == item.path || selected?.hasPrefix(item.path + "/") == true { selected = nil; markdown = ""; baseline = ""; documentVersion += 1 }
            sessions = sessions.filter { $0.key != item.path && !$0.key.hasPrefix(item.path + "/") }; try library.saveSessions(sessions)
            mutateSidebar { $0.remove(item.path) }; items = try library.scan()
        } catch { self.error = error.localizedDescription }
    }
    func reveal(_ path: String? = nil) { if let url = try? library?.url(for: path ?? selected ?? "") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
}
