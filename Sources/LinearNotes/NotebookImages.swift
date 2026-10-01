import Foundation
import WebKit
import NotesCore

@MainActor final class NotebookImages: NSObject, WKURLSchemeHandler {
    weak var store: NotebookStore?
    weak var tab: NoteTab?
    private var loading: [ObjectIdentifier: Task<Void, Never>] = [:]
    init(store: NotebookStore, tab: NoteTab) { self.store = store; self.tab = tab }
    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let id = ObjectIdentifier(task as AnyObject)
        loading[id] = Task { @MainActor in
          defer { loading.removeValue(forKey: id) }
          do {
            guard let url = task.request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let note = parts.queryItems?.first(where: { $0.name == "note" })?.value,
                  let reference = parts.queryItems?.first(where: { $0.name == "src" })?.value,
                  let store, let tab, tab.selected == note, let library = store.library else { throw LibraryError.invalidPath }
            let data: Data
            if let remote = URL(string: reference), remote.scheme == "https", remote.host == "uploads.linear.app" {
                guard let key = try LinearKeychain.read() else { throw LinearAPI.APIError(message: "Connect to Linear to view this image.") }
                data = try await LinearAPI(key: key).image(remote)
            } else {
                let file = try library.imageURL(reference, in: note)
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 20 * 1024 * 1024 else { throw LibraryError.invalidImage }
                data = try Data(contentsOf: file, options: .mappedIfSafe)
            }
            try Task.checkCancellation()
            guard tab.selected == note, store.library?.root == library.root else { throw LibraryError.invalidPath }
            let type = try NoteLibrary.imageType(data)
            task.didReceive(URLResponse(url: url, mimeType: type.mime, expectedContentLength: data.count, textEncodingName: nil))
            task.didReceive(data); task.didFinish()
          } catch { if !Task.isCancelled { task.didFailWithError(error) } }
        }
    }
    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) { loading.removeValue(forKey: ObjectIdentifier(task as AnyObject))?.cancel() }
}
