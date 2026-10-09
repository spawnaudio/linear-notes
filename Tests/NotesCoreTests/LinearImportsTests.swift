import XCTest
@testable import NotesCore

final class LinearImportsTests: XCTestCase {
    private var root: URL!
    private var library: NoteLibrary!
    private let id = "77777777-7777-4777-8777-777777777777"
    private let project = "88888888-8888-4888-8888-888888888888"
    private let sourceURL = "https://linear.app/test/document/guide"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        library = try NoteLibrary(root: root)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testRefreshPreservesRawLocalPropertiesAndValidatesSource() throws {
        let path = try library.importLinearDocument(id: id, projectID: project, title: "Guide", sourceURL: sourceURL, content: "Local body", parent: "")
        let local = "\u{FEFF}" + (try library.read(path)).replacingOccurrences(of: "---\nLocal body", with: "tags: [café, notes]\ncustom: |\n  Keep exactly: yes\n  --- literal\n  ```\n---\nLocal body").replacingOccurrences(of: "\n", with: "\r\n")
        let incoming = LinearDocument(id: id.uppercased(), title: "New title", url: sourceURL + "-new", content: "---\ntags: [remote]\n---\nNew body\n")
        let updated = try NoteLibrary.refreshedLinearMarkdown(incoming, replacing: local)
        XCTAssertTrue(updated.contains("tags: [café, notes]\r\ncustom: |\r\n  Keep exactly: yes\r\n  --- literal\r\n  ```\r\n"))
        XCTAssertTrue(updated.hasPrefix("\u{FEFF}---\r\n"))
        XCTAssertTrue(updated.hasSuffix("---\r\nNew body\n"))
        XCTAssertFalse(updated.contains("tags: [remote]"))
        XCTAssertEqual(NoteLibrary.linearSource(in: updated)?.url, sourceURL + "-new")
        XCTAssertThrowsError(try NoteLibrary.refreshedLinearMarkdown(LinearDocument(id: UUID().uuidString, title: "Wrong", url: sourceURL, content: "Body"), replacing: local))
        XCTAssertThrowsError(try NoteLibrary.refreshedLinearMarkdown(LinearDocument(id: id, title: "Empty", url: sourceURL, content: nil), replacing: local))
        XCTAssertThrowsError(try NoteLibrary.refreshedLinearMarkdown(LinearDocument(id: id, title: "Unsafe", url: "https://user@linear.app/doc", content: "Body"), replacing: local))
        XCTAssertNil(NoteLibrary.linearSource(in: "---\nlinearDocumentId: \(id)\nlinearProjectId: \(project)\nlinearDocumentUrl: \(sourceURL)\n---not a delimiter\nBody"))
        XCTAssertNil(NoteLibrary.linearSource(in: (try library.read(path)).replacingOccurrences(of: "linearDocumentId:", with: "linearDocumentId: \(id)\nlinearDocumentId:")))
    }

    func testRefreshConflictAndKeepBothNeverOverwriteOriginalOrStealImportIdentity() throws {
        let path = try library.importLinearDocument(id: id, projectID: project, title: "Guide", sourceURL: sourceURL, content: "Local body", parent: "")
        let original = try library.read(path)
        let candidate = try NoteLibrary.refreshedLinearMarkdown(LinearDocument(id: id, title: "Guide", url: sourceURL, content: "Incoming body"), replacing: original)
        try library.save(original + "\nExternal edit", to: path, expected: original)
        XCTAssertThrowsError(try library.save(candidate, to: path, expected: original)) { XCTAssertEqual($0 as? LibraryError, .conflict) }
        let copy = try library.createUnique(name: "Guide — From Linear", content: NoteLibrary.unlinkedLinearMarkdown(candidate))
        XCTAssertEqual(try library.read(path), original + "\nExternal edit")
        XCTAssertNil(NoteLibrary.linearSource(in: try library.read(copy)))
        XCTAssertTrue(try library.read(copy).contains("linearDocumentUrl:"))
        XCTAssertEqual(try library.importLinearDocument(id: id, projectID: project, title: "Guide", sourceURL: sourceURL, content: "Another import", parent: ""), path)
        XCTAssertEqual(try library.read(path), original + "\nExternal edit")
    }

    func testImageReferencesIncludeInlineAndOnlyDefinitionsUsedByImages() {
        let text = #"""
        ![Nested [alt]](https://example.com/a_(b).png "Title")
        ![Escaped](https://example.com/c\(d\).png)
        ![Angled](<https://example.com/e.png> 'Title')
        ![Full][ PICTURE ] ![Collapsed][] ![Shortcut]
        [Normal link](https://example.com/link.png)
        [link][plain]
        [picture]: <https://example.com/ref.png> "Reference"
        [Collapsed]: https://example.com/collapsed.png
        [shortcut]:
          https://example.com/shortcut.png
        [plain]: https://example.com/plain.png
        """#
        XCTAssertEqual(Set(NoteLibrary.remoteImageURLs(in: text).map(\.absoluteString)), Set(["https://example.com/a_(b).png", "https://example.com/c(d).png", "https://example.com/e.png", "https://example.com/ref.png", "https://example.com/collapsed.png", "https://example.com/shortcut.png"]))
        let url = URL(string: "https://example.com/ref.png")!
        let updated = NoteLibrary.replacingImageURLs(in: text, with: [url: "../Attachments/local.png"])
        XCTAssertEqual(updated, text.replacingOccurrences(of: "![Full][ PICTURE ]", with: "![Full](<../Attachments/local.png> \"Reference\")"))
    }

    func testImageReferencesLeaveCodeFrontmatterEscapesAndPlainLinksVerbatim() {
        let url = "https://example.com/image.png"
        let text = "---\nexample: ![yaml](\(url))\n---\n![Real](\(url)) [Normal](\(url))\n\\![Escaped](\(url))\n`![Inline](\(url))`\n``\n![Multiline](\(url))\n``\n```md\n![Fence](\(url))\n```still code\n![Still fenced](\(url))\n```\n> ~~~md\n> ![Quoted code](\(url))\n> ~~~\n    ![Indented](\(url))\n"
        let updated = NoteLibrary.replacingImageURLs(in: text, with: [URL(string: url)!: "Attachments/local.png"])
        XCTAssertEqual(NoteLibrary.remoteImageURLs(in: text), [URL(string: url)!])
        XCTAssertEqual(updated, text.replacingOccurrences(of: "![Real](\(url))", with: "![Real](Attachments/local.png)"))
        XCTAssertTrue(NoteLibrary.remoteImageURLs(in: "![Invalid](\(url) invalid title)").isEmpty)
        XCTAssertTrue(NoteLibrary.remoteImageURLs(in: "![HTTP](http://example.com/image.png) ![Credentials](https://user@example.com/image.png)").isEmpty)
    }

    func testReimportStillFindsOriginalAfterLocalSourcePropertiesAreEdited() throws {
        let path = try library.importLinearDocument(id: id, projectID: project, title: "Guide", sourceURL: sourceURL, content: "Local body", parent: "")
        let original = try library.read(path)
        let edited = original.replacingOccurrences(of: "linearProjectId: " + project + "\n", with: "").replacingOccurrences(of: "linearDocumentUrl:", with: "customSourceURL:")
        try library.save(edited, to: path, expected: original)
        XCTAssertNil(NoteLibrary.linearSource(in: edited))
        XCTAssertEqual(try library.importLinearDocument(id: id, projectID: project, title: "Guide", sourceURL: sourceURL, content: "Incoming", parent: ""), path)
        XCTAssertEqual(try library.read(path), edited)
    }

    func testSharedReferenceImageRewritePreservesNormalHyperlinkAndTitle() {
        let text = "![Picture][shared] [View online][shared]\n[shared]: https://example.com/image.png \"A title\""
        let rewritten = NoteLibrary.replacingImageURLs(in: text, with: [URL(string: "https://example.com/image.png")!: "Attachments/local.png"])
        XCTAssertEqual(rewritten, "![Picture](<Attachments/local.png> \"A title\") [View online][shared]\n[shared]: https://example.com/image.png \"A title\"")
    }

    func testReferenceTitlesKeepLiteralCodeMarkersAndEscapedLabelsResolve() {
        let text = #"![Picture][my\]label] [Online][my\]label]"# + "\n" + #"[my\]label]: https://example.com/image.png "A `literal` title""#
        let rewritten = NoteLibrary.replacingImageURLs(in: text, with: [URL(string: "https://example.com/image.png")!: "Attachments/local.png"])
        XCTAssertEqual(rewritten, #"![Picture](<Attachments/local.png> "A `literal` title") [Online][my\]label]"# + "\n" + #"[my\]label]: https://example.com/image.png "A `literal` title""#)
    }

    func testDuplicateImageDefinitionsUseFirstAndRepeatedInlineImagesAllRewrite() {
        let text = "![A][ref]\n[ref]: https://example.com/first.png\n[ref]: https://example.com/ignored.png\n![One](https://example.com/first.png)\n![Two](<https://example.com/first.png>)"
        let url = URL(string: "https://example.com/first.png")!
        XCTAssertEqual(NoteLibrary.remoteImageURLs(in: text), [url])
        XCTAssertEqual(NoteLibrary.replacingImageURLs(in: text, with: [url: "Attachments/local.png"]), "![A](<Attachments/local.png>)\n[ref]: https://example.com/first.png\n[ref]: https://example.com/ignored.png\n![One](Attachments/local.png)\n![Two](<Attachments/local.png>)")
    }
}
