# Linear Notes MVP - Changelog

This document records feature-set changes and additions after the original product outline. The original outline remains in [Linear Notes - v1.0 Ideation](<Linear Notes - v1.0 Ideation.md>).

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
