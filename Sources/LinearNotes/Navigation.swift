import SwiftUI
import AppKit
import NotesCore

/// One entry in the window's back/forward history: a tab and the note it showed.
struct NavigationVisit: Equatable {
    let tab: UUID
    let path: String?
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.path == rhs.path && (lhs.path != nil || lhs.tab == rhs.tab) }
}

/// Linear-style navigation: back/forward through visited notes, a Recent list, and copyable links.
extension NotebookStore {
    var canGoBack: Bool { visitIndex > 0 }
    var canGoForward: Bool { visitIndex < visits.count - 1 }
    var recentItems: [NoteItem] { recent.compactMap { path in items.first { $0.path == path && !$0.isFolder } } }

    func recordVisit() {
        let visit = NavigationVisit(tab: activeTab.id, path: activeTab.selected)
        if visits.indices.contains(visitIndex), visits[visitIndex] == visit { return }
        visits = Array(visits.prefix(visitIndex + 1)) + [visit]
        if visits.count > 100 { visits.removeFirst(visits.count - 100) }
        visitIndex = visits.count - 1
        if let path = visit.path { remember(recent: path) }
    }
    func goBack() { navigate(by: -1) }
    func goForward() { navigate(by: 1) }
    /// Steps through history within the visited tab, as Linear's back and forward do, skipping notes that no longer exist.
    private func navigate(by offset: Int) {
        var target = visitIndex + offset
        while visits.indices.contains(target), let path = visits[target].path, !items.contains(where: { $0.path == path && !$0.isFolder }) { target += offset }
        guard visits.indices.contains(target) else { return }
        let visit = visits[target], tab = allTabs.first(where: { $0.id == visit.tab }) ?? activeTab
        guard let pane = panes.first(where: { $0.tabs.contains { $0.id == tab.id } }) else { return }
        afterSave { [self] in
            visitIndex = target; activePaneID = pane.id; pane.selectedTabID = tab.id
            guard tab.selected != visit.path else { saveWorkspace(); return }
            guard let path = visit.path, let text = try? library?.read(path) else { showRecent(); return }
            tab.selected = path; tab.markdown = text; tab.baseline = text; tab.dirty = false
            tab.headings = []; tab.activeHeading = -1; tab.session = sessions[path]
            tab.mode = EditorMode(rawValue: tab.session?.mode ?? "live") ?? .live
            tab.status = "Saved locally"; tab.conflict = false; tab.saveFailed = false; tab.error = nil; tab.documentVersion += 1
            mutateSidebar { $0.lastSelected = path }; saveWorkspace()
        }
    }

    /// Keeps history and Recent pointing at a note or folder after it moves or is renamed.
    func remapNavigation(_ old: String, to new: String) {
        func map(_ path: String) -> String { path == old ? new : path.hasPrefix(old + "/") ? new + path.dropFirst(old.count) : path }
        var merged: [NavigationVisit] = [], index = -1
        for (offset, visit) in visits.enumerated() {
            let next = NavigationVisit(tab: visit.tab, path: visit.path.map(map))
            if merged.last != next { merged.append(next) }
            if offset == visitIndex { index = merged.count - 1 }
        }
        visits = merged; visitIndex = index
        recent = recent.map(map)
        if let library { UserDefaults.standard.set(recent, forKey: "recentNotes." + library.root.path) }
    }

    /// Shows the Recent list in the active tab, as Linear does when a sidebar view is chosen.
    func showRecent() {
        afterSave { [self] in
            let tab = activeTab
            guard tab.selected != nil else { return }
            tab.selected = nil; tab.markdown = ""; tab.baseline = ""; tab.dirty = false
            tab.headings = []; tab.activeHeading = -1; tab.properties = ""; tab.propertyRows = []
            tab.error = nil; tab.conflict = false; tab.saveFailed = false; tab.status = "Saved locally"
            tab.documentVersion += 1
            saveWorkspace()
        }
    }

    func loadRecent() {
        guard let library else { recent = []; return }
        recent = UserDefaults.standard.stringArray(forKey: "recentNotes." + library.root.path) ?? []
        visits = []; visitIndex = -1
    }
    private func remember(recent path: String) {
        recent.removeAll { $0 == path }; recent.insert(path, at: 0)
        if recent.count > 50 { recent.removeLast(recent.count - 50) }
        if let library { UserDefaults.standard.set(recent, forKey: "recentNotes." + library.root.path) }
    }

    func modified(_ path: String) -> Date? {
        guard let url = try? library?.url(for: path) else { return nil }
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
    func editedLabel(_ path: String, now: Date = .now) -> String {
        guard let date = modified(path) else { return "" }
        if now.timeIntervalSince(date) < 60 { return "Edited just now" }
        if now.timeIntervalSince(date) < 7 * 86_400 {
            let formatter = RelativeDateTimeFormatter(); formatter.unitsStyle = .short
            return "Edited " + formatter.localizedString(for: date, relativeTo: now)
        }
        return "Edited " + date.formatted(.dateTime.month(.abbreviated).day())
    }

    func fileDetails(_ path: String) -> (size: String, created: String?)? {
        guard let url = try? library?.url(for: path), let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey]) else { return nil }
        return (ByteCountFormatter.string(fromByteCount: Int64(values.fileSize ?? 0), countStyle: .file), values.creationDate?.formatted(.dateTime.month(.abbreviated).day().year()))
    }

    /// Copies the note's file URL, the local equivalent of Linear's shareable document link.
    /// Links between notes are still inserted with `@` or the link dialog, which keep them relative.
    func copyLink(_ path: String) {
        guard let url = try? library?.url(for: path) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }
}
