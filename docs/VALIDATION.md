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
