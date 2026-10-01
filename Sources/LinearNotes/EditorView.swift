import SwiftUI
import WebKit
import NotesCore
import UniformTypeIdentifiers

@MainActor final class EditorBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    weak var store: NotebookStore?
    weak var webView: WKWebView?
    var ready = false
    var loadedVersion = -1
    var loadedMode: EditorMode?
    var loadedNotes: [String] = []
    var loadingDocument = false
    var printing = false
    init(store: NotebookStore) { self.store = store }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let data = message.body as? [String: Any], let store else { return }
        switch data["type"] as? String {
        case "ready": ready = true; update()
        case "change": if let text = data["markdown"] as? String, let id = data["id"] as? String { store.changed(text, id: id) }
        case "save": store.save()
        case "viewState": if let id = data["id"] as? String, let state = data["state"] { store.rememberSession(state, id: id) }
        case "openNote":
            if data["id"] as? String == store.selected, let selected = store.selected, let reference = data["reference"] as? String, let library = store.library {
                do { let url = try library.noteURL(reference, in: selected); store.select(String(url.path.dropFirst(library.root.path.count + 1))) }
                catch { store.error = "This note link could not be opened: " + error.localizedDescription }
            }
        case "outline":
            if data["id"] as? String == store.selected {
                store.headings = (data["headings"] as? [[String: Any]] ?? []).compactMap { row in
                    guard let index = row["index"] as? Int, let level = row["level"] as? Int, (1...6).contains(level), let text = row["text"] as? String else { return nil }
                    return NoteHeading(id: index, level: level, text: text)
                }
                store.activeHeading = data["active"] as? Int ?? -1
            }
        case "headingActive": if data["id"] as? String == store.selected { store.activeHeading = data["active"] as? Int ?? -1 }
        case "quickOpen": store.quickOpenVisible = true
        case "attachment":
            guard store.mode == .live, let id = data["id"] as? String, id == store.selected,
                  let request = data["request"] as? String, let base64 = data["data"] as? String,
                  base64.utf8.count <= 28 * 1024 * 1024, let bytes = Data(base64Encoded: base64), let library = store.library else { return }
            do {
                let reference = try library.storeImage(bytes, for: id)
                webView?.callAsyncJavaScript("window.notes.attachment(payload)", arguments: ["payload": ["id": id, "request": request, "src": reference]], in: nil, in: .page, completionHandler: nil)
            } catch {
                store.error = error.localizedDescription
                webView?.callAsyncJavaScript("window.notes.attachment(payload)", arguments: ["payload": ["id": id, "request": request, "error": error.localizedDescription]], in: nil, in: .page, completionHandler: nil)
            }
        case "properties":
            if data["id"] as? String == store.selected {
                store.properties = data["text"] as? String ?? ""
                store.propertyRows = (data["rows"] as? [[String: String]] ?? []).compactMap { row in
                    guard let name = row["name"], let value = row["value"] else { return nil }
                    return (name: name, value: value)
                }
            }
        case "stats": if data["id"] as? String == store.selected { store.words = data["words"] as? Int ?? 0 }
        case "openLink":
            if let raw = data["url"] as? String, let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        default: break
        }
    }
    func update() {
        guard ready, let store, let webView else { return }
        if loadedVersion != store.documentVersion {
            var payload: [String: Any] = ["id": store.selected ?? "", "markdown": store.markdown, "mode": store.mode.rawValue, "assetBase": "notes-asset:", "textSize": store.textSize, "focus": store.focusNewNote, "notes": noteLinks()]
            if let selected = store.selected, let state = store.sessions[selected], let bytes = try? JSONEncoder().encode(state), let object = try? JSONSerialization.jsonObject(with: bytes) { payload["state"] = object }
            if let term = store.pendingFind { payload["find"] = term }
            store.focusNewNote = false; store.pendingFind = nil
            loadedVersion = store.documentVersion; loadedMode = store.mode; loadingDocument = true
            let version = loadedVersion
            webView.callAsyncJavaScript("window.notes.load(payload)", arguments: ["payload": payload], in: nil, in: .page) { [weak self, weak store] result in
                if self?.loadedVersion == version { self?.loadingDocument = false }
                if case let .failure(error) = result { store?.error = "The editor could not load: \(error.localizedDescription)" }
            }
        } else if loadedMode != store.mode {
            loadedMode = store.mode
            webView.callAsyncJavaScript("window.notes.setMode(mode)", arguments: ["mode": store.mode.rawValue], in: nil, in: .page, completionHandler: nil)
        }
        let paths = store.items.filter { !$0.isFolder }.map(\.path)
        if paths != loadedNotes { loadedNotes = paths; webView.callAsyncJavaScript("window.notes.setNotes(notes)", arguments: ["notes": noteLinks()], in: nil, in: .page, completionHandler: nil) }
    }
    private func noteLinks() -> [[String: String]] {
        guard let store, let selected = store.selected, let library = store.library else { return [] }
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
            guard success, let self, let webView = self.webView, self.store?.selected != nil else { return }
            self.printing = true
            webView.callAsyncJavaScript("await window.notes.preparePrint()", arguments: [:], in: nil, in: .page) { [weak self] result in
                guard let self, let webView = self.webView else { return }
                if case let .failure(error) = result { self.store?.error = error.localizedDescription; self.finishPrint() }
                else {
                    guard let window = webView.window else { self.finishPrint(); return }
                    let info = NSPrintInfo.shared.copy() as! NSPrintInfo
                    info.topMargin = 40; info.bottomMargin = 40; info.leftMargin = 40; info.rightMargin = 40
                    info.horizontalPagination = .fit; info.isVerticallyCentered = false
                    let operation = webView.printOperation(with: info)
                    operation.jobTitle = self.store?.selected.map { NoteItem(path: $0, isFolder: false).title } ?? "Note"
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
        guard ready, let webView, let store, let id = store.selected else { completion(true); return }
        guard !loadingDocument, loadedVersion == store.documentVersion else { completion(false); return }
        webView.evaluateJavaScript("({markdown:window.notes.getMarkdown(),state:window.notes.viewState()})") { [weak store] value, error in
            guard let store else { completion(true); return }
            if let error { store.error = error.localizedDescription; completion(false); return }
            guard store.selected == id, let value = value as? [String: Any], let text = value["markdown"] as? String else { completion(false); return }
            store.changed(text, id: id)
            if let state = value["state"] { store.rememberSession(state, id: id, immediately: true) }
            completion(store.save())
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
    func makeCoordinator() -> EditorBridge { EditorBridge(store: store) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(NotebookImages(store: store), forURLScheme: "notes-asset")
        config.userContentController.add(context.coordinator, name: "notes")
        let view = WKWebView(frame: .zero, configuration: config); view.navigationDelegate = context.coordinator; view.uiDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground"); view.isInspectable = ProcessInfo.processInfo.arguments.contains("--inspect")
        context.coordinator.webView = view; store.bridge = context.coordinator
        if let url = Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Editor") {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else { store.error = "The editor resources are missing. Rebuild the app using scripts/build.sh." }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) { context.coordinator.update() }
    static func dismantleNSView(_ view: WKWebView, coordinator: EditorBridge) { view.configuration.userContentController.removeScriptMessageHandler(forName: "notes") }
}
