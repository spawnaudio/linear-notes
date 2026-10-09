import XCTest
import AppKit
import SwiftUI
import NotesCore
@testable import LinearNotes

private final class ImageReply: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: (URLRequest) -> (Int, Data) = { _ in (500, Data()) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, bytes) = Self.response(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bytes); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

final class LinearNoteActionsTests: XCTestCase {
    @MainActor func testRefreshUpdatesEveryPaneAndKeepsConflictingCopies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = NotebookStore(root: root)
        defer {
            store.poller?.invalidate(); store.sessionSave?.cancel(); store.allTabs.forEach { $0.autosave?.cancel() }
            try? FileManager.default.removeItem(at: root)
        }
        let library = try XCTUnwrap(store.library), id = UUID().uuidString
        let path = try library.importLinearDocument(id: id, projectID: UUID().uuidString, title: "Linked", sourceURL: "https://linear.app/test/document/linked", content: "Local body", parent: "")
        store.items = try library.scan(); store.select(path); store.split(.right)
        let original = try library.read(path)
        let incoming = original.replacingOccurrences(of: "Local body", with: "Incoming body")
        try store.applyLinearRefresh(incoming, to: path, expected: original, keepBoth: false)
        XCTAssertTrue(store.allTabs.allSatisfy { $0.markdown == incoming && $0.baseline == incoming })
        try library.save("External edit", to: path, expected: incoming)
        XCTAssertThrowsError(try store.applyLinearRefresh(original, to: path, expected: incoming, keepBoth: false)) { XCTAssertEqual($0 as? LibraryError, .conflict) }
        XCTAssertEqual(try library.read(path), "External edit")
        try store.applyLinearRefresh(incoming, to: path, expected: incoming, keepBoth: true)
        XCTAssertNotEqual(store.selected, path)
        XCTAssertEqual(try library.read(path), "External edit")
        XCTAssertNil(NoteLibrary.linearSource(in: store.markdown))
        XCTAssertTrue(store.markdown.contains("Incoming body"))
    }

    @MainActor func testOfflineImagesAcrossPanesAndFailedDownloadsNeverOverwrite() async throws {
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jhX8AAAAASUVORK5CYII=")!
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ImageReply.self]
        let client = LinearAPI(key: "test-key", session: URLSession(configuration: config))
        for outcome in ["success", "failure", "conflict"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let original = "![One](https://example.com/image.png)\n![Two](https://example.com/image.png)\n"
            try original.write(to: root.appendingPathComponent("Images.md"), atomically: true, encoding: .utf8)
            let store = NotebookStore(root: root)
            var window: NSWindow?
            defer {
                window?.orderOut(nil); window?.contentView = nil
                store.poller?.invalidate(); store.sessionSave?.cancel(); store.allTabs.forEach { $0.autosave?.cancel() }
                try? FileManager.default.removeItem(at: root)
            }
            store.split(.right)
            let target = store.activeTab
            if outcome == "success" {
                _ = try store.library!.create(name: "Other", parent: "", content: "Untouched")
                store.items = try store.library!.scan(); store.activate(store.panes[0]); store.select("Other.md")
                window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                window?.contentView = NSHostingView(rootView: ContentView(store: store)); window?.orderFront(nil)
                for _ in 0..<200 where !store.panes.allSatisfy({ $0.tab.bridge?.ready == true && $0.tab.bridge?.loadingDocument == false }) { try await Task.sleep(for: .milliseconds(20)) }
                XCTAssertTrue(store.panes.allSatisfy { $0.tab.bridge?.ready == true })
                store.activate(target)
            }
            ImageReply.response = { request in
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                if outcome == "conflict" { try! "External edit".write(to: root.appendingPathComponent("Images.md"), atomically: true, encoding: .utf8) }
                return (outcome == "failure" ? 403 : 200, png)
            }
            store.saveImagesLocally(using: client)
            if outcome == "success" { store.activate(store.panes[0]) }
            for _ in 0..<200 where store.savingImages { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertFalse(store.savingImages)
            let disk = try store.library!.read("Images.md")
            if outcome == "success" {
                XCTAssertTrue(disk.contains("Attachments/")); XCTAssertFalse(disk.contains("https://"))
                XCTAssertTrue(store.allTabs.filter { $0.selected == "Images.md" }.allSatisfy { $0.markdown == disk && !$0.dirty })
                XCTAssertEqual(try store.library!.read("Other.md"), "Untouched")
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Attachments").path).count, 1)
            } else {
                XCTAssertEqual(disk, outcome == "conflict" ? "External edit" : original)
                XCTAssertNotNil(store.error)
                if outcome == "failure" {
                    ImageReply.response = { _ in (200, png) }
                    store.saveImagesLocally(using: client)
                    for _ in 0..<200 where store.savingImages { try await Task.sleep(for: .milliseconds(10)) }
                    XCTAssertFalse(store.savingImages); XCTAssertNil(store.error)
                    XCTAssertTrue(try store.library!.read("Images.md").contains("Attachments/"))
                }
            }
        }
    }
}
