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
}
