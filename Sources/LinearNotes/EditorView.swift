import SwiftUI
import WebKit
import NotesCore

@MainActor final class EditorBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var store: NotebookStore?
    weak var webView: WKWebView?
    let fetcher = LinkPreviewFetcher()
    var ready = false
    var loadedVersion = -1
    var loadedMode: EditorMode?
    init(store: NotebookStore) { self.store = store }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let data = message.body as? [String: Any], let store else { return }
        switch data["type"] as? String {
        case "ready": ready = true; update()
        case "change": if let text = data["markdown"] as? String, let id = data["id"] as? String { store.changed(text, id: id) }
        case "save": store.save()
        case "stats": if data["id"] as? String == store.selected { store.words = data["words"] as? Int ?? 0 }
        case "openLink":
            if let raw = data["url"] as? String, let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        case "fetchCardPreview":
            if let raw = data["url"] as? String { Task { [weak self] in await self?.fetchCardPreview(raw) } }
        default: break
        }
    }
    func update() {
        guard ready, let store, let webView else { return }
        if loadedVersion != store.documentVersion {
            var payload: [String: Any] = ["id": store.selected ?? "", "markdown": store.markdown, "mode": store.mode.rawValue]
            if store.markdown.contains(#""card")"#) {
                payload["previews"] = store.cardPreviewsJSON()
            }
            loadedVersion = store.documentVersion; loadedMode = store.mode
            webView.callAsyncJavaScript("window.notes.load(payload)", arguments: ["payload": payload], in: nil, in: .page) { [weak store] result in
                if case let .failure(error) = result { store?.error = "The editor could not load: \(error.localizedDescription)" }
            }
        } else if loadedMode != store.mode {
            loadedMode = store.mode
            webView.callAsyncJavaScript("window.notes.setMode(mode)", arguments: ["mode": store.mode.rawValue], in: nil, in: .page, completionHandler: nil)
        }
    }
    func command(_ name: String) {
        webView?.callAsyncJavaScript("window.notes.command(command)", arguments: ["command": name], in: nil, in: .page, completionHandler: nil)
    }
    func fetchCardPreview(_ raw: String) async {
        guard let store,
              let library = store.library,
              let url = LinkPreviewing.normalizeURL(raw),
              url.scheme?.lowercased() == "https" else { return }
        if let preview = library.preview(for: url) {
            applyCardPreview(url: url, preview: preview)
            return
        }
        do {
            let fetched = try await fetcher.fetch(url: url)
            guard !fetched.title.isEmpty || !fetched.description.isEmpty || fetched.imageData != nil else { return }
            let preview = LinkPreview(
                title: fetched.title,
                description: fetched.description,
                imageURL: fetched.imageURL?.absoluteString,
                imageFile: nil,
                fetchedAt: Date()
            )
            do {
                try library.savePreview(preview, for: url, imageData: fetched.imageData, type: fetched.type)
                applyCardPreview(url: url, preview: library.preview(for: url) ?? preview)
            } catch {
                applyCardPreview(url: url, preview: preview, imageData: fetched.imageData, type: fetched.type)
            }
        } catch {
            return
        }
    }
    private func applyCardPreview(url: URL, preview: LinkPreview, imageData: Data? = nil, type: String? = nil) {
        guard let store, let webView else { return }
        var payload = store.cardPreviewJSON(for: url, preview: preview)
        if payload["imageSrc"] == nil, let imageData, let type {
            payload["imageSrc"] = "data:\(type);base64," + imageData.base64EncodedString()
        }
        payload["url"] = url.absoluteString
        webView.callAsyncJavaScript("window.notes.applyCardPreview(payload)", arguments: ["payload": payload], in: nil, in: .page, completionHandler: nil)
    }
    func flush(_ completion: @escaping @MainActor (Bool) -> Void) {
        guard ready, let webView, let store, let id = store.selected else { completion(true); return }
        webView.evaluateJavaScript("window.notes.getMarkdown()") { [weak store] value, error in
            guard let store else { completion(true); return }
            if let error { store.error = error.localizedDescription; completion(false); return }
            if let value = value as? String { store.changed(value, id: id) }
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
        config.userContentController.add(context.coordinator, name: "notes")
        let view = WKWebView(frame: .zero, configuration: config); view.navigationDelegate = context.coordinator
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
