# Editor chrome, callout folds, and rich-card previews

Date: 2026-09-07
Status: approved
Scope: Live Preview editor in the macOS app (`Editor/` + native host glue)

This spec covers three changes that stay inside the v1.0 product rules: local Markdown as source of truth, organisation and app cache in `.linear-notes/`, Linear Documents + Markdown Preview chrome, no account or server. Visual and behaviour language follows [Linear Notes - Design Documentation](../../Linear%20Notes%20-%20Design%20Documentation.md): the page is primary, popovers are quiet, cards are document objects, accent is for focus not fill, hairlines beat dashboard shadows. Linear OAuth/sync is out of scope.

## Goals

1. Callouts honor GitHub/Obsidian fold markers in the UI.
2. Rich cards can show a short summary and a square image preview when metadata is available, matching a compact Linear-style link card.
3. Remove the persistent formatting bar. Formatting lives on a selection popover; block insert lives on the slash menu. Space dismisses the slash menu without running a command.

## Non-goals

- iOS, cloud sync, collaboration, version history
- Fetching previews when merely opening a note
- Open Graph thumbnails loaded live from the web on every render
- Embeds, favicons, oEmbed players
- Changing the portable card Markdown syntax (`[Title](<url> "card")`)
- Typed property schemas, wikilinks, math, diagrams
- A “refresh preview” control (follow-up, not this slice)
- Replacing native app menus or existing keyboard shortcuts
- Removing the native Live / Reading / Source control (that stays in the Mac window)
- Linear workspace OAuth, document port, or two-way sync
- Copying Linear marketing tokens (near-black `#010102` canvas, dark-only)

## Invariants

- Notes remain UTF-8 Markdown. Pins, bookmarks, and link-preview cache never go into note bodies.
- Live, Reading, and Source stay distinct. Source does not grow extra chrome.
- HTTPS links only for cards and fetches. `javascript:` and other non-http(s) URLs still cannot become cards.
- Two-click cards stay: first click selects, second click opens. Enter opens a selected card; Delete removes it in Live mode.
- If a fetch fails, the card falls back to the current compact layout (icon, title, host). No broken image hole.
- Native mode switching remains in the Mac window. The in-document format strip is what goes away.

---

## 1. Callout folds

### Behaviour

The parser already stores `fold` from `> [!NOTE]+` / `> [!NOTE]-`. The heading becomes a control that toggles collapse.

- Collapsed: body hidden; kind, title, and icon remain. Chevron indicates collapsed.
- Expanded: current layout plus a chevron on the heading.
- Click heading (or Enter/Space when the heading is focused) toggles. Content editing is unchanged while expanded.
- Works in Live and Reading. Source shows the markers as text; no extra UI.
- New callouts from slash commands stay unmarked and expanded (`fold` empty).
- After the user collapses, serialize `-`. After they expand a callout that has been toggled, serialize `+`. Unmarked callouts that were never toggled stay unmarked if they remain expanded.

### Markdown

```markdown
> [!TIP]
> Always expanded until the user folds it.

> [!WARNING]-
> Collapsed.

> [!NOTE]+
> Explicitly expanded after a toggle.
```

### UI

Keep existing callout colors, radius, and icons. Add a small chevron on the heading row. Heading stays `contenteditable="false"`. Do not animate if `prefers-reduced-motion`.

### Tests

- Round-trip `-` and `+` through Live Preview.
- Click heading collapses; markdown gains `-`.
- Slash-inserted callout has no fold marker until toggled.
- Reading mode can fold without allowing body edits.

---

## 2. Rich-card previews

### Markdown (unchanged)

```markdown
[mymind is the extension for your mind.](<https://mymind.com> "card")
```

Title may be updated from `og:title` only when the user did not supply display text (empty title, or title equal to the URL/hostname).

### Cache

Store preview data under the notes folder, not in the file:

- `.linear-notes/link-previews.json` — keyed by normalized HTTPS URL. Fields: `title`, `description`, `imageURL`, `imageFile` (relative path inside `.linear-notes/`), `fetchedAt`.
- `.linear-notes/previews/<hash>` — downloaded image bytes when fetch succeeds.

Missing cache ⇒ compact card. Corrupt or absent image file ⇒ compact card (or text-only preview card without the image column). Deleting `.linear-notes/` resets previews without deleting notes.

### Privacy

The link dialog states, near the Rich card action:

> Linear Notes looks up a title, summary, and image for this page on your Mac. Nothing is sent to a Linear Notes server.

Lookup happens only at insert, only for that HTTPS URL, using the Mac’s network. Cached bytes stay in `.linear-notes/`. There is no Linear Notes backend.

### Card states

| State | Appearance | Behaviour |
| --- | --- | --- |
| Default | Compact, or preview layout if cache has description and/or image | First click selects |
| Selected | Hairline accent ring (no lavender fill, no drop shadow) | Second click or Enter opens |
| Unavailable | Compact card; never an empty image box | Same as default |
| Deleted | Node removed from the document | Delete in Live mode |

### When to fetch

Native Swift (`URLSession`) fetches once when the user inserts a rich card: paste-URL chooser → Rich card, or link dialog → Rich card. No fetch on document load (cached previews still apply). No fetch from the WKWebView page (`connect-src` stays `'none'`).

Timeout: 5 seconds for HTML, 5 seconds for the image. Parse `og:title`, `og:description` or `twitter:description`, `og:image` or `twitter:image`. Resolve relative image URLs against the page URL. Download the image only if the response is an image and at most 2 MB. Never follow a redirect to a different origin for HTML; an image CDN on another host is allowed when `og:image` is https.

After success, native writes the cache and pushes `{ url, title, description, imageSrc }` into the editor for that card node. `imageSrc` is a `data:` URL built from the cached image bytes. The web view’s file access remains the bundled editor folder; it must not load remote `https` images. On document load, native includes cached previews in the `load` payload so cards hydrate without a network round-trip.

Access preview files via the notebook `.linear-notes` directory the same way as `sidebar.json`. Do not use `NoteLibrary.url(for:)`, which rejects dotted path components.

### Layout

**With preview:** full-width rounded row, hairline `--line` border, `--bg` / card surface fill (not accent). Left: title (one line, ellipsis), description (two lines, ellipsis), URL (muted, `https://hostname` with `www.` stripped). Right: square (card-height) image, `object-fit: cover`, flush to top/right/bottom, sharing the card radius. Padding on the text side only. Light and dark use existing tokens. No drop shadow.

**Without preview:** keep the current compact card (leading icon, title, host+path, trailing arrow).

Selected: accent ring only (replace the current `box-shadow` glow). The image is not a separate hit target. Description without an image still uses the preview text layout, without a blank image column.

### Tests

- Inserting a card with a fixture HTML page stores description + image and shows the preview layout.
- Failed fetch keeps compact card and `[Title](<url> "card")`.
- Reopening the note shows the cached preview without network.
- Two-click and Enter/Delete unchanged.
- Dangerous URLs still never become cards.

---

## 3. Editor chrome: no persistent bar

### Remove

Delete the sticky `#formatbar`. Live mode chrome is document + property pills only. Reclaim the 43px top offset so the page sits higher.

Keep all current formatting shortcuts and native menu commands. Native Live / Reading / Source switching is unchanged.

### Popover grammar

`#bubble` and `#slash` use a popover surface, hairline `--line` border, radius 8–12, and short appear-from-caret motion. No drop shadow. Keyboard navigation stays. `prefers-reduced-motion` disables slide. Accent is for the selected row / active mark, not the panel fill.

### Selection popover

On a non-empty text selection in Live mode, show `#bubble` above the range.

Include the old bar’s controls, compact:

- Turn into: a compact menu of Text and Heading 1–4 only (not the full slash list)
- Bold, italic, strikethrough, inline code, link
- Bulleted list, checklist, quote

Hide when: caret only, selected atom (rich card), slash menu open, Reading/Source, click away, Escape, or scroll (same as today).

Active marks/nodes should reflect on the buttons (`active` class), including Turn into.

### Slash menu

Unchanged trigger: `/` at the start of an otherwise empty paragraph in Live mode. Scrollable floating list, existing commands, ↑↓, Enter/click executes and deletes `/query`, Escape closes and leaves the query.

**Space closes the menu without executing.** The space is inserted as normal text. `/` plus space is not a filter. Remove spaces from the slash filter pattern so `/heading` still filters and `/heading ` dismisses.

Click outside closes without executing.

### Tests

- No `#formatbar` in the DOM (or it is gone from the layout).
- Selecting a word shows the popover; all moved commands still work.
- `/call` filters; Enter inserts a callout.
- `/` then Space leaves `/ ` in the paragraph and hides the menu.
- Escape leaves `/call` visible and hides the menu.
- Link dialog includes the privacy sentence near Rich card.
- `load` with a `previews` map shows description/image without sending `fetchCardPreview`.

---

## Architecture

```
Native (Swift)                         Editor (WKWebView)
─────────────────                      ──────────────────
load({ markdown, previews })
  previews from .linear-notes/         → hydrate card node views

insert rich card
  ← fetchCardPreview { url }
  HTTPS GET page + image
  write link-previews.json + previews/<hash>
  → notes.applyCardPreview({ url, title, description, imageSrc })
                                       imageSrc is a data: URL

Callout fold / slash / bubble stay in Editor/. Fold is already in Markdown.
```

`NotesCore` may own preview cache read/write next to `sidebar.json` so the files stay a library concern. The web editor does not perform network I/O.

Content Security Policy: keep `connect-src 'none'`. Keep `img-src data: file:`; card images are `data:` URLs supplied by native code, never remote URLs.

## Error handling

- Network failure, non-HTML, missing OG tags: compact card; optional silent skip (no toast required).
- Image too large or not an image: keep text preview if description exists; otherwise compact.
- Cache write failure: still show in-memory preview for the session; next open is compact until a later insert succeeds.

## Implementation order

1. Remove format bar; expand selection bubble; Space dismisses slash.
2. Callout fold UI + markdown serialization.
3. Native preview fetch + cache + card node view layout.

Editor Playwright tests first for (1) and (2). Native tests for cache path and URL safety. Manual: paste a public https URL as a rich card once network is involved.

## Limits

- Previews can go stale until a later refresh feature exists.
- Sites that block non-browser user agents may yield compact cards.
- Very large notebooks with many unique card URLs grow `.linear-notes/previews/`; no eviction in this slice.
- Turn into in the bubble uses the same command set as the old Text control; it does not become a full Linear slash menu.
