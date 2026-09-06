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
                Button("New Note…") { store.create() }.keyboardShortcut("n")
                Button("New Folder…") { store.create(folder: true) }.keyboardShortcut("n", modifiers: [.command, .shift])
                Divider(); Button("Open Notes Folder…", action: store.chooseFolder).keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) { Button("Save") { store.bridge?.flush { _ in } }.keyboardShortcut("s") }
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
                Button("Code Block") { store.bridge?.command("codeBlock") }.keyboardShortcut("\\", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") { store.sidebarVisible.toggle() }.keyboardShortcut("\\")
                Divider()
                Button("Live Preview") { store.mode = .live }.keyboardShortcut("1", modifiers: [.command, .control])
                Button("Reading Mode") { store.mode = .reading }.keyboardShortcut("2", modifiers: [.command, .control])
                Button("Source Mode") { store.mode = .source }.keyboardShortcut("3", modifiers: [.command, .control])
            }
            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") {
                    let alert = NSAlert(); alert.messageText = "Make yourself at home."
                    alert.informativeText = "⌘B  Bold     ⌘I  Italic     ⌘U  Underline\n⌘E  Inline code     ⌘K  Link or card\n⌘⇧S  Strikethrough\n⌘⇧7 / 8 / 9  Checklist / bullets / numbers\n⌘⌥1–4  Heading levels\n⌘⇧\\  Code block\n⌘N  New note     ⌘⇧N  New folder\n⌘O  Open notes folder     ⌘S  Save\n⌘\\  Toggle sidebar\n⌃⌘1 / 2 / 3  Live / reading / source\n\nType / at the start of a paragraph for blocks.\nDrag near a row’s edge to reorder. Drop in the middle of a folder to move inside it.\nRight-click any item to pin or bookmark it.\nRich cards: click to select, then click again to open."
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
                window.backgroundColor = NSColor.windowBackgroundColor
                window.setFrameAutosaveName("LinearNotesMainWindow")
            }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let bridge = store?.bridge else { return .terminateNow }
        bridge.flush { success in sender.reply(toApplicationShouldTerminate: success) }
        return .terminateLater
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if canClose { return true }
        guard let bridge = store?.bridge else { return true }
        bridge.flush { [weak self, weak sender] success in
            if success { self?.canClose = true; sender?.close(); self?.canClose = false }
        }
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
