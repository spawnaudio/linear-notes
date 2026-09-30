import Foundation

private final class LinearNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public struct LinearProject: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let url: String
}

public struct LinearDocument: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let url: String
    public let content: String?
}

public struct LinearAPI: Sendable {
    public let key: String
    private let session: URLSession
    public init(key: String, session: URLSession = .shared) { self.key = key; self.session = session }

    private struct Failure: Decodable { let message: String }
    private struct Failures: Decodable { let errors: [Failure]? }
    private struct Reply<T: Decodable>: Decodable { let data: T? }
    private struct Page: Decodable { let hasNextPage: Bool; let endCursor: String? }
    private struct Connection<T: Decodable>: Decodable { let nodes: [T]; let pageInfo: Page }
    private struct Projects: Decodable { let projects: Connection<LinearProject> }
    private struct Documents: Decodable { struct Project: Decodable { let documents: Connection<LinearDocument> }; let project: Project? }
    private struct Document: Decodable { let document: LinearDocument? }

    public struct APIError: LocalizedError, Sendable {
        public let message: String
        public init(message: String) { self.message = message }
        public var errorDescription: String? { message }
    }

    private func request<T: Decodable>(_ query: String, variables: [String: String] = [:], as: T.Type) async throws -> T {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !key.contains("\n"), !key.contains("\r") else { throw APIError(message: "Enter a valid Linear API key.") }
        var request = URLRequest(url: URL(string: "https://api.linear.app/graphql")!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue(key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, response) = try await session.data(for: request, delegate: LinearNoRedirects())
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError(message: status == 401 || status == 403 ? "Linear rejected this key. Check its read permissions." : status == 429 ? "Linear is rate limiting requests. Try again shortly." : "Linear could not load this request (HTTP \(status)).")
        }
        guard data.count <= 32 * 1024 * 1024 else { throw APIError(message: "The Linear response is too large to open.") }
        if let errors = try JSONDecoder().decode(Failures.self, from: data).errors, !errors.isEmpty { throw APIError(message: errors.map(\.message).joined(separator: "\n")) }
        let reply = try JSONDecoder().decode(Reply<T>.self, from: data)
        guard let result = reply.data else { throw APIError(message: "Linear returned no data.") }
        return result
    }

    public func projects() async throws -> [LinearProject] {
        let query = "query($after: String) { projects(first: 50, after: $after) { nodes { id name url } pageInfo { hasNextPage endCursor } } }"
        var result: [LinearProject] = [], cursor: String?
        repeat {
            try Task.checkCancellation()
            let page = try await request(query, variables: cursor.map { ["after": $0] } ?? [:], as: Projects.self).projects
            result += page.nodes
            guard !page.pageInfo.hasNextPage || (page.pageInfo.endCursor != nil && page.pageInfo.endCursor != cursor) else { throw APIError(message: "Linear returned an incomplete project list. Try again.") }
            cursor = page.pageInfo.hasNextPage ? page.pageInfo.endCursor : nil
        } while cursor != nil
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func documents(project id: String) async throws -> [LinearDocument] {
        let query = "query($id: String!, $after: String) { project(id: $id) { documents(first: 50, after: $after) { nodes { id title url } pageInfo { hasNextPage endCursor } } } }"
        var result: [LinearDocument] = [], cursor: String?
        repeat {
            try Task.checkCancellation()
            var variables = ["id": id]; if let cursor { variables["after"] = cursor }
            guard let page = try await request(query, variables: variables, as: Documents.self).project?.documents else { throw APIError(message: "This project is no longer available.") }
            result += page.nodes
            guard !page.pageInfo.hasNextPage || (page.pageInfo.endCursor != nil && page.pageInfo.endCursor != cursor) else { throw APIError(message: "Linear returned an incomplete document list. Try again.") }
            cursor = page.pageInfo.hasNextPage ? page.pageInfo.endCursor : nil
        } while cursor != nil
        return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func document(id: String) async throws -> LinearDocument {
        let query = "query($id: String!) { document(id: $id) { id title url content } }"
        guard let document = try await request(query, variables: ["id": id], as: Document.self).document, document.content != nil else { throw APIError(message: "This document's content is no longer available.") }
        return document
    }

    public func image(_ url: URL) async throws -> Data {
        guard url.scheme == "https", url.host == "uploads.linear.app", url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { throw LibraryError.invalidPath }
        var request = URLRequest(url: url); request.timeoutInterval = 30
        request.setValue(key, forHTTPHeaderField: "Authorization")
        let (bytes, response) = try await session.bytes(for: request, delegate: LinearNoRedirects())
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError(message: "This Linear image could not be loaded. Check the connection and key permissions.") }
        guard response.expectedContentLength <= 20 * 1024 * 1024 else { throw LibraryError.invalidImage }
        var data = Data()
        for try await byte in bytes {
            if data.count >= 20 * 1024 * 1024 { throw LibraryError.invalidImage }
            data.append(byte)
        }
        _ = try NoteLibrary.imageType(data)
        return data
    }
}
