import Foundation
import NotesCore

struct LinkPreviewFetcher {
    private static let maximumImageBytes = 2_000_000

    private let htmlSession: URLSession
    private let imageSession: URLSession
    private let redirectDelegate: HTMLRedirectDelegate?

    init(session: URLSession? = nil) {
        if let session {
            self.htmlSession = session
            self.imageSession = session
            self.redirectDelegate = nil
        } else {
            let redirectDelegate = HTMLRedirectDelegate()
            self.redirectDelegate = redirectDelegate
            self.htmlSession = URLSession(configuration: Self.configuration(), delegate: redirectDelegate, delegateQueue: nil)
            self.imageSession = URLSession(configuration: Self.configuration())
        }
    }

    private static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.httpAdditionalHeaders = ["User-Agent": "LinearNotes/0.1 (link-preview)"]
        return configuration
    }

    func fetch(url: URL) async throws -> (title: String, description: String, imageURL: URL?, imageData: Data?, type: String?) {
        guard url.scheme?.lowercased() == "https" else {
            return ("", "", nil, nil, nil)
        }

        let (htmlData, htmlResponse) = try await htmlSession.data(for: request(for: url))
        guard let htmlHTTPResponse = htmlResponse as? HTTPURLResponse,
              isHTMLResponse(htmlHTTPResponse),
              LinkPreviewing.isSameOrigin(htmlHTTPResponse.url, as: url),
              let html = String(data: htmlData, encoding: .utf8) else {
            return ("", "", nil, nil, nil)
        }

        let pageURL = htmlHTTPResponse.url ?? url
        let parsed = LinkPreviewing.parseHTML(html, pageURL: pageURL)
        let image = try await fetchImage(from: parsed.imageURL)
        return (parsed.title, parsed.description, image.url, image.data, image.type)
    }

    private func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "GET"
        request.setValue("LinearNotes/0.1 (link-preview)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func isHTMLResponse(_ response: HTTPURLResponse) -> Bool {
        guard (200..<300).contains(response.statusCode),
              let type = mimeType(from: response) else { return false }
        return type == "text/html" || type.hasPrefix("text/")
    }

    private func fetchImage(from imageURL: URL?) async throws -> (url: URL?, data: Data?, type: String?) {
        guard let imageURL,
              imageURL.scheme?.lowercased() == "https" else {
            return (imageURL, nil, nil)
        }

        let (data, response) = try await imageSession.data(for: request(for: imageURL))
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let type = mimeType(from: httpResponse),
              (httpResponse.url ?? imageURL).scheme?.lowercased() == "https",
              type.hasPrefix("image/"),
              isAcceptableImageContentLength(httpResponse),
              data.count <= Self.maximumImageBytes else {
            return (imageURL, nil, nil)
        }
        return (httpResponse.url ?? imageURL, data, type)
    }

    private func isAcceptableImageContentLength(_ response: HTTPURLResponse) -> Bool {
        let headerLength = response.value(forHTTPHeaderField: "Content-Length")
            .flatMap { Int64($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let length = headerLength ?? response.expectedContentLength
        guard length >= 0 else { return true }
        return length <= Self.maximumImageBytes
    }

    private func mimeType(from response: HTTPURLResponse) -> String? {
        let header = response.value(forHTTPHeaderField: "Content-Type") ?? response.mimeType
        return header?.lowercased().split(separator: ";", maxSplits: 1).first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

private final class HTMLRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let originalURL = task.originalRequest?.url,
              let redirectURL = request.url,
              LinkPreviewing.isSameOrigin(redirectURL, as: originalURL) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
