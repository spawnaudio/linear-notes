import Foundation

public struct LinearImportSource: Equatable, Sendable {
    public let documentID: String
    public let projectID: String
    public let url: String
}

private struct LinearFrontmatter {
    let header: String
    let body: String
    let newline: String

    init?(_ text: String) {
        let expression = try! NSRegularExpression(pattern: #"\A\x{FEFF}?---(\r?\n)([\s\S]*?)^(?:---|\.\.\.)[ \t]*\r?(?:\n|\z)"#, options: .anchorsMatchLines)
        guard let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text), let separator = Range(match.range(at: 1), in: text) else { return nil }
        header = String(text[range]); body = String(text[range.upperBound...]); newline = String(text[separator])
    }

    func values(_ key: String) -> [String] {
        header.components(separatedBy: "\n").filter { $0.hasPrefix(key + ":") }.compactMap { line in
            let value = String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\"") { return try? JSONDecoder().decode(String.self, from: Data(value.utf8)) }
            if value.hasPrefix("'"), value.hasSuffix("'") { return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
            return value
        }
    }

    func value(_ key: String) -> String? { let values = values(key); return values.count == 1 ? values[0] : nil }

    func replacing(_ key: String, with value: String?) -> String {
        let expression = try! NSRegularExpression(pattern: "^" + key + #":[^\r\n]*(?:\r?\n)?"#, options: .anchorsMatchLines)
        var result = header
        for match in expression.matches(in: header, range: NSRange(header.startIndex..., in: header)).reversed() {
            result.replaceSubrange(Range(match.range, in: result)!, with: value.map { key + ": " + $0 + newline } ?? "")
        }
        return result
    }
}

private struct MarkdownImageReference {
    let range: NSRange
    let url: URL
    var prefix = ""
    var suffix = ""
}

extension NoteLibrary {
    static func hasLinearDocumentID(_ id: String, in text: String) -> Bool {
        LinearFrontmatter(text)?.values("linearDocumentId").contains { $0.lowercased() == id.lowercased() } == true
    }

    static func validLinearURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return url.scheme == "https" && url.host == "linear.app" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }

    public static func linearSource(in text: String) -> LinearImportSource? {
        guard let header = LinearFrontmatter(text), let id = header.value("linearDocumentId"), UUID(uuidString: id) != nil,
              let project = header.value("linearProjectId"), UUID(uuidString: project) != nil,
              let url = header.value("linearDocumentUrl"), validLinearURL(url) else { return nil }
        return LinearImportSource(documentID: id.lowercased(), projectID: project.lowercased(), url: url)
    }

    public static func refreshedLinearMarkdown(_ document: LinearDocument, replacing current: String) throws -> String {
        guard let source = linearSource(in: current), source.documentID == document.id.lowercased(),
              validLinearURL(document.url), let content = document.content, let header = LinearFrontmatter(current) else { throw LibraryError.invalidPath }
        let url = String(data: try JSONEncoder().encode(document.url), encoding: .utf8)!
        return header.replacing("linearDocumentUrl", with: url) + (LinearFrontmatter(content)?.body ?? content)
    }

    /// A separate incoming copy must not take ownership of the original's import identity.
    public static func unlinkedLinearMarkdown(_ text: String) -> String {
        guard let header = LinearFrontmatter(text) else { return text }
        let withoutID = header.replacing("linearDocumentId", with: nil) + header.body
        guard let updated = LinearFrontmatter(withoutID) else { return text }
        return updated.replacing("linearProjectId", with: nil) + updated.body
    }

    public static func remoteImageURLs(in text: String) -> [URL] {
        var seen: Set<URL> = []
        return imageReferences(in: text).compactMap { seen.insert($0.url).inserted ? $0.url : nil }
    }

    public static func replacingImageURLs(in text: String, with replacements: [URL: String]) -> String {
        var result = text
        for reference in imageReferences(in: text).reversed() {
            guard let replacement = replacements[reference.url], let range = Range(reference.range, in: result) else { continue }
            result.replaceSubrange(range, with: reference.prefix + replacement + reference.suffix)
        }
        return result
    }

    private static func imageReferences(in text: String) -> [MarkdownImageReference] {
        // shortcut: Markdown image syntax only; extend for HTML images if Linear imports require them.
        let masked = NSMutableString(string: text)
        func hide(_ range: NSRange) {
            let original = (text as NSString).substring(with: range)
            masked.replaceCharacters(in: range, with: String(original.utf16.map { $0 == 10 ? "\n" : " " }.joined()))
        }
        let headerLength = LinearFrontmatter(text)?.header.utf16.count ?? 0
        if headerLength > 0 { hide(NSRange(location: 0, length: headerLength)) }
        var offset = 0, fence: Character?, fenceLength = 0
        for line in text.components(separatedBy: "\n") {
            if offset < headerLength { offset += line.utf16.count + 1; continue }
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            while trimmed.hasPrefix(">") { trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces) }
            let marker = trimmed.first, length = trimmed.prefix { $0 == marker }.count
            if (marker == "`" || marker == "~") && length >= 3 {
                if fence == nil { fence = marker; fenceLength = length }
                else if fence == marker && length >= fenceLength && trimmed.dropFirst(length).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                hide(NSRange(location: offset, length: line.utf16.count))
            } else if fence != nil || line.hasPrefix("    ") || line.hasPrefix("\t") { hide(NSRange(location: offset, length: line.utf16.count)) }
            offset += line.utf16.count + 1
        }
        var characters = Array((masked as String).utf16), index = 0
        func escaped(_ position: Int) -> Bool {
            var preceding = position - 1, count = 0
            while preceding >= 0 && characters[preceding] == 92 { count += 1; preceding -= 1 }
            return count % 2 == 1
        }
        // Match equal backtick runs, including multiline spans, before looking for image syntax.
        while index < characters.count {
            guard characters[index] == 96, !escaped(index) else { index += 1; continue }
            let start = index
            while index < characters.count && characters[index] == 96 { index += 1 }
            let length = index - start
            var end = index
            while end < characters.count {
                guard characters[end] == 96 else { end += 1; continue }
                let run = end
                while end < characters.count && characters[end] == 96 { end += 1 }
                if end - run == length {
                    hide(NSRange(location: start, length: end - start)); index = end; break
                }
            }
        }
        characters = Array((masked as String).utf16)
        let markdown = masked as String
        func label(_ text: String) -> String {
            text.replacingOccurrences(of: ##"\\([!"#$%&'()*+,\-./:;<=>?@\[\]^_`{|}~\\])"##, with: "$1", options: .regularExpression).split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        }
        func brackets(at start: Int) -> (value: String, end: Int)? {
            guard start < characters.count, characters[start] == 91 else { return nil }
            var end = start + 1, depth = 1
            while end < characters.count {
                if !escaped(end) {
                    if characters[end] == 91 { depth += 1 }
                    if characters[end] == 93 { depth -= 1; if depth == 0 { return (String(decoding: characters[(start + 1)..<end], as: UTF16.self), end + 1) } }
                }
                end += 1
            }
            return nil
        }
        func destination(at start: Int) -> (range: NSRange, url: URL, end: Int)? {
            var first = start
            while first < characters.count && [9, 10, 13, 32].contains(characters[first]) { first += 1 }
            guard first < characters.count else { return nil }
            let angled = characters[first] == 60
            if angled { first += 1 }
            var end = first, depth = 0
            while end < characters.count {
                let c = characters[end]
                if !escaped(end) {
                    if angled && c == 62 { break }
                    if angled && [10, 13, 60].contains(c) { return nil }
                    if !angled {
                        if c == 40 { depth += 1 }
                        if c == 41 { if depth == 0 { break }; depth -= 1 }
                        if [9, 10, 13, 32].contains(c) { break }
                    }
                }
                end += 1
            }
            guard end > first, depth == 0, !angled || (end < characters.count && characters[end] == 62) else { return nil }
            let raw = String(decoding: characters[first..<end], as: UTF16.self)
            let unescaped = raw.replacingOccurrences(of: ##"\\([!"#$%&'()*+,\-./:;<=>?@\[\]^_`{|}~\\])"##, with: "$1", options: .regularExpression)
            guard let url = URL(string: unescaped), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return nil }
            return (NSRange(location: first, length: end - first), url, end + (angled ? 1 : 0))
        }
        var definitions: [String: (url: URL, title: String)] = [:]
        let definitionEnd = try! NSRegularExpression(pattern: #"(?:[ \t\r\n]+("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\((?:\\.|[^)\\])*\)))?[ \t]*(?:\r?\n|\z)"#)
        let reference = try! NSRegularExpression(pattern: #"^ {0,3}\[((?:\\.|[^\]\\\n])+)\]:[ \t]*(?:\r?\n[ \t]*)?"#, options: .anchorsMatchLines)
        for match in reference.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown)) {
            let key = label((markdown as NSString).substring(with: match.range(at: 1)))
            if definitions[key] == nil, let value = destination(at: NSMaxRange(match.range)),
               let ending = definitionEnd.firstMatch(in: markdown, options: .anchored, range: NSRange(location: value.end, length: characters.count - value.end)) {
                let titleRange = ending.range(at: 1)
                definitions[key] = (value.url, titleRange.location == NSNotFound ? "" : " " + (text as NSString).substring(with: titleRange))
            }
        }
        var references: [MarkdownImageReference] = []
        let close = try! NSRegularExpression(pattern: #"(?:[ \t\r\n]+(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\((?:\\.|[^)\\])*\)))?[ \t\r\n]*\)"#)
        index = 0
        while index < characters.count {
            guard characters[index] == 33, !escaped(index), let alt = brackets(at: index + 1) else { index += 1; continue }
            if alt.end < characters.count && characters[alt.end] == 40 {
                if let value = destination(at: alt.end + 1) {
                    if close.firstMatch(in: markdown, options: .anchored, range: NSRange(location: value.end, length: characters.count - value.end)) != nil { references.append(MarkdownImageReference(range: value.range, url: value.url)) }
                }
            } else {
                let explicit = brackets(at: alt.end)
                let key = label(explicit.flatMap { $0.value.isEmpty ? nil : $0.value } ?? alt.value)
                if let definition = definitions[key] {
                    let end = explicit?.end ?? alt.end
                    let altText = (text as NSString).substring(with: NSRange(location: index, length: alt.end - index))
                    references.append(MarkdownImageReference(range: NSRange(location: index, length: end - index), url: definition.url, prefix: altText + "(<", suffix: ">" + definition.title + ")"))
                }
            }
            index = alt.end
        }
        return references
    }
}
