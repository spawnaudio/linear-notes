import SwiftUI
import Combine
import NotesCore

@MainActor final class NoteTab: ObservableObject, Identifiable {
    let id: UUID
    @Published var selected: String?
    @Published var markdown = ""
    @Published var mode: EditorMode = .live
    @Published var properties = ""
    @Published var propertyRows: [(name: String, value: String)] = []
    @Published var headings: [NoteHeading] = []
    @Published var activeHeading = -1
    @Published var documentVersion = 0
    @Published var status = "Saved locally"
    @Published var error: String?
    @Published var conflict = false
    @Published var saveFailed = false
    @Published var words = 0
    var baseline = ""
    var dirty = false
    var pendingFind: String?
    var focusNewNote = false
    var session: NoteSession?
    var autosave: Task<Void, Never>?
    weak var bridge: EditorBridge?
    init(id: UUID = UUID()) { self.id = id }
}

@MainActor final class NotePane: ObservableObject, Identifiable {
    let id: UUID
    @Published var tabs: [NoteTab]
    @Published var selectedTabID: UUID
    var tab: NoteTab { tabs.first { $0.id == selectedTabID } ?? tabs[0] }
    init(id: UUID = UUID(), tabs: [NoteTab]) {
        self.id = id; self.tabs = tabs; selectedTabID = tabs[0].id
    }
}

enum SplitDirection: String, CaseIterable {
    case left, right, up, down
    var title: String { "Split " + rawValue }
    var horizontal: Bool { self == .left || self == .right }
    var before: Bool { self == .left || self == .up }
}

indirect enum PaneLayout: Codable, Equatable {
    case pane(UUID)
    case split(id: UUID, horizontal: Bool, fraction: Double, first: PaneLayout, second: PaneLayout)
    var paneIDs: [UUID] {
        switch self { case .pane(let id): [id]; case .split(_, _, _, let first, let second): first.paneIDs + second.paneIDs }
    }
    func replacing(_ id: UUID, with next: PaneLayout) -> PaneLayout {
        switch self {
        case .pane(let pane): return pane == id ? next : self
        case .split(let split, let horizontal, let fraction, let first, let second):
            return .split(id: split, horizontal: horizontal, fraction: fraction, first: first.replacing(id, with: next), second: second.replacing(id, with: next))
        }
    }
    func removing(_ id: UUID) -> PaneLayout? {
        switch self {
        case .pane(let pane): return pane == id ? nil : self
        case .split(let split, let horizontal, let fraction, let first, let second):
            let a = first.removing(id), b = second.removing(id)
            guard let a else { return b }; guard let b else { return a }
            return .split(id: split, horizontal: horizontal, fraction: fraction, first: a, second: b)
        }
    }
    func resizing(_ id: UUID, to value: Double) -> PaneLayout {
        switch self {
        case .pane: return self
        case .split(let split, let horizontal, let fraction, let first, let second):
            return .split(id: split, horizontal: horizontal, fraction: split == id ? min(0.9, max(0.1, value)) : fraction, first: first.resizing(id, to: value), second: second.resizing(id, to: value))
        }
    }
}

struct WorkspaceState: Codable {
    struct Tab: Codable { var id: UUID; var path: String?; var session: NoteSession? }
    struct Pane: Codable { var id: UUID; var selected: UUID; var tabs: [Tab] }
    var layout: PaneLayout
    var active: UUID
    var panes: [Pane]
}

extension NotebookStore {
    var allTabs: [NoteTab] { panes.flatMap(\.tabs) }
    var activePane: NotePane { panes.first { $0.id == activePaneID } ?? panes[0] }
    var activeTab: NoteTab { activePane.tab }
    func observePanes() {
        paneObservers = panes.map { $0.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() } }
            + allTabs.map { $0.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() } }
    }
    func resetWorkspace() {
        allTabs.forEach { $0.autosave?.cancel() }
        let pane = NotePane(tabs: [NoteTab()])
        panes = [pane]; layout = .pane(pane.id); activePaneID = pane.id; observePanes()
    }
    @discardableResult func restoreWorkspace() -> Bool {
        guard let library else { return false }
        do {
            guard let state: WorkspaceState = try library.workspace() else { return false }
            let ids = state.layout.paneIDs
            guard !ids.isEmpty, Set(ids).count == ids.count, Set(ids) == Set(state.panes.map(\.id)),
                  state.panes.count == ids.count, ids.contains(state.active),
                  state.panes.allSatisfy({ pane in !pane.tabs.isEmpty && pane.tabs.contains { $0.id == pane.selected } }) else { return false }
            let tabIDs = state.panes.flatMap { $0.tabs.map(\.id) }
            guard Set(tabIDs).count == tabIDs.count else { return false }
            let restored = try state.panes.map { saved in
                let tabs = try saved.tabs.compactMap { savedTab -> NoteTab? in
                    let tab = NoteTab(id: savedTab.id)
                    if let path = savedTab.path {
                        guard items.contains(where: { $0.path == path && !$0.isFolder }) else { return nil }
                        tab.selected = path; tab.markdown = try library.read(path); tab.baseline = tab.markdown
                    }
                    tab.session = savedTab.session; tab.mode = EditorMode(rawValue: savedTab.session?.mode ?? "live") ?? .live
                    return tab
                }
                let pane = NotePane(id: saved.id, tabs: tabs.isEmpty ? [NoteTab()] : tabs)
                if pane.tabs.contains(where: { $0.id == saved.selected }) { pane.selectedTabID = saved.selected }
                return pane
            }
            panes = restored; layout = state.layout; activePaneID = state.active; observePanes()
            return true
        } catch { self.error = "The previous tab layout could not be restored: " + error.localizedDescription; return false }
    }
    func saveWorkspace() {
        guard let library else { return }
        let state = WorkspaceState(layout: layout, active: activePaneID, panes: panes.map { pane in
            .init(id: pane.id, selected: pane.selectedTabID, tabs: pane.tabs.map { tab in
                var session = tab.session ?? NoteSession(mode: tab.mode.rawValue, positions: [:]); session.mode = tab.mode.rawValue
                return .init(id: tab.id, path: tab.selected, session: session)
            })
        })
        do { try library.saveWorkspace(state) } catch { self.error = "The tab layout could not be saved: " + error.localizedDescription }
    }
    func activate(_ pane: NotePane, tab: NoteTab? = nil) {
        guard panes.contains(where: { $0.id == pane.id }) else { return }
        let nextTab = tab.flatMap { candidate in pane.tabs.first { $0.id == candidate.id } } ?? pane.tab
        guard activePaneID != pane.id || pane.selectedTabID != nextTab.id else { return }
        activePaneID = pane.id
        pane.selectedTabID = nextTab.id
        saveWorkspace()
    }
    func activate(_ tab: NoteTab) {
        if let pane = panes.first(where: { $0.tabs.contains { $0.id == tab.id } }) { activate(pane, tab: tab) }
    }
    func selectTab(_ tab: NoteTab, in pane: NotePane) {
        flushTab(pane.tab) { [self] success in if success { activate(pane, tab: tab) } }
    }
    func newTab() {
        afterSave { [self] in
            let tab = NoteTab(); activePane.tabs.append(tab); activePane.selectedTabID = tab.id
            observePanes(); saveWorkspace(); quickOpenVisible = true
        }
    }
    func split(_ direction: SplitDirection, paneID: UUID? = nil, tabID: UUID? = nil) {
        afterSave { [self] in
            guard let source = panes.first(where: { $0.id == (paneID ?? activePaneID) }) else { return }
            let original = source.tabs.first { $0.id == (tabID ?? source.selectedTabID) } ?? source.tab
            let copy = NoteTab(); copy.selected = original.selected; copy.markdown = original.markdown; copy.baseline = original.baseline
            copy.mode = original.mode; copy.session = original.session
            let next = NotePane(tabs: [copy]); insertPane(next, beside: source, direction: direction)
            observePanes(); activate(next)
        }
    }
    func insertPane(_ pane: NotePane, beside source: NotePane, direction: SplitDirection) {
        panes.append(pane)
        layout = layout.replacing(source.id, with: .split(id: UUID(), horizontal: direction.horizontal, fraction: 0.5,
            first: .pane(direction.before ? pane.id : source.id), second: .pane(direction.before ? source.id : pane.id)))
    }
    func closeTab(_ tab: NoteTab, in pane: NotePane) {
        afterSave { [self] in
            guard let index = pane.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
            pane.tabs.remove(at: index)
            if pane.tabs.isEmpty { removePane(pane) }
            else if pane.selectedTabID == tab.id { pane.selectedTabID = pane.tabs[min(index, pane.tabs.count - 1)].id }
            observePanes(); saveWorkspace()
        }
    }
    private func removePane(_ pane: NotePane) {
        if let remaining = layout.removing(pane.id) {
            layout = remaining; panes.removeAll { $0.id == pane.id }
            if activePaneID == pane.id { activePaneID = remaining.paneIDs[0] }
        } else { let tab = NoteTab(); pane.tabs = [tab]; pane.selectedTabID = tab.id }
    }
    func closePane(_ pane: NotePane) {
        afterSave { [self] in removePane(pane); observePanes(); saveWorkspace() }
    }
    func moveTab(_ id: UUID, to paneID: UUID, before: UUID? = nil, direction: SplitDirection? = nil) {
        afterSave { [self] in
            guard let source = panes.first(where: { $0.tabs.contains { $0.id == id } }),
                  let tab = source.tabs.first(where: { $0.id == id }), let target = panes.first(where: { $0.id == paneID }) else { return }
            guard before != id else { return }
            source.tabs.removeAll { $0.id == id }
            if source.selectedTabID == id, let first = source.tabs.first { source.selectedTabID = first.id }
            var destination = target
            if let direction {
                destination = NotePane(tabs: [tab]); insertPane(destination, beside: target, direction: direction)
            } else {
                let index = before.flatMap { before in target.tabs.firstIndex { $0.id == before } } ?? target.tabs.count
                target.tabs.insert(tab, at: index)
            }
            if source.tabs.isEmpty {
                if source.id == target.id, direction != nil {
                    let empty = NoteTab(); source.tabs = [empty]; source.selectedTabID = empty.id
                } else { removePane(source) }
            }
            observePanes(); activate(destination, tab: tab)
        }
    }
    func cycleTab(_ offset: Int) {
        let pane = activePane, index = activePane.tabs.firstIndex { $0.id == activePane.selectedTabID } ?? 0
        selectTab(pane.tabs[(index + offset + pane.tabs.count) % pane.tabs.count], in: pane)
    }
    func flushAll(_ completion: @escaping @MainActor (Bool) -> Void) {
        let tabs = allTabs
        func flush(_ index: Int) {
            guard index < tabs.count else { saveWorkspace(); completion(true); return }
            let tab = tabs[index]
            flushTab(tab) { success in if success { flush(index + 1) } else { completion(false) } }
        }
        flush(0)
    }
    private func flushTab(_ tab: NoteTab, completion: @escaping @MainActor (Bool) -> Void) {
        let finish: @MainActor (Bool) -> Void = { [self] success in
            if !success, tab.error != nil { activate(tab) }
            completion(success)
        }
        if let bridge = tab.bridge, bridge.ready { bridge.flush(finish) }
        else { finish(save(tab: tab)) }
    }
}
