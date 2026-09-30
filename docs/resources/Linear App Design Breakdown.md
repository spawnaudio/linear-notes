# Linear App Design Breakdown

> A replication-oriented analysis of Linear's macOS desktop application UI, based on seven supplied screenshots captured on 12 September 2026. This is an observational design specification, not an export of Linear's private design tokens or source code.

## 1. Purpose and use

This document translates the visible design language of Linear into a reusable system that can guide other desktop and web applications. The goal is not a pixel-for-pixel clone or use of Linear's trademarks. The goal is to reproduce the qualities that make the interface feel recognisably Linear-like: dense but calm, fast, keyboard-oriented, structurally rigorous, and visually quiet until status or action requires emphasis.

Use this document as:

* a design brief for a new application;
* a component-library specification;
* a token and layout reference for designers and engineers;
* a review checklist for visual and interaction fidelity; and
* a guide for adapting the style without copying Linear's brand assets.

## 2. Evidence and confidence

### Directly observed

The screenshots show:

* the dark macOS desktop application;
* the persistent workspace sidebar and application tab strip;
* an initiatives table;
* an initiative overview with a primary content column and contextual right rail;
* a board grouped by team and workflow state;
* selected, inactive, filled, outlined, muted, warning, success, and accent states;
* cards, metadata chips, segmented controls, property rows, activity rows, icons, dividers, and charts; and
* close-up details of tabs, headers, outer window edges, corner radii, and the help button.

### Estimated rather than authoritative

Exact CSS values, typeface files, animation curves, breakpoints, internal component names, and source tokens cannot be recovered from screenshots. Measurements below are practical approximations. The full-window screenshots appear to be Retina captures, so many physical pixel measurements have been interpreted at approximately 2:1 into logical UI pixels. Validate the values in a live prototype and tune optically.

## 3. The design thesis

Linear's UI is built from five mutually reinforcing ideas:

1. **Structure before decoration.** Layout, grouping, alignment, and typography do almost all the work. Ornament is minimal.
2. **Low-contrast depth.** Surfaces are separated by small changes in charcoal value and hairline borders, not heavy shadows.
3. **Compact rhythm.** Controls, rows, and cards are dense, but consistent spacing and muted secondary text keep them readable.
4. **Meaningful colour.** Most of the app is neutral. Saturated colour is reserved for identity, state, health, priority, team, and selection.
5. **Progressive disclosure.** Primary actions and information stay visible; detail, menus, filters, secondary controls, and metadata appear contextually.

The result should feel more like a precise instrument than a decorative dashboard.

## 4. Overall application anatomy

### 4.1 Window and shell

The desktop window is a large rounded rectangle floating against the macOS desktop. It uses a nearly black outer shell, a fine border, and a radius of roughly 14–16 logical pixels. There is little or no conventional drop shadow inside the captured frame; separation mainly comes from the black desktop background and the window outline.

The shell has four persistent zones:

1. **macOS/window controls:** traffic-light controls and compact navigation utilities at the top-left.
2. **application tab strip:** a horizontal row of page tabs across the top.
3. **workspace sidebar:** a fixed vertical navigation rail on the left.
4. **active view:** the main rounded content surface to the right, sometimes with its own contextual side panel.

Recommended desktop proportions:

| Region | Practical starting value |
| -- | -- |
| Outer window radius | 14–16px |
| Application tab strip | 42–46px high |
| Sidebar | 270–300px wide |
| Main content header | 46–52px high |
| Compact toolbar row | 40–46px high |
| Contextual right rail | 300–380px wide |
| Main content minimum width | 640px |

### 4.2 Layer model

Use a small, disciplined elevation ladder:

* **Layer 0 — desktop/background:** outside the app, black or near-black.
* **Layer 1 — shell/sidebar/top chrome:** the darkest in-app surface.
* **Layer 2 — main canvas:** slightly lighter than the shell.
* **Layer 3 — rows, cards, panels, selected areas:** one value step lighter.
* **Layer 4 — hover, active control, floating menu:** another subtle step lighter.
* **Layer 5 — focus/attention:** expressed mainly with border or semantic colour, not a large shadow.

Avoid stacking many visibly different greys. The design works because adjacent layers differ only enough to explain containment.

## 5. Colour system

### 5.1 Neutral palette

Linear's existing brand reference names its dark base **Nordic Gray** `#222326`. In the screenshots, the surrounding shell and sidebar appear somewhat darker, while the content canvas sits close to that base. The following implementation palette is therefore an approximation tuned to the supplied images:

| Token | Suggested value | Use |
| -- | -- | -- |
| `--bg-desktop` | `#090A0C` | Background outside the app window |
| `--bg-shell` | `#17181B` | Window chrome, sidebar, tab strip |
| `--bg-canvas` | `#1F2023` | Primary content canvas |
| `--bg-subtle` | `#242529` | Group headers, secondary containers |
| `--bg-panel` | `#292A2E` | Cards, property panels, active rows |
| `--bg-control` | `#303138` | Filled controls, selected tabs |
| `--bg-hover` | `#35363C` | Hover and stronger active state |
| `--border-soft` | `#2B2C31` | Dividers and nested boundaries |
| `--border-default` | `#383A40` | Card and panel outlines |
| `--border-strong` | `#484A52` | Selected/focused outlines |
| `--text-primary` | `#F1F1F3` | Titles and primary values |
| `--text-secondary` | `#C6C7CB` | Standard body and row text |
| `--text-muted` | `#92949B` | Labels, metadata, inactive navigation |
| `--text-faint` | `#6F7178` | Disabled or extremely secondary content |

Important: do not use pure white for normal text. The interface stays comfortable because even the brightest text is slightly softened.

### 5.2 Semantic and identity colours

The screenshots use small, saturated accents against large neutral fields:

| Role | Suggested range | Typical use |
| -- | -- | -- |
| Cyan | `#22B8CF`–`#35C2D7` | team identity, systems labels, links, chart line |
| Blue/indigo | `#5B6EE1`–`#6C79F5` | completed state, progress, focus |
| Green | `#48B982`–`#57C792` | on track, growth, study/team identity |
| Yellow | `#E2C000`–`#F2CE00` | in progress, at risk, favourite/star |
| Orange | `#F28C45`–`#FF9850` | warning, house/personal identity |
| Red/coral | `#EE5559`–`#FF646B` | urgent, SPAWN identity, risk |
| Purple | `#A875E8`–`#B886F2` | creative identity and secondary charts |

Colour is normally shown as a 6–12px dot, 14–18px icon, narrow chart line, status ring, or small badge. Large blocks of saturated colour would break the visual language.

### 5.3 Contrast rules

* Keep surfaces close in luminance, but keep text-to-surface contrast strong enough for comfortable reading.
* Primary text should meet WCAG AA where possible; body text should target at least 4.5:1.
* Do not rely on colour alone. Pair every workflow state with a label, icon, shape, or position.
* Muted text must remain readable. Do not make tertiary content merely decorative if it conveys dates, counts, or ownership.

## 6. Typography

### 6.1 Character

The typography is a neutral modern grotesk with a large x-height, compact metrics, and little personality of its own. It is used to make information feel direct and operational. A close implementation choice is **Inter**, with the native system stack as a robust fallback:

```css
font-family: Inter, ui-sans-serif, -apple-system, BlinkMacSystemFont,
  "Segoe UI", sans-serif;
```

Treat this as a reproduction recommendation, not confirmation of Linear's internal font.

### 6.2 Type scale

| Style | Size | Weight | Line height | Use |
| -- | -- | -- | -- | -- |
| Display/title | 28–32px | 600–650 | 1.15–1.25 | Initiative/project title |
| Update headline | 22–25px | 600–650 | 1.25–1.35 | Card headline |
| Section heading | 17–19px | 600 | 1.3 | Content section title |
| Standard UI/body | 14–15px | 450–500 | 1.45–1.6 | Navigation, body, property values |
| Compact UI | 12.5–13.5px | 500 | 1.35–1.45 | Dense rows, chips, tabs |
| Metadata | 11.5–12.5px | 450–500 | 1.3–1.4 | IDs, counts, timestamps |

### 6.3 Typographic hierarchy

* Use weight changes sparingly. Most hierarchy comes from size, value, and position.
* Primary titles are bright and semibold; subtitles are smaller and grey.
* Property labels are muted and aligned in a stable left column; values are brighter.
* Table headers are muted and compact, not bold uppercase.
* Issue IDs are smaller and dimmer than issue names.
* Avoid excessive letter spacing. The interface feels compact, not editorial.

## 7. Spacing and sizing

### 7.1 Base rhythm

Use a 4px base unit with the following preferred sequence:

`2, 4, 6, 8, 10, 12, 16, 20, 24, 32, 40, 48`

The design often uses small optical adjustments, but these values are sufficient for a coherent implementation.

### 7.2 Common dimensions

| Element | Suggested dimensions |
| -- | -- |
| Sidebar row | 30–34px high; 8–12px horizontal inset |
| App tab | 30–34px high; 8–12px radius |
| Segmented-control item | 30–32px high; pill radius |
| Icon button | 28–34px square |
| Primary card | 10–12px radius; 16–20px padding |
| Property panel | 10–12px radius; 14–18px padding |
| Chip/tag | 24–28px high; 8–10px horizontal padding |
| Table item row | 46–58px high |
| Board card | 74–110px typical; 10–12px padding |
| Major page gutter | 24–40px |
| Dense column gap | 8–16px |

### 7.3 Alignment

The interface relies on hard alignment lines:

* all sidebar icons occupy the same narrow icon column;
* labels and counts share predictable baselines;
* property labels align separately from property values;
* table columns remain consistent across group sections;
* board cards align to column edges;
* header controls use a single vertical centreline; and
* content columns use stable left and right gutters.

If a recreation feels untidy, fix alignment before changing colour or shadow.

## 8. Shape, borders, and depth

### 8.1 Radius hierarchy

* 4–6px: tiny badges, compact embedded metadata.
* 7–9px: sidebar selections, tabs, small controls.
* 10–12px: cards, panels, board items.
* 14–16px: major view container and app window.
* 999px: status chips, segmented controls, avatar rings.

### 8.2 Borders

Borders are typically 1px and low contrast. They do three jobs:

1. define the outer window and major content container;
2. separate cards/panels from the canvas; and
3. clarify interactive controls when fill alone is insufficient.

Dividers are quieter than borders. Use them between rows or structural areas, but avoid drawing a box around every piece of information.

### 8.3 Shadows

Use little or no shadow for static embedded cards. If a menu, tooltip, popover, or dragged item needs elevation, use a soft, broad, low-opacity black shadow combined with a slightly stronger border. The feeling should be lifted, not glossy.

## 9. Navigation shell

### 9.1 Workspace sidebar

The sidebar is the application's persistent information spine. It is visually quiet, approximately 270–300px wide, and scrolls independently when content exceeds height.

Anatomy:

* workspace switcher at the top;
* search and create controls;
* primary personal navigation;
* workspace-level navigation;
* favourites;
* team sections with expandable children;
* a circular help control pinned near the bottom-left.

Sidebar row recipe:

* 16–18px leading icon;
* 8–10px gap;
* single-line label with ellipsis;
* optional right-aligned count;
* 8–12px outer horizontal inset;
* 30–34px total height;
* 7–9px selected background radius.

Inactive rows use muted grey. A selected row uses a filled grey surface and brighter text, but normally no coloured accent bar. Team identity is carried by small coloured icons rather than tinting the whole row.

Section labels such as “Workspace”, “Favorites”, and “Your teams” are small, muted, and separated by generous vertical whitespace. Disclosure chevrons are tiny and subordinate.

### 9.2 Application tab strip

The top strip behaves like a compact browser tab bar:

* previous/next navigation lives toward the left;
* open contexts appear as rounded dark tabs;
* the selected tab has a slightly lighter fill and brighter label;
* tabs may contain a small entity icon and truncated name;
* a plus button creates a new tab/context; and
* inactive tabs can collapse to icon-only forms, visible in the close-up screenshot.

Recommended tab state styling:

| State | Treatment |
| -- | -- |
| Inactive | shell background, muted icon/text |
| Hover | subtle filled surface, brighter icon |
| Active | `--bg-control`, bright text, soft 1px outline |
| Attention | small semantic icon or dot; do not recolour full tab |

### 9.3 Page header

Inside the main view, the header repeats the current entity icon and title. Supporting actions sit at the right edge: link, notification, add, star, overflow, filters, display settings, or view controls. The header is separated with a hairline divider.

This repeated title is deliberate: the app tab communicates global context, while the page header anchors actions within the current view.

## 10. Controls and interaction language

### 10.1 Icon buttons

Icon buttons are compact, usually 28–34px square, and use 16–18px line icons. Resting states may have no fill; hover and active states gain a soft circular or rounded-square fill. Destructive actions should introduce red only when relevant.

### 10.2 Segmented controls

Examples include “Active / Planned / All initiatives” and “Overview / Activity / Projects”. The outer group does not need a strongly outlined container; each option appears as an individual low-contrast pill. The selected option has a lighter fill and brighter, slightly heavier text.

### 10.3 Chips and metadata pills

Chips communicate labels, project links, progress, teams, dates, and other metadata.

Recipe:

* height 24–28px;
* full pill radius;
* transparent or very subtle fill;
* 1px quiet border;
* 6–8px coloured dot or 14px icon;
* 6px internal gap;
* 12–13px medium-weight text;
* optional small chevron for editable values.

Do not make all chips equally bright. Editable/active chips may be slightly stronger; informational chips should recede.

### 10.4 Menus and disclosure

Overflow is represented by horizontal ellipsis. Disclosure uses compact chevrons. These controls are frequently visually faint until hover. Maintain at least a 28px click target even when the visible icon is only 14px.

### 10.5 Selection and focus

The screenshots show selection mainly through filled surfaces. A complete implementation should add an accessible keyboard focus ring using a desaturated blue/indigo outline outside the control. Do not replace focus with hover.

## 11. Initiatives table pattern

The initiative list combines spreadsheet structure with grouped-list readability.

### Structure

* page title and “New initiative” action;
* status segment control;
* filter/display icon controls;
* muted column-header row;
* collapsible status group headers;
* two-line item rows; and
* a wide flexible name column followed by compact metadata columns.

### Group header

The group row is a full-width subtle surface with:

* disclosure chevron;
* coloured status ring/icon;
* group name;
* item count; and
* optional actions at the far right.

### Item row

Each initiative row uses:

* a small entity icon;
* bright primary name;
* muted one-line summary beneath;
* label and outcome chips;
* a compact priority glyph;
* coloured lead-team icon and short key; and
* right-aligned target date.

Rows are not individually boxed. The table reads as one surface. Hover should add a very subtle row fill, while selection can add a stronger fill. Preserve 44px or larger click height even if the visible content feels denser.

### Column behaviour

* Name takes remaining width and truncates first.
* Tags may collapse or reduce before priority/team/date.
* Important fixed fields stay aligned.
* At narrower widths, move secondary fields into a row detail drawer rather than crushing every column.

## 12. Initiative/project overview pattern

The overview page uses a document-like primary column plus an operational right rail.

### Primary column

The main column contains:

* large entity icon;
* title and subtitle;
* inline property summary;
* labels;
* linked resources;
* latest update card;
* expandable description; and
* long-form rich content.

The content is left aligned with generous top spacing. The primary column remains substantially wider than the right rail, roughly a 60:40 to 65:35 division in the screenshots.

### Right rail

The right rail contains stacked panels for:

* detailed properties;
* progress/health chart and counts; and
* recent activity.

Each panel has a quiet border, 10–12px radius, and 14–18px padding. Panel headers are muted and compact. Values remain brighter than their labels.

### Latest update card

This is the strongest content card on the page. Its hierarchy is:

1. card header (“Latest update” and Update action);
2. status, author, and timestamp metadata;
3. large update headline;
4. body copy with section headings and bullets;
5. a compact change summary; and
6. comment/reaction actions at the bottom.

The card is visually self-contained but still belongs to the canvas: outline and slight tonal shift, not a bright floating panel.

### Progress chart

The chart uses saturated lines and translucent fills on a dark neutral panel. Controls beneath it are pill segments. Legend rows combine a status icon, label, and right-aligned count. Keep chart grid lines extremely faint or omit them.

## 13. Board pattern

The board screenshot demonstrates high information density without visual chaos.

### Grid

* horizontal team columns;
* horizontal workflow-state swimlanes;
* one or more issue cards per intersection;
* a persistent contextual inspector at the right;
* large empty cells where no work exists; and
* subtle alternating or bounded column regions.

The board prioritises position as data: team is horizontal, status is vertical. Because location already carries meaning, cards do not repeat every property.

### Column headers

Column headers use a team icon, team name/key, count, overflow, and add action. They remain compact and aligned across the grid.

### Swimlane headers

State rows use a full-width subtle strip with disclosure, coloured state icon, label, count, and overflow. The coloured icon is the main semantic cue; the strip itself stays neutral.

### Issue cards

Card anatomy:

* muted issue identifier at top-left;
* avatar at top-right;
* status icon plus primary issue title;
* compact metadata row containing priority, due date, project, and progress; and
* ellipsis/truncation for long metadata.

Cards use a `--bg-panel` fill, quiet border, roughly 10px radius, and a minimum click height near 72px. Hover should lift by value and border, not by moving several pixels.

### Empty states

Empty board cells are allowed to remain empty. A faint, full-width add target appears only where useful or on hover. Do not fill every cell with explanatory text.

### Contextual inspector

The right inspector stays within the view and provides details about the current board: name, description, visibility, owner, and segmented result groupings. It is made from stacked panels rather than one monolithic card.

## 14. Iconography and imagery

### Icons

* Use a consistent 1.5–2px stroke icon family.
* Default size is 16px; major entity icons may be 20–28px.
* Rounded stroke caps and joins fit the interface.
* Use filled icons selectively for entity identities or strong status.
* Keep semantic colour inside the icon rather than colouring nearby text by default.

Lucide, Phosphor, or a custom outline set can approximate the style if stroke, optical size, and alignment are normalised.

### Avatars

Avatars are small, typically 16–22px in dense contexts. They identify ownership without dominating the row or card. Use circular clipping and provide initials/fallback colour.

### Images and rich content

Large images belong in expandable description or document areas, not in the navigation shell. Respect the same canvas width and corner-radius system. Avoid adding image shadows unless the image needs separation from a similarly coloured canvas.

## 15. State and feedback system

Every reusable control should define these states:

| State | Expected treatment |
| -- | -- |
| Rest | neutral, low contrast |
| Hover | one surface step lighter; icon/text brightens |
| Pressed | slightly darker or inset-looking fill |
| Selected | persistent filled surface and primary text |
| Focus-visible | 2px accessible accent ring, offset 1–2px |
| Disabled | reduced contrast; no hover response |
| Loading | contained skeleton or small spinner; layout remains stable |
| Error | concise inline red/coral message plus icon |
| Success | small green confirmation; avoid large celebratory overlays |

Optimistic updates suit this product language: reflect common changes immediately, then show a small unobtrusive rollback/error message if persistence fails.

## 16. Motion

Motion should make the interface feel fast and continuous, never theatrical.

Recommended timings:

* hover/fill transition: 80–120ms;
* menu/popover: 120–160ms;
* panel/drawer: 160–220ms;
* reorder/drag settling: 180–240ms; and
* route/content crossfade: 120–180ms.

Use ease-out for entering, ease-in for leaving, and a standard ease-in-out for layout changes. Keep transforms to 2–6px where needed. Respect `prefers-reduced-motion` and remove nonessential translation or scaling.

## 17. Content design

The copy is concise, operational, and noun-led:

* navigation uses short labels;
* actions use compact verbs (“Update”, “Add”, “Show options”);
* metadata avoids sentences;
* empty states are brief;
* titles use sentence case; and
* counts sit beside the object they quantify.

Long-form updates are the exception: they use document typography inside a clearly bounded card. Keep application chrome terse so rich content can breathe.

## 18. Responsive and adaptive behaviour

The screenshots show a desktop-first interface. A faithful adaptation should collapse by priority rather than uniformly shrinking.

### Wide desktop (about 1440px and above)

* sidebar visible;
* main content and right rail visible;
* table columns mostly visible;
* board shows several team columns plus inspector.

### Standard desktop (about 1100–1439px)

* sidebar remains visible or becomes slightly narrower;
* right rail may narrow;
* secondary table columns truncate;
* board scrolls horizontally.

### Compact desktop/tablet (about 760–1099px)

* sidebar becomes an overlay or icon rail;
* right rail becomes a slide-over inspector;
* tables hide secondary columns;
* primary title and action header remain fixed;
* board remains horizontally scrollable rather than compressing cards below usability.

### Mobile/narrow (below about 760px)

Do not force the desktop shell into a tiny width. Use a dedicated hierarchy:

* top app bar replaces tab strip and persistent sidebar;
* lists replace wide tables;
* board can switch to one group at a time;
* property rail becomes a full-screen detail sheet; and
* command/search remains globally accessible.

## 19. Accessibility requirements

A visually faithful recreation still needs improvements that screenshots cannot prove:

* 44×44px touch targets on touch devices; at least 28–32px pointer targets on desktop with adequate spacing;
* visible keyboard focus for all controls;
* full keyboard navigation across sidebar, tabs, lists, boards, menus, and dialogs;
* semantic headings and landmarks;
* correct table semantics for tabular views;
* labelled icon-only buttons and meaningful tooltips;
* text alternatives for avatars, charts, and status icons;
* status conveyed by text/shape as well as colour;
* contrast testing for muted copy and disabled states;
* reduced-motion support;
* zoom to 200% without loss of content or action; and
* screen-reader announcements for saves, reorders, filter changes, and optimistic-update failures.

## 20. Recommended design tokens

```css
:root {
  color-scheme: dark;

  --bg-desktop: #090a0c;
  --bg-shell: #17181b;
  --bg-canvas: #1f2023;
  --bg-subtle: #242529;
  --bg-panel: #292a2e;
  --bg-control: #303138;
  --bg-hover: #35363c;

  --border-soft: #2b2c31;
  --border-default: #383a40;
  --border-strong: #484a52;

  --text-primary: #f1f1f3;
  --text-secondary: #c6c7cb;
  --text-muted: #92949b;
  --text-faint: #6f7178;

  --cyan: #2dbed2;
  --blue: #6574eb;
  --green: #50bd87;
  --yellow: #ebc800;
  --orange: #f4934d;
  --red: #f05b61;
  --purple: #ad7ce9;

  --space-1: 4px;
  --space-2: 8px;
  --space-3: 12px;
  --space-4: 16px;
  --space-5: 20px;
  --space-6: 24px;
  --space-8: 32px;

  --radius-xs: 5px;
  --radius-sm: 8px;
  --radius-md: 11px;
  --radius-lg: 15px;
  --radius-pill: 999px;

  --control-sm: 28px;
  --control-md: 32px;
  --row-compact: 34px;
  --row-standard: 52px;

  --duration-fast: 100ms;
  --duration-standard: 160ms;
  --ease-out: cubic-bezier(.2, .8, .2, 1);
}
```

## 21. Reusable component set

Build the style as composable primitives rather than one-off screens.

### Foundations

* `AppWindow`
* `AppTabStrip`
* `Sidebar`
* `MainView`
* `PageHeader`
* `SplitPane`
* `InspectorRail`
* `Surface`
* `Stack` and `Inline`

### Navigation and actions

* `NavSection`
* `NavItem`
* `AppTab`
* `IconButton`
* `Button`
* `SegmentedControl`
* `DropdownMenu`
* `CommandMenu`

### Data display

* `EntityIcon`
* `Avatar`
* `StatusIcon`
* `TagChip`
* `PropertyRow`
* `ActivityRow`
* `StatRow`
* `ProgressChart`
* `ResourceLink`

### Lists and boards

* `DataTable`
* `GroupRow`
* `EntityRow`
* `BoardGrid`
* `BoardColumnHeader`
* `SwimlaneHeader`
* `IssueCard`
* `EmptyDropTarget`

Each component should consume the same spacing, radius, border, typography, and semantic-colour tokens. Avoid component-specific greys unless the token system genuinely cannot express the requirement.

## 22. Construction sequence for another app

 1. **Build the shell first.** Establish outer radius, tab strip, sidebar, canvas, and major dividers.
 2. **Lock the density.** Implement the base type scale, 4px spacing rhythm, control heights, and icon sizes.
 3. **Create the neutral surface ladder.** Test boundaries on a calibrated display before introducing accents.
 4. **Build navigation primitives.** Sidebar rows, tabs, icon buttons, segmentation, and keyboard focus.
 5. **Build metadata primitives.** Chips, avatars, status rings, property rows, counts, and timestamps.
 6. **Implement one canonical list view.** Prove grouped rows, truncation, selection, and responsive hiding.
 7. **Implement one canonical detail view.** Prove document column, cards, properties, activity, and inspector behaviour.
 8. **Add board composition if needed.** Reuse existing cards and group headers; do not create a second visual language.
 9. **Add motion and optimistic feedback.** Keep the layout stable and the response immediate.
10. **Run accessibility and density QA.** Test keyboard-only use, 200% zoom, contrast, long labels, empty data, and large counts.

## 23. Fidelity checklist

### Shell

- [ ] Window, sidebar, canvas, and panels use a restrained five-layer surface ladder.
- [ ] Outer and major-container radii are larger than card/control radii.
- [ ] The sidebar and top tab strip read as one dark shell.
- [ ] The active view is clearly contained without a heavy shadow.

### Hierarchy

- [ ] Primary titles are bright and semibold, never excessively bold.
- [ ] Metadata is muted but readable.
- [ ] Alignment lines are consistent across icons, labels, values, and counts.
- [ ] Colour is concentrated in small semantic elements.

### Components

- [ ] Selected navigation uses a neutral filled state.
- [ ] Segmented controls use compact pills.
- [ ] Chips have consistent height, border, icon/dot, and padding.
- [ ] Cards use quiet borders and tonal elevation.
- [ ] Icon-only actions have tooltips and accessible names.

### Behaviour

- [ ] Hover, pressed, selected, focus, disabled, loading, error, and success states are defined.
- [ ] Common edits feel immediate.
- [ ] Long names truncate predictably and reveal the full value on hover/focus.
- [ ] Narrow layouts collapse lower-priority information rather than shrinking everything.
- [ ] Reduced motion and keyboard navigation are supported.

## 24. Common mistakes that make a recreation feel wrong

* Making the canvas pure black and every card obviously lighter.
* Using large shadows instead of subtle borders and tonal changes.
* Using too many font sizes or heavy weights.
* Making every action a labelled button.
* Tinting whole rows/cards with semantic colour.
* Giving chips inconsistent heights and radii.
* Over-padding the sidebar and board cards.
* Compressing wide tables until values become unreadable.
* Using colour as the only status signal.
* Animating every hover with scale or large translation.
* Adding gradients, glass blur, or glow where the interface calls for restraint.
* Copying Linear's logo, names, or proprietary brand assets instead of adapting the system to the new product's identity.

## 25. Screenshot-specific observations

### Screenshot 1 — Initiatives list

Demonstrates the persistent shell, grouped table, two-line initiative rows, semantic label chips, lead-team icons, aligned target dates, and large calm empty canvas beneath the list. It is the best reference for dense list hierarchy and column behaviour.

### Screenshots 2 and 6 — Initiative overview

Demonstrate the document-like primary column, inline properties, linked resources, large update card, right-side property/progress/activity panels, segmented view tabs, and nested card hierarchy. The two captures also show how the same layout holds at slightly different window proportions.

### Screenshot 3 — Current cycle board

Demonstrates a multi-dimensional board: team columns, workflow swimlanes, issue cards, empty cells, metadata density, filters, and a right-side view inspector. It is the strongest reference for operational density and positional meaning.

### Screenshot 4 — Collapsed application tabs

Shows icon-only inactive tabs, a filled active entity tab, compact navigation chevron, and plus action. It confirms the difference between the darkest tab-strip background and the slightly lighter active-tab surface.

### Screenshot 5 — Active tab and page title

Shows repeated context across the application tab and page header, plus the favourite star and overflow action. It is useful for icon size, text weight, active-tab radius, and header divider treatment.

### Screenshot 7 — Outer corner and help control

Shows the nested-radius relationship between app window and main content container, the thin outer border, the darker sidebar/canvas boundary, and the circular help button anchored near the lower-left.

## 26. Final design rule

When deciding whether to add a visible treatment, ask: **does this element need more hierarchy, more meaning, or more feedback?** If the answer is no, leave it quiet. Linear's visual identity is created as much by what it withholds as by what it displays.

---

### Source note

Prepared from seven user-supplied screenshots dated 12 September 2026 and the initiative resource “Linear Styles”, which records Nordic Gray (`#222326`). Other values are observational estimates for prototyping and should be validated in the target app.
