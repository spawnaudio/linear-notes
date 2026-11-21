# Overhaul v2 — Linear Fidelity Spec

**Status:** Merged into main as Linear Notes v2 · 7 November 2026 ([#8](https://github.com/spawnaudio/linear-notes/pull/8))
**Branch:** `experiments/claude/app-overhaul-v2` (merged)
**Purpose:** Define exactly how Linear Notes changes so its shell, tabs, and writing experience read as Linear Documents running as a standalone Mac app.

---

## Contents

1. [Intent and boundaries](#1-intent-and-boundaries)
2. [Evidence](#2-evidence)
3. [Window anatomy](#3-window-anatomy)
4. [Foundation tokens](#4-foundation-tokens)
5. [Sidebar](#5-sidebar)
6. [Title bar and tabs](#6-title-bar-and-tabs)
7. [Page header](#7-page-header)
8. [Document page](#8-document-page)
9. [Editor blocks and menus](#9-editor-blocks-and-menus)
10. [Details rail](#10-details-rail)
11. [Command menu and shortcuts](#11-command-menu-and-shortcuts)
12. [Icons](#12-icons)
13. [What stays the same](#13-what-stays-the-same)
14. [Out of scope](#14-out-of-scope)
15. [Default decisions](#15-default-decisions)
16. [Build sequence](#16-build-sequence)
17. [Fidelity checklist](#17-fidelity-checklist)

---

## 1. Intent and boundaries

### What changes

The v1.3 design deliberately stopped short of reproducing Linear. This experiment reverses that for **layout, density, typography, colour, and behaviour**. When this spec and `Linear Notes - Design Documentation.md` disagree, this spec wins on this branch only.

### What does not change

- **No Linear brand assets.** No Linear logo, wordmark, product artwork, or Linear's own icon set. All iconography uses **SF Symbols** (see [Icons](#12-icons)).
- **Local-first behaviour stays.** Plain Markdown files, autosave, conflict handling, recovery, Linear import and refresh, and split panes keep their current implementation.
- **The shipped app stays untouched.** The experiment packages as a separate app beside `Linear Notes v2.app`.

---

## 2. Evidence

### Sources

| Source | What it shows |
| --- | --- |
| Linear docs, *Project documents* screenshot | Document page: header, breadcrumbs, icon tile, title, headings, body, outline markers |
| Linear docs, *Editor* screenshot | Floating formatting toolbar and selection colour (light) |
| Linear docs, *Favorites* screenshot | Current dark sidebar, title bar navigation, page header, project title block |
| Linear docs, header *Copy link* screenshot | Heading hover handle and its menu |
| Linear changelog, *Team documents* screenshot | Pill-style view switcher (Overview · Documents · Members) |
| Linear blog, *How we redesigned the Linear UI*, "After" screenshot | Light theme shell, sidebar sections, header actions, right properties rail |
| `docs/resources/Linear App Design Breakdown.md` | Spacing rhythm, radii, component recipes |
| Linear docs, *Editor* and *Project documents* pages | Markdown shortcuts, slash menu contents, heading links |

Screenshots were viewed for measurement only and are **not committed** to the repository.

### Confidence

- Colours below were **sampled from the screenshots**. Marketing images can be colour-managed or brightened, so treat them as starting values and correct them against the live Linear app during review.
- Sizes are estimated from proportions and rounded to the 4pt rhythm.

---

## 3. Window anatomy

Linear uses an **inverted L**: one dark shell holds the title bar row and the sidebar, and the content sits in a single inset rounded panel.

```text
┌──────────────────────────────────────────────────────────────────────┐
│ ● ● ●            ←  →  🕘 │ [▣ Tab one ×] [▣ Tab two] [+]          │  title bar row · 40pt · shell
├──────────────────────────┬───────────────────────────────────────────┤
│ [SP] Notebook ⌄   🔍  ✎  │ ╭───────────────────────────────────────╮ │
│                          │ │ ▢ Folder › Note title  ⋯ ☆   Edited… 🔗│ │  page header · 44pt
│ ▢ Recent                 │ ├───────────────────────────────────────┤ │
│ ▢ Drafts             3   │ │                                       │ │
│                          │ │        ▣                              │ │
│ Favorites ▾              │ │        Note title                     │ │
│ ▢ Weekly plan            │ │        Properties  ·chip· ·chip·      │ │
│                          │ │                                       │ │
│ Notes ▾                  │═│        Body text…                     │ │  ═ outline markers
│ ▸ ▢ Projects             │ │                                       │ │
│   ▢ Notes app            │ │                                       │ │
│                          │ ╰───────────────────────────────────────╯ │
│ (?)                      │                                           │
└──────────────────────────┴───────────────────────────────────────────┘
```

### Measurements

| Element | Value |
| --- | --- |
| Sidebar width | 244pt default, resizable 220–320pt |
| Title bar row | 40pt, shell background |
| Content panel inset | 8pt right and bottom; 0pt to the sidebar; 8pt left when the sidebar is hidden |
| Content panel radius | 12pt, 1pt hairline border |
| Page header | 44pt, hairline divider below |
| Status strip | **Removed** (see [Default decisions](#15-default-decisions)) |

Split panes keep working. Each pane is its own rounded panel separated by an 8pt shell gutter, which already matches how Linear separates its list and detail panels.

---

## 4. Foundation tokens

### Colour

Sampled values with recommended tokens. Dark is the reference appearance; light is fully supported.

| Token | Dark | Light | Use |
| --- | --- | --- | --- |
| `shell` | `#090909` | `#ECECEC` | Title bar row, sidebar |
| `canvas` | `#0F1011` | `#FCFCFD` | Content panel, document page |
| `raised` | `#141417` | `#F4F4F5` | Search button, inline code, code blocks |
| `control` | `#1F2025` | `#EAEAEC` | Compose button, active tab, pressed state |
| `selected` | `#1E1F23` | `#DEDEDE` | Selected sidebar row |
| `hover` | `#18191C` | `#E6E6E7` | Hover rows and buttons |
| `border` | `#232429` | `#E3E3E5` | Panel outline, toolbar outline |
| `divider` | `#1E2025` | `#EDEDEF` | Header divider, row dividers |
| `text-primary` | `#F7F8F8` | `#161616` | Titles, headings, active labels |
| `text-body` | `#E6E7E9` | `#1C1C1E` | Document body |
| `text-secondary` | `#E3E4E5` | `#3C3C3F` | Sidebar labels, tab labels |
| `text-muted` | `#959597` | `#66666A` | Section labels, icons, property labels |
| `text-faint` | `#5A5A5C` | `#ADADAD` | Placeholders, "Edited" timestamps |
| `accent` | `#5E6AD2` | `#5E6AD2` | Links, focus, checked boxes, icon tiles |
| `accent-tint` | `#1C1E30` | `#E8EAFB` | Document icon tile background |
| `selection` | `#2F3463` | `#C2C6ED` | Text selection highlight |
| `star` | `#F2C94C` | `#F2C94C` | Favourite star when on |

Rules carried over from the reference:

- **No pure white body text** in dark mode. Only titles and headings reach `text-primary`.
- **Colour is for state.** The accent appears on links, focus rings, checked boxes, and the document icon tile, and nowhere else by default.
- Every token is defined once for Swift (`Palette`) and once for CSS (`editor.css`), and both must change together.

### Typography

| Style | Size / line height | Weight | Notes |
| --- | --- | --- | --- |
| Document title | 28 / 34pt | 600 | Inter Display, tracking −0.02em |
| Heading 1 | 24 / 30pt | 600 | Inter Display |
| Heading 2 | 20 / 26pt | 600 | |
| Heading 3 | 17 / 24pt | 600 | |
| Heading 4 | 15 / 22pt | 600 | |
| Body | 15 / 24pt | 400 | `text-body` |
| UI label | 13 / 18pt | 500 | Sidebar rows, tabs, breadcrumbs |
| Section label | 12 / 16pt | 500 | `text-muted` |
| Metadata | 12 / 16pt | 400 | Counts, timestamps |
| Code | 13 / 20pt | 400 | SF Mono |

- **Typeface:** bundle **Inter Variable** and **Inter Display** (SIL Open Font License) for both SwiftUI and the editor, with SF Pro as the fallback. Add the licence to `THIRD_PARTY_NOTICES.md`.
- The existing text-size commands (`⌘+`, `⌘−`, `⌘0`) scale the body and keep these ratios.

### Spacing, radius, motion

| Token | Value |
| --- | --- |
| Rhythm | 4pt base: 2, 4, 6, 8, 12, 16, 20, 24, 32, 40 |
| Radius | 4 (chips, inline code) · 6 (rows, tabs, buttons) · 8 (menus, toolbar, code blocks) · 12 (panels) |
| Icon size | 16pt in rows and headers, 14pt in tabs and toolbar |
| Control target | 28pt square buttons, 30pt rows |
| Motion | 120ms ease-out for hover and disclosure; none under Reduce Motion |
| Elevation | Menus and toolbar only: 1pt border plus a soft 0 4 16 black at 24% (dark) or 8% (light) |

---

## 5. Sidebar

### Structure, top to bottom

1. **Workspace switcher row.** A 20pt rounded-square tile with the notebook's initials on a stable colour, then the notebook name and a small chevron. The menu holds *Open another folder…*, *Import from Linear…*, and *Show in Finder*.
2. **Search and compose buttons**, right-aligned on the same row. Search is a 28pt button on `raised`; compose is a 28pt button on `control`. Search opens the command menu, and compose creates a note with `⌘N`.
3. **Primary row:** *Recent*, which shows recently opened notes as a Linear-style list in the current tab.
4. **Favorites** section: the existing bookmarks, renamed. The header star toggles membership, and drag-and-drop reordering stays.
5. **Notes** section: the folder tree.
6. **Help button**, a 24pt circle with `?` pinned bottom-left, opening keyboard shortcuts and help.

### Row recipe

| Property | Value |
| --- | --- |
| Height | 30pt |
| Insets | 8pt outer, 8pt inner leading |
| Icon | 16pt, `text-muted`; `text-primary` when selected |
| Gap | 8pt icon to label |
| Label | 13pt / 500, `text-secondary`, single line with tail truncation |
| Count badge | 12pt text in a 20pt-high rounded rectangle on `raised` |
| Selected | `selected` fill, 6pt radius, brighter label, **no accent bar** |
| Nesting | +16pt per level; the disclosure chevron sits in the parent's icon column |

### Section headers

Section headers are 12pt / 500 `text-muted` labels with a tiny disclosure triangle **after** the label, as in "Favorites ▾", plus 20pt of space above. On hover, a `+` appears at the right edge: a new note for *Notes*, or a folder for *Favorites*.

### What goes away

- The inline *Find a note…* field. Search moves into the command menu ([§11](#11-command-menu-and-shortcuts)).
- The footer "On your Mac" label and its `+` menu, which compose and the section `+` replace.

---

## 6. Title bar and tabs

### Title bar row

- The traffic lights sit at the top-left of the shell.
- **Back, forward, and history** buttons are right-aligned to the sidebar's edge, as in Linear. Back and forward step through each tab's navigation history (`⌘[` and `⌘]`). History opens a menu of recently viewed notes.
- The **tab strip** starts at the content panel's left edge, in the same 40pt row.

### Tab recipe

| State | Treatment |
| --- | --- |
| Inactive | No fill; 14pt document icon and 13pt label in `text-muted` |
| Hover | `hover` fill; label in `text-secondary`; close `×` appears |
| Active | `control` fill, 1pt `border` outline, label in `text-primary`, close `×` always visible |
| Size | 28pt high, 6pt radius, 8pt horizontal padding, label 160pt max with tail truncation |
| Crowded | Inactive tabs shrink toward icon-only before the strip scrolls |
| New tab | Plain `+` button after the last tab |

Tab drag, reorder, and drop-to-split behaviour is unchanged. With split panes, the leftmost pane's strip shares the title bar row, and the other panes keep a matching 40pt strip above their panels.

---

## 7. Page header

The page header is 44pt high, sits inside the content panel, and has a hairline `divider` below.

### Left side

- When the sidebar is hidden, a sidebar toggle.
- **Breadcrumbs:** a 16pt folder icon with the folder name, `›` separators, and finally the note's document icon with its title in `text-primary`. Earlier crumbs are `text-secondary` and clickable. Long paths collapse their middle crumbs into `…`.
- A `⋯` menu with *Rename*, *Move to…*, *Copy link*, *Copy as Markdown*, *Mode* (Live, Reading, Source), *Print / Save as PDF*, *Refresh from Linear…*, *Show in Finder*, and *Move to Trash*.
- A `☆` button that adds the note to Favorites. When on, it shows a filled `star` colour.

### Right side

- An `Edited 3m ago` timestamp in `text-faint`. It changes to `Saving…` and `Unsaved changes` as needed, and the save error banner stays.
- A link button that copies the note's file link. Links between notes still come from `@` and the link dialog, which keep them relative.
- A 1pt vertical divider.
- A details rail toggle (`⌘⌥\`).

The Live, Reading, and Source segmented buttons are **removed** from the header. Modes remain available from the `⋯` menu, the View menu, and `⌃⌘1`–`3`.

---

## 8. Document page

### Column

- The column is centred with an **720pt** maximum text width and 48pt minimum side gutters.
- The top margin is 56pt above the icon tile, and the bottom has 40vh of scroll space so the last line can sit mid-screen.

### Title block

1. **Icon tile:** 32pt square, 6pt radius, `accent-tint` background, 18pt `doc.text.fill` glyph in `accent`. An `icon:` property in the note's YAML can set an emoji or SF Symbol name instead.
2. **Title:** the note's file name, at the document-title size, editable in place. Pressing Return or moving focus away renames the file through the existing rename path, which also updates links. An empty title shows an "Untitled" placeholder in `text-faint`.
3. **Properties row**, shown only when the note has YAML properties. A muted "Properties" label is followed by compact chips (24pt high, 4pt radius, `raised` fill) with a `+` to add one. The existing properties dialog stays the editor for complex YAML.
4. 24pt gap, then the body.

### Outline markers

- A vertical stack of short horizontal dashes sits on the panel's left edge, one per heading, as in Linear's document outline.
- Dashes are 12pt wide for H1 and narrower for deeper levels, 6pt apart, in `text-faint`. The current section is `text-secondary`.
- On hover, the rail expands into a floating outline listing the headings, and clicking one scrolls to it.
- When there are more than 24 headings, only top-level headings are shown, matching Linear's cap.
- This replaces the outline list in the details rail.

### Heading hover handle

- Hovering a heading shows a `⋯` handle (vertical ellipsis) in the left gutter.
- Its menu offers *Copy link*, which copies a Markdown link to `note.md#heading-slug`, and *Make collapsible*.

---

## 9. Editor blocks and menus

### Block styling

| Block | Treatment |
| --- | --- |
| Paragraph | 0 top / 12pt bottom margin |
| Headings | 32pt above H1/H2, 24pt above H3/H4, 8pt below |
| Bulleted list | Bullets in `text-muted`, 24pt indent, 4pt item gap |
| Numbered list | Numbers in `text-muted`, tabular figures |
| Checklist | 16pt rounded-square box (4pt radius, 1.5pt `text-muted` border); checked fills `accent` with a white check, and the item text dims to `text-muted` with **no** strikethrough |
| Blockquote | 2pt left bar in `border`, 14pt left padding, `text-secondary` |
| Collapsible section | A disclosure triangle with a bold summary line; the content is indented 24pt |
| Code block | `raised` fill, 8pt radius, 1pt `border`, 16pt padding, 13pt SF Mono; a language label and copy button appear top-right on hover |
| Inline code | `raised` fill, 4pt radius, 2/4pt padding, 13pt SF Mono, with the accent tint removed |
| Divider | 1pt `divider`, 24pt vertical margin |
| Link | `accent`, no underline, underline on hover |
| Note link | Inline mention chip: 14pt document icon plus title, `raised` fill, 4pt radius |
| Table | 1pt `divider` grid, header row in `text-muted` 13pt / 500, no zebra striping |
| Image | 8pt radius, centred; resize handles appear on hover |
| Callout | Restyled as Linear-style: `raised` fill, 8pt radius, emoji or icon at left, and no coloured border |
| Selection | `selection` colour |

### Markdown shortcuts

These match Linear's editor:

| Input | Result |
| --- | --- |
| `#` to `####` then Space | Heading 1 to 4 |
| `*`, `-`, or `+` then Space | Bulleted list |
| `1.` then Space | Numbered list |
| `[]` then Space | Checklist |
| `>` then Space | Blockquote |
| `>>>` then Space | Collapsible section |
| `___` then Space | Divider |
| ` ``` ` | Code block |
| `|--` | Table |
| `:name` | Emoji suggestions |
| `@` | Mention: a note link picker |

### Keyboard shortcuts in the editor

| Action | Shortcut |
| --- | --- |
| Bold, italic, underline | `⌘B`, `⌘I`, `⌘U` |
| Strikethrough | `⌘⇧S` |
| Inline code | `⌘E` |
| Link (with a selection) | `⌘K` |
| Bulleted, numbered, checklist | `⌘⇧8`, `⌘⇧9`, `⌘⇧7` |
| Code block | `⌘⇧\` |
| Toggle checklist item | `⌘↩` (`⌘⇧↩` includes nested items) |
| Line break | `⇧↩` |
| Leave code block or quote | `↩↩` |

### Floating toolbar

- The toolbar appears above a non-empty selection, holding: **text style ⌄**, a separator, bold, italic, strikethrough, underline, link, quote, collapsible, inline code, code block, list ⌄.
- It is 36pt high, with an 8pt radius, `canvas` fill, a 1pt `border`, and menu elevation.
- Buttons are 28pt with 16pt SF Symbols in `text-muted`. Active marks show `text-primary` on a `hover` fill.
- Linear's trailing *comment* button is omitted because comments are out of scope.

### Slash menu

- The menu is 260pt wide and 8pt-radius, with a search field at the top that filters as the user types after `/`.
- Rows are 32pt, each with a 16pt icon, a label, and a right-aligned shortcut hint in `text-faint`.
- Groups: *Text* (headings, lists, checklist, quote, collapsible, divider), *Insert* (code block, table, image, callout, note link, date), and *Linear* (import and refresh actions).
- Up and down arrows move through the rows, Return inserts, and Escape closes.

### Implementation notes from step 3

- **Focus:** the writing surface and title show the accent caret instead of a focus ring, as Linear does. Buttons, menus, and fields keep visible focus rings.
- **Quote bar:** uses its own `quote-bar` token (`#34353B` dark, `#D6D6DA` light), because `border` is nearly invisible against the dark canvas.
- **Menus:** the slash menu, `@` mentions, the toolbar's text style and list menus, the heading menu, and the outline share one floating style on a `floating` surface (`#17181B` dark, `#FFFFFF` light).
- **Collapsible sections** remember open or closed in the file (`<details open>`) when toggled in Live mode, as checkboxes do. Reading mode only changes the view.
- **Not yet built:** `:name` emoji suggestions, image resize handles, and double-Return to leave a code block (Return three times still works).

---

## 10. Details rail

- The details rail is a 280pt rounded panel on the `canvas` surface to the right of the content panel, with the same 8pt shell gutter used between split panes.
- Its sections each have a 12pt `text-muted` label:
  - **Properties:** label and value rows (30pt, 16pt icon plus value).
  - **Note:** word count, character count, and reading time.
  - **File:** relative path, size, and created and modified dates, with *Show in Finder*.
  - **Linear:** source issue or document link, last refreshed time, and *Refresh from Linear…*, shown only for imported notes.
- The rail closes by default and stays toggled with `⌘⌥\`.

---

## 11. Command menu and shortcuts

### Command menu (`⌘K`)

- **Opening:** `⌘K` opens the command menu when there is no text selection in the editor. With a selection, it still inserts a link, matching Linear. `⌘P` and the sidebar search button open the same menu.
- **Appearance:** a centred 640pt sheet with an 8pt radius, a 48pt search field, and 36pt result rows.
- **Contents:**
  - Notes, matched by title first and then by full text using the existing library search with passage previews.
  - Commands such as *New note*, *New folder*, *Toggle sidebar*, *Split right*, and *Import from Linear*.
  - Recently opened notes, shown when the query is empty.

### App shortcuts

These keep the current shortcuts and add Linear's navigation:

| Action | Shortcut |
| --- | --- |
| Command menu | `⌘K` / `⌘P` |
| New note | `⌘N` |
| Back / forward | `⌘[` / `⌘]` |
| Toggle sidebar | `⌘\` |
| Toggle details rail | `⌘⌥\` |
| Keyboard shortcuts help | `⌘/` |

---

## 12. Icons

### Mapping

All glyphs come from **SF Symbols**.

| Use | SF Symbol |
| --- | --- |
| Document | `doc.text` (`doc.text.fill` in the icon tile) |
| Folder (closed / open) | `folder` / `folder.fill` |
| Recent | `clock` |
| Drafts | `square.and.pencil` |
| Search | `magnifyingglass` |
| Compose | `square.and.pencil` |
| Back / forward | `arrow.left` / `arrow.right` |
| History | `clock.arrow.circlepath` |
| Favorite (off / on) | `star` / `star.fill` |
| More | `ellipsis` |
| Copy link | `link` |
| Sidebar / details rail | `sidebar.left` / `sidebar.right` |
| Help | `questionmark.circle` |
| Disclosure | `chevron.right` / `chevron.down` (8pt, `text-muted`) |
| Text style | `textformat.size` |
| Bold / italic / strike / underline | `bold` / `italic` / `strikethrough` / `underline` |
| Quote | `quote.opening` |
| Collapsible | `chevron.up.chevron.down` |
| Inline code / code block | `chevron.left.forwardslash.chevron.right` / `curlybraces` |
| Lists | `list.bullet` / `list.number` / `checklist` |
| Table / image / callout | `tablecells` / `photo` / `lightbulb` |

### Icons inside the editor web view

SF Symbols are not available to web content directly. At editor load, Swift renders the needed symbols with `NSImage(systemSymbolName:)` into a small template sprite. The sprite is passed through the existing bridge and applied as CSS masks, so the icons follow the theme colour and match the native chrome exactly.

---

## 13. What stays the same

- Notebook storage, autosave, external edit conflicts and *Keep both*, draft recovery.
- Linear import, *Refresh from Linear*, *Save images locally*.
- Tabs and split panes, drag to split, layout restore.
- Find and Find and Replace (restyled as a Linear-style popover at the panel's top-right).
- Relative note links and link updates on move and rename.
- Print / Save as PDF.
- Reading and Source modes, moved out of the header.
- All existing tests continue to pass.

---

## 14. Out of scope

- Comments, real-time collaboration, presence, notifications, and an inbox.
- Linear's AI agent and document history.
- Issues, projects, boards, and other Linear views.
- Any Linear logo, wordmark, or proprietary icon.

---

## 15. Default decisions

These defaults are applied unless SPAWN changes them.

| Topic | Default | Alternative |
| --- | --- | --- |
| Document title | The **file name**, editable in place, renaming the file | Use the first `#` heading as the title |
| Status strip | **Removed**; save state moves to the header, and counts move to the details rail | Keep a slim status strip |
| Sidebar search field | **Removed**; search opens in the `⌘K` command menu | Keep the inline field |
| Mode switcher | **Moved** to the `⋯` menu and View menu | Keep a compact header control |
| Collapsible sections on disk | Stored as HTML `<details><summary>` | A custom Markdown fence |
| Accent | Linear indigo `#5E6AD2` | Keep the current lavender `#8794F5` |
| Typeface | **Bundled Inter** | System SF Pro only |
| App identity | ~~Packaged as **Linear Notes Overhaul.app** with its own bundle identifier~~ Merged into main as **Linear Notes v2.app**, keeping `local.linearnotes.app` and its settings (SPAWN, 7 November 2026) | Separate identifier for side-by-side runs |

---

## 16. Build sequence

1. **Tokens and fonts.** Update `Palette` and the editor CSS variables, bundle Inter, and add the icon sprite bridge.
2. **Shell.** Build the inverted-L layout, title bar row with back, forward, and history, and the restyled tab strip.
3. **Sidebar.** Add the workspace switcher, search and compose, primary rows, Favorites, the Notes tree, and the help button.
4. **Page header and command menu.** Add breadcrumbs, `⋯`, the star, the timestamp, and `⌘K`.
5. **Document page.** Add the icon tile, title-as-file-name, properties row, outline markers, and heading handles.
6. **Editor blocks.** Restyle the blocks, then build the floating toolbar, the slash menu, and collapsible sections.
7. **Details rail and Find popover.**
8. **Package and compare.** Run side-by-side screenshots against Linear in both appearances, then walk through the [fidelity checklist](#17-fidelity-checklist).

Steps 1–5 correspond to plan step 2, steps 6–7 to plan step 3, and step 8 to plan step 4.

---

## 17. Fidelity checklist

### Shell

- [ ] The sidebar and title bar share one continuous `shell` surface, and the content is a single inset 12pt panel.
- [ ] Back, forward, and history align to the sidebar's right edge in the title bar row.
- [ ] Tabs are 28pt with 6pt radius; only the active tab has a fill and outline.

### Sidebar

- [ ] All row icons share one column, and all labels share one baseline grid.
- [ ] The selected row uses a neutral fill with no accent bar.
- [ ] Section labels are muted, with the disclosure triangle after the label.

### Document

- [ ] The icon tile, title, and body share one left edge.
- [ ] Body text is 15/24 in `text-body`, and headings alone reach `text-primary`.
- [ ] The outline markers reflect headings and track the current section.
- [ ] The floating toolbar, slash menu, and heading menu share one menu style.

### Behaviour

- [ ] Every action in Linear's editor shortcut list works the same way here.
- [ ] Autosave, conflicts, recovery, and Linear refresh behave exactly as in v1.3.4.
- [ ] Light and dark appearances both pass WCAG AA for body text, and Reduce Motion removes all transitions.
- [ ] Keyboard-only use reaches every control, with visible focus rings.
