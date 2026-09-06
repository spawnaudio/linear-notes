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
