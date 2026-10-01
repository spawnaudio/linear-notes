import Foundation

public struct NotePosition: Codable, Equatable, Sendable {
    public var from: Int
    public var to: Int
    public var scroll: Double
}

public struct NoteSession: Codable, Equatable, Sendable {
    public var mode: String
    public var positions: [String: NotePosition]
    public init(mode: String, positions: [String: NotePosition]) { self.mode = mode; self.positions = positions }
}

extension NoteLibrary {
    private func metadataURL(_ name: String) throws -> URL {
        let directory = root.appendingPathComponent(".linear-notes", isDirectory: true)
        let file = directory.appendingPathComponent(name)
        for url in [directory, file] where FileManager.default.fileExists(atPath: url.path) {
            guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw LibraryError.invalidPath }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return file
    }

    private func readMetadata<T: Decodable>(_ name: String, default fallback: T) throws -> T {
        let file = try metadataURL(name)
        return FileManager.default.fileExists(atPath: file.path) ? try JSONDecoder().decode(T.self, from: Data(contentsOf: file)) : fallback
    }

    private func writeMetadata<T: Encodable>(_ value: T, name: String) throws {
        try JSONEncoder().encode(value).write(to: metadataURL(name), options: .atomic)
    }

    public func sessions() throws -> [String: NoteSession] { try readMetadata("session.json", default: [:]) }
    public func saveSessions(_ value: [String: NoteSession]) throws { try writeMetadata(value, name: "session.json") }
    public func workspace<T: Decodable>() throws -> T? { try readMetadata("workspace.json", default: Optional<T>.none) }
    public func saveWorkspace<T: Encodable>(_ value: T) throws { try writeMetadata(value, name: "workspace.json") }

    public func recordDraft(_ text: String?, for path: String) throws {
        _ = try url(for: path)
        // ponytail: one small recovery file, per-note files if large drafts make typing slow.
        var drafts: [String: String] = try readMetadata("recovery.json", default: [:])
        drafts[path] = text
        try writeMetadata(drafts, name: "recovery.json")
    }

    /// Recover to separate files, preserving any original or external edits.
    public func recoverDrafts() throws -> [String] {
        var drafts: [String: String] = try readMetadata("recovery.json", default: [:])
        var recovered: [String] = []
        for path in drafts.keys.sorted() {
            _ = try url(for: path)
            let text = drafts[path]!
            if (try? read(path)) != text {
                let item = NoteItem(path: path, isFolder: false)
                let parent = FileManager.default.fileExists(atPath: try url(for: item.parent).path) ? item.parent : ""
                recovered.append(try createUnique(name: item.title + " — Recovered", parent: parent, content: text))
            }
            drafts.removeValue(forKey: path)
            try writeMetadata(drafts, name: "recovery.json")
        }
        return recovered
    }

    public func createUnique(name: String = "Untitled", parent: String = "", content: String = "") throws -> String {
        var candidate = name, number = 2
        while FileManager.default.fileExists(atPath: try url(for: parent.isEmpty ? candidate + ".md" : parent + "/" + candidate + ".md").path) {
            candidate = "\(name) \(number)"; number += 1
        }
        return try create(name: candidate, parent: parent, content: content)
    }
}
