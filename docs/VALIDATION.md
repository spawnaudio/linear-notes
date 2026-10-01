# MVP validation

Tested on the development Mac with Xcode-beta and the installed Google Chrome. Results apply to this local build, not to an App Store or notarized release.

## Automated checks

- **8 storage tests:** Unicode and exact file contents; rejection of external-edit overwrite; folder renames preserving descendant pins/bookmarks/selection; manual pin ordering; cross-folder moves; cycle rejection; duplicate/path traversal rejection; symbolic-link filtering; metadata independence.
- **14 browser interaction tests:** Markdown rendering and unchanged mode switches; edited Markdown round-trips; two-click cards; read-only behaviour; slash commands and leaving callouts; source editing; property editing; normal links and cards; Markdown typing and isolated undo histories; inert HTML preservation; light/dark and narrow layouts; empty/CRLF frontmatter; pasted URL choice; checkbox persistence and unsafe-card rejection.
- Release build and local code-signature verification performed by `scripts/build.sh`.

## Native walkthrough

- Opened the packaged app with the included local notebook.
- Created `MVP validation.md` through the native New Note dialog.
- Edited Markdown source, switched to Live Preview, and confirmed callout rendering.
- Typed an additional sentence in the live editor, saved, and confirmed the exact file on disk.
- Switched to another note and back; the saved content remained intact.
- Toggled bookmarking and collapsed the sidebar.
- Removed the temporary note through the app's Trash action; its bookmark disappeared with it.
- Quit cleanly and reopened the final packaged build with the sample notebook.

The computer-use clipboard helper timed out once without changing the file. Entering text through the accessible source field and typing in the live editor both worked. This is recorded as an automation limitation; clipboard paste is independently covered in the browser tests.

## Not established by these checks

Full accessibility coverage, native drag-and-drop across every layout, performance on large folders, network-drive coordination, simultaneous edits in another app, signing with a Developer ID, notarization, installation on another Mac, and an iOS host have not been validated. The app currently targets the architecture of the Mac on which it is built.


## Desktop design redesign — 1 October 2026

- All 8 storage tests passed; the redesign leaves the storage implementation unchanged.
- All 15 editor tests passed, including a new check for metadata and semantic callout contrast in light/dark appearance, legible read-only properties, and removal of formatting chrome in Reading/Source without rewriting Markdown.
- The release app built and passed local signature verification. The bundled stylesheet was compared with the editor source.
- Inspected the native dark shell, Live Preview, Source, and Reading, including Reading at 820 × 620. A temporary copy of the example notebook was used. Native source editing/save was not established by this walkthrough; editing and persistence are covered separately by editor and storage tests.
- Native light appearance was not established by the attempted per-process override; light editor rendering and contrast were verified in browser tests. Full accessibility and native drag-and-drop coverage remain unverified.

The app is built at `dist/Linear Notes.app`. The native dark preview is `artifacts/redesign-native-dark.png`.


### Window shell correction — 1 October 2026

Compared the native preview with the supplied Linear screenshot. The context strip now belongs to the dark shell. The document header/editor/error region is a separately clipped 12pt rounded panel with a full hairline border and an 8pt right inset; the status strip sits below it in the shell. Removed the sidebar's continuous vertical divider and the status-bar divider. Window background follows the shell palette and the native titlebar separator is hidden. Release build and local signature verification passed; inspected all four panel corners in the native capture. No storage or editor behaviour changed.


### Right sidebar and floating formatting — 1 October 2026

- 17 browser tests passed, including selection-preserving floating bold/underline, narrow-window toolbar bounds, grouped slash shortcuts and dismissal, native-host property previews, nested property content, and property edits from Source mode.
- 8 storage tests passed. Release packaging and local signature verification passed.
- In a uniquely named temporary native preview, opened, closed, and reopened the details sidebar; inspected the labelled property rows, modes, word count, save state, file path, bookmark/pin/Finder actions; confirmed property editing is disabled in Reading and enabled in Source; opened the property editor from Source. Used a temporary notebook, leaving the existing app instance alone.
- Inspected screenshots of the native sidebar, floating formatting, and slash menu. The fixed formatting toolbar is absent from source and bundled editor HTML. Full accessibility and all native drag interactions remain unverified.


### Linear Notes v1.2 installation — 1 October 2026

- Final release rebuilt as `dist/Linear Notes v1.2.app` with bundle version 1.2.0 (build 2).
- Installed at `/Applications/Linear Notes v1.2.app`; local signature verification passed.
- Installed executable hash matches the release executable. Installed editor JavaScript, CSS, and HTML match the bundled sources; the fixed formatting toolbar is absent.
- Launched the installed app and verified its running executable comes from that exact Applications path.

## Five feature additions — 1.3.0 · 1 October 2026

- All **14 native tests** pass (11 storage, 3 read-only Linear API). Added checks cover body/draft search and title ranking, Unicode matching, local image validation and secure paths, attachment links after note moves, preserving fenced/inline code examples, stable source IDs after renamed/edited imports, filename collisions, API pagination/errors, inaccessible documents, and image-host restrictions.
- All **21 editor tests** pass. New coverage includes actual raster rendering; alt text, replacement, removal and mode preservation; image paste/drop through the native message contract; discarding stale replies; images within prose without losing surrounding text; coloured/emoji callouts, legacy titles/fold markers and undo; malformed metadata preservation; heading outline/navigation; and retaining the link shortcut alongside quick switching.
- `scripts/build.sh` produced **dist/Linear Notes v1.3.app** and verified its local signature. The release used the default Xcode build system; native tests used the native SwiftPM build system with compiler plugins enabled.
- A separate QA bundle and temporary notebook verified native content search for a phrase absent from filenames, highlighted matching excerpts, no results for an absent phrase, `⌘P` arrow/Enter note switching, local image rendering through the secure asset handler, image insertion from the native picker with a new relative attachment saved on disk, heading outline/navigation, and mode switching. The selected note and saved attachment references persisted after quitting and reopening the QA app. The QA app was closed and its temporary notebook removed.
- The native Linear connection sheet opens and requires a key before Connect is enabled. No real workspace credential was supplied, so live project browsing/import, Keychain save/removal after successful connection, authenticated Linear image rendering, and workspace permissions remain unverified. API request/response behaviour used stub responses; this is not live integration proof.
- Images imported as remote URLs still need connectivity; no offline asset copying or two-way sync was implemented. Very large notebooks, all native drag/clipboard formats, full accessibility, and distribution signing/notarization remain unverified.

### Installed replacement — 1 October 2026

- Rebuilt v1.3 with `scripts/build.sh` and verified the packaged and installed signatures.
- Replaced `/Applications/Linear Notes v1.2.app` with `/Applications/Linear Notes v1.3.app`; the installed bundle reports 1.3.0 and its executable SHA-256 matches the packaged build.
- Launched the installed executable and verified a registered on-screen native window. macOS was locked during installation, so accessibility inspection and a fresh screenshot of the installed window were unavailable. The earlier 35 passing checks and isolated native walkthrough apply to the same feature implementation; live Linear integration still requires a workspace key.

## Capture, retrieval, and recovery — 1.3.1 · 1 October 2026

- All **19 native tests** and **26 editor tests** pass. The new checks cover unique instant capture, save failures and conflict copies, recovery/session metadata and symlink rejection, relative note links across source/target/folder moves, rollback after a failed link rewrite, Unicode passage matching across formatting, per-mode cursor/scroll restoration, note-link keyboard activation, document scaling, slash/image controls, and print layout/state preservation. Native checks were rerun after the print-sheet correction.
- The release bundle reports **1.3.1** (build 4), retaining **Linear Notes v1.3.app**. Release packaging and local signature verification pass. The editor source and packaged resources match.
- A separate QA bundle and temporary notebook verified native instant capture/typing with saved Markdown, passage search and Return activation in the quick switcher, labelled find controls and a 1/1 count, and selection/scroll at the matching passage. Source mode, selection, and scroll survived quitting and reopening.
- Seeded unsaved recovery metadata was reopened in the native app: the recovered text appeared in a separate “Recovered” note and the original file stayed byte-for-byte unchanged. This verifies recovery from a stored draft, not every possible crash timing before the native host receives an edit.
- The initial synchronous print operation produced three blank pages. Deferring the operation until the WebKit callback completes and using a native asynchronous print sheet fixed it. The final native PDF contains **3 pages and 1,298 text characters**, including the final matching passage, without editor controls. Returning from export restored Live Preview and the previous scroll position. The browser print test independently verifies light print colours, hidden controls, PDF output, and Source-mode restoration.
- The existing Linear palette, shell dimensions, spacing, and default document font sizes are retained; new controls reuse existing popover styling and appear when invoked. Accessible names/roles and keyboard interactions were inspected or tested, but a full VoiceOver usability audit remains unverified.
- Very large notebooks, every Markdown link edge case, multi-device editing, distribution signing/notarization, and live signed-in Linear import remain unverified. Recovery is local draft protection, not history, sync, or a backup.

### Installed replacement — 1.3.1

- Replaced `/Applications/Linear Notes v1.3.app` in place. The installed bundle reports **1.3.1** (build 4) and passes local signature verification.
- Installed executable SHA-256 is `378b353920e65948d967c25079d4f92bd9c32054178ac68809d92fbf7b58aa62`; it matches the packaged executable. Installed editor JS/CSS/HTML also match the release bundle.
- Launched the replacement from that exact Applications path and verified its running executable and accessible native window. Personal notebook contents were not used for QA edits.

## Tabs and split panes — 1.3.2 · 1 October 2026

- **24 native tests** and **26 editor tests** pass. The five new workspace checks cover repeated splits in all four directions, tab order and movement between groups, split creation from moved tabs, collapse on closing, persisted split ratios/active tabs/per-tab mode and position, shared drafts, inactive-tab conflicts, all-editor save blocking, note renames, external updates, and missing-file restoration.
- A native SwiftUI window with actual WKWebView editors verified nested right/down splits, editor-pointer activation, a Source edit appearing in a separate Reading pane, opening another note in the active group, saving all views, closing a group, and Keep both after an external edit. The external file remained unchanged and the draft opened separately. The native light appearance was captured and inspected using a temporary notebook; the window and notebook were removed after the check.
- Release packaging and local signature verification pass. The updated bundle is **dist/Linear Notes v1.3.app**, version **1.3.2** (build 5). This change does not replace the installed Applications bundle.
- Native drag gestures/drop highlighting, all divider gestures, full keyboard/VoiceOver usability, dark native pane appearance, and performance with many panes or very large notes still need manual coverage. Reorder/move/split operations are covered at the workspace-state layer. Each visible pane has a separate editor; sibling views reload when the shared draft changes.
- Separate windows and stacked tabs are outside this feature. Existing live Linear integration limitations remain unchanged.

### Installed replacement — 1.3.2 · 2 October 2026

- Rebuilt the editor and release app, then replaced `/Applications/Linear Notes v1.3.app` in place. The installed bundle reports **1.3.2** (build 5) and passes local signature verification.
- Installed executable SHA-256 is `61677559ed0ae7b617949f2a0ddd96f894b5ee80ae9927d49b467c5ce5ec5c02`; it matches the packaged executable. Installed editor JavaScript, CSS, and HTML match the release bundle.
- Launched the replacement and verified its running executable comes from that exact Applications path. A copy of the previous 1.3.1 app was retained temporarily for rollback.
- The 24 native and 26 editor checks above were completed during feature implementation on 1 October; they were not rerun for this installation. Native drag-gesture coverage remains unverified.

### Drag tab arrangement — 2 October 2026

- Version **1.3.3** (build 6): **25 native tests passed** with Xcode-beta and native SwiftPM, including regression checks for every lone-tab split edge, edge hit regions, tab order, restored layouts, shared drafts, conflict protection, and real WKWebView editors.
- Used an isolated, locally signed app copy and temporary A/B/C notes for actual mouse gestures. Verified insertion before a tab, after a tab, after the last tab, transfer to another tab bar, center transfer over the editor, and nested left/right/up/down edge splits. A lone-tab edge drop kept an empty source pane; moving the last tab to another group collapsed the source pane.
- Quit and reopened that temporary app: the pane tree, active pane, and tab orders survived. All three Markdown files retained their exact original contents.
- Native tab buttons prevent SwiftUI button tracking from swallowing the drag. The tab strip respects the window titlebar; the declared custom drag type reaches tab destinations, and the native editor routes tab drops to the pane layout. Other editor drops keep WebKit's existing handling.
- Release packaging and local signature verification passed. Replaced **/Applications/Linear Notes v1.3.app** in place with **1.3.3** (build 6). All installed bundle files match the packaged build; executable SHA-256: `19f156103b2582dacab4d3647566297c0609ed18a93a41bd20638d1aa00b15cb`. The installed executable launched (PID 84412) and its native window was confirmed through accessibility.
- The previous installed bundle is retained in a temporary rollback folder. The 26 browser/editor tests recorded for 1.3.2 were not rerun for this native drag fix; editor JavaScript did not change in this update. Native drag coverage is limited to the layouts and gestures above.
