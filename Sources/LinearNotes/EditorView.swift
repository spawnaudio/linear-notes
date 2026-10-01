import SwiftUI
import WebKit
import NotesCore
import UniformTypeIdentifiers

@MainActor final class EditorBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    weak var store: NotebookStore?
    weak var tab: NoteTab?
    weak var webView: WKWebView?
    var ready = false
    var loadedVersion = -1
    var loadedMode: EditorMode?
    var loadedNotes: [String] = []
    var loadingDocument = false
    var printing = false
    init(store: NotebookStore, tab: NoteTab) { self.store = store; self.tab = tab }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let data = message.body as? [String: Any], let store, let tab else { return }
        switch data["type"] as? String {
        case "ready": ready = true; update()
        case "focus": store.activate(tab)
        case "change": if !loadingDocument, loadedVersion == tab.documentVersion, let text = data["markdown"] as? String, let id = data["id"] as? String { store.changed(text, id: id, tab: tab) }
        case "save": store.save(tab: tab)
        case "viewState": if !loadingDocument, loadedVersion == tab.documentVersion, let id = data["id"] as? String,
            let state = data["state"] as? [String: Any], state["mode"] as? String == tab.mode.rawValue { store.rememberSession(state, id: id, tab: tab) }
        case "openNote":
            if data["id"] as? String == tab.selected, let selected = tab.selected, let reference = data["reference"] as? String, let library = store.library {
                do { let url = try library.noteURL(reference, in: selected); store.activate(tab); store.select(String(url.path.dropFirst(library.root.path.count + 1))) }
                catch { tab.error = "This note link could not be opened: " + error.localizedDescription }
            }
        case "outline":
            if data["id"] as? String == tab.selected {
                tab.headings = (data["headings"] as? [[String: Any]] ?? []).compactMap { row in
                    guard let index = row["index"] as? Int, let level = row["level"] as? Int, (1...6).contains(level), let text = row["text"] as? String else { return nil }
                    return NoteHeading(id: index, level: level, text: text)
                }
                tab.activeHeading = data["active"] as? Int ?? -1
            }
        case "headingActive": if data["id"] as? String == tab.selected { tab.activeHeading = data["active"] as? Int ?? -1 }
        case "quickOpen": store.activate(tab); store.quickOpenVisible = true
        case "attachment":
            guard tab.mode == .live, let id = data["id"] as? String, id == tab.selected,
                  let request = data["request"] as? String, let base64 = data["data"] as? String,
                  base64.utf8.count <= 28 * 1024 * 1024, let bytes = Data(base64Encoded: base64), let library = store.library else { return }
            do {
                let reference = try library.storeImage(bytes, for: id)
                webView?.callAsyncJavaScript("window.notes.attachment(payload)", arguments: ["payload": ["id": id, "request": request, "src": reference]], in: nil, in: .page, completionHandler: nil)
            } catch {
                tab.error = error.localizedDescription
                webView?.callAsyncJavaScript("window.notes.attachment(payload)", arguments: ["payload": ["id": id, "request": request, "error": error.localizedDescription]], in: nil, in: .page, completionHandler: nil)
            }
        case "properties":
            if data["id"] as? String == tab.selected {
                tab.properties = data["text"] as? String ?? ""
                tab.propertyRows = (data["rows"] as? [[String: String]] ?? []).compactMap { row in
                    guard let name = row["name"], let value = row["value"] else { return nil }
                    return (name: name, value: value)
                }
            }
        case "stats": if data["id"] as? String == tab.selected { tab.words = data["words"] as? Int ?? 0 }
        case "openLink":
            if let raw = data["url"] as? String, let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        default: break
        }
    }
    func update() {
        guard ready, let store, let tab, let webView else { return }
        if loadedVersion != tab.documentVersion {
            var payload: [String: Any] = ["id": tab.selected ?? "", "markdown": tab.markdown, "mode": tab.mode.rawValue, "assetBase": "notes-asset:", "textSize": store.textSize, "focus": tab.focusNewNote, "notes": noteLinks()]
            if tab.selected != nil, let state = tab.session, let bytes = try? JSONEncoder().encode(state), let object = try? JSONSerialization.jsonObject(with: bytes) { payload["state"] = object }
            if let term = tab.pendingFind { payload["find"] = term }
            tab.focusNewNote = false; tab.pendingFind = nil
            loadedVersion = tab.documentVersion; loadedMode = tab.mode; loadingDocument = true
            let version = loadedVersion
            webView.callAsyncJavaScript("window.notes.load(payload)", arguments: ["payload": payload], in: nil, in: .page) { [weak self, weak tab] result in
                if self?.loadedVersion == version { self?.loadingDocument = false }
                if case let .failure(error) = result { tab?.error = "The editor could not load: \(error.localizedDescription)" }
            }
        } else if loadedMode != tab.mode {
            loadedMode = tab.mode
            webView.callAsyncJavaScript("window.notes.setMode(mode)", arguments: ["mode": tab.mode.rawValue], in: nil, in: .page, completionHandler: nil)
        }
        let paths = store.items.filter { !$0.isFolder }.map(\.path)
        if paths != loadedNotes { loadedNotes = paths; webView.callAsyncJavaScript("window.notes.setNotes(notes)", arguments: ["notes": noteLinks()], in: nil, in: .page, completionHandler: nil) }
    }
    private func noteLinks() -> [[String: String]] {
        guard let store, let tab, let selected = tab.selected, let library = store.library else { return [] }
        return store.items.filter { !$0.isFolder && $0.path != selected }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }.compactMap { item in
            guard let reference = try? library.noteReference(to: item.path, from: selected) else { return nil }
            return ["title": item.title, "path": item.path, "reference": reference]
        }
    }
    func find(_ term: String) { webView?.callAsyncJavaScript("window.notes.find(term)", arguments: ["term": term], in: nil, in: .page, completionHandler: nil) }
    func showFind() { webView?.evaluateJavaScript("window.notes.showFind()", completionHandler: nil) }
    func textSize(_ size: Int) { webView?.callAsyncJavaScript("window.notes.textSize(size)", arguments: ["size": size], in: nil, in: .page, completionHandler: nil) }
    func printDocument() {
        guard !printing else { return }
        flush { [weak self] success in
            guard success, let self, let webView = self.webView, self.tab?.selected != nil else { return }
            self.printing = true
            webView.callAsyncJavaScript("await window.notes.preparePrint()", arguments: [:], in: nil, in: .page) { [weak self] result in
                guard let self, let webView = self.webView else { return }
                if case let .failure(error) = result { self.tab?.error = error.localizedDescription; self.finishPrint() }
                else {
                    guard let window = webView.window else { self.finishPrint(); return }
                    let info = NSPrintInfo.shared.copy() as! NSPrintInfo
                    info.topMargin = 40; info.bottomMargin = 40; info.leftMargin = 40; info.rightMargin = 40
                    info.horizontalPagination = .fit; info.isVerticallyCentered = false
                    let operation = webView.printOperation(with: info)
                    operation.jobTitle = self.tab?.selected.map { NoteItem(path: $0, isFolder: false).title } ?? "Note"
                    // Let WebKit finish its script callback before the asynchronous print sheet runs.
                    DispatchQueue.main.async {
                        operation.runModal(for: window, delegate: self, didRun: #selector(self.printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
                    }
                }
            }
        }
    }
    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) { finishPrint() }
    private func finishPrint() { printing = false; webView?.evaluateJavaScript("window.notes.finishPrint()", completionHandler: nil) }
    func showProperties() {
        webView?.evaluateJavaScript("window.notes.properties()", completionHandler: nil)
    }
    func jumpToHeading(_ index: Int) {
        webView?.callAsyncJavaScript("window.notes.jumpToHeading(index)", arguments: ["index": index], in: nil, in: .page, completionHandler: nil)
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]; panel.allowsMultipleSelection = false
        completionHandler(panel.runModal() == .OK ? panel.urls : nil)
    }
    func command(_ name: String) {
        webView?.callAsyncJavaScript("window.notes.command(command)", arguments: ["command": name], in: nil, in: .page, completionHandler: nil)
    }
    func flush(_ completion: @escaping @MainActor (Bool) -> Void) {
        guard ready, let webView, let store, let tab, let id = tab.selected else { completion(true); return }
        guard !loadingDocument, loadedVersion == tab.documentVersion else { completion(false); return }
        webView.evaluateJavaScript("({markdown:window.notes.getMarkdown(),state:window.notes.viewState()})") { [weak store, weak tab] value, error in
            guard let store, let tab else { completion(true); return }
            if let error { tab.error = error.localizedDescription; completion(false); return }
            guard !self.loadingDocument, self.loadedVersion == tab.documentVersion, tab.selected == id,
                  let value = value as? [String: Any], let text = value["markdown"] as? String else { completion(false); return }
            store.changed(text, id: id, tab: tab)
            if let state = value["state"] { store.rememberSession(state, id: id, immediately: true, tab: tab) }
            completion(store.save(tab: tab))
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        // The only permitted page is the bundled editor. Notes never become executable pages.
        if navigationAction.navigationType == .other, navigationAction.request.url?.isFileURL == true { decisionHandler(.allow) }
        else { decisionHandler(.cancel) }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { ready = false; loadedVersion = -1; webView.reload() }
}

struct MarkdownEditorView: NSViewRepresentable {
    @ObservedObject var store: NotebookStore
    @ObservedObject var tab: NoteTab
    var tabDragChanged: (Bool, SplitDirection?) -> Void = { _, _ in }
    var tabDropped: (UUID, SplitDirection?) -> Void = { _, _ in }
    func makeCoordinator() -> EditorBridge { EditorBridge(store: store, tab: tab) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(NotebookImages(store: store, tab: tab), forURLScheme: "notes-asset")
        config.userContentController.add(context.coordinator, name: "notes")
        let view = NoteWebView(frame: .zero, configuration: config); view.navigationDelegate = context.coordinator; view.uiDelegate = context.coordinator
        view.registerForDraggedTypes([.init(tabType.identifier)])
        view.tabDragChanged = tabDragChanged; view.tabDropped = tabDropped
        view.setValue(false, forKey: "drawsBackground"); view.isInspectable = ProcessInfo.processInfo.arguments.contains("--inspect")
        context.coordinator.webView = view; tab.bridge = context.coordinator
        if let url = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Editor") {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else { tab.error = "The editor resources are missing. Rebuild the app using scripts/build.sh." }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        if let view = view as? NoteWebView { view.tabDragChanged = tabDragChanged; view.tabDropped = tabDropped }
        context.coordinator.update()
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: EditorBridge) { view.configuration.userContentController.removeScriptMessageHandler(forName: "notes") }
}

// WebKit handles drops before the surrounding SwiftUI pane can receive them.
private final class NoteWebView: WKWebView {
    var tabDragChanged: (Bool, SplitDirection?) -> Void = { _, _ in }
    var tabDropped: (UUID, SplitDirection?) -> Void = { _, _ in }
    private func draggedTab(_ sender: NSDraggingInfo) -> UUID? {
        sender.draggingPasteboard.string(forType: .init(tabType.identifier)).flatMap(UUID.init(uuidString:))
    }
    private func edge(_ sender: NSDraggingInfo) -> SplitDirection? {
        let point = convert(sender.draggingLocation, from: nil)
        return paneDropDirection(at: CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y), in: bounds.size, header: 0)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard draggedTab(sender) != nil else { return super.draggingEntered(sender) }
        tabDragChanged(true, edge(sender)); return .move
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard draggedTab(sender) != nil else { return super.draggingUpdated(sender) }
        tabDragChanged(true, edge(sender)); return .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        tabDragChanged(false, nil); super.draggingExited(sender)
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        draggedTab(sender) != nil || super.prepareForDragOperation(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let id = draggedTab(sender) else { return super.performDragOperation(sender) }
        let direction = edge(sender); tabDragChanged(false, nil); tabDropped(id, direction); return true
    }
}
