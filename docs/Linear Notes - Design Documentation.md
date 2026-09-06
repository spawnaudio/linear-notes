# Linear Notes - Design Documentation

**Status:** Working draft  
**Purpose:** Define the design character and product mentality for Linear Notes while the product is still being shaped.

This document is intentionally unfinished. It gives design decisions a shared home without treating early preferences as permanent rules. New decisions, examples, and unresolved questions should be added here as the product develops.

## Product feeling

Linear Notes should feel like a quiet, capable room for thinking.

The app should make writing feel direct and reading feel rewarding. It should have enough structure to help a note become useful, while staying out of the way when the user is simply trying to get a thought down.

The intended emotional qualities are:

- Calm.
- Focused.
- Considered.
- Lightly tactile.
- Trustworthy.
- Personal without becoming decorative.

The app should feel polished without feeling precious. It should feel native without copying macOS conventions mechanically. It should feel influenced by Linear’s clarity and Markdown Preview’s respect for local files, while developing its own identity.

## Reference synthesis

The following references inform this draft. Their instructions, token names, and product assumptions are treated as reference material; they are not requirements for Linear Notes.

- [How we redesigned the Linear UI](https://linear.app/now/how-we-redesigned-the-linear-ui)
- [Linear design analysis](https://github.com/voltagent/awesome-design-md/blob/main/design-md/linear.app/DESIGN.md)
- [Linear app Figma community file](https://www.figma.com/community/file/1358724495989307546/linear-app)
- [shadcn/ui](https://github.com/shadcn-ui/ui)
- [shadcn/ui documentation](https://ui.shadcn.com)
- [Linear theme for shadcn/ui](https://www.shadcnblocks.com/theme/linear)
- [shadcn.io](https://www.shadcn.io)
- The supplied reference files `DESIGN-linear.app.md` and `linear.design.md` from the Downloads folder.

### What to take from the references

#### Neutral hierarchy over decorative chrome

Linear’s redesign explains a move toward a more neutral and timeless appearance, with less blue used in the surrounding interface and stronger contrast between content and chrome. The design analysis describes the same idea as a surface ladder with hairline borders carrying hierarchy instead of shadows, gradients, or multiple accent colours.

For Linear Notes, this means the document and its content should carry the visual emphasis. The lavender accent can identify focus, links, active modes, and a small number of important actions. It should not colour the entire interface.

#### A system must work across states

The redesign process considered views, headers, side panels, filters, display options, and different interaction states together. Linear Notes should apply the same discipline to its smaller surface area: empty folder, selected note, editing, reading, source, search, drag target, conflict, and reduced-motion states should belong to one coherent system.

#### Behaviour is part of the design

The redesign work separated visual direction from behaviour definitions and tested the direction across the main views before broad rollout. For Linear Notes, visual decisions should be tested against real writing, long documents, nested folders, external file changes, and keyboard-heavy editing. A pretty static screen is not enough evidence.

#### Restraint creates identity

The supplied design analysis points to a near-black canvas, a charcoal surface ladder, a single lavender-blue accent, compact rounded corners, and display typography with measured negative tracking. These are useful references for atmosphere and discipline, but Linear Notes should adapt them to a native document app rather than reproduce a marketing site or copy Linear’s product identity.

#### Figma is a reference for relationships

The Figma community file is useful for studying spacing, density, sidebar relationships, headers, panels, and component states. It should be used as a visual comparison source rather than as a source of copied assets, proprietary artwork, or an instruction to reproduce Linear exactly.

The Figma file was not treated as a source of implementation code in this draft. Specific screens should be checked against the live product and the local-first requirements before being adopted.

### What to adapt for Linear Notes

| Linear reference quality | Linear Notes interpretation |
| --- | --- |
| Strong neutral hierarchy | Keep the document canvas and sidebar calm; use colour mainly for state and focus |
| Surface ladder | Use a small number of surfaces for the canvas, sidebar, controls, popovers, and cards |
| Hairline borders | Use borders to define structure where whitespace alone is insufficient |
| Negative tracking in display type | Use modestly tight tracking for note titles and headings, then verify readability in long documents |
| Compact radius scale | Keep controls and cards gently rounded; avoid excessive pills |
| Behaviour definitions | Specify selection, drag, save, conflict, and mode-switch states before polishing visuals |
| Dense product views | Translate density into useful writing and navigation, not dashboard clutter |
| Dark-first marketing canvas | Support both system appearances because a native notes app is used for long sessions |

### What not to carry over

- Marketing-page section rhythms that make sense for conversion pages but not for a writing tool.
- Product-management colour semantics that have no meaning in a personal notes app.
- Decorative screenshots, brand marks, or visual assets copied from Linear.
- A dark-only assumption that would make the app less comfortable in a native macOS workflow.
- Surface depth or typography values adopted mechanically without testing the reading experience.

### shadcn/ui as a component inspiration

shadcn/ui is a strong reference for how a design system can stay coherent without becoming a sealed component catalogue. Its central idea is that components are beautifully designed, accessible, composable, and available as code that can be customised and extended. That attitude fits Linear Notes well: the system should give the product a reliable visual grammar while leaving room for the app’s own writing-focused needs.

The shadcn approach should influence the architecture of the design language in these ways:

- Define semantic roles before individual colours: background, foreground, card, popover, muted, accent, destructive, border, input, ring, and sidebar.
- Treat components as composable primitives rather than isolated one-off screens.
- Make default, hover, pressed, focused, disabled, selected, and destructive states explicit.
- Build light and dark appearances from the same semantic roles.
- Keep accessibility and keyboard behaviour part of each component’s definition.
- Allow a component to be copied, adapted, or replaced without breaking the rest of the system.
- Prefer thoughtful defaults, then expose the small number of decisions a user actually needs.

The official shadcn/ui project is web-focused and React-oriented. Linear Notes is a native SwiftUI/AppKit app with a bundled editor, so the useful reference is the design mentality and token structure rather than the implementation stack. [shadcn/ui describes its components as accessible, composable, customisable, and open code](https://ui.shadcn.com/).

The shadcnblocks Linear theme is useful for studying a complete semantic theme: soft surfaces, indigo-leaning accents, Inter for display and text, JetBrains Mono for code, and named roles for cards, popovers, inputs, rings, and sidebars. It is a theme reference rather than an official Linear specification, and the site states that it is not officially affiliated with shadcn/ui or Tailwind CSS. [Linear theme](https://www.shadcnblocks.com/theme/linear)

shadcn.io is useful as a reference for treating a design document as a portable contract that can guide people and AI tools. Linear Notes should use that idea carefully: this document can guide future implementation, but it should not replace visual review in the native app or turn taste into rigid generated output. [shadcn.io design-system workflow](https://www.shadcn.io/)

### Linear Notes component direction

| Component family | Design direction |
| --- | --- |
| Buttons | Quiet default and ghost states; one clear primary action; strong focus state |
| Sidebar rows | Composable row with icon, label, pin/bookmark state, selection, and drag target |
| Mode switcher | Segmented control with clear current mode and keyboard access |
| Property pills | Compact semantic badge; readable value; editable without opening a large inspector |
| Popovers | Surface lift, hairline border, short motion, keyboard navigation, no visual spectacle |
| Callouts | Semantic colour role plus calm surface; content remains part of the document flow |
| Rich cards | Document object with selected, opened, unavailable, and deleted states |
| Dialogs | Focused task, explicit cancel/save actions, clear recovery language |
| Empty states | One useful next action and a short explanation |

The goal is a small set of primitives that can compose into the sidebar, editor toolbar, properties, menus, dialogs, and document blocks. Each primitive should have a defined contract before it receives additional visual polish.

## Design mentality

### Make the page the primary place

The document is the centre of the experience. Navigation, formatting controls, properties, and status information should support the page rather than compete with it.

When the user is writing, the page should have the visual weight. When the user is organising, the sidebar should become more useful without making the editor feel distant.

### Reduce decisions while writing

Writing should not require the user to configure a system before they can begin. The first useful action should be obvious: open a note or create one.

Defaults should be sensible and quiet. Advanced controls should appear when they are relevant, through slash commands, contextual menus, keyboard shortcuts, or a small selection toolbar.

### Keep structure visible but soft

Hierarchy should be easy to scan through spacing, typography, indentation, and subtle grouping. Borders, fills, and icons should clarify relationships without making the interface feel boxed in.

The design should prefer a gentle indication over a loud announcement:

- A selected row uses a soft tint rather than a heavy highlight.
- A property uses a compact pill rather than a large panel.
- A callout uses a quiet surface and accent rather than a saturated banner.
- A conflict is visible and actionable without becoming an alarm state.

### Respect the file

The Markdown file is the user’s document. The app is a thoughtful interface around it, not a container that owns it.

The design should make local storage feel understandable. Saving should be quiet, visible, and reliable. Source mode should always remain available. App-specific organisation data should stay separate from the note body.

### Avoid shame and pressure

The app should never imply that the user is behind, disorganised, or using it incorrectly. Empty states, reminders, and recovery flows should be neutral and kind.

There should be no streak pressure, productivity scoring, aggressive nudges, or catch-up language unless deliberately added later as a separate product decision.

## Visual language

### Composition

- Use a restrained two-part layout: navigation on the left, document space on the right.
- Let the editor breathe with a readable maximum width and generous vertical rhythm.
- Keep the top toolbar compact and visually quiet.
- Use alignment and whitespace before adding dividers or containers.
- Keep utility information close to where it is useful: properties near the title, save state near the bottom edge, document modes in the top bar.

### Typography

Typography carries most of the hierarchy.

- Use a native system sans-serif for interface text and document text unless a deliberate reading typeface is introduced later.
- Use weight and scale more often than colour to create hierarchy.
- Keep headings compact, clear, and slightly tight in tracking.
- Keep body text comfortable to read over longer sessions.
- Use monospace only for source, code, keyboard hints, and inline code.
- Avoid excessive all-caps labels, decorative lettering, and text that feels like a dashboard.

Suggested hierarchy:

| Role | Character |
| --- | --- |
| Document title | Largest, confident, compact |
| Section heading | Clear separation without interruption |
| Subheading | Useful for scanning, not visual noise |
| Body text | Comfortable and calm |
| Metadata | Small, muted, secondary |
| Code/source | Monospaced and precise |

### Colour

Colour should establish tone, state, and emphasis.

- The canvas should be neutral and easy on the eyes.
- The sidebar should be subtly distinct from the document canvas.
- The accent colour should be reserved for focus, selection, links, and small moments of action.
- Muted text should remain readable and should not carry essential meaning alone.
- Callout colours should be semantic but restrained.
- Destructive states should be clear without using red as general decoration.

Light and dark appearances should feel like the same product. Dark mode should not be a simple inversion; surfaces, borders, muted text, and callout backgrounds should be tuned for their context.

## Draft foundation tokens

These are working design tokens, not a final locked design system. They provide a vocabulary for future implementation and discussion.

### Accent

The reference material identifies Linear’s lavender-blue as `#5e6ad2`, with a lighter hover around `#828fff`. Linear Notes can use this as a restrained inspiration while allowing the final accent to be tuned for native macOS contrast and personal preference.

| Token | Draft value | Use |
| --- | --- | --- |
| Accent | `#5e6ad2` | Focus, links, selected mode, primary action |
| Accent hover | `#828fff` | Hover and active feedback |
| Accent focus | `#5e69d1` | Focus tint or focus ring support |

### Dark surfaces

The Linear reference analysis uses `#010102` as a near-black canvas with charcoal surfaces from `#0f1011` through `#191a1b`. Linear Notes should test a slightly softer native dark canvas before adopting the deepest values, because documents are read for long periods.

| Token | Reference value | Draft role |
| --- | --- | --- |
| Canvas | `#010102` | Reference dark canvas; test for reading comfort |
| Surface 1 | `#0f1011` | Sidebar or quiet panel |
| Surface 2 | `#141516` | Control group or raised surface |
| Surface 3 | `#18191a` | Popover or selected surface |
| Hairline | `#23252a` | Subtle border |
| Strong hairline | `#34343a` | Focused or clearly bounded control |

The light appearance should use the same semantic roles with a neutral canvas and soft grey surfaces. It should not be designed as a separate visual language.

### Typography

The supplied analysis describes Linear Display, Linear Text, and Linear Mono, with SF Pro Display and Inter-like fallbacks. Linear Notes should prefer native system typography first, then introduce a dedicated display face only if long-document testing shows a meaningful improvement.

| Token | Draft size | Draft weight | Draft tracking |
| --- | ---: | ---: | ---: |
| Document title | 32–40px | 600 | Slightly negative |
| Heading 2 | 22–26px | 600 | Slightly negative |
| Heading 3 | 18–20px | 600 | Near neutral |
| Body | 16–18px | 400 | Neutral |
| Interface | 12–14px | 400–500 | Neutral |
| Caption | 11–12px | 400–500 | Neutral or slightly positive |
| Mono | 12–14px | 400 | Neutral |

The final values should be judged by reading comfort, line length, heading rhythm, and behaviour at larger system text sizes.

### Spacing and radius

Use a 4px base unit as a starting point:

`4 · 8 · 12 · 16 · 24 · 32 · 48`

Use a restrained radius scale:

`4 · 6 · 8 · 12 · 16`

Pills are reserved for compact properties, statuses, and tags. They should not become the default shape for buttons, cards, or navigation.

### Surfaces and borders

- Prefer one or two quiet surface levels over many cards.
- Use thin, low-contrast borders to define controls and editable regions.
- Use rounded corners sparingly and consistently.
- Avoid floating panels unless they support an immediate task.
- Avoid shadows that make the interface feel like a web dashboard.

### Icons

Icons should be simple, familiar, and secondary to labels when a label is useful.

- Use a consistent stroke and optical weight.
- Avoid icons that require interpretation for important actions.
- Use pin, bookmark, folder, note, search, and mode icons consistently across the app.
- Do not use decorative icon clusters to fill empty space.

## Interaction principles

### Direct manipulation

The user should be able to understand what an object is and what will happen before acting on it.

- Click a note to open it.
- Click a folder to expand or collapse it.
- Drag near a row edge to reorder.
- Drop in the middle of a folder to move inside it.
- Right-click for organisation actions.
- Use the keyboard when it is faster.

Drag-and-drop should provide a clear insertion line or destination outline. The interaction should never leave the user guessing whether an item will be reordered or nested.

### Rich link cards

Rich cards should behave as objects inside the document rather than behaving like instantly activated browser links.

1. The first click selects the card.
2. The selected state is visually obvious but restrained.
3. The second click opens the URL.
4. Enter opens a selected card.
5. Delete removes it while editing.
6. Escape moves the cursor back into the document.

The card should always retain a portable Markdown representation.

### Modes

The three document modes should feel like views of the same document:

- **Live Preview:** the primary writing experience; Markdown is rendered while editing.
- **Reading:** a calm, non-editable document view for review and reference.
- **Source:** direct access to the exact Markdown text.

Switching modes should not feel like changing applications. The document position, context, and visual identity should remain stable where possible.

### Feedback

Feedback should be timely, brief, and proportional.

- Saving can be shown as a small status, not a blocking notification.
- Successful actions should usually be visible through the changed interface state.
- Errors should explain what happened and offer the next useful action.
- External-edit conflicts should protect the draft and make the choices understandable.
- Loading should be quiet and should not flash unnecessarily.

### Motion

Motion should help the user understand spatial relationships.

- Sidebar collapse should be smooth and short.
- Selection changes should feel immediate.
- Menus and popovers should appear from their point of relevance.
- Drag targets should respond quickly.
- Avoid decorative motion, bouncing, or delayed transitions.
- Respect Reduce Motion.

## State and hierarchy model

Every important surface should be designed as a set of related states rather than a single screenshot.

### Document states

- Empty: invite one useful next action.
- Reading: reduce controls and protect the document from accidental edits.
- Live editing: expose writing tools without hiding the page.
- Source editing: show the exact Markdown with predictable text-editor behaviour.
- Saving: show quiet progress near the document edge.
- Saved: confirm through a small, stable status.
- External change: protect the draft and explain the recovery choices.
- Missing or moved file: preserve context and make the next action clear.

### Navigation states

- Folder closed or open.
- Note selected or unselected.
- Pinned or ordinary within its parent.
- Bookmarked or absent from bookmarks.
- Search inactive, active, with results, or with no results.
- Dragging with a reorder target or nesting target.
- Sidebar expanded, collapsed, or temporarily needed on a narrow window.

### Hierarchy rules

Use this order when deciding what should attract attention:

1. The current document and the user’s text.
2. The current location and navigation context.
3. The next relevant action.
4. Document properties and status.
5. Secondary organisation and system controls.

When a screen feels busy, reduce secondary chrome before reducing document readability.

## Design review method

The Linear redesign process is useful as a working method as well as a visual reference. Linear Notes should use a small, repeatable loop:

1. Choose one surface or behaviour to improve.
2. Define the states it needs to support.
3. Test the direction in a real document and a compact document.
4. Check light and dark appearances.
5. Check keyboard, pointer, and reduced-motion behaviour.
6. Use the feature in the app for a short period before locking the decision.
7. Record the decision, evidence, and remaining uncertainty below.

The first test cases should include a blank note, a long note, a note with properties, nested folders, a selected rich card, a conflict, and a narrow window. Design quality should be judged through these transitions, not only through the default state.

## Component behaviour language

When documenting a component, describe both its appearance and its behaviour.

```markdown
### Component name

Purpose:

Default state:

Hover state:

Focused state:

Selected state:

Disabled or unavailable state:

Keyboard behaviour:

Pointer behaviour:

Reduced-motion behaviour:

Markdown or file effect:
```

This keeps the design document useful to implementation work without turning it into a copy of any external design system.

## Document content design

### Markdown as a visible contract

The app should render Markdown beautifully while keeping the underlying syntax understandable and portable.

Supported syntax should have a consistent visual treatment between Live Preview and Reading mode. Source mode should never be hidden behind a proprietary representation.

### Callouts and quotes

Callouts are for information that benefits from semantic emphasis: notes, tips, warnings, cautions, and important context.

Quotes are for a distinct voice or thought. They should be visually separate from callouts and use italic text by default.

Both should feel like part of the document flow rather than like external widgets.

### Properties

Frontmatter properties should feel lightweight. Pills are useful as a quick summary and entry point, but the full YAML remains authoritative.

The interface should avoid implying that every YAML value is a fully typed or validated property until that system exists.

### Empty states

Empty states should answer one question: what can I do next?

They should be short, warm, and specific. A first-use empty state can explain that notes remain local and invite the user to choose a folder or create a note. It should not become a product tour.

## Native macOS character

Linear Notes should feel like a Mac application through its behaviour as much as its appearance.

- Use native window behaviour, menus, keyboard shortcuts, file dialogs, Finder actions, and Trash.
- Support light and dark appearance from the system.
- Preserve familiar focus and selection behaviour.
- Make text editing feel at home on macOS.
- Keep files accessible through Finder and other editors.
- Prefer system conventions when they improve clarity, while retaining the product’s visual calm.

The future iOS version should share the same design principles and document model while adapting navigation, editing controls, and gestures to the platform rather than shrinking the Mac layout.

## Accessibility and inclusion

Accessibility is part of the design character, not a finishing layer.

- Every important action needs a meaningful label.
- Keyboard navigation should cover the sidebar, document modes, menus, dialogs, and editor actions.
- Focus should be visible in both appearances.
- Colour should not be the only way to communicate state.
- Text should remain readable at larger sizes.
- Reduced motion should be respected.
- Reading mode should provide a clear, low-distraction experience.
- Error messages should describe recovery in plain language.

## Boundaries

The design should avoid:

- A crowded productivity dashboard.
- Excessive cards, gradients, or decorative glass effects.
- Hidden state that requires guesswork.
- Aggressive onboarding.
- Unrequested cloud or account concepts in the local-first experience.
- A visual clone of Linear that could be mistaken for Linear.
- Proprietary document behaviours that make Markdown less portable.

## Working design questions

These questions remain open until deliberately decided:

- Should the document title be editable separately from the first H1, or should the first H1 remain the title?
- Should the sidebar support an outline view for headings in the current document?
- Should rich cards eventually fetch metadata locally, and how should privacy be communicated?
- How should images appear when they are local, remote, or unavailable?
- Should callouts support collapsing in Live Preview and Reading mode?
- Should properties gain typed controls for dates, statuses, and tags?
- Should the app include a command palette in v1.1?
- Which parts of the design need a dedicated iOS adaptation rather than shared styling?

## Design decision log

Use this section for decisions that affect the product’s design language.

### Decision template

```markdown
#### YYYY-MM-DD — Decision title

**Decision:**

**Reason:**

**Affected surfaces:**

**Open follow-up:**
```

### Current decisions

#### 2026-09-07 — Page-primary chrome and local previews

**Decision:** The editor keeps page-primary chrome by removing the persistent formatting bar in favour of contextual selection controls. Rich-card previews are fetched locally at insert time with explicit privacy copy, cached outside Markdown, and limited to HTTPS. Callout folds work in Live Preview and Reading mode, `data:` image URLs can render from cached previews, and the interface should adapt Linear-inspired hierarchy without adopting Linear marketing tokens.

**Reason:** Writing should keep visual weight on the document while still exposing formatting at the moment of selection. Preview lookup must stay understandable in a local-first app, and cached metadata should never make note files less portable. Folded callouts are document state users can see in both writing and reading contexts, while the visual language should remain Linear Notes' own native product system rather than a copy of Linear's brand surface.

**Affected surfaces:** Editor chrome, selection popover, slash commands, rich-card insertion, preview cache, link dialog privacy copy, callout rendering, Live Preview, Reading mode, and design tokens.

**Open follow-up:** Decide whether stale previews need manual refresh, whether blocked preview lookups should expose a retry affordance, and how far image preview support should extend beyond cached HTTPS metadata.

#### 2026-09-06 — Calm local-first document workspace

**Decision:** The page is primary, Markdown remains portable, and the interface uses restrained hierarchy instead of dashboard density.

**Reason:** The product is intended for sustained writing and reference, not task surveillance or gamified productivity.

**Affected surfaces:** Window layout, typography, sidebar, editor modes, properties, saving feedback, and empty states.

**Open follow-up:** Confirm the final type scale, accent colour, and title treatment through continued use.

## Reference notes

The official Linear redesign article was used for process and hierarchy principles: neutral colour treatment, stronger content contrast, shared light/dark theme generation, structured layouts, explicit behaviour definitions, stress testing, and dogfooding before broad rollout.

The supplied Linear design analysis and the VoltAgent `DESIGN.md` were used for the draft vocabulary around a near-black canvas, charcoal surface ladder, lavender accent, hairline borders, negative display tracking, 4px spacing, and compact radius values. Those values remain references until they are tested in the native notes workflow.

The Figma community file was used as a visual reference target for layout relationships and component states. No proprietary assets or implementation code were copied from it. Screen-specific decisions should be checked against the actual file and the needs of a local Markdown app before being adopted.

The downloaded files `DESIGN-linear.app.md` and `linear.design.md` were treated as supplied reference documents. Their embedded descriptions, tokens, and recommendations informed the comparisons above; their contents were not treated as instructions to change Linear Notes’ scope or identity.
