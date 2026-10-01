import XCTest
import NotesCore
@testable import LinearNotes

final class NotebookStoreTests: XCTestCase {
    func testCaptureResumeAndSaveFailureActions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await MainActor.run {
            let store = NotebookStore(root: root)
            defer { store.poller?.invalidate(); store.autosave?.cancel(); store.sessionSave?.cancel() }
            store.create(); XCTAssertEqual(store.selected, "Untitled.md"); XCTAssertTrue(store.focusNewNote)
            store.changed("First draft", id: store.selected!); XCTAssertTrue(store.save())
            store.rememberSession(["mode": "source", "positions": ["source": ["from": 5, "to": 5, "scroll": 120]]], id: store.selected!, immediately: true)
            store.create(); XCTAssertEqual(store.selected, "Untitled 2.md")
            store.select("Untitled.md"); XCTAssertEqual(store.mode, .source)
            store.changed("Local draft", id: "Untitled.md")
            try "External version".write(to: root.appendingPathComponent("Untitled.md"), atomically: true, encoding: .utf8)
            XCTAssertFalse(store.save()); XCTAssertTrue(store.conflict)
            store.keepBoth(); XCTAssertEqual(store.markdown, "Local draft")
            XCTAssertEqual(try store.library!.read("Untitled.md"), "External version")
            let selected = store.selected!
            store.changed("Retry this", id: selected)
            // A file replacing the metadata directory simulates a recovery-cleanup failure.
            let metadata = root.appendingPathComponent(".linear-notes")
            try FileManager.default.moveItem(at: metadata, to: root.appendingPathComponent("Saved metadata"))
            try Data().write(to: metadata)
            XCTAssertFalse(store.save()); XCTAssertTrue(store.saveFailed); XCTAssertFalse(store.conflict)
            try FileManager.default.removeItem(at: metadata)
            try FileManager.default.moveItem(at: root.appendingPathComponent("Saved metadata"), to: metadata)
            XCTAssertTrue(store.save()); XCTAssertFalse(store.saveFailed)
            XCTAssertEqual(try store.library!.read(selected), "Retry this")
        }
    }
}
