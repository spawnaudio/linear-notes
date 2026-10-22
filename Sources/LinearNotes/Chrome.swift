import SwiftUI
import AppKit

/// Back, forward, and history, aligned to the sidebar's right edge in the title bar row.
struct NavigationButtons: View {
    @ObservedObject var store: NotebookStore
    var body: some View {
        HStack(spacing: 2) {
            Button { store.goBack() } label: { ChromeIcon("arrow.left", size: 13) }
                .disabled(!store.canGoBack).help("Back · ⌘[").accessibilityLabel("Back")
            Button { store.goForward() } label: { ChromeIcon("arrow.right", size: 13) }
                .disabled(!store.canGoForward).help("Forward · ⌘]").accessibilityLabel("Forward")
            Menu {
                if store.recentItems.isEmpty { Text("No recent notes") }
                ForEach(store.recentItems.prefix(15)) { item in
                    Button(item.title) { store.select(item.path) }
                }
            } label: { ChromeIcon("clock", size: 13) }
                .menuStyle(.button).buttonStyle(ChromeButtonStyle()).menuIndicator(.hidden)
                .help("Recently viewed").accessibilityLabel("Recently viewed")
        }
    }
}

/// A primary sidebar row such as Recent: icon column, label, optional count.
struct NavigationRow: View {
    let title: String
    let icon: String
    let selected: Bool
    var count: Int? = nil
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ChromeIcon(icon, size: 13, color: selected ? Palette.primary : Palette.muted)
                Text(title).font(Typeface.ui(13, 500)).foregroundStyle(selected ? Palette.primary : Palette.secondary).lineLimit(1)
                Spacer(minLength: 4)
                if let count, count > 0 {
                    Text("\(count)").font(Typeface.ui(12, 500)).foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 20).background(Palette.raised, in: RoundedRectangle(cornerRadius: 5))
                }
            }.padding(.horizontal, 8).frame(height: 30).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Palette.selected : hovering ? Palette.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Linear's quiet section label with the disclosure triangle after the text and a hover `+`.
struct SectionHeader: View {
    let title: String
    let expanded: Bool
    var add: (() -> Void)? = nil
    var addLabel = ""
    let toggle: () -> Void
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggle) {
                HStack(spacing: 5) {
                    Text(title).font(Typeface.ui(12, 500)).foregroundStyle(Palette.muted)
                    Image(systemName: "triangle.fill").font(.system(size: 5)).foregroundStyle(Palette.muted)
                        .rotationEffect(.degrees(expanded ? 180 : 90))
                }.padding(.horizontal, 8).frame(height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(title).accessibilityValue(expanded ? "Expanded" : "Collapsed")
            Spacer()
            if let add {
                Button(action: add) { Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted) }
                    .buttonStyle(ChromeButtonStyle(size: 22)).opacity(hovering ? 1 : 0).accessibilityLabel(addLabel).help(addLabel)
            }
        }.padding(.top, 20).onHover { hovering = $0 }
    }
}

@MainActor func showShortcuts() {
    let alert = NSAlert(); alert.messageText = "Keyboard shortcuts"
    alert.informativeText = """
    ⌘K  Command menu (with a selection: link)     ⌘N  New note
    ⌘[ / ⌘]  Back / forward     ⌘T  New tab     ⌘W  Close tab
    ⌘\\  Toggle sidebar     ⌘⌥\\  Details rail
    ⌘F  Find in document     ⌘⌥F  Find and replace

    ⌘B  Bold     ⌘I  Italic     ⌘U  Underline     ⌘⇧S  Strikethrough
    ⌘E  Inline code     ⌘⇧\\  Code block
    ⌘⇧7 / 8 / 9  Checklist / bullets / numbers     ⌘↩  Check item (⌘⇧↩ with nested)
    ⌘⌥1–4  Heading levels     ⌃⌘1 / 2 / 3  Live / reading / source
    ⌘+ / −  Document text size     ⌘0  Default size     ⌘⇧P  Print / Save PDF

    Type / for blocks, @ to link a note, # to #### for headings, [] for a checklist,
    > for a quote, >>> for a collapsible section, and |-- for a table.
    Press Return in the title to rename the note; ↑ on the first line returns to the title.
    Drag near a row’s edge to reorder. Drop in the middle of a folder to move inside it.
    """
    alert.runModal()
}

@MainActor func showBackupHelp() {
    let alert = NSAlert(); alert.messageText = "Keep a copy of your whole notes folder."
    alert.informativeText = "Back up the entire folder, including Attachments and the hidden .linear-notes folder, with Time Machine or a copy on another drive. Markdown files remain readable in other apps.\n\nUnsaved drafts are kept locally and recovered as separate notes after an unexpected exit. This is crash recovery, not version history or a backup. If the original changed outside the app, Keep both preserves both copies.\n\nDeleted notes can be restored from Finder’s Trash. To share a document, choose File → Print / Save as PDF."
    alert.addButton(withTitle: "OK"); alert.runModal()
}
