# Linear Notes

A minimal macOS notes app inspired by [Linear Documents](https://linear.app/docs/documents) and [Markdown Preview](https://markdownpreview.app). Your notes are ordinary local Markdown files. No account or server.

## Try it

Open **dist/Linear Notes.app**, then choose a folder containing `.md` or `.markdown` files. The included `Examples/Notebook` is a small starter notebook. The app remembers folders you choose through its folder picker.

Requires macOS 15 or later. This is a locally signed MVP, not a notarized distribution build. The app is called Linear Notes as a working title; it is not affiliated with Linear.

## Included in v0.1

- Live rich-text Markdown editing, read-only Reading mode, and plain-text Source mode.
- Linear's core formatting shortcuts, headings 1–4, slash commands, and a selection toolbar.
- Bullets, numbered lists, checklists, tables, code blocks, links, horizontal rules, and undo/redo.
- GitHub/Obsidian-style callouts and separate italic quote blocks.
- Pasted URL chooser: Markdown link or rich card. A card selects on the first click and opens on the second. Enter opens a selected card; Delete removes it in editing mode.
- YAML frontmatter displayed as compact property pills; click a pill to edit the YAML. Nested structures remain in the file, with top-level fields shown as pills.
- Native sidebar with folders, filename search, drag sorting, pins within each parent folder, and a separate bookmark section.
- Animated sidebar collapse, system light/dark appearance, native file dialogs, and Finder/Trash actions.
- Automatic local saving, external change detection, and a **Keep both** action for conflicting drafts.

## Organise notes

Right-click an item for pin, bookmark, rename, new child items, and Trash actions. Drop at the top/bottom edge of a row to reorder; drop in the middle of a folder to move inside it. Drop on the **Notes** section label to move to the root. Drop on **Bookmarks** to add a bookmark, or on a bookmark row to arrange that section. Pinned and unpinned items remain separate sorting groups.

## Shortcuts

| Action | Shortcut |
| --- | --- |
| New note / folder | ⌘N / ⌘⇧N |
| Open notes folder / save | ⌘O / ⌘S |
| Bold / italic / underline | ⌘B / ⌘I / ⌘U |
| Strikethrough / inline code | ⌘⇧S / ⌘E |
| Link or card | ⌘K |
| Headings 1–4 | ⌘⌥1–4 |
| Checklist / bullets / numbers | ⌘⇧7 / ⌘⇧8 / ⌘⇧9 |
| Code block | ⌘⇧\\ |
| Toggle sidebar | ⌘\\ |
| Live / reading / source | ⌃⌘1 / ⌃⌘2 / ⌃⌘3 |

Type `/` at the start of a paragraph for blocks. Type Markdown prefixes such as `## ` or `> ` directly; Markdown paste also renders in place. Use slash commands to insert callouts, or paste their Markdown syntax.

## Files and portability

Notes are UTF-8 files, saved with coordinated atomic replacement. Reading, switching modes, and opening documents do not rewrite their contents. Live edits use Tiptap's Markdown serializer, which can normalise whitespace and equivalent Markdown syntax. Source edits preserve the exact text you enter.

Sidebar preferences are separate in `.linear-notes/sidebar.json` inside the notes folder. They never become note frontmatter. Removing that metadata resets organisation preferences without removing notes.

Rich cards remain valid Markdown links: `[Title](<https://example.com> "card")`. Other readers display a normal link. Callouts use `> [!NOTE]`, `> [!TIP]`, `> [!WARNING]`, and other named types. Underline uses the editor's `++underlined++` extension; support varies between Markdown readers.

## Build and test

Open `Package.swift` in Xcode, or run:

```sh
bash scripts/test.sh
bash scripts/build.sh
```

The scripts select Xcode-beta when installed. The editor bundle is checked in so native builds do not require npm or network access. To edit and rebuild the editor:

```sh
cd Editor
npm ci
npm run build
npm test
```

Browser tests use the local Google Chrome installation on macOS. `npm run build` produces the offline resources under `Sources/LinearNotes/Resources/Editor`. The build script packages `dist/Linear Notes.app` and verifies its local signature.

## MVP boundaries

- The window, navigation, menus, file access, and lifecycle are native SwiftUI/AppKit. The embedded rich editor uses bundled Tiptap/ProseMirror in WKWebView. There is no Electron runtime or hosted editor.
- Rich cards show a supplied title and URL. They do not fetch website metadata, thumbnails, or embedded media.
- Images retain their Markdown references and display placeholders. Image loading/attachments, math, diagrams, wikilinks, footnotes, and full Obsidian extensions are outside this first version. Arbitrary HTML is preserved as inert source blocks.
- Callout fold markers are retained but callouts are always expanded. Properties use a simple YAML source editor; this is not a full typed property system.
- No cloud sync, collaboration, version history, or iOS app yet. The Foundation-only `NotesCore` and platform-independent editor are separated for future iOS reuse.
- External changes are checked every two seconds. Simultaneous writes by editors that ignore file coordination still require care; test with a small notebook first. Very large libraries/files and full accessibility coverage have not been validated.

See [validation notes](docs/VALIDATION.md) and [third-party notices](docs/THIRD_PARTY_NOTICES.md).

Product history is kept in [Linear Notes - v1.0 Ideation](<docs/Linear Notes - v1.0 Ideation.md>) and [Linear Notes MVP - Changelog](<docs/Linear Notes MVP - Changelog.md>). The ideation document preserves the original plan; the changelog records later feature-set updates.

The working visual and interaction principles are documented in [Linear Notes - Design Documentation](<docs/Linear Notes - Design Documentation.md>). The attached Linear reference files are kept under [docs/resources](<docs/resources>).
