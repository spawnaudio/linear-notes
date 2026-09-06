import Foundation

public struct NoteItem: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let isFolder: Bool
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public var title: String { isFolder ? name : (name as NSString).deletingPathExtension }
    public var parent: String { let p = (path as NSString).deletingLastPathComponent; return p == "." ? "" : p }
    public init(path: String, isFolder: Bool) { self.path = path; self.isFolder = isFolder }
}

public struct SidebarState: Codable, Equatable, Sendable {
    public var version = 1
    public var order: [String: [String]] = [:]
    public var pinned: Set<String> = []
    public var bookmarks: [String] = []
    public var expanded: Set<String> = []
    public var lastSelected: String?
    public init() {}

    public mutating func remap(_ old: String, to new: String) {
        func map(_ p: String) -> String { p == old ? new : (p.hasPrefix(old + "/") ? new + p.dropFirst(old.count) : p) }
        pinned = Set(pinned.map(map)); expanded = Set(expanded.map(map)); bookmarks = bookmarks.map(map)
        order = Dictionary(uniqueKeysWithValues: order.map { (map($0.key), $0.value.map(map)) })
        lastSelected = lastSelected.map(map)
    }

    public mutating func remove(_ path: String) {
        func keep(_ p: String) -> Bool { p != path && !p.hasPrefix(path + "/") }
        pinned = pinned.filter(keep); expanded = expanded.filter(keep); bookmarks = bookmarks.filter(keep)
        order = order.filter { keep($0.key) }.mapValues { $0.filter(keep) }
        if let p = lastSelected, !keep(p) { lastSelected = nil }
    }
}

public enum LibraryError: LocalizedError {
    case invalidPath, invalidName, exists, conflict, unsupportedEncoding, folderCycle
    public var errorDescription: String? {
        switch self {
        case .invalidPath: "This item is outside the notes folder, or is a symbolic link."
        case .invalidName: "Use a name without slashes, a leading dot, or a colon."
        case .exists: "An item with this name already exists."
        case .conflict: "This file changed outside the app. Your draft is still here. Keep both versions before continuing."
        case .unsupportedEncoding: "This file is not UTF-8 Markdown. Convert it to UTF-8 before editing."
        case .folderCycle: "A folder cannot be moved inside itself."
        }
    }
}

/// Foundation-only storage shared with a future iOS host. Markdown is the source of truth.
public final class NoteLibrary {
    public let root: URL
    public var sidebar: SidebarState
    private let fm = FileManager.default

    public init(root: URL) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        let metadata = self.root.appendingPathComponent(".linear-notes/sidebar.json")
        if FileManager.default.fileExists(atPath: metadata.path) {
            sidebar = try JSONDecoder().decode(SidebarState.self, from: Data(contentsOf: metadata))
        } else { sidebar = SidebarState() }
    }

    public func url(for path: String) throws -> URL {
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."), !path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) else { throw LibraryError.invalidPath }
        let url = root.appendingPathComponent(path).standardizedFileURL
        let resolved = url.resolvingSymlinksInPath()
        guard resolved.path == url.path, url.path == root.path || url.path.hasPrefix(root.path + "/") else { throw LibraryError.invalidPath }
        return url
    }

    public func scan() throws -> [NoteItem] {
        var result: [NoteItem] = []
        func walk(_ folder: URL, _ prefix: String) throws {
            for url in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true { continue }
                let path = prefix + url.lastPathComponent
                if values.isDirectory == true {
                    result.append(NoteItem(path: path, isFolder: true)); try walk(url, path + "/")
                } else if ["md", "markdown"].contains(url.pathExtension.lowercased()) { result.append(NoteItem(path: path, isFolder: false)) }
            }
        }
        try walk(root, "")
        return result
    }

    public func children(of parent: String, in items: [NoteItem]) -> [NoteItem] {
        let ordering = sidebar.order[parent] ?? []
        return items.filter { $0.parent == parent }.sorted { a, b in
            if sidebar.pinned.contains(a.path) != sidebar.pinned.contains(b.path) { return sidebar.pinned.contains(a.path) }
            let ai = ordering.firstIndex(of: a.path), bi = ordering.firstIndex(of: b.path)
            if ai != nil || bi != nil { return (ai ?? Int.max) < (bi ?? Int.max) }
            if a.isFolder != b.isFolder { return a.isFolder }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    public func read(_ path: String) throws -> String {
        let data = try Data(contentsOf: url(for: path))
        guard let text = String(data: data, encoding: .utf8) else { throw LibraryError.unsupportedEncoding }
        return text
    }

    /// Compare inside a coordinated write, then replace atomically. Never overwrite a known external edit.
    public func save(_ text: String, to path: String, expected: String) throws {
        let destination = try url(for: path)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                let current = try String(contentsOf: coordinatedURL, encoding: .utf8)
                guard current == expected else { throw LibraryError.conflict }
                try Data(text.utf8).write(to: coordinatedURL, options: .atomic)
            } catch { writeError = error }
        }
        if let error = coordinationError { throw error }
        if let error = writeError { throw error }
    }

    public func saveSidebar() throws {
        let directory = root.appendingPathComponent(".linear-notes", isDirectory: true)
        if fm.fileExists(atPath: directory.path) {
            let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw LibraryError.invalidPath }
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(sidebar).write(to: directory.appendingPathComponent("sidebar.json"), options: .atomic)
    }

    public func create(name: String, parent: String = "", folder: Bool = false, content: String = "") throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.hasPrefix("."), !clean.contains("/"), !clean.contains(":"), !clean.contains("\n") else { throw LibraryError.invalidName }
        let filename = folder || ["md", "markdown"].contains((clean as NSString).pathExtension.lowercased()) ? clean : clean + ".md"
        let path = parent.isEmpty ? filename : parent + "/" + filename
        let target = try url(for: path)
        guard !fm.fileExists(atPath: target.path) else { throw LibraryError.exists }
        if folder { try fm.createDirectory(at: target, withIntermediateDirectories: false) }
        else { try Data(content.utf8).write(to: target, options: .withoutOverwriting) }
        sidebar.order[parent, default: []].append(path)
        try saveSidebar()
        return path
    }

    @discardableResult public func move(_ path: String, to parent: String, before: String? = nil, newName: String? = nil) throws -> String {
        let name = newName ?? (path as NSString).lastPathComponent
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains(":"), !name.contains("\n") else { throw LibraryError.invalidName }
        let target = parent.isEmpty ? name : parent + "/" + name
        guard parent != path, !parent.hasPrefix(path + "/") else { throw LibraryError.folderCycle }
        let oldParent = NoteItem(path: path, isFolder: false).parent
        if target != path {
            let destination = try url(for: target)
            guard !fm.fileExists(atPath: destination.path) else { throw LibraryError.exists }
            try fm.moveItem(at: url(for: path), to: destination)
            sidebar.remap(path, to: target)
        }
        sidebar.order[oldParent] = sidebar.order[oldParent, default: []].filter { $0 != path && $0 != target }
        var siblings = sidebar.order[parent, default: []].filter { $0 != target }
        if let before, let index = siblings.firstIndex(of: before) { siblings.insert(target, at: index) } else { siblings.append(target) }
        sidebar.order[parent] = siblings
        try saveSidebar()
        return target
    }
}
