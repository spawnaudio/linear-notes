import XCTest
@testable import NotesCore

private final class LinearStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: (URLRequest) -> (Int, String) = { _ in (500, "") }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.response(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

final class LinearAPITests: XCTestCase {
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
        for reference in ["https://example.com/image.png", "https://uploads.linear.app.evil.test/image.png", "https://user@uploads.linear.app/image.png", "http://uploads.linear.app/image.png"] {
            do { _ = try await client().image(URL(string: reference)!); XCTFail("Must reject untrusted image URLs") } catch { }
        }
        LinearStub.response = { request in XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "test-key"); return (401, "") }
        do { _ = try await client().image(URL(string: "https://uploads.linear.app/image.png")!); XCTFail("Must reject inaccessible images") } catch { }
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
