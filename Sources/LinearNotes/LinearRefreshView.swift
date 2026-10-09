import SwiftUI
import NotesCore

struct LinearRefreshView: View {
    @ObservedObject var store: NotebookStore
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var root: URL?
    @State private var original = ""
    @State private var incoming = ""
    @State private var loading = true
    @State private var error: String?
    @State private var revision = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Refresh from Linear").font(.system(size: 21, weight: .semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close Linear refresh")
            }
            Text("Review the incoming document before replacing your local copy. Keep both saves it as a separate note.")
                .foregroundStyle(Palette.secondary)
            HStack(alignment: .top, spacing: 20) {
                preview("Local copy", text: original)
                Divider()
                preview("Incoming from Linear", text: incoming)
            }.frame(height: 360)
            if loading { ProgressView().controlSize(.small) }
            if let error { Text(error).foregroundStyle(.orange).font(.system(size: 12)).textSelection(.enabled) }
            HStack {
                Button("Reload preview") { revision += 1 }.disabled(loading)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Keep both") { apply(keepBoth: true) }.disabled(loading || incoming.isEmpty)
                Button("Replace local copy") { apply(keepBoth: false) }
                    .buttonStyle(.borderedProminent).disabled(loading || incoming.isEmpty || incoming == original)
            }
        }
        .padding(28).frame(width: 850).foregroundStyle(Palette.primary).background(Palette.panel).tint(Palette.accent)
        .onExitCommand { dismiss() }
        .task(id: revision) { await loadPreview() }
    }

    private func preview(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            // shortcut: selectable Markdown preview, reuse the editor if rich comparison is needed.
            ScrollView { Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .accessibilityLabel(title)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadPreview() async {
        loading = true; error = nil; incoming = ""
        defer { loading = false }
        if path.isEmpty { path = store.selected ?? ""; root = store.library?.root }
        let saved = await withCheckedContinuation { continuation in store.flushAll { continuation.resume(returning: $0) } }
        guard saved else { error = store.error ?? "Save your draft before refreshing."; return }
        do {
            try Task.checkCancellation()
            guard let library = store.library, library.root == root, !path.isEmpty else { throw LibraryError.invalidPath }
            original = try library.read(path)
            guard let source = NoteLibrary.linearSource(in: original) else { throw LinearAPI.APIError(message: "This note is no longer linked to a Linear document.") }
            guard let key = try LinearKeychain.read() else { throw LinearAPI.APIError(message: "Connect through File → Import from Linear before refreshing this note.") }
            let document = try await LinearAPI(key: key).document(id: source.documentID)
            try Task.checkCancellation()
            guard store.library?.root == root else { throw LibraryError.invalidPath }
            incoming = try NoteLibrary.refreshedLinearMarkdown(document, replacing: original)
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }

    private func apply(keepBoth: Bool) {
        loading = true; error = nil
        store.flushAll { success in
            defer { loading = false }
            guard success else { error = store.error ?? "Save your draft before applying the refresh."; return }
            do {
                guard let library = store.library, library.root == root else { throw LibraryError.invalidPath }
                try store.applyLinearRefresh(incoming, to: path, expected: original, keepBoth: keepBoth)
                dismiss()
            } catch {
                self.error = (error as? LibraryError) == .conflict ? "The local copy changed after this preview. Reload to review the latest versions, or keep both." : error.localizedDescription
            }
        }
    }
}

extension NotebookStore {
    func applyLinearRefresh(_ incoming: String, to path: String, expected: String, keepBoth: Bool) throws {
        guard let library else { throw LibraryError.invalidPath }
        if keepBoth {
            let item = NoteItem(path: path, isFolder: false)
            let copy = try library.createUnique(name: item.title + " — Linear copy", parent: item.parent, content: NoteLibrary.unlinkedLinearMarkdown(incoming))
            items = try library.scan(); select(copy)
        } else {
            try library.save(incoming, to: path, expected: expected)
            refreshFromDisk()
        }
    }

    func saveImagesLocally(using suppliedClient: LinearAPI? = nil) {
        guard !savingImages, let library, let path = selected else { return }
        let tab = activeTab
        savingImages = true
        flushAll { [self] success in
            guard success, self.library?.root == library.root else { savingImages = false; return }
            Task { @MainActor in
                defer { savingImages = false }
                do {
                    let original = try library.read(path)
                    let urls = NoteLibrary.remoteImageURLs(in: original)
                    let client = try suppliedClient ?? LinearAPI(key: LinearKeychain.read() ?? "")
                    var references: [URL: String] = [:]
                    for url in urls {
                        let data = try await client.image(url)
                        try Task.checkCancellation()
                        guard self.library?.root == library.root else { throw LibraryError.invalidPath }
                        references[url] = try library.storeImage(data, for: path)
                    }
                    let saved = await withCheckedContinuation { continuation in flushAll { continuation.resume(returning: $0) } }
                    guard saved else { throw LibraryError.conflict }
                    guard self.library?.root == library.root else { throw LibraryError.invalidPath }
                    let revised = NoteLibrary.replacingImageURLs(in: original, with: references)
                    try library.save(revised, to: path, expected: original)
                    for view in allTabs where view.selected == path { view.error = nil }
                    refreshFromDisk()
                    for view in allTabs where view.selected == path { view.status = "\(urls.count) image(s) saved locally" }
                } catch {
                    tab.error = "Images could not all be saved locally. The note was kept unchanged. " + error.localizedDescription
                }
            }
        }
    }
}
