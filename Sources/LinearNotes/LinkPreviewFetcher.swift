import Foundation
import NotesCore

struct LinkPreviewFetcher {
    private let session: URLSession

    init(session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.httpAdditionalHeaders = ["User-Agent": "LinearNotes/0.1 (link-preview)"]
        return URLSession(configuration: configuration)
    }()) {
        self.session = session
    }

    func fetch(url: URL) async throws -> (title: String, description: String, imageURL: URL?, imageData: Data?, type: String?) {
        guard url.scheme?.lowercased() == "https" else {
            return ("", "", nil, nil, nil)
        }

        let (htmlData, htmlResponse) = try await session.data(for: request(for: url))
        guard let htmlHTTPResponse = htmlResponse as? HTTPURLResponse,
              isHTMLResponse(htmlHTTPResponse),
              isSameOrigin(htmlHTTPResponse.url, as: url),
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

    private func isSameOrigin(_ finalURL: URL?, as requestURL: URL) -> Bool {
        guard let finalURL else { return true }
        return finalURL.scheme?.lowercased() == requestURL.scheme?.lowercased()
            && finalURL.host?.lowercased() == requestURL.host?.lowercased()
    }

    private func fetchImage(from imageURL: URL?) async throws -> (url: URL?, data: Data?, type: String?) {
        guard let imageURL,
              imageURL.scheme?.lowercased() == "https" else {
            return (imageURL, nil, nil)
        }

        let (data, response) = try await session.data(for: request(for: imageURL))
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let type = mimeType(from: httpResponse),
              (httpResponse.url ?? imageURL).scheme?.lowercased() == "https",
              type.hasPrefix("image/"),
              data.count <= 2_000_000 else {
            return (imageURL, nil, nil)
        }
        return (httpResponse.url ?? imageURL, data, type)
    }

    private func mimeType(from response: HTTPURLResponse) -> String? {
        let header = response.value(forHTTPHeaderField: "Content-Type") ?? response.mimeType
        return header?.lowercased().split(separator: ";", maxSplits: 1).first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
