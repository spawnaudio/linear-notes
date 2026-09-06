import XCTest
@testable import NotesCore

final class LinkPreviewTests: XCTestCase {
    func testNormalizeRejectsJavascriptAndKeepsHTTPS() {
        XCTAssertNil(LinkPreviewing.normalizeURL("javascript:alert(1)"))
        XCTAssertEqual(LinkPreviewing.normalizeURL("HTTPS://WWW.Example.com/a/?q=1#frag")?.absoluteString, "https://www.example.com/a/?q=1")
    }

    func testParseOpenGraphAndResolveRelativeImage() {
        let html = """
        <html><head>
        <title>Fallback</title>
        <meta property="og:title" content="mymind is the extension for your mind.">
        <meta property="og:description" content="A private place to save notes.">
        <meta property="og:image" content="/og.png">
        </head></html>
        """
        let page = URL(string: "https://mymind.com/page")!
        let parsed = LinkPreviewing.parseHTML(html, pageURL: page)
        XCTAssertEqual(parsed.title, "mymind is the extension for your mind.")
        XCTAssertEqual(parsed.description, "A private place to save notes.")
        XCTAssertEqual(parsed.imageURL?.absoluteString, "https://mymind.com/og.png")
    }

    func testCacheRoundTripDoesNotTouchMarkdown() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try NoteLibrary(root: root)
        let note = try library.create(name: "Note", content: "# Hi\n")
        let url = URL(string: "https://example.com/a")!
        let preview = LinkPreview(title: "Example", description: "Hello", imageURL: "https://cdn.example/a.png", imageFile: nil, fetchedAt: Date(timeIntervalSince1970: 1))
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10])
        try library.savePreview(preview, for: url, imageData: png, type: "image/png")
        XCTAssertEqual(try library.read(note), "# Hi\n")
        let stored = try XCTUnwrap(library.preview(for: url))
        XCTAssertEqual(stored.title, "Example")
        XCTAssertEqual(stored.description, "Hello")
        XCTAssertEqual(library.previewImageData(for: url)?.prefix(4), png.prefix(4))
        XCTAssertEqual(try NoteLibrary(root: root).preview(for: url)?.title, "Example")
    }

    func testMissingPreviewIsNil() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNil(try NoteLibrary(root: root).preview(for: URL(string: "https://example.com")!))
    }
}
