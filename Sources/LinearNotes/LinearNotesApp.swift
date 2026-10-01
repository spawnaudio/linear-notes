import SwiftUI
import AppKit

@main struct LinearNotesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = NotebookStore()
    var body: some Scene {
        Window("Linear Notes", id: "main") {
            ContentView(store: store)
                .onAppear { delegate.store = store; delegate.attachWindow() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1140, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") { store.create() }.keyboardShortcut("n")
                Button("New Folder…") { store.create(folder: true) }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Tab") { store.newTab() }.keyboardShortcut("t").disabled(store.library == nil)
                Button("Close Tab") { store.closeTab(store.activeTab, in: store.activePane) }.keyboardShortcut("w")
                Divider(); Button("Open Notes Folder…", action: store.chooseFolder).keyboardShortcut("o")
                Button("Import from Linear…") { store.linearImportVisible = true }.disabled(store.library == nil)
            }
            CommandGroup(replacing: .saveItem) { Button("Save") { store.bridge?.flush { _ in } }.keyboardShortcut("s") }
            CommandGroup(replacing: .printItem) {
                Button("Print / Save as PDF…") { store.bridge?.printDocument() }.keyboardShortcut("p", modifiers: [.command, .shift]).disabled(store.selected == nil)
            }
            CommandMenu("Find") {
                Button("Find in Document…") { store.bridge?.showFind() }.keyboardShortcut("f").disabled(store.selected == nil)
            }
            CommandMenu("Format") {
                Button("Bold") { store.bridge?.command("bold") }.keyboardShortcut("b")
                Button("Italic") { store.bridge?.command("italic") }.keyboardShortcut("i")
                Button("Underline") { store.bridge?.command("underline") }.keyboardShortcut("u")
                Button("Strikethrough") { store.bridge?.command("strike") }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Inline Code") { store.bridge?.command("code") }.keyboardShortcut("e")
                Button("Link…") { store.bridge?.command("link") }.keyboardShortcut("k")
                Divider()
                ForEach(1...4, id: \.self) { level in Button("Heading \(level)") { store.bridge?.command("h\(level)") }.keyboardShortcut(KeyEquivalent(Character(String(level))), modifiers: [.command, .option]) }
                Divider()
                Button("Bullet List") { store.bridge?.command("bullet") }.keyboardShortcut("8", modifiers: [.command, .shift])
                Button("Numbered List") { store.bridge?.command("ordered") }.keyboardShortcut("9", modifiers: [.command, .shift])
                Button("Checklist") { store.bridge?.command("task") }.keyboardShortcut("7", modifiers: [.command, .shift])
                Button("Quote") { store.bridge?.command("quote") }
                Button("Callout") { store.bridge?.command("callout") }
                Button("Image…") { store.bridge?.command("image") }.disabled(store.mode != .live || store.selected == nil)
                Button("Code Block") { store.bridge?.command("codeBlock") }.keyboardShortcut("\\", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Button("Find a Note…") { store.quickOpenVisible = true }.keyboardShortcut("p")
                Button("Toggle Sidebar") { store.sidebarVisible.toggle() }.keyboardShortcut("\\")
                Button("Toggle Details Sidebar") { store.inspectorVisible.toggle() }.keyboardShortcut("\\", modifiers: [.command, .option])
                Divider()
                Button("Split Right") { store.split(.right) }.keyboardShortcut(.rightArrow, modifiers: [.command, .option]).disabled(store.library == nil)
                Button("Split Down") { store.split(.down) }.keyboardShortcut(.downArrow, modifiers: [.command, .option]).disabled(store.library == nil)
                Button("Next Tab") { store.cycleTab(1) }.keyboardShortcut(.tab, modifiers: [.control])
                Button("Previous Tab") { store.cycleTab(-1) }.keyboardShortcut(.tab, modifiers: [.control, .shift])
                Button("Close Pane") { store.closePane(store.activePane) }.disabled(store.panes.count == 1)
                Divider()
                Button("Live Preview") { store.mode = .live }.keyboardShortcut("1", modifiers: [.command, .control])
                Button("Reading Mode") { store.mode = .reading }.keyboardShortcut("2", modifiers: [.command, .control])
                Button("Source Mode") { store.mode = .source }.keyboardShortcut("3", modifiers: [.command, .control])
                Divider()
                Button("Larger Document Text") { store.textSize = min(24, store.textSize + 1) }.keyboardShortcut("+", modifiers: [.command]).disabled(store.textSize >= 24)
                Button("Smaller Document Text") { store.textSize = max(12, store.textSize - 1) }.keyboardShortcut("-", modifiers: [.command]).disabled(store.textSize <= 12)
                Button("Default Document Text Size") { store.textSize = 15 }.keyboardShortcut("0")
            }
            CommandGroup(replacing: .help) {
                Button("Backing Up and Recovering Notes") {
                    let alert = NSAlert(); alert.messageText = "Keep a copy of your whole notes folder."
                    alert.informativeText = "Back up the entire folder, including Attachments and the hidden .linear-notes folder, with Time Machine or a copy on another drive. Markdown files remain readable in other apps.\n\nUnsaved drafts are kept locally and recovered as separate notes after an unexpected exit. This is crash recovery, not version history or a backup. If the original changed outside the app, Keep both preserves both copies.\n\nDeleted notes can be restored from Finder’s Trash. To share a document, choose File → Print / Save as PDF."
                    alert.addButton(withTitle: "OK"); alert.runModal()
                }
                Button("Keyboard Shortcuts") {
                    let alert = NSAlert(); alert.messageText = "Make yourself at home."
                    alert.informativeText = "⌘B  Bold     ⌘I  Italic     ⌘U  Underline\n⌘E  Inline code     ⌘K  Link or card\n⌘P  Find and switch notes\n⌘F  Find in document     ⌘⇧P  Print / Save PDF\n⌘+ / −  Document text size     ⌘0  Default size\n⌘⇧S  Strikethrough\n⌘⇧7 / 8 / 9  Checklist / bullets / numbers\n⌘⌥1–4  Heading levels\n⌘⇧\\  Code block\n⌘N  New note     ⌘⇧N  New folder\n⌘O  Open notes folder     ⌘S  Save\n⌘\\  Toggle sidebar     ⌘⌥\\  Details and outline\n⌃⌘1 / 2 / 3  Live / reading / source\n\nType / at the start of a paragraph for blocks.\nDrag near a row’s edge to reorder. Drop in the middle of a folder to move inside it.\nRight-click any item to pin or bookmark it.\nRich cards: click to select, then click again to open."
                    alert.runModal()
                }
            }
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var store: NotebookStore?
    var canClose = false
    func attachWindow() {
        DispatchQueue.main.async {
            if let window = NSApp.windows.first {
                window.delegate = self; window.titlebarAppearsTransparent = true
                window.backgroundColor = NSColor(Palette.sidebar)
                window.titlebarSeparatorStyle = .none
                window.setFrameAutosaveName("LinearNotesMainWindow")
            }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }
        store.flushAll { success in sender.reply(toApplicationShouldTerminate: success) }
        return .terminateLater
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if canClose { return true }
        guard let store else { return true }
        store.flushAll { [weak self, weak sender] success in
            if success { self?.canClose = true; sender?.close(); self?.canClose = false }
        }
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
