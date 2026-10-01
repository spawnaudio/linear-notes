# Linear Notes

Linear Project: [Linear Notes App](https://linear.app/spawn-audio/project/linear-notes-app-f39bbd5383e7/overview).

A minimal macOS notes app inspired by [Linear Documents](https://linear.app/docs/documents) and [Markdown Preview](https://markdownpreview.app). Your notes are ordinary local Markdown files. No account is required for local notes. Linear import is optional.

## Try it

Open **dist/Linear Notes v1.3.app**, then choose a folder containing `.md` or `.markdown` files. The included `Examples/Notebook` is a small starter notebook. The app remembers folders you choose through its folder picker.

Requires macOS 15 or later. This is a locally signed MVP, not a notarized distribution build. The app is called Linear Notes as a working title; it is not affiliated with Linear.

## Included

- Live rich-text Markdown editing, read-only Reading mode, and plain-text Source mode.
- Linear's core formatting shortcuts, headings 1–4, slash commands, and a selection toolbar.
- Bullets, numbered lists, checklists, tables, code blocks, links, horizontal rules, and undo/redo.
- GitHub/Obsidian-style callouts with custom colours and icons/emoji, plus separate italic quote blocks.
- Pasted URL chooser: Markdown link or rich card. A card selects on the first click and opens on the second. Enter opens a selected card; Delete removes it in editing mode.
- YAML frontmatter displayed as compact property pills; click a pill to edit the YAML. Nested structures remain in the file, with top-level fields shown as pills.
- Native sidebar with folders, content search with matching excerpts, drag sorting, pins within each parent folder, and a separate bookmark section.
- Instant **⌘N** capture into a unique Untitled note, ready to type; rename it later.
- Find within a document with **⌘F**, match highlighting/counts, and next/previous navigation in all three modes. Library search results jump to the matching passage.
- Remembered mode, cursor/selection, and scroll position for each note.
- Tab groups with nested splits in all four directions, draggable/reorderable tabs, resizable dividers, and layouts restored when reopening the notebook. Different panes can show the same note in different modes, with a shared draft.
- Relative Markdown links to other notes from the existing link dialog; open inside the app and update when notes/folders move or rename through the app.
- Native **File → Print / Save as PDF…**, with a clean document layout.
- Document text sizing in View, visible keyboard focus, and labelled editor controls.
- Quick note switching with **⌘P**, arrow keys, and Enter. **⌘K** still inserts a link.
- Clickable heading outline in the existing right details sidebar, with the current section highlighted in Live Preview and Reading.
- Paste, drop, or insert PNG/JPEG/GIF/WebP images; replace, remove, and edit alt text in Live Preview.
- Optional read-only Linear project browser and document import, using a personal API key stored in macOS Keychain.
- Animated sidebar collapse, system light/dark appearance, native file dialogs, and Finder/Trash actions.
- Automatic local saving, separate recovered copies of unsaved drafts after an unexpected exit, **Retry** for save failures, and **Keep both** for conflicting drafts.

## Organise notes

Right-click an item for pin, bookmark, rename, new child items, and Trash actions. Drop at the top/bottom edge of a row to reorder; drop in the middle of a folder to move inside it. Drop on the **Notes** section label to move to the root. Drop on **Bookmarks** to add a bookmark, or on a bookmark row to arrange that section. Pinned and unpinned items remain separate sorting groups.

## Shortcuts

Right-click a tab or use the split button beside the tabs to split left, right, up, or down. Drag a tab title to reorder it; the insertion line shows whether it lands before or after another tab. Drop on another group's tab bar to move it, or on a pane's editor edge to create a split; the highlighted area shows its destination. Splitting a lone tab leaves an empty pane in its place. Drag dividers to resize. Closing the last tab in a group collapses that split. Sidebar note drops open in the target pane or a new split. The details sidebar and menu commands follow the active pane. Layouts live in `.linear-notes/workspace.json`; note files stay ordinary Markdown.

| Action | Shortcut |
| --- | --- |
| New note / folder | ⌘N / ⌘⇧N |
| New / close tab | ⌘T / ⌘W |
| Split right / down | ⌘⌥→ / ⌘⌥↓ |
| Next / previous tab in group | ⌃Tab / ⌃⇧Tab |
| Open notes folder / save | ⌘O / ⌘S |
| Bold / italic / underline | ⌘B / ⌘I / ⌘U |
| Strikethrough / inline code | ⌘⇧S / ⌘E |
| Link or card | ⌘K |
| Find and switch notes | ⌘P, then ↑ / ↓ and Return |
| Find within document | ⌘F; Return / ⇧Return for next / previous |
| Print / Save as PDF | ⌘⇧P |
| Larger / smaller / default document text | ⌘+ / ⌘− / ⌘0 |
| Headings 1–4 | ⌘⌥1–4 |
| Checklist / bullets / numbers | ⌘⇧7 / ⌘⇧8 / ⌘⇧9 |
| Code block | ⌘⇧\\ |
| Toggle sidebar | ⌘\\ |
| Live / reading / source | ⌃⌘1 / ⌃⌘2 / ⌃⌘3 |

Type `/` at the start of a paragraph for blocks. Type Markdown prefixes such as `## ` or `> ` directly; Markdown paste also renders in place. Use slash commands to insert callouts, or paste their Markdown syntax.

## Images and Linear import

Use **Format → Image…**, the `/image` command, or paste/drop an image into Live Preview. Select the image to replace it, edit its alt text, or remove it. Images must be PNG, JPEG, GIF, or WebP, under 20 MB and 40 megapixels. Attached files are stored under `Attachments/` in the notebook with relative Markdown links. Moving a note or folder through the app updates its managed attachment links. Move the whole notebook when transferring it to another Mac; manually moving individual notes outside the app can break relative links. The managed `Attachments` folder stays at the notebook root. Removing an image from a note retains the file so undo and other references remain safe.

Choose **File → Import from Linear…** or use the workspace menu. Connect with a personal API key that can read the relevant projects and documents. Select a project, preview a document, choose a destination folder, then import its Markdown. The source ID, project ID, and source URL are retained in frontmatter; the details sidebar links to the original. Importing the same source again opens the existing local copy, including after a rename, and preserves local edits. Disconnect removes the saved key and keeps imported notes.

Imported remote images retain their URLs and require a connection. Images hosted at `uploads.linear.app` load through the saved key; the key is never passed to editor JavaScript, other image hosts, or redirected requests. Public HTTPS images load without that key. This version imports individual documents and does not sync changes back to Linear. [Linear API authentication](https://linear.app/developers/graphql) describes the supported personal-key authentication.

## Files and portability

Notes are UTF-8 files, saved with coordinated atomic replacement. Reading, switching modes, and opening documents do not rewrite their contents. Live edits use Tiptap's Markdown serializer, which can normalise whitespace and equivalent Markdown syntax. Source edits preserve the exact text you enter.

Sidebar preferences, reading positions, and unsaved draft recovery live separately in the hidden `.linear-notes` folder. They never become note frontmatter. An unexpected exit restores unsaved work as separate “Recovered” notes, preserving original files and external edits. Recovery is not version history.

Back up or transfer the **whole notebook folder**, including `Attachments` and `.linear-notes`, using Time Machine or a copy on another drive. **Help → Backing Up and Recovering Notes** explains recovery and Finder’s Trash.

In the link dialog, search for another note or enter a relative `.md` / `.markdown` reference. In Reading, click or press Return to open a note link; in Live Preview, use ⌘click or ⌘Return. Standard inline links and reference definitions are updated when you move or rename notes through the app. Manually moving files in Finder does not update links.

Rich cards remain valid Markdown links: `[Title](<https://example.com> "card")`. Other readers display a normal link. Callouts use `> [!NOTE]`, `> [!TIP]`, `> [!WARNING]`, and other named types. Click the callout icon to choose a colour and icon/emoji. Custom styling is stored in a small HTML comment on the callout header; existing titles and fold markers remain. Other Markdown readers can ignore that comment and retain the callout content. Underline uses the editor's `++underlined++` extension; support varies between Markdown readers.

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

Browser tests use the local Google Chrome installation on macOS. `npm run build` produces the offline resources under `Sources/LinearNotes/Resources/Editor`. The build script packages `dist/Linear Notes v1.3.app` and verifies its local signature.

## MVP boundaries

- The window, navigation, menus, file access, and lifecycle are native SwiftUI/AppKit. The embedded rich editor uses bundled Tiptap/ProseMirror in WKWebView. There is no Electron runtime or hosted editor.
- Rich cards show a supplied title and URL. They do not fetch website metadata, thumbnails, or embedded media.
- Raster images render in Live Preview and Reading. Unsupported or unavailable images show a placeholder. Math, diagrams, wikilinks, footnotes, and full Obsidian extensions remain outside this version. Arbitrary HTML is preserved as inert source blocks.
- Callout fold markers are retained but callouts are always expanded. Properties use a simple YAML source editor; this is not a full typed property system.
- No cloud sync, collaboration, version history, or iOS app yet. Linear import uses a personal key rather than OAuth and retains remote image references; remote assets are not copied into the notebook for offline use. The shared `NotesCore` and platform-independent editor are separated for future iOS reuse.
- External changes are checked every two seconds. Simultaneous writes by editors that ignore file coordination still require care; test with a small notebook first. Search scans file content on demand; very large libraries/files and full accessibility coverage have not been validated.

See [validation notes](docs/VALIDATION.md) and [third-party notices](docs/THIRD_PARTY_NOTICES.md).

Product history is kept in [Linear Notes - v1.0 Ideation](<docs/Linear Notes - v1.0 Ideation.md>) and [Linear Notes MVP - Changelog](<docs/Linear Notes MVP - Changelog.md>). The ideation document preserves the original plan; the changelog records later feature-set updates.

The working visual and interaction principles are documented in [Linear Notes - Design Documentation](<docs/Linear Notes - Design Documentation.md>). The attached Linear reference files are kept under [docs/resources](<docs/resources>).
