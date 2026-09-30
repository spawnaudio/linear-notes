# Linear Notes MVP - Changelog

This document records feature-set changes and additions after the original product outline. The original outline remains in [Linear Notes - v1.0 Ideation](<Linear Notes - v1.0 Ideation.md>).

## 1.3.0 — Images, finding notes, and Linear import · 1 October 2026

### Added / Changed / Fixed

- Real image rendering in Live Preview and Reading, with paste/drop, a native image picker, replacement/removal, and alt-text editing. Raster attachments remain separate portable files; app-managed note moves update their relative links.
- Content search with matching excerpts and a native `⌘P` quick switcher with arrow/Enter navigation. `⌘K` remains the link shortcut.
- Read-only Linear project/document browsing and single-document Markdown import. Personal keys stay in macOS Keychain; source metadata supports duplicate-safe import after local renames and retains local edits. Authenticated Linear raster images load through the native host with a strict host check and no redirects.
- Callout colours and icon/emoji selection through a contextual picker. Custom metadata preserves existing titles, fold markers, content, and undo.
- Heading outline in the existing details sidebar, with click-to-scroll, hierarchy, and current-section highlighting. Available in Live Preview and Reading.
- Corrected rich-card tokenization so it cannot split image Markdown; preserved surrounding text for images within paragraphs.
- Packaged as **Linear Notes v1.3.app**, version **1.3.0**.

### Validation

- 14 native tests and 21 editor tests pass, including attachment move/path checks, search drafts, API pagination/errors/host validation, duplicate-safe imports, image paste/drop, stale replies, callout styles/undo, and heading navigation.
- Native walkthrough used an isolated app and temporary notebook: content search/empty results, keyboard quick switching, local image rendering and native image insertion/save, outline navigation, mode switching, and the Linear connection sheet.
- Release build and local signature verification pass.

### Limits

- Live Linear browsing/import and authenticated image loading require a personal key and have not been verified against a signed-in workspace. Request handling was tested with stub responses.
- Imported remote image URLs require a connection; images are not copied for offline use. No automatic or two-way synchronization, OAuth connection, or bulk import.
- Full accessibility coverage and very large notebook performance remain unverified. Callout fold markers remain preserved without collapsing the callout body.

## 1.2.0 — Desktop redesign · 1 October 2026

### Changed

- Linear desktop design reference adopted for the window shell, inset content panel, surface palette, typography, controls, cards, and interaction states.
- Rounded document panel separated from the darker tab/status shell; removed the sidebar footer divider and aligned the app title with window controls.
- Added a collapsible right details sidebar with expanded properties, document mode, word count, save status, file path, and pin/bookmark/Finder actions (`⌘⌥\`).
- Removed the fixed formatting bar. Text selection opens the floating formatting toolbar; slash commands use compact grouped rows and shortcut hints.
- Improved light/dark contrast for metadata, callouts, and primary actions, plus keyboard activation and accessible names for native controls.
- App bundle is named **Linear Notes v1.2.app**, with version **1.2.0**.

### Validation

- 8 storage tests and 17 editor interaction tests pass.
- Native details sidebar open/close, property display, Reading-mode restrictions, and property editing from Source checked with a temporary notebook.
- Release build and local signature verification pass. Full accessibility, native light appearance, and every drag interaction remain unverified.

## 0.1.0 — Initial MVP

### Added

- Native macOS SwiftUI/AppKit application shell.
- Local Markdown and Markdown-compatible file storage.
- Live Preview, Reading, and Source modes.
- Linear-inspired formatting shortcuts and slash commands.
- Heading levels 1 through 4.
- Bold, italic, underline, strikethrough, inline code, lists, numbered lists, checklists, quotes, code blocks, tables, links, and dividers.
- GitHub/Obsidian-style callouts.
- Separate italic quote blocks.
- YAML frontmatter displayed as compact document-property pills.
- Rich link cards stored as portable Markdown links with a `"card"` marker.
- Two-click rich-card interaction: select first, open second.
- Local sidebar with folder and file navigation.
- Manual drag-and-drop ordering and folder moves.
- Pinned files and folders within their parent folders.
- Separate bookmarks section.
- Sidebar collapse animation.
- Search across the notes folder.
- Native create, rename, Finder reveal, and Trash actions.
- UTF-8 local saving with external-edit conflict detection.
- Keep-both recovery for an unsaved draft when the source file changes externally.
- Light and dark appearance support.
- Included sample notebook and editor guide.

### Validation

- 8 native storage tests pass.
- 14 editor interaction tests pass.
- Native create, edit, save, switch, reopen, bookmark, sidebar, and Trash workflow verified.
- Locally signed macOS app bundle produced by `scripts/build.sh`.

### Known MVP boundaries

- Rich cards do not fetch website metadata, thumbnails, or embeds.
- Images retain references and display placeholders.
- Callout fold markers are retained but callouts are expanded.
- No cloud sync, collaboration, version history, or iOS host yet.
- Full accessibility coverage, very large libraries, network-drive coordination, and simultaneous editing have not been fully validated.

## Change entry template

Use this format for future additions:

```markdown
## YYYY-MM-DD — Short change title

### Added / Changed / Fixed

- What changed.
- Why it changed.
- Any user-facing behaviour or shortcut changes.

### Validation

- Tests or manual workflow completed.

### Limits

- Known gaps, compatibility notes, or follow-up work.
```
