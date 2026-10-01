import Foundation

extension NoteLibrary {
    public func noteURL(_ reference: String, in note: String) throws -> URL {
        let file = try imageURL(reference, in: note)
        guard ["md", "markdown"].contains(file.pathExtension.lowercased()) else { throw LibraryError.invalidPath }
        _ = try read(String(file.path.dropFirst(root.path.count + 1)))
        return file
    }

    public func noteReference(to path: String, from note: String) throws -> String {
        _ = try url(for: path); _ = try url(for: note)
        return relativeReference(to: path, from: note)
    }

    private func relativeReference(to path: String, from note: String) -> String {
        let target = path.split(separator: "/"), source = NoteItem(path: note, isFolder: false).parent.split(separator: "/")
        let common = zip(source, target).prefix { $0 == $1 }.count
        let relative = String(repeating: "../", count: source.count - common) + target.dropFirst(common).joined(separator: "/")
        return relative.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "/-._~")))!
    }

    func rebaseLinks(_ text: String, from old: String, to next: String, moved: String, target: String) -> String {
        // Inline Markdown links and reference definitions; leave code and frontmatter verbatim.
        let links = try! NSRegularExpression(pattern: #"!?\[(?:\\.|[^\]\\])*\]\((?:<([^>\n]+)>|([^\s)]+))(?:\s+["'][^"']*["'])?\)|^ {0,3}\[[^\]]+\]:\s*(?:<([^>\n]+)>|(\S+))"#)
        let inlineCode = try! NSRegularExpression(pattern: #"(`+).*?\1"#)
        var output: [String] = [], fence: Character?, fenceLength = 0
        var frontmatter = text.hasPrefix("---\n") || text.hasPrefix("---\r\n") || text.hasPrefix("\u{FEFF}---")
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if frontmatter {
                output.append(line)
                if index > 0 && ["---", "..."].contains(trimmed) { frontmatter = false }
                continue
            }
            let marker = trimmed.first
            let count = trimmed.prefix { $0 == marker }.count
            if (marker == "`" || marker == "~") && count >= 3 {
                if fence == nil { fence = marker; fenceLength = count }
                else if marker == fence && count >= fenceLength { fence = nil }
                output.append(line); continue
            }
            var revised = line
            if fence == nil && !line.hasPrefix("    ") && !line.hasPrefix("\t") {
                let code = inlineCode.matches(in: line, range: NSRange(line.startIndex..., in: line))
                for match in links.matches(in: line, range: NSRange(line.startIndex..., in: line)).reversed() {
                    guard !code.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) else { continue }
                    let capture = (1...4).map { match.range(at: $0) }.first { $0.location != NSNotFound }!
                    guard let range = Range(capture, in: revised), var parts = URLComponents(string: String(revised[range])),
                          parts.scheme == nil, parts.host == nil, !parts.path.isEmpty,
                          let file = try? imageURL(String(revised[range]), in: old) else { continue }
                    let destination = String(file.path.dropFirst(root.path.count + 1))
                    let image = line[Range(match.range, in: line)!].hasPrefix("!")
                    let managedImage = destination.hasPrefix("Attachments/") && UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil
                    guard image ? managedImage : ["md", "markdown"].contains(file.pathExtension.lowercased()) else { continue }
                    let relocated = destination == moved || destination.hasPrefix(moved + "/") ? target + destination.dropFirst(moved.count) : destination
                    if old != next || relocated != destination {
                        parts.percentEncodedPath = relativeReference(to: relocated, from: next)
                        revised.replaceSubrange(range, with: parts.string!)
                    }
                }
            }
            output.append(revised)
        }
        return output.joined(separator: "\n")
    }
}
