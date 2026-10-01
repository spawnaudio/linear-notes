import Foundation
import ImageIO

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

public enum LibraryError: LocalizedError, Equatable {
    case invalidPath, invalidName, exists, conflict, unsupportedEncoding, folderCycle, invalidImage, attachmentFolder
    public var errorDescription: String? {
        switch self {
        case .invalidPath: "This item is outside the notes folder, or is a symbolic link."
        case .invalidName: "Use a name without slashes, a leading dot, or a colon."
        case .exists: "An item with this name already exists."
        case .conflict: "This file changed outside the app. Your draft is still here. Keep both versions before continuing."
        case .unsupportedEncoding: "This file is not UTF-8 Markdown. Convert it to UTF-8 before editing."
        case .folderCycle: "A folder cannot be moved inside itself."
        case .invalidImage: "Choose a PNG, JPEG, GIF, or WebP image under 20 MB and 40 megapixels."
        case .attachmentFolder: "Keep the Attachments folder at the notebook root so image links stay valid. Move notes inside it individually."
        }
    }
}

public struct NoteSearchResult: Identifiable, Sendable {
    public var id: String { item.path }
    public let item: NoteItem
    public let excerpt: String
    public let titleMatch: Bool
}

/// Storage shared with a future iOS host. Markdown is the source of truth.
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
                    if path == "Attachments" {
                        let assets = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey])
                        if !assets.isEmpty, try assets.allSatisfy({
                            let regular = try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
                            return ["png", "jpg", "gif", "webp"].contains($0.pathExtension.lowercased()) && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil && regular
                        }) { continue }
                    }
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

    public func search(_ query: String, in items: [NoteItem], drafts: [String: String] = [:]) throws -> [NoteSearchResult] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // ponytail: scan notebook text on demand; add an index if large notebooks make this slow.
        return try items.filter { !$0.isFolder }.compactMap { item in
            try Task.checkCancellation()
            let text = try drafts[item.path] ?? read(item.path)
            let titleMatch = item.path.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            let match = term.isEmpty ? nil : text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive])
            guard term.isEmpty || titleMatch || match != nil else { return nil }
            let start = match.map { text.index($0.lowerBound, offsetBy: -35, limitedBy: text.startIndex) ?? text.startIndex } ?? text.startIndex
            let end = text.index(start, offsetBy: 160, limitedBy: text.endIndex) ?? text.endIndex
            let excerpt = (start > text.startIndex ? "…" : "") + text[start..<end].split(whereSeparator: \.isWhitespace).joined(separator: " ") + (end < text.endIndex ? "…" : "")
            return NoteSearchResult(item: item, excerpt: excerpt, titleMatch: titleMatch)
        }.sorted { a, b in
            if a.titleMatch != b.titleMatch { return a.titleMatch }
            return a.item.path.localizedStandardCompare(b.item.path) == .orderedAscending
        }
    }

    public static func imageType(_ data: Data) throws -> (extension: String, mime: String) {
        guard !data.isEmpty, data.count <= 20 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 40_000_000 / height else { throw LibraryError.invalidImage }
        switch type {
        case "public.png": return ("png", "image/png")
        case "public.jpeg": return ("jpg", "image/jpeg")
        case "com.compuserve.gif": return ("gif", "image/gif")
        case "org.webmproject.webp": return ("webp", "image/webp")
        default: throw LibraryError.invalidImage
        }
    }

    public func storeImage(_ data: Data, for note: String) throws -> String {
        _ = try read(note)
        let type = try Self.imageType(data)
        let directory = try url(for: "Attachments")
        if !fm.fileExists(atPath: directory.path) { try fm.createDirectory(at: directory, withIntermediateDirectories: false) }
        let name = UUID().uuidString.lowercased() + "." + type.extension
        try data.write(to: url(for: "Attachments/" + name), options: .withoutOverwriting)
        return String(repeating: "../", count: NoteItem(path: note, isFolder: false).parent.split(separator: "/").count) + "Attachments/" + name
    }

    public func imageURL(_ reference: String, in note: String) throws -> URL {
        guard let parts = URLComponents(string: reference), parts.scheme == nil, parts.host == nil,
              !parts.path.isEmpty, !parts.path.hasPrefix("/") else { throw LibraryError.invalidPath }
        let destination = URL(fileURLWithPath: parts.path, relativeTo: try url(for: note).deletingLastPathComponent()).standardizedFileURL
        guard destination.path.hasPrefix(root.path + "/") else { throw LibraryError.invalidPath }
        return try url(for: String(destination.path.dropFirst(root.path.count + 1)))
    }

    public func existingLinearImport(_ id: String) throws -> String? {
        guard UUID(uuidString: id) != nil else { throw LibraryError.invalidPath }
        for item in try scan() where !item.isFolder {
            let text = try read(item.path).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\u{FEFF}", with: "")
            guard text.hasPrefix("---\n"), let end = text.dropFirst(4).range(of: "\n---") else { continue }
            let header = String(text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound])
            if header.split(separator: "\n").contains(where: { line in
                let pair = line.split(separator: ":", maxSplits: 1)
                return pair.count == 2 && pair[0] == "linearDocumentId" && pair[1].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")).lowercased() == id.lowercased()
            }) { return item.path }
        }
        return nil
    }

    public func importLinearDocument(id: String, projectID: String, title: String, sourceURL: String, content: String, parent: String) throws -> String {
        guard UUID(uuidString: id) != nil, UUID(uuidString: projectID) != nil,
              let source = URL(string: sourceURL), source.scheme == "https", source.host == "linear.app" else { throw LibraryError.invalidPath }
        if let existing = try existingLinearImport(id) { return existing }
        var clean = String(title.components(separatedBy: CharacterSet(charactersIn: "/:\n\r")).joined(separator: "-").trimmingCharacters(in: CharacterSet(charactersIn: ". ")).prefix(120))
        while clean.utf8.count > 200 { clean.removeLast() }
        let base = clean.isEmpty ? "Linear document" : clean
        var name = base, number = 2
        while fm.fileExists(atPath: try url(for: parent.isEmpty ? name + ".md" : parent + "/" + name + ".md").path) { name = "\(base) \(number)"; number += 1 }
        let quotedURL = String(data: try JSONEncoder().encode(sourceURL), encoding: .utf8)!
        let metadata = "---\nlinearDocumentId: \(id.lowercased())\nlinearProjectId: \(projectID.lowercased())\nlinearDocumentUrl: \(quotedURL)\n---\n"
        return try create(name: name + ".md", parent: parent, content: metadata + content)
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
            if path == "Attachments", try fm.contentsOfDirectory(at: url(for: path), includingPropertiesForKeys: nil).contains(where: { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil && ["png", "jpg", "gif", "webp"].contains($0.pathExtension.lowercased()) }) { throw LibraryError.attachmentFolder }
            let destination = try url(for: target)
            guard !fm.fileExists(atPath: destination.path) else { throw LibraryError.exists }
            let notes = try scan().filter { !$0.isFolder }
            let rewrites = try notes.map { note in
                let next = note.path == path || note.path.hasPrefix(path + "/") ? target + note.path.dropFirst(path.count) : note.path
                let text = try read(note.path)
                return (next, text, rebaseLinks(text, from: note.path, to: next, moved: path, target: target))
            }
            try fm.moveItem(at: url(for: path), to: destination)
            var written: [(String, String, String)] = []
            do {
                for (next, original, updated) in rewrites where original != updated {
                    try save(updated, to: next, expected: original); written.append((next, original, updated))
                }
            } catch {
                // Roll back only our own edits; coordinated saves preserve concurrent external writes.
                for (next, original, updated) in written.reversed() { try? save(original, to: next, expected: updated) }
                try? fm.moveItem(at: destination, to: url(for: path))
                throw error
            }
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
