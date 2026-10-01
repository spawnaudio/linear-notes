import XCTest
import NotesCore
import SwiftUI
import WebKit
@testable import LinearNotes

final class WorkspaceTests: XCTestCase {
    private func notebook(_ body: @MainActor (NotebookStore, URL) throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "# Alpha\n".write(to: root.appendingPathComponent("A.md"), atomically: true, encoding: .utf8)
        try "# Bravo\n".write(to: root.appendingPathComponent("B.md"), atomically: true, encoding: .utf8)
        try await MainActor.run {
            let store = NotebookStore(root: root)
            defer { store.poller?.invalidate(); store.sessionSave?.cancel(); store.allTabs.forEach { $0.autosave?.cancel() } }
            try body(store, root)
        }
    }
    func testNestedSplitsTabsAndLayoutRestore() async throws {
        try await notebook { store, root in
            store.select("A.md"); store.select("B.md")
            let first = store.activePane
            XCTAssertEqual(first.tabs.map(\.selected), ["A.md", "B.md"])
            store.select("A.md"); XCTAssertEqual(first.tabs.count, 2)
            store.split(.right); store.mode = .source
            store.rememberSession(["mode": "source", "positions": ["source": ["from": 3, "to": 3, "scroll": 25]]], id: "A.md", immediately: true)
            store.split(.down); store.split(.left); store.split(.up)
            XCTAssertEqual(store.panes.count, 5)
            XCTAssertEqual(Set(store.layout.paneIDs), Set(store.panes.map(\.id)))
            guard case .split(let id, _, _, _, _) = store.layout else { return XCTFail("Expected split") }
            store.layout = store.layout.resizing(id, to: 0.35); store.saveWorkspace()
            let restored = NotebookStore(root: root)
            defer { restored.poller?.invalidate(); restored.sessionSave?.cancel() }
            XCTAssertEqual(restored.layout, store.layout)
            XCTAssertEqual(restored.activePaneID, store.activePaneID)
            XCTAssertEqual(restored.panes.count, 5)
            XCTAssertEqual(restored.selected, "A.md"); XCTAssertEqual(restored.mode, .source)
            XCTAssertEqual(restored.activeTab.session?.positions["source"]?.from, 3)
            XCTAssertEqual(restored.panes.first { $0.id == first.id }?.tabs.map(\.selected), ["A.md", "B.md"])
        }
    }
    func testTabReorderMoveEdgeSplitAndCollapse() async throws {
        try await notebook { store, _ in
            store.select("A.md"); store.select("B.md")
            let first = store.activePane, a = first.tabs[0], b = first.tabs[1]
            store.moveTab(b.id, to: first.id, before: a.id)
            XCTAssertEqual(first.tabs.map(\.id), [b.id, a.id])
            store.moveTab(b.id, to: first.id)
            XCTAssertEqual(first.tabs.map(\.id), [a.id, b.id])
            store.moveTab(a.id, to: first.id)
            XCTAssertEqual(first.tabs.map(\.id), [b.id, a.id])
            store.split(.down)
            let second = store.activePane
            store.moveTab(a.id, to: second.id)
            XCTAssertTrue(second.tab === a); XCTAssertEqual(first.tabs.count, 1)
            store.moveTab(a.id, to: second.id, direction: .right)
            XCTAssertEqual(store.panes.count, 3); XCTAssertTrue(store.activeTab === a)
            store.closeTab(b, in: first)
            XCTAssertEqual(store.panes.count, 2); XCTAssertFalse(store.layout.paneIDs.contains(first.id))
            store.closePane(second)
            XCTAssertEqual(store.layout, .pane(store.activePaneID))
            store.closeTab(a, in: store.activePane)
            XCTAssertEqual(store.panes.count, 1); XCTAssertEqual(store.activePane.tabs.count, 1); XCTAssertNil(store.selected)
        }
    }
    func testLoneTabCanBeDraggedToEverySplitEdge() async throws {
        let size = CGSize(width: 800, height: 600)
        XCTAssertNil(paneDropDirection(at: CGPoint(x: 10, y: 20), in: size, header: 46))
        XCTAssertNil(paneDropDirection(at: CGPoint(x: 400, y: 300), in: size, header: 46))
        XCTAssertEqual(paneDropDirection(at: CGPoint(x: 10, y: 300), in: size, header: 46), .left)
        XCTAssertEqual(paneDropDirection(at: CGPoint(x: 790, y: 300), in: size, header: 46), .right)
        XCTAssertEqual(paneDropDirection(at: CGPoint(x: 400, y: 70), in: size, header: 46), .up)
        XCTAssertEqual(paneDropDirection(at: CGPoint(x: 400, y: 590), in: size, header: 46), .down)
        try await notebook { store, root in
            store.select("A.md")
            let tab = store.activeTab
            for direction in SplitDirection.allCases {
                let source = store.activePane
                store.moveTab(tab.id, to: source.id, direction: direction)
                XCTAssertTrue(store.activeTab === tab)
                XCTAssertEqual(source.tabs.count, 1); XCTAssertNil(source.tab.selected)
                XCTAssertNotEqual(store.activePaneID, source.id)
                let ids = store.layout.paneIDs
                XCTAssertEqual(ids.firstIndex(of: store.activePaneID)! < ids.firstIndex(of: source.id)!, direction.before)
                XCTAssertEqual(try store.library!.read("A.md"), "# Alpha\n")
            }
            XCTAssertEqual(store.panes.count, 5)
            let restored = NotebookStore(root: root)
            defer { restored.poller?.invalidate(); restored.sessionSave?.cancel() }
            XCTAssertEqual(restored.layout, store.layout)
            XCTAssertEqual(restored.activeTab.id, tab.id)
            XCTAssertEqual(restored.selected, "A.md")
        }
    }
    func testSharedDraftsIndependentModesAndAllPaneConflictProtection() async throws {
        try await notebook { store, root in
            store.select("A.md"); let original = store.activeTab
            store.split(.right); let copy = store.activeTab
            store.mode = .reading
            store.changed("# Shared edit\n", id: "A.md", tab: original)
            XCTAssertEqual(copy.markdown, original.markdown); XCTAssertEqual(copy.mode, .reading); XCTAssertEqual(original.mode, .live)
            XCTAssertTrue(store.save(tab: copy)); XCTAssertFalse(original.dirty)
            XCTAssertEqual(try store.library!.read("A.md"), "# Shared edit\n")
            store.select("B.md")
            store.changed("Unsaved original", id: "A.md", tab: original)
            try "External original".write(to: root.appendingPathComponent("A.md"), atomically: true, encoding: .utf8)
            var flushed: Bool?
            store.flushAll { flushed = $0 }
            XCTAssertEqual(flushed, false); XCTAssertTrue(original.conflict)
            XCTAssertTrue(store.activeTab === original)
            let count = store.panes.count
            store.split(.down); XCTAssertEqual(store.panes.count, count)
            XCTAssertEqual(original.markdown, "Unsaved original")
            XCTAssertEqual(try store.library!.read("A.md"), "External original")
            store.activate(original); store.keepBoth()
            XCTAssertEqual(store.markdown, "Unsaved original")
            XCTAssertEqual(copy.markdown, "External original"); XCTAssertFalse(copy.dirty)
            store.flushAll { flushed = $0 }; XCTAssertEqual(flushed, true)
        }
    }
    func testMovesRefreshEveryTabAndMissingFilesRestoreSafely() async throws {
        try await notebook { store, root in
            store.select("A.md"); store.split(.right); store.select("B.md")
            store.move("A.md", parent: "", newName: "Renamed.md")
            XCTAssertEqual(store.allTabs.filter { $0.selected == "Renamed.md" }.count, 2)
            try "# Changed outside\n".write(to: root.appendingPathComponent("Renamed.md"), atomically: true, encoding: .utf8)
            store.refreshFromDisk()
            XCTAssertTrue(store.allTabs.filter { $0.selected == "Renamed.md" }.allSatisfy { $0.markdown == "# Changed outside\n" })
            store.saveWorkspace()
            try FileManager.default.removeItem(at: root.appendingPathComponent("Renamed.md"))
            let restored = NotebookStore(root: root)
            defer { restored.poller?.invalidate(); restored.sessionSave?.cancel() }
            XCTAssertEqual(restored.panes.count, 2)
            XCTAssertFalse(restored.allTabs.contains { $0.selected == "Renamed.md" })
            XCTAssertEqual(restored.selected, "B.md")
            store.open(root, remember: false)
            XCTAssertEqual(store.panes.count, 2)
        }
    }
    @MainActor func testNativeEditorsAcrossNestedSplits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "# Alpha\n".write(to: root.appendingPathComponent("A.md"), atomically: true, encoding: .utf8)
        try "# Bravo\n".write(to: root.appendingPathComponent("B.md"), atomically: true, encoding: .utf8)
        let store = NotebookStore(root: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ContentView(store: store))
        window.orderFront(nil)
        defer {
            window.orderOut(nil); window.contentView = nil; store.poller?.invalidate(); store.sessionSave?.cancel()
            store.allTabs.forEach { $0.autosave?.cancel() }; try? FileManager.default.removeItem(at: root)
        }
        func ready(_ count: Int) async throws {
            // Allow SwiftUI to replace views after the layout tree changes.
            try await Task.sleep(for: .milliseconds(100))
            for _ in 0..<200 {
                if store.panes.count == count, store.panes.allSatisfy({ pane in
                    let tab = pane.tab
                    return tab.bridge?.ready == true && tab.bridge?.loadingDocument == false && tab.bridge?.loadedVersion == tab.documentVersion && tab.bridge?.loadedMode == tab.mode
                }) { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTFail("Native editors did not finish loading")
            throw NSError(domain: "WorkspaceTests", code: 1)
        }
        func script(_ tab: NoteTab, _ source: String) async throws -> String? {
            guard let view = tab.bridge?.webView else { throw NSError(domain: "WorkspaceTests", code: 2) }
            return try await withCheckedThrowingContinuation { continuation in
                view.evaluateJavaScript(source) { [view] value, error in
                    _ = view
                    if let error {
                        XCTFail("Native script failed: \(source) — \(error)")
                        continuation.resume(throwing: error)
                    }
                    else { continuation.resume(returning: value as? String) }
                }
            }
        }
        try await ready(1)
        let first = store.activePane, original = store.activeTab
        store.split(.right); try await ready(2)
        let second = store.activePane, copy = store.activeTab
        store.mode = .reading; try await ready(2)
        store.split(.down); try await ready(3)
        let third = store.activePane
        _ = try await script(original, "document.querySelector('.tiptap').dispatchEvent(new PointerEvent('pointerdown', {bubbles:true})); 'focused'")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(store.activePaneID, first.id)
        store.mode = .source; try await ready(3)
        _ = try await script(original, "{ const field = document.getElementById('source'); field.value = '# Native shared edit\\n'; field.dispatchEvent(new Event('input', {bubbles:true})); 'edited'; }")
        try await Task.sleep(for: .milliseconds(100)); try await ready(3)
        let mirrored = try await script(copy, "window.notes.getMarkdown()")
        XCTAssertEqual(mirrored, "# Native shared edit\n"); XCTAssertEqual(copy.mode, .reading)
        store.activate(third); store.select("B.md")
        for _ in 0..<100 where store.selected != "B.md" { try await Task.sleep(for: .milliseconds(50)) }
        try await ready(3)
        let bravo = try await script(store.activeTab, "window.notes.getMarkdown()")
        XCTAssertEqual(bravo, "# Bravo\n")
        let flushed = await withCheckedContinuation { continuation in store.flushAll { continuation.resume(returning: $0) } }
        XCTAssertTrue(flushed); XCTAssertEqual(try store.library!.read("A.md"), "# Native shared edit\n")
        store.closePane(second); try await ready(2)
        XCTAssertFalse(store.layout.paneIDs.contains(second.id))
        _ = try await script(original, "{ const field = document.getElementById('source'); field.value = 'Native conflict draft'; field.dispatchEvent(new Event('input', {bubbles:true})); 'edited'; }")
        try await Task.sleep(for: .milliseconds(100)); try await ready(2)
        try "External copy".write(to: root.appendingPathComponent("A.md"), atomically: true, encoding: .utf8)
        let conflictFlush = await withCheckedContinuation { continuation in store.flushAll { continuation.resume(returning: $0) } }
        XCTAssertFalse(conflictFlush); XCTAssertTrue(store.activeTab === original)
        store.keepBoth()
        for _ in 0..<100 where store.selected == "A.md" { try await Task.sleep(for: .milliseconds(50)) }
        try await ready(2)
        XCTAssertEqual(store.markdown, "Native conflict draft")
        XCTAssertEqual(try store.library!.read("A.md"), "External copy")
        // Opt-in native preview for local QA; normal test runs leave no image artifact.
        if let output = ProcessInfo.processInfo.environment["LINEAR_NOTES_QA_PREVIEW"], let view = window.contentView,
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
        }
    }
}
