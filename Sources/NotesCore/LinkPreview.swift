import Foundation

public struct LinkPreview: Codable, Equatable, Sendable {
    public var title: String
    public var description: String
    public var imageURL: String?
    public var imageFile: String?
    public var fetchedAt: Date

    public init(title: String, description: String, imageURL: String?, imageFile: String?, fetchedAt: Date) {
        self.title = title
        self.description = description
        self.imageURL = imageURL
        self.imageFile = imageFile
        self.fetchedAt = fetchedAt
    }
}

struct LinkPreviewStore: Codable {
    var version: Int
    var items: [String: LinkPreview]
}

public enum LinkPreviewing {
    public static func normalizeURL(_ string: String) -> URL? {
        guard var components = URLComponents(string: string),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        components.scheme = scheme
        components.host = components.host?.lowercased()
        components.fragment = nil
        return components.url
    }

    public static func parseHTML(_ html: String, pageURL: URL) -> (title: String, description: String, imageURL: URL?) {
        let metadata = metaContent(in: html)
        let title = metadata["og:title"] ?? titleContent(in: html) ?? ""
        let description = metadata["og:description"] ?? metadata["twitter:description"] ?? ""
        let image = metadata["og:image"] ?? metadata["twitter:image"]
        let imageURL = image.flatMap { URL(string: $0, relativeTo: pageURL)?.absoluteURL }
        return (title: title, description: description, imageURL: imageURL)
    }

    public static func fileName(for url: URL) -> String {
        fileName(for: url, type: nil)
    }

    public static func isSameOrigin(_ redirectURL: URL?, as requestURL: URL) -> Bool {
        guard let redirectURL else { return true }
        return redirectURL.scheme?.lowercased() == requestURL.scheme?.lowercased()
            && redirectURL.host?.lowercased() == requestURL.host?.lowercased()
    }

    static func fileName(for url: URL, type: String?) -> String {
        let normalized = normalizeURL(url.absoluteString)?.absoluteString ?? url.absoluteString
        let prefix = String(sha256Hex(normalized).prefix(16))
        let ext = safeImageExtension(type: type, url: url) ?? "jpg"
        return "previews/\(prefix).\(ext)"
    }

    private static func metaContent(in html: String) -> [String: String] {
        guard let metaRegex = try? NSRegularExpression(pattern: #"<meta\b[^>]*>"#, options: [.caseInsensitive]) else { return [:] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var result: [String: String] = [:]
        for match in metaRegex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            let attributes = attributes(in: tag)
            guard let key = attributes["property"] ?? attributes["name"],
                  let content = attributes["content"] else { continue }
            let normalizedKey = key.lowercased()
            if result[normalizedKey] == nil {
                result[normalizedKey] = unescape(content)
            }
        }
        return result
    }

    private static func attributes(in tag: String) -> [String: String] {
        guard let attrRegex = try? NSRegularExpression(
            pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>]+))"#,
            options: [.caseInsensitive]
        ) else { return [:] }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        var result: [String: String] = [:]
        for match in attrRegex.matches(in: tag, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: tag) else { continue }
            let valueRange = (2...4).compactMap { index -> Range<String.Index>? in
                let range = match.range(at: index)
                guard range.location != NSNotFound else { return nil }
                return Range(range, in: tag)
            }.first
            guard let valueRange else { continue }
            result[String(tag[nameRange]).lowercased()] = String(tag[valueRange])
        }
        return result
    }

    private static func titleContent(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<title\b[^>]*>(.*?)</title>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let titleRange = Range(match.range(at: 1), in: html) else { return nil }
        return unescape(String(html[titleRange])).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func safeImageExtension(type: String?, url: URL) -> String? {
        let allowed = Set(["jpg", "png", "webp", "gif"])
        if let type {
            switch type.lowercased().split(separator: ";", maxSplits: 1).first?.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "image/jpeg", "image/jpg": return "jpg"
            case "image/png": return "png"
            case "image/webp": return "webp"
            case "image/gif": return "gif"
            default: break
            }
        }
        let ext = url.pathExtension.lowercased()
        return allowed.contains(ext) ? ext : nil
    }

    private static func sha256Hex(_ string: String) -> String {
        sha256(Array(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ bytes: [UInt8]) -> [UInt8] {
        let constants: [UInt32] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
        ]
        var hash: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
        ]
        var message = bytes
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }
        for offset in stride(from: 0, to: message.count, by: 64) {
            var words = Array(repeating: UInt32(0), count: 64)
            for index in 0..<16 {
                let start = offset + index * 4
                words[index] = UInt32(message[start]) << 24
                    | UInt32(message[start + 1]) << 16
                    | UInt32(message[start + 2]) << 8
                    | UInt32(message[start + 3])
            }
            for index in 16..<64 {
                let s0 = rotateRight(words[index - 15], by: 7) ^ rotateRight(words[index - 15], by: 18) ^ (words[index - 15] >> 3)
                let s1 = rotateRight(words[index - 2], by: 17) ^ rotateRight(words[index - 2], by: 19) ^ (words[index - 2] >> 10)
                words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
            }
            var a = hash[0], b = hash[1], c = hash[2], d = hash[3]
            var e = hash[4], f = hash[5], g = hash[6], h = hash[7]
            for index in 0..<64 {
                let s1 = rotateRight(e, by: 6) ^ rotateRight(e, by: 11) ^ rotateRight(e, by: 25)
                let ch = (e & f) ^ (~e & g)
                let temp1 = h &+ s1 &+ ch &+ constants[index] &+ words[index]
                let s0 = rotateRight(a, by: 2) ^ rotateRight(a, by: 13) ^ rotateRight(a, by: 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ maj
                h = g; g = f; f = e; e = d &+ temp1
                d = c; c = b; b = a; a = temp1 &+ temp2
            }
            hash[0] = hash[0] &+ a; hash[1] = hash[1] &+ b; hash[2] = hash[2] &+ c; hash[3] = hash[3] &+ d
            hash[4] = hash[4] &+ e; hash[5] = hash[5] &+ f; hash[6] = hash[6] &+ g; hash[7] = hash[7] &+ h
        }
        return hash.flatMap { word in
            [
                UInt8((word >> 24) & 0xff),
                UInt8((word >> 16) & 0xff),
                UInt8((word >> 8) & 0xff),
                UInt8(word & 0xff)
            ]
        }
    }

    private static func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}
