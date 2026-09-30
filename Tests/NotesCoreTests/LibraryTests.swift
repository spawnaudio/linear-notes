import XCTest
@testable import NotesCore

final class LibraryTests: XCTestCase {
    var root: URL!
    var library: NoteLibrary!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        library = try NoteLibrary(root: root)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testUnicodeMarkdownPersistsExactly() throws {
        let original = "---\ntags: [notes, café]\n---\n\n# Héllo 👋\n\n> [!TIP]\n> Keep it simple.\n"
        let path = try library.create(name: "Café", content: original)
        XCTAssertEqual(try library.read(path), original)
        try library.save(original + "\nEdit", to: path, expected: original)
        XCTAssertEqual(try library.read(path), original + "\nEdit")
    }
    func testConflictNeverOverwritesExternalContent() throws {
        let path = try library.create(name: "A", content: "original")
        try "external".write(to: library.url(for: path), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try library.save("draft", to: path, expected: "original"))
        XCTAssertEqual(try library.read(path), "external")
    }
    func testRenameFolderRetainsNestedPinsBookmarksAndSelection() throws {
        _ = try library.create(name: "Old", folder: true)
        _ = try library.create(name: "Note", parent: "Old")
        library.sidebar.pinned = ["Old/Note.md"]
        library.sidebar.bookmarks = ["Old", "Old/Note.md"]
        library.sidebar.lastSelected = "Old/Note.md"
        try library.move("Old", to: "", newName: "New")
        XCTAssertEqual(library.sidebar.bookmarks, ["New", "New/Note.md"])
        XCTAssertEqual(library.sidebar.pinned, ["New/Note.md"])
        XCTAssertEqual(library.sidebar.lastSelected, "New/Note.md")
        XCTAssertEqual(try library.read("New/Note.md"), "")
        XCTAssertEqual(try NoteLibrary(root: root).sidebar, library.sidebar)
    }
    func testPinnedItemsStayInTheirParentsWithManualOrder() throws {
        for name in ["A", "B", "C"] { _ = try library.create(name: name) }
        library.sidebar.pinned = ["B.md", "C.md"]
        try library.move("C.md", to: "", before: "B.md")
        XCTAssertEqual(library.children(of: "", in: try library.scan()).map(\.path), ["C.md", "B.md", "A.md"])
    }
    func testMoveAcrossFoldersAndRejectCycles() throws {
        _ = try library.create(name: "A", folder: true)
        _ = try library.create(name: "B", parent: "A", folder: true)
        _ = try library.create(name: "Note", content: "hello")
        try library.move("Note.md", to: "A/B")
        XCTAssertEqual(try library.read("A/B/Note.md"), "hello")
        XCTAssertThrowsError(try library.move("A", to: "A/B"))
    }
    func testDuplicateAndPathTraversalAreRejected() throws {
        _ = try library.create(name: "Note")
        XCTAssertThrowsError(try library.create(name: "Note"))
        XCTAssertThrowsError(try library.url(for: "../outside.md"))
        XCTAssertThrowsError(try library.url(for: "/etc/passwd"))
        XCTAssertThrowsError(try library.create(name: ".hidden"))
        XCTAssertThrowsError(try library.move("Note.md", to: "", newName: "../bad"))
    }
    func testSymlinkAndHiddenFilesAreExcluded() throws {
        _ = try library.create(name: "Visible")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Alias.md"), withDestinationURL: root.appendingPathComponent("Visible.md"))
        XCTAssertEqual(try library.scan().map(\.path), ["Visible.md"])
        XCTAssertThrowsError(try library.read("Alias.md"))
    }
    func testMetadataDoesNotModifyMarkdown() throws {
        _ = try library.create(name: "Note", content: "# Original\n")
        library.sidebar.bookmarks = ["Note.md"]; library.sidebar.pinned = ["Note.md"]
        try library.saveSidebar()
        XCTAssertEqual(try library.read("Note.md"), "# Original\n")
        XCTAssertEqual(try NoteLibrary(root: root).sidebar.bookmarks, ["Note.md"])
    }

    func testContentSearchIncludesDraftsAndRanksTitles() throws {
        _ = try library.create(name: "Reference", content: "An idea about café sidebars 📝.")
        _ = try library.create(name: "Sidebar", content: "A title match")
        let draft = try library.create(name: "Unfinished", content: "Old")
        let items = try library.scan()
        XCTAssertEqual(try library.search("sidebar", in: items).map(\.id), ["Sidebar.md", "Reference.md"])
        XCTAssertTrue(try library.search("cafe", in: items).first?.excerpt.contains("café") == true)
        XCTAssertEqual(try library.search("unsaved", in: items, drafts: [draft: "An unsaved thought"]).map(\.id), [draft])
        XCTAssertTrue(try library.search("absent", in: items).isEmpty)
    }

    func testImagesStayLocalAndSurviveNoteMoves() throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=")!
        _ = try library.create(name: "Projects", folder: true)
        let path = try library.create(name: "Visual", parent: "Projects")
        let image = try library.storeImage(png, for: path)
        XCTAssertTrue(image.hasPrefix("../Attachments/"))
        XCTAssertEqual(try Data(contentsOf: library.imageURL(image, in: path)), png)
        _ = try library.storeImage(png, for: path)
        XCTAssertFalse(try library.scan().contains { $0.path == "Attachments" })
        let content = "# Visual\n\n![A screenshot](\(image))\n\n`![Inline example](\(image))`\n\n```md\n![Example](\(image))\n```\n"
        try library.save(content, to: path, expected: "")
        let moved = try library.move(path, to: "")
        let output = try library.read(moved)
        XCTAssertTrue(output.contains("![A screenshot](Attachments/"))
        XCTAssertTrue(output.contains("```md\n![Example](../Attachments/"))
        XCTAssertTrue(output.contains("`![Inline example](../Attachments/"))
        _ = try library.create(name: UUID().uuidString, parent: "Attachments", content: "A user note")
        XCTAssertTrue(try library.scan().contains { $0.parent == "Attachments" && !$0.isFolder })
        XCTAssertThrowsError(try library.move("Attachments", to: "Projects"))
        XCTAssertThrowsError(try library.imageURL("../../etc/passwd", in: moved))
        XCTAssertThrowsError(try library.imageURL("file:///etc/passwd", in: moved))
        XCTAssertThrowsError(try library.storeImage(Data("<svg onload='alert(1)'/>".utf8), for: moved))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Alias.png"), withDestinationURL: try library.imageURL(image, in: path))
        XCTAssertThrowsError(try library.imageURL("Alias.png", in: moved))
    }

    func testLinearImportsKeepSourceAndNeverOverwriteRepeatedImports() throws {
        let id = UUID().uuidString, project = UUID().uuidString
        _ = try library.create(name: "Editor Guide", content: "Personal note")
        let path = try library.importLinearDocument(id: id, projectID: project, title: "Editor Guide", sourceURL: "https://linear.app/test/document/guide", content: "# Imported\n", parent: "")
        XCTAssertEqual(path, "Editor Guide 2.md")
        let original = try library.read(path)
        XCTAssertTrue(original.contains("linearDocumentId: \(id.lowercased())"))
        XCTAssertTrue(original.contains("linearDocumentUrl:"))
        let edited = (original + "\nLocal draft").replacingOccurrences(of: "\n", with: "\r\n")
        try library.save(edited, to: path, expected: original)
        let renamed = try library.move(path, to: "", newName: "Renamed.md")
        XCTAssertEqual(try library.importLinearDocument(id: id, projectID: project, title: "Editor Guide", sourceURL: "https://linear.app/test/document/guide", content: "Different remote text", parent: ""), renamed)
        XCTAssertEqual(try library.read(renamed), edited)
        XCTAssertEqual(try library.read("Editor Guide.md"), "Personal note")
        XCTAssertThrowsError(try library.importLinearDocument(id: id, projectID: project, title: "Bad", sourceURL: "https://example.com/document", content: "", parent: ""))
    }
}
