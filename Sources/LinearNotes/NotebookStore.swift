import SwiftUI
import AppKit
import Combine
import NotesCore

enum EditorMode: String, CaseIterable { case live, reading, source
    var title: String { switch self { case .live: "Live Preview"; case .reading: "Reading"; case .source: "Source" } }
    var icon: String { switch self { case .live: "pencil.line"; case .reading: "book"; case .source: "chevron.left.forwardslash.chevron.right" } }
}

@MainActor final class NotebookStore: ObservableObject {
    @Published var items: [NoteItem] = []
    @Published var selected: String?
    @Published var markdown = ""
    @Published var mode: EditorMode = .live
    @Published var sidebarVisible = true
    @Published var query = ""
    @Published var documentVersion = 0
    @Published var metadataVersion = 0
    @Published var status = "Saved locally"
    @Published var error: String?
    @Published var conflict = false
    @Published var words = 0
    @Published var rootName = "My notes"
    var library: NoteLibrary?
    var baseline = ""
    var dirty = false
    var securityURL: URL?
    var autosave: Task<Void, Never>?
    var poller: Timer?
    weak var bridge: EditorBridge?

    init() {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--library"), args.indices.contains(index + 1) {
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
    func open(_ url: URL, remember: Bool = true) {
        guard save() else { return }
        do {
            let acquired = url.startAccessingSecurityScopedResource()
            let next: NoteLibrary
            do { next = try NoteLibrary(root: url); _ = try next.scan() }
            catch { if acquired { url.stopAccessingSecurityScopedResource() }; throw error }
            securityURL?.stopAccessingSecurityScopedResource(); securityURL = acquired ? url : nil
            library = next; rootName = url.lastPathComponent; selected = nil; markdown = ""; baseline = ""; dirty = false
            error = nil; conflict = false; items = try next.scan(); documentVersion += 1
            if remember, let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) { UserDefaults.standard.set(bookmark, forKey: "notesFolderBookmark") }
            let last = next.sidebar.lastSelected
            if let first = items.first(where: { !$0.isFolder && $0.path == last }) ?? next.children(of: "", in: items).first(where: { !$0.isFolder }) ?? items.first(where: { !$0.isFolder }) { select(first.path) }
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
    private func finishSelection(_ path: String) {
        guard path != selected, save(), let library else { return }
        do {
            let text = try library.read(path); selected = path; markdown = text; baseline = text; dirty = false
            status = "Saved locally"; conflict = false; error = nil; documentVersion += 1
            mutateSidebar { $0.lastSelected = path }
        } catch { self.error = error.localizedDescription }
    }
    func changed(_ text: String, id: String) {
        guard id == selected, text != markdown else { return }
        markdown = text; dirty = text != baseline; status = dirty ? "Saving…" : "Saved locally"
        autosave?.cancel(); autosave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350)); guard !Task.isCancelled else { return }; self?.save()
        }
    }
    @discardableResult func save() -> Bool {
        autosave?.cancel()
        guard dirty, let library, let selected else { return true }
        do {
            try library.save(markdown, to: selected, expected: baseline)
            baseline = markdown; dirty = false; status = "Saved locally"; error = nil; conflict = false; return true
        } catch {
            self.error = error.localizedDescription; status = "Draft not saved"; conflict = true; return false
        }
    }
    func keepBoth() {
        guard let selected, let library else { return }
        let item = NoteItem(path: selected, isFolder: false)
        let parentExists = item.parent.isEmpty || items.contains { $0.isFolder && $0.path == item.parent }
        let draftParent = parentExists ? item.parent : ""
        var index = 1; var name = item.title + " — My draft"
        while items.contains(where: { $0.parent == draftParent && $0.title == name }) { index += 1; name = item.title + " — My draft \(index)" }
        do {
            let path = try library.create(name: name, parent: draftParent, content: markdown)
            dirty = false; items = try library.scan(); self.selected = nil; error = nil; conflict = false; select(path)
        } catch { self.error = error.localizedDescription }
    }
    func refreshFromDisk() {
        guard let library else { return }
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
    func create(folder: Bool = false, parent: String? = nil) {
        guard library != nil else { chooseFolder(); return }
        guard save() else { return }
        let alert = NSAlert(); alert.messageText = folder ? "New folder" : "New note"; alert.informativeText = folder ? "Give this folder a name." : "Your note will be saved as a Markdown file."
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 310, height: 25)); input.placeholderString = folder ? "Folder name" : "Untitled"
        alert.accessoryView = input; alert.addButton(withTitle: "Create"); alert.addButton(withTitle: "Cancel"); alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let parent = parent ?? insertionParent
            let title = name.isEmpty ? "Untitled" : (["md", "markdown"].contains((name as NSString).pathExtension.lowercased()) ? (name as NSString).deletingPathExtension : name)
            let path = try library!.create(name: name.isEmpty ? "Untitled" : name, parent: parent, folder: folder, content: folder ? "" : "# \(title)\n\n")
            items = try library!.scan(); if !parent.isEmpty { mutateSidebar { $0.expanded.insert(parent) } }
            if !folder { mode = .live; select(path) }
        } catch { self.error = error.localizedDescription }
    }
    func rename(_ item: NoteItem) {
        guard save() else { return }
        let alert = NSAlert(); alert.messageText = "Rename \(item.isFolder ? "folder" : "note")"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 310, height: 25)); input.stringValue = item.title
        alert.accessoryView = input; alert.addButton(withTitle: "Rename"); alert.addButton(withTitle: "Cancel"); alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let ext = (item.name as NSString).pathExtension
        move(item.path, parent: item.parent, newName: item.isFolder ? name : name + "." + ext)
    }
    func move(_ path: String, parent: String, before: String? = nil, newName: String? = nil) {
        guard save(), let library else { return }
        do {
            // Seed order from what is actually visible, including previously unindexed files.
            library.sidebar.order[parent] = children(parent).map(\.path)
            let oldSelected = selected
            let next = try library.move(path, to: parent, before: before, newName: newName)
            items = try library.scan(); metadataVersion += 1
            if let oldSelected, oldSelected == path || oldSelected.hasPrefix(path + "/") {
                selected = next + oldSelected.dropFirst(path.count); documentVersion += 1
            }
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
    func trash(_ item: NoteItem) {
        guard save(), let library else { return }
        let alert = NSAlert(); alert.messageText = "Move “\(item.title)” to Trash?"; alert.informativeText = item.isFolder ? "The folder and its contents can be restored from Finder’s Trash." : "You can restore this note from Finder’s Trash."
        alert.addButton(withTitle: "Move to Trash"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.trashItem(at: library.url(for: item.path), resultingItemURL: nil)
            if selected == item.path || selected?.hasPrefix(item.path + "/") == true { selected = nil; markdown = ""; baseline = ""; documentVersion += 1 }
            mutateSidebar { $0.remove(item.path) }; items = try library.scan()
        } catch { self.error = error.localizedDescription }
    }
    func reveal(_ path: String? = nil) { if let url = try? library?.url(for: path ?? selected ?? "") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }

    func cardPreviewsJSON() -> [String: [String: String]] {
        guard let library else { return [:] }
        return library.previewIndex.reduce(into: [:]) { result, item in
            guard let url = URL(string: item.key), url.scheme?.lowercased() == "https" else { return }
            result[item.key] = cardPreviewJSON(for: url, preview: item.value)
        }
    }

    func cardPreviewJSON(for url: URL, preview: LinkPreview) -> [String: String] {
        var payload = ["title": preview.title, "description": preview.description]
        if let imageSrc = previewImageDataURL(for: url, preview: preview) {
            payload["imageSrc"] = imageSrc
        }
        return payload
    }

    private func previewImageDataURL(for url: URL, preview: LinkPreview) -> String? {
        guard let data = library?.previewImageData(for: url),
              let mime = previewImageMimeType(preview.imageFile) else { return nil }
        return "data:\(mime);base64," + data.base64EncodedString()
    }

    private func previewImageMimeType(_ imageFile: String?) -> String? {
        switch imageFile?.split(separator: ".").last?.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "webp": "image/webp"
        case "gif": "image/gif"
        default: nil
        }
    }
}
