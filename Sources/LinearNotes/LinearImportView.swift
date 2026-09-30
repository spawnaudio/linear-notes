import SwiftUI
import Security
import NotesCore

enum LinearKeychain {
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "local.linearnotes.linear", kSecAttrAccount as String: "personal-api-key"] }
    static func read() throws -> String? {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw error(status) }
        return value
    }
    static func save(_ key: String) throws {
        let values: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item.merge(values) { _, new in new }; item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil); guard added == errSecSuccess else { throw error(added) }
        } else if status != errSecSuccess { throw error(status) }
    }
    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw error(status) }
    }
    private static func error(_ status: OSStatus) -> NSError { NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain: \(SecCopyErrorMessageString(status, nil) as String? ?? "Could not access the Linear key.")"]) }
}

struct LinearImportView: View {
    @ObservedObject var store: NotebookStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var api: LinearAPI?
    @State private var projects: [LinearProject] = []
    @State private var projectID = ""
    @State private var documents: [LinearDocument] = []
    @State private var documentID = ""
    @State private var preview: LinearDocument?
    @State private var parent = ""
    @State private var loading = false
    @State private var error: String?
    @State private var root: URL?
    @State private var connectionTask: Task<Void, Never>?
    private var project: LinearProject? { projects.first { $0.id == projectID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Import from Linear").font(.system(size: 21, weight: .semibold)); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close Linear import") }
            if api == nil {
                Text("Connect with a personal API key that can read projects and documents. Your key is saved in macOS Keychain.").foregroundStyle(Palette.secondary)
                SecureField("Linear API key", text: $key).textFieldStyle(.roundedBorder).onSubmit { connect() }
                HStack {
                    Link("Create a key in Linear", destination: URL(string: "https://linear.app/settings/api")!)
                    Spacer(); Button("Connect") { connect() }.buttonStyle(.borderedProminent).disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loading)
                }
            } else {
                HStack {
                    Picker("Project", selection: $projectID) { ForEach(projects) { Text($0.name).tag($0.id) } }.disabled(loading || projects.isEmpty)
                    Button("Disconnect") {
                        do { try LinearKeychain.remove(); api = nil; key = ""; projects = []; documents = []; preview = nil; error = nil }
                        catch { self.error = error.localizedDescription }
                    }.disabled(loading)
                }
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Documents").foregroundStyle(Palette.muted)
                        List(documents, selection: $documentID) { document in Label(document.title, systemImage: "doc.text").tag(document.id) }
                            .listStyle(.plain).frame(width: 240)
                        if documents.isEmpty && !loading { Text("No documents in this project.").foregroundStyle(Palette.muted) }
                        if let project, let url = URL(string: project.url), url.scheme == "https", url.host == "linear.app" { Link("Open project in Linear", destination: url) }
                    }
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let preview {
                                Text(preview.title).font(.system(size: 24, weight: .semibold))
                                // ponytail: selectable Markdown preview; reuse the editor if rich import previews become necessary.
                                Text(preview.content ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                if let url = URL(string: preview.url), url.scheme == "https", url.host == "linear.app" { Link("Open in Linear", destination: url) }
                            } else { Text(loading ? "Loading…" : "Select a document to preview it.").foregroundStyle(Palette.muted) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                    }
                }.frame(height: 330)
                Picker("Save to", selection: $parent) {
                    Text(store.rootName).tag("")
                    ForEach(store.items.filter(\.isFolder).sorted { $0.path < $1.path }) { Text($0.path).tag($0.path) }
                }
                Text("Imports a local copy. The original stays in Linear.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                HStack { Button("Refresh projects") { connect(api?.key) }.disabled(loading); Spacer(); Button("Cancel") { dismiss() }; Button("Import document") { importDocument() }.buttonStyle(.borderedProminent).disabled(loading || preview == nil || project == nil || store.library == nil) }
            }
            if loading { ProgressView().controlSize(.small) }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled) }
        }
        .padding(28).frame(width: api == nil ? 520 : 850).foregroundStyle(Palette.primary).background(Palette.panel).tint(Palette.accent)
        .onExitCommand { dismiss() }
        .onDisappear { connectionTask?.cancel() }
        .task {
            root = store.library?.root; parent = store.insertionParent
            do { if let saved = try LinearKeychain.read() { connect(saved) } }
            catch { self.error = error.localizedDescription }
        }
        .task(id: projectID) {
            guard let api, !projectID.isEmpty else { return }
            let id = projectID; documents = []; preview = nil; documentID = ""; loading = true; error = nil
            defer { if projectID == id { loading = false } }
            do { let results = try await api.documents(project: id); try Task.checkCancellation(); documents = results; documentID = results.first?.id ?? "" }
            catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
        .task(id: documentID) {
            preview = nil
            guard let api, !documentID.isEmpty else { return }
            let id = documentID; loading = true; error = nil
            defer { if documentID == id { loading = false } }
            do { let result = try await api.document(id: id); try Task.checkCancellation(); preview = result }
            catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }

    private func connect(_ saved: String? = nil) {
        let value = (saved ?? key).trimmingCharacters(in: .whitespacesAndNewlines)
        loading = true; error = nil
        connectionTask?.cancel()
        connectionTask = Task { @MainActor in
            defer { loading = false }
            do {
                let client = LinearAPI(key: value); let results = try await client.projects()
                try Task.checkCancellation()
                try LinearKeychain.save(value); key = ""; api = client; projects = results
                projectID = results.contains { $0.id == projectID } ? projectID : results.first?.id ?? ""
                if results.isEmpty { error = "No projects are available to this key." }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }

    private func importDocument() {
        guard let project, let preview, let content = preview.content, let library = store.library, library.root == root else { error = "Choose a notes folder before importing."; return }
        store.bridge?.flush { success in
            guard success else { error = store.error; return }
            guard store.library?.root == library.root else { error = "The notes folder changed. Reopen import to choose its destination."; return }
            do {
                let path = try library.importLinearDocument(id: preview.id, projectID: project.id, title: preview.title, sourceURL: preview.url, content: content, parent: parent)
                store.items = try library.scan(); store.mode = .live; store.select(path); dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
