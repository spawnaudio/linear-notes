# Linear Notes - v1.0 Ideation

This document preserves the original product outline for Linear Notes. It is the reference point for the first version, before implementation details and later feature additions were introduced.

## Product idea

Create a minimal, beautiful notes and documentation app for macOS where notes are written as Markdown files and stored locally. The experience should feel close to Linear Documents while taking visual and reading inspiration from Markdown Preview.

Primary references:

- [Linear Documents](https://linear.app/docs/documents)
- [Markdown Preview](https://markdownpreview.app)
- [Markdown Preview source](https://github.com/pluk-inc/markdown-preview)

## Core principles

- Local-first Markdown files.
- A calm, minimal interface with strong typography and generous reading space.
- Live rendering while writing instead of a separate preview window.
- Native macOS behaviour, with an architecture that can support a future iOS version.
- Manual organisation that stays understandable and user-controlled.
- Portable files that remain useful outside the app.

## Initial feature outline

### Editing and Markdown

- Markdown syntax.
- Shortcuts modelled on Linear Documents.
- Slash commands.
- Heading sizes 1 through 4.
- Live Preview editing with rendered Markdown visible while writing.
- Reading mode for rendered, non-editable Markdown.
- Source mode for plain-text Markdown editing.

### Links

Pasted links should support either a normal Markdown link or a rich link card, following the interaction style of Linear.

Rich link card behaviour:

1. The first click highlights or selects the card.
2. The first click does not open the URL or expose a code block.
3. A second click opens the link.

### Blocks and formatting

- Markdown callouts similar to GitHub or Obsidian.
- A separate quote block with italic text.
- Quote blocks should share the useful interaction model of callouts while using different styling.
- YAML frontmatter or document properties.
- Document properties should be shown as small pill-like controls where possible.

### Sidebar and organisation

- Sidebar for file and folder navigation.
- Manual folder and file organisation with drag and drop.
- Pinned folders and files that remain at the top of their parent folder.
- Drag-and-drop ordering for pinned items.
- Bookmarks in a separate sidebar section.
- Collapsible sidebar with a smooth animation.

## Initial product boundary

The first version should begin with a focused macOS MVP rather than attempting every future integration at once. The core loop is:

1. Choose a local notes folder.
2. Open or create a Markdown note.
3. Write in Live Preview, Reading, or Source mode.
4. Organise notes with folders, pins, bookmarks, and drag and drop.
5. Save ordinary Markdown files locally.

Future ideas such as iOS support, richer embeds, cloud sync, collaboration, version history, and broader Markdown extensions can build on this foundation.

## Design direction

The visual direction combines Linear’s restrained document editor with Markdown Preview’s native reading experience:

- Quiet sidebar with clear hierarchy.
- Subtle borders and compact controls.
- Comfortable document width and generous vertical rhythm.
- Focused formatting toolbar.
- Light and dark appearance support.
- Clear separation between editing, reading, and source views.

## Decision record

The implementation should keep Markdown as the source of truth. App-specific organisation data, such as pins and bookmarks, should be stored separately so it does not pollute note contents or reduce portability.
