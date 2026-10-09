import XCTest
@testable import NotesCore

private final class LinearStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: (URLRequest) -> (Int, String) = { _ in (500, "") }
    nonisolated(unsafe) static var binary: Data?
    nonisolated(unsafe) static var headers: [String: String]?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.response(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: Self.headers)!
        if status == 302, let location = Self.headers?["Location"], let url = URL(string: location) {
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: url), redirectResponse: response)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.binary ?? Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

final class LinearAPITests: XCTestCase {
    override func setUp() { LinearStub.binary = nil; LinearStub.headers = nil }
    private func client() -> LinearAPI {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [LinearStub.self]
        return LinearAPI(key: "test-key", session: URLSession(configuration: config))
    }
    func testPaginationAndReadOnlyRequests() async throws {
        var requests = 0
        LinearStub.response = { request in
            requests += 1
            XCTAssertEqual(request.url?.host, "api.linear.app")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "test-key")
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertFalse(body.contains("mutation"))
            return requests == 1 ? (200, #"{"data":{"projects":{"nodes":[{"id":"a","name":"Zulu","url":"https://linear.app/test/project/a"}],"pageInfo":{"hasNextPage":true,"endCursor":"next"}}}}"#) : (200, #"{"data":{"projects":{"nodes":[{"id":"b","name":"Alpha","url":"https://linear.app/test/project/b"}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}"#)
        }
        let projects = try await client().projects()
        XCTAssertEqual(projects.map(\.name), ["Alpha", "Zulu"]); XCTAssertEqual(requests, 2)
    }
    func testGraphQLErrorsAndPermissionFailuresAreNotSuccess() async {
        for (status, body) in [(200, #"{"data":{"projects":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}},"errors":[{"message":"Access denied"}]}"#), (200, #"{"data":{"projects":null},"errors":[{"message":"Access denied"}]}"#), (401, "")] {
            LinearStub.response = { _ in (status, body) }
            do { _ = try await client().projects(); XCTFail("Must report the API failure") } catch { XCTAssertFalse(error.localizedDescription.isEmpty); if status == 200 { XCTAssertEqual(error.localizedDescription, "Access denied") } }
        }
        LinearStub.response = { _ in XCTFail("The key must never be sent to this host"); return (200, "") }
        for reference in ["https://user@uploads.linear.app/image.png", "http://uploads.linear.app/image.png", "https://example.com:444/image.png"] {
            do { _ = try await client().image(URL(string: reference)!); XCTFail("Must reject untrusted image URLs") } catch { }
        }
        LinearStub.response = { request in XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "test-key"); return (401, "") }
        do { _ = try await client().image(URL(string: "https://uploads.linear.app/image.png")!); XCTFail("Must reject inaccessible images") } catch { }
    }
    func testImagesAuthorizeOnlyLinearUploadsAndValidateRasterData() async throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=")!
        LinearStub.binary = png
        var requests = 0
        LinearStub.response = { request in
            requests += 1
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), request.url?.host == "uploads.linear.app" ? "test-key" : nil)
            XCTAssertFalse(request.httpShouldHandleCookies)
            return (200, "")
        }
        for reference in ["https://uploads.linear.app/image.png", "https://example.com/image.png", "https://uploads.linear.app.evil.test/image.png"] {
            let data = try await client().image(URL(string: reference)!)
            XCTAssertEqual(data, png)
        }
        XCTAssertEqual(requests, 3)
        LinearStub.binary = nil
        LinearStub.response = { _ in (200, "<svg onload='alert(1)'/>") }
        do { _ = try await client().image(URL(string: "https://example.com/image.svg")!); XCTFail("Must reject non-raster data") } catch { XCTAssertEqual(error as? LibraryError, .invalidImage) }
        LinearStub.headers = ["Content-Length": String(21 * 1024 * 1024)]
        do { _ = try await client().image(URL(string: "https://example.com/image.png")!); XCTFail("Must reject oversized response") } catch { XCTAssertEqual(error as? LibraryError, .invalidImage) }
        LinearStub.headers = ["Location": "https://example.com/redirect.png"]
        LinearStub.response = { request in XCTAssertEqual(request.url?.host, "uploads.linear.app"); return (302, "") }
        do { _ = try await client().image(URL(string: "https://uploads.linear.app/image.png")!); XCTFail("Must reject redirects") } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
    }
    func testDocumentListsThenFetchesContentAndRejectsMissingContent() async throws {
        LinearStub.response = { _ in (200, #"{"data":{"project":{"documents":{"nodes":[{"id":"doc","title":"Guide","url":"https://linear.app/test/document/guide"}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}"#) }
        let documents = try await client().documents(project: "project")
        XCTAssertEqual(documents.count, 1)
        LinearStub.response = { _ in (200, ##"{"data":{"document":{"id":"doc","title":"Guide","url":"https://linear.app/test/document/guide","content":"# Body"}}}"##) }
        let document = try await client().document(id: "doc")
        XCTAssertEqual(document.content, "# Body")
        LinearStub.response = { _ in (200, #"{"data":{"document":{"id":"doc","title":"Guide","url":"https://linear.app/test/document/guide","content":null}}}"#) }
        do { _ = try await client().document(id: "doc"); XCTFail("Must not import missing content as an empty document") } catch { }
    }
}
