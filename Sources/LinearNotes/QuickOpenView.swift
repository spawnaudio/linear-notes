import SwiftUI
import NotesCore

struct SearchResultRow: View {
    let result: NoteSearchResult
    let query: String
    private var excerpt: AttributedString {
        var text = AttributedString(result.excerpt)
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty, let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
            text[range].foregroundColor = Palette.accent; text[range].font = .system(size: 12, weight: .semibold)
        }
        return text
    }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.text").foregroundStyle(Palette.muted).padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(result.item.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.primary)
                Text(result.item.path).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                Text(excerpt).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10).contentShape(Rectangle())
    }
}

struct QuickOpenView: View {
    @ObservedObject var store: NotebookStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var index = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Search titles and note content", text: $store.query).textFieldStyle(.plain).font(.system(size: 17)).focused($focused).onSubmit(open)
                Text("⌘P").foregroundStyle(Palette.muted)
            }.padding(12).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
            if let error = store.searchError { Text(error).foregroundStyle(.orange).font(.system(size: 12)) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(Array(store.searchResults.enumerated()), id: \.element.id) { entry in
                            Button { index = entry.offset; open() } label: { SearchResultRow(result: entry.element, query: store.query) }
                                .buttonStyle(.plain).background(index == entry.offset ? Palette.control : .clear, in: RoundedRectangle(cornerRadius: 8)).id(entry.offset)
                        }
                        if store.searchResults.isEmpty { Text(store.searching ? "Searching…" : "No notes found").foregroundStyle(Palette.muted).padding(25) }
                    }
                }.frame(height: 300).onChange(of: index) { _, value in proxy.scrollTo(value, anchor: .center) }
            }
            HStack { Text("↑ ↓ Navigate"); Text("↵ Open"); Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }.font(.system(size: 11)).foregroundStyle(Palette.muted)
        }.padding(18).frame(width: 650).background(Palette.panel).foregroundStyle(Palette.primary)
        .onAppear { focused = true; store.refreshSearch() }
        .onChange(of: store.query) { index = 0 }
        .onChange(of: store.searchResults.map(\.id)) { index = min(index, max(0, store.searchResults.count - 1)) }
        .onKeyPress(.downArrow) { index = min(index + 1, max(0, store.searchResults.count - 1)); return .handled }
        .onKeyPress(.upArrow) { index = max(0, index - 1); return .handled }
        .onExitCommand { dismiss() }
    }
    private func open() {
        guard !store.searching, store.searchResults.indices.contains(index) else { return }
        store.select(store.searchResults[index].id); dismiss()
    }
}
