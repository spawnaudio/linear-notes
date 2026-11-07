import SwiftUI
import NotesCore

struct SearchResultRow: View {
    let result: NoteSearchResult
    let query: String
    private var excerpt: AttributedString {
        var text = AttributedString(result.excerpt)
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty, let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[range].foregroundColor = Palette.primary; text[range].font = Typeface.ui(12, 600)
        }
        return text
    }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ChromeIcon("doc.text", size: 13).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(result.item.title).font(Typeface.ui(13, 500)).foregroundStyle(Palette.primary).lineLimit(1)
                    if !result.item.parent.isEmpty { Text(result.item.parent).font(Typeface.ui(12)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.head) }
                }
                if !result.excerpt.isEmpty && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(excerpt).font(Typeface.ui(12)).foregroundStyle(Palette.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle())
    }
}

struct QuickOpenView: View {
    @ObservedObject var store: NotebookStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var index = 0

    struct Command: Identifiable {
        let title: String
        let icon: String
        let shortcut: String
        let run: @MainActor (NotebookStore) -> Void
        var id: String { title }
    }
    @MainActor static let commands: [Command] = [
        Command(title: "New note", icon: "square.and.pencil", shortcut: "⌘N") { $0.create() },
        Command(title: "New folder…", icon: "folder.badge.plus", shortcut: "⌘⇧N") { $0.create(folder: true) },
        Command(title: "New tab", icon: "plus.square.on.square", shortcut: "⌘T") { $0.newTab() },
        Command(title: "Show recent notes", icon: "clock", shortcut: "") { $0.showRecent() },
        Command(title: "Split right", icon: "rectangle.split.2x1", shortcut: "⌘⌥→") { $0.split(.right) },
        Command(title: "Split down", icon: "rectangle.split.1x2", shortcut: "⌘⌥↓") { $0.split(.down) },
        Command(title: "Toggle sidebar", icon: "sidebar.left", shortcut: "⌘\\") { $0.sidebarVisible.toggle() },
        Command(title: "Toggle details", icon: "sidebar.right", shortcut: "⌘⌥\\") { $0.inspectorVisible.toggle() },
        Command(title: "Import from Linear…", icon: "square.and.arrow.down", shortcut: "") { $0.linearImportVisible = true },
        Command(title: "Open notes folder…", icon: "folder", shortcut: "⌘O") { $0.chooseFolder() },
        Command(title: "Keyboard shortcuts", icon: "keyboard", shortcut: "⌘/") { _ in showShortcuts() }
    ]
    private var matchingCommands: [Command] {
        let term = store.searchTerm
        if term.isEmpty { return Array(Self.commands.prefix(3)) }
        return Self.commands.filter { $0.title.localizedCaseInsensitiveContains(term) }
    }
    private var rowCount: Int { matchingCommands.count + store.searchResults.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ChromeIcon("magnifyingglass", size: 14)
                TextField("Search notes or type a command…", text: $store.query).textFieldStyle(.plain)
                    .font(Typeface.ui(15)).foregroundStyle(Palette.primary).focused($focused).onSubmit(open)
            }.padding(.horizontal, 16).frame(height: 48)
            Rectangle().fill(Palette.divider).frame(height: 1)
            if let error = store.searchError { Text(error).foregroundStyle(Palette.warning).font(Typeface.ui(12)).padding(.horizontal, 16).padding(.top, 8) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !matchingCommands.isEmpty { label("Commands") }
                        ForEach(Array(matchingCommands.enumerated()), id: \.element.id) { entry in
                            Button { index = entry.offset; open() } label: { commandRow(entry.element, selected: index == entry.offset) }
                                .buttonStyle(.plain).id(entry.offset)
                        }
                        if !store.searchResults.isEmpty { label(store.searchTerm.isEmpty ? "Notes" : "Matching notes") }
                        ForEach(Array(store.searchResults.enumerated()), id: \.element.id) { entry in
                            let position = matchingCommands.count + entry.offset
                            Button { index = position; open() } label: {
                                SearchResultRow(result: entry.element, query: store.query)
                                    .background(index == position ? Palette.selected : .clear, in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain).id(position).accessibilityAddTraits(index == position ? .isSelected : [])
                        }
                        if store.searchResults.isEmpty && matchingCommands.isEmpty {
                            Text(store.searching ? "Searching…" : "No results").font(Typeface.ui(13)).foregroundStyle(Palette.faint).padding(20)
                        }
                    }.padding(8)
                }.frame(height: 360).onChange(of: index) { _, value in proxy.scrollTo(value, anchor: .center) }
            }
            Rectangle().fill(Palette.divider).frame(height: 1)
            HStack(spacing: 14) { Text("↑↓ Navigate"); Text("↵ Open"); Text("esc Close"); Spacer() }
                .font(Typeface.ui(11)).foregroundStyle(Palette.faint).padding(.horizontal, 16).frame(height: 32)
        }
        .frame(width: 640).background(Palette.canvas).foregroundStyle(Palette.secondary)
        .onAppear { focused = true; store.refreshSearch() }
        .onChange(of: store.query) { index = 0 }
        .onChange(of: store.searchResults.map(\.id)) { index = min(index, max(0, rowCount - 1)) }
        .onKeyPress(.downArrow) { index = min(index + 1, max(0, rowCount - 1)); return .handled }
        .onKeyPress(.upArrow) { index = max(0, index - 1); return .handled }
        .onKeyPress(.return) { open(); return .handled }
        .onExitCommand { dismiss() }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Typeface.ui(12, 500)).foregroundStyle(Palette.muted).padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
    }
    private func commandRow(_ command: Command, selected: Bool) -> some View {
        HStack(spacing: 10) {
            ChromeIcon(command.icon, size: 13)
            Text(command.title).font(Typeface.ui(13, 500)).foregroundStyle(Palette.primary)
            Spacer()
            Text(command.shortcut).font(Typeface.ui(12)).foregroundStyle(Palette.faint)
        }.padding(.horizontal, 10).frame(height: 36).contentShape(Rectangle())
            .background(selected ? Palette.selected : .clear, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func open() {
        let commands = matchingCommands
        if commands.indices.contains(index) {
            let command = commands[index], store = store
            dismiss(); store.query = ""
            // Let the sheet finish closing so a command can present its own sheet.
            Task { @MainActor in try? await Task.sleep(for: .milliseconds(250)); command.run(store) }
            return
        }
        let note = index - commands.count
        guard !store.searching, store.searchResults.indices.contains(note) else { return }
        store.openSearchResult(store.searchResults[note].id); dismiss()
    }
}
