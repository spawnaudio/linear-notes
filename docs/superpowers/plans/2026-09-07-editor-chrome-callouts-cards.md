# Editor chrome, callout folds, and card previews Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the sticky editor format bar in favour of a full selection popover and Space-dismissing slash menu; honor callout fold markers in Live and Reading; show cached Open Graph title/summary/image on rich cards without putting that data in Markdown.

**Architecture:** Editor behaviour lives in `Editor/src` (Tiptap) and is copied into `Sources/LinearNotes/Resources/Editor` via `npm run build`. Preview HTML parsing and `.linear-notes/` cache live in Foundation `NotesCore`. Native `EditorBridge` fetches HTTPS pages on insert only and injects `data:` images into the web view, which never performs network I/O (`connect-src 'none'`).

**Tech Stack:** Swift 6 / NotesCore / WKWebView, Tiptap 3, Playwright, `URLSession`.

**Spec:** `docs/superpowers/specs/2026-09-07-editor-chrome-callouts-cards-design.md`

## Global Constraints

- Markdown remains `[Title](<https://url> "card")`; previews never enter the note body.
- Preview files live under `.linear-notes/` next to `sidebar.json`. Do not use `NoteLibrary.url(for:)` for those paths (it rejects dotted components).
- WKWebView file access stays the bundled Editor folder. Card images are `data:` URLs, never remote `https` images.
- `connect-src 'none'` stays. Fetch only on Rich card insert, HTTPS only, 5s HTML timeout, 5s image timeout, image ≤ 2 MB.
- Native Live / Reading / Source control stays in the Mac window. Only `#formatbar` is removed.
- Popovers and selected cards: hairline + accent ring, no drop shadow, no accent fill.
- Space dismisses slash without executing; the space character is inserted.
- Do not implement Linear OAuth, command palette, local note images, or preview refresh.
- After `Editor/src` changes: `cd Editor && npm test && npm run build`.
- After Swift changes: `bash scripts/test.sh`.

## File map

| File | Role |
| --- | --- |
| `Editor/src/index.html` | Remove `#formatbar`; expand `#bubble`; `#turn-into` menu; privacy copy in link dialog |
| `Editor/src/editor.css` | Popover/card/callout fold styles; drop selected-card box-shadow |
| `Editor/src/editor.js` | Slash Space; bubble commands; callout fold UI; `previews` + `applyCardPreview` |
| `Editor/tests/editor.spec.js` | Playwright coverage |
| `Sources/NotesCore/LinkPreview.swift` | URL normalize, HTML parse, cache index |
| `Sources/NotesCore/Library.swift` | Read/write preview cache beside sidebar |
| `Tests/NotesCoreTests/LinkPreviewTests.swift` | Parser + cache tests |
| `Sources/LinearNotes/LinkPreviewFetcher.swift` | `URLSession` fetch |
| `Sources/LinearNotes/EditorView.swift` | `fetchCardPreview` + `previews` on load |
| `docs/Linear Notes MVP - Changelog.md` | 0.1.x entry |
| `README.md` | Boundaries and shortcuts chrome |
| `docs/Linear Notes - Design Documentation.md` | Decision log |

---

### Task 1: Selection popover and slash Space

**Files:**
- Modify: `Editor/src/index.html`
- Modify: `Editor/src/editor.css` (popover + `#formatbar` rules)
- Modify: `Editor/src/editor.js`
- Test: `Editor/tests/editor.spec.js`

**Interfaces:**
- Consumes: existing `execute`, `updateSlash`, `updateBubble`, `slashCommands`
- Produces: no `#formatbar`; `#bubble` contains Turn into + marks + lists/quote; `#turn-into` list of `text`, `h1`–`h4`; slash filter `/^\/(\w*)$/`; Space in `handleKeyDown` when `#slash` is open calls `hideSlash()` and returns `false`

- [ ] **Step 1: Write the failing tests**

Append to `Editor/tests/editor.spec.js`:

```javascript
test('has no persistent format bar and formats from the selection popover', async ({ page }) => {
  await load(page, '# Hello world\n\n');
  await expect(page.locator('#formatbar')).toHaveCount(0);
  await page.locator('.tiptap h1').click();
  await page.keyboard.press('Meta+a');
  await expect(page.locator('#bubble')).toBeVisible();
  await page.locator('#bubble [data-command=bold]').click();
  expect(await markdown(page)).toContain('**Hello world**');
});

test('slash Space dismisses without inserting a command', async ({ page }) => {
  await load(page, '');
  await page.locator('.tiptap').click();
  await page.keyboard.type('/call');
  await expect(page.locator('#slash')).toBeVisible();
  await page.keyboard.press('Space');
  await expect(page.locator('#slash')).toBeHidden();
  expect(await markdown(page)).toMatch(/\/call /);
  await expect(page.locator('.callout')).toHaveCount(0);
});

test('slash Escape leaves the query', async ({ page }) => {
  await load(page, '');
  await page.locator('.tiptap').click();
  await page.keyboard.type('/call');
  await page.keyboard.press('Escape');
  await expect(page.locator('#slash')).toBeHidden();
  expect(await markdown(page)).toContain('/call');
});

test('link dialog explains local preview lookup', async ({ page }) => {
  await load(page, '');
  await page.evaluate(() => window.notes.command('link'));
  await expect(page.locator('#link-dialog')).toContainText('on your Mac');
  await expect(page.locator('#link-dialog')).toContainText('Nothing is sent to a Linear Notes server');
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Editor && npm test -- tests/editor.spec.js`

Expected: FAIL — `#formatbar` still exists; Space keeps slash open (filter includes spaces).

- [ ] **Step 3: Implement chrome**

In `Editor/src/index.html`:

- Delete the entire `#formatbar` block (lines 11–24).
- Replace `#bubble` with:

```html
<div id="bubble" class="popover" role="toolbar" aria-label="Selection formatting" hidden>
  <button type="button" id="turn-into-btn" title="Turn into">Text <span class="down">⌄</span></button>
  <span class="separator"></span>
  <button data-command="bold" title="Bold · ⌘B"><b>B</b></button>
  <button data-command="italic" title="Italic · ⌘I"><i>I</i></button>
  <button data-command="strike" title="Strikethrough · ⌘⇧S"><s>S</s></button>
  <button data-command="code" title="Inline code · ⌘E">‹›</button>
  <button data-command="link" title="Link · ⌘K">↗</button>
  <span class="separator"></span>
  <button data-command="bullet" title="Bullet list · ⌘⇧8">☷</button>
  <button data-command="task" title="Checklist · ⌘⇧7">☑</button>
  <button data-command="quote" title="Quote">❞</button>
</div>
<div id="turn-into" class="popover" role="menu" aria-label="Turn into" hidden>
  <button data-command="text" role="menuitem">Text</button>
  <button data-command="h1" role="menuitem">Heading 1</button>
  <button data-command="h2" role="menuitem">Heading 2</button>
  <button data-command="h3" role="menuitem">Heading 3</button>
  <button data-command="h4" role="menuitem">Heading 4</button>
</div>
```

- In `#link-dialog`, after the existing `<p>`, add:

```html
<p class="dialog-privacy">Linear Notes looks up a title, summary, and image for this page on your Mac. Nothing is sent to a Linear Notes server.</p>
```

In `Editor/src/editor.js`:

- `applyMode`: delete `$('formatbar').style.visibility = ...`. Guard any remaining `$('formatbar')` access.
- `updateSlash` match: `const match = /^\/(\w*)$/.exec(before);`
- In `handleKeyDown`, before Arrow handling:

```javascript
if (!$('slash').hidden && event.key === ' ') { hideSlash(); return false; }
```

- `updateBubble`: after positioning, set `#turn-into-btn` label from current heading/paragraph; toggle `.active` on mark/list buttons via `editor.isActive(...)`.
- `#turn-into-btn` mousedown: preventDefault, toggle `#turn-into` under the button. Hide `#turn-into` whenever bubble hides.
- Change `execute('paragraph')` so it no longer opens a mini slash. Keep `case 'text': return chain.setParagraph().run();`
- Click-away: `if (!e.target.closest('#slash') && !e.target.closest('#bubble') && !e.target.closest('#turn-into')) { hideSlash(); $('turn-into').hidden = true; }`

In `Editor/src/editor.css`:

- Remove `#formatbar` rules (or leave unused selectors deleted).
- `#page` does not need a 43px offset for a missing bar.
- `.popover`: `background: var(--bg); border: 1px solid var(--line); border-radius: 9px;` — **no `box-shadow`**.
- `#bubble .separator` reuse `.separator`.
- `#turn-into` same popover language; stacked buttons.

- [ ] **Step 4: Build editor bundle and run tests**

Run:

```sh
cd Editor && npm test && npm run build
```

Expected: new tests PASS; existing 14 tests still PASS. `Sources/LinearNotes/Resources/Editor/` updated.

- [ ] **Step 5: Commit**

```bash
git add Editor/src/index.html Editor/src/editor.css Editor/src/editor.js Editor/tests/editor.spec.js Sources/LinearNotes/Resources/Editor
git commit -m "feat: move formatting to the selection popover"
```

---

### Task 2: Callout folds

**Files:**
- Modify: `Editor/src/editor.js` (`Callout` node)
- Modify: `Editor/src/editor.css`
- Test: `Editor/tests/editor.spec.js`

**Interfaces:**
- Consumes: existing `attrs.fold` (`''` | `'+'` | `'-'`) already parsed/serialized
- Produces: heading button toggles fold; collapsed hides `.callout-content`; first collapse writes `-`; expand after toggle writes `+`; unmarked expanded callouts stay unmarked until toggled

- [ ] **Step 1: Write the failing tests**

```javascript
test('callout fold markers round-trip and the heading toggles collapse', async ({ page }) => {
  await load(page, '> [!TIP]-\n> Hidden body\n');
  await expect(page.locator('.callout-content')).toBeHidden();
  await page.locator('.callout-heading').click();
  await expect(page.locator('.callout-content')).toBeVisible();
  expect(await markdown(page)).toContain('> [!TIP]+');
  await page.locator('.callout-heading').click();
  expect(await markdown(page)).toContain('> [!TIP]-');
});

test('new slash callouts stay unmarked until folded', async ({ page }) => {
  await load(page, '');
  await page.locator('.tiptap').click();
  await page.keyboard.type('/callout');
  await page.keyboard.press('Enter');
  expect(await markdown(page)).toMatch(/> \[!NOTE\]\n/);
  await page.locator('.callout-heading').click();
  expect(await markdown(page)).toContain('> [!NOTE]-');
});

test('reading mode can fold a callout without editing the body', async ({ page }) => {
  await load(page, '> [!NOTE]\n> Keep\n', 'reading');
  await page.locator('.callout-heading').click();
  expect(await markdown(page)).toContain('> [!NOTE]-');
  expect(await markdown(page)).toContain('> Keep');
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Editor && npm test -- tests/editor.spec.js`

Expected: FAIL — content always visible; click heading does nothing.

- [ ] **Step 3: Implement fold UI**

`renderHTML` / `addNodeView` for Callout:

- Root `aside.callout` with `data-kind` and `data-fold`.
- Heading is a `button.callout-heading` (`contenteditable="false"`) containing chevron + title. `type="button"`.
- Click heading: `ed.commands.updateAttributes('callout', { fold: node.attrs.fold === '-' ? '+' : '-' })`.
- Keyboard: Enter/Space on heading toggles (button default).
- CSS: `.callout[data-fold="-"] .callout-content { display: none; }`
- Chevron via CSS `::after` or a `span.callout-chevron`; no motion when `prefers-reduced-motion`.
- `renderMarkdown` already emits `${node.attrs.fold || ''}`.

Do not use `addNodeView` if `updateAttributes` + `renderHTML` with a heading plugin is enough. If ProseMirror eats button clicks, use `addNodeView` mirroring `RichLink` (`stopEvent` for the heading only, contentDOM for `.callout-content`).

Preferred: `addNodeView` with `contentDOM` = `.callout-content`, heading handled in the view.

```javascript
addNodeView() {
  return ({ node, editor: ed, getPos }) => {
    const dom = document.createElement('aside');
    dom.className = 'callout';
    dom.dataset.kind = node.attrs.kind;
    if (node.attrs.fold) dom.dataset.fold = node.attrs.fold;
    const heading = document.createElement('button');
    heading.type = 'button';
    heading.className = 'callout-heading';
    heading.textContent = node.attrs.title || node.attrs.kind.charAt(0).toUpperCase() + node.attrs.kind.slice(1);
    const content = document.createElement('div');
    content.className = 'callout-content';
    heading.addEventListener('mousedown', e => e.preventDefault());
    heading.addEventListener('click', e => {
      e.preventDefault(); e.stopPropagation();
      const pos = getPos(); if (typeof pos !== 'number') return;
      const fold = (ed.state.doc.nodeAt(pos)?.attrs.fold === '-') ? '+' : '-';
      ed.chain().command(({ tr }) => { tr.setNodeMarkup(pos, undefined, { ...node.attrs, fold }); return true; }).run();
    });
    dom.append(heading, content);
    return {
      dom, contentDOM: content,
      update: updated => {
        if (updated.type !== node.type) return false;
        node = updated;
        dom.dataset.kind = updated.attrs.kind;
        if (updated.attrs.fold) dom.dataset.fold = updated.attrs.fold; else delete dom.dataset.fold;
        heading.textContent = updated.attrs.title || updated.attrs.kind.charAt(0).toUpperCase() + updated.attrs.kind.slice(1);
        return true;
      }
    };
  };
}
```

- [ ] **Step 4: Run tests and build**

```sh
cd Editor && npm test && npm run build
```

Expected: PASS including new fold tests and existing callout round-trip.

- [ ] **Step 5: Commit**

```bash
git add Editor/src/editor.js Editor/src/editor.css Editor/tests/editor.spec.js Sources/LinearNotes/Resources/Editor
git commit -m "feat: fold callouts from the heading"
```

---

### Task 3: Preview parse and cache in NotesCore

**Files:**
- Create: `Sources/NotesCore/LinkPreview.swift`
- Modify: `Sources/NotesCore/Library.swift`
- Create: `Tests/NotesCoreTests/LinkPreviewTests.swift`

**Interfaces:**
- Produces:

```swift
public struct LinkPreview: Codable, Equatable, Sendable {
    public var title: String
    public var description: String
    public var imageURL: String?
    public var imageFile: String?
    public var fetchedAt: Date
}

public enum LinkPreviewing {
    public static func normalizeURL(_ string: String) -> URL?
    public static func parseHTML(_ html: String, pageURL: URL) -> (title: String, description: String, imageURL: URL?)
    public static func fileName(for url: URL) -> String
}

extension NoteLibrary {
    public func preview(for url: URL) -> LinkPreview?
    public func savePreview(_ preview: LinkPreview, for url: URL, imageData: Data?, type: String?) throws
    public func previewImageData(for url: URL) -> Data?
}
```

`normalizeURL`: require `http`/`https`; reject other schemes; drop fragment; lowercase host; keep path/query.

`parseHTML`: first `og:title` else `<title>`; `og:description` else `twitter:description`; `og:image` else `twitter:image`, resolved against `pageURL`. Prefer case-insensitive meta `property`/`name`/`content`.

`fileName`: hex prefix of SHA256 of normalized URL absoluteString + a safe extension from image type (`jpg`/`png`/`webp`/`gif`) stored under `previews/`.

`savePreview` writes `.linear-notes/link-previews.json` as `{ "version": 1, "items": { "<normalized URL>": LinkPreview } }` using the same directory creation as `saveSidebar()`. Image bytes go to `.linear-notes/previews/<fileName>`. JSON dates: ISO-8601.

- [ ] **Step 1: Write the failing tests**

`Tests/NotesCoreTests/LinkPreviewTests.swift`:

```swift
import XCTest
@testable import NotesCore

final class LinkPreviewTests: XCTestCase {
    func testNormalizeRejectsJavascriptAndKeepsHTTPS() {
        XCTAssertNil(LinkPreviewing.normalizeURL("javascript:alert(1)"))
        XCTAssertEqual(LinkPreviewing.normalizeURL("HTTPS://WWW.Example.com/a/?q=1#frag")?.absoluteString, "https://www.example.com/a/?q=1")
    }

    func testParseOpenGraphAndResolveRelativeImage() {
        let html = """
        <html><head>
        <title>Fallback</title>
        <meta property="og:title" content="mymind is the extension for your mind.">
        <meta property="og:description" content="A private place to save notes.">
        <meta property="og:image" content="/og.png">
        </head></html>
        """
        let page = URL(string: "https://mymind.com/page")!
        let parsed = LinkPreviewing.parseHTML(html, pageURL: page)
        XCTAssertEqual(parsed.title, "mymind is the extension for your mind.")
        XCTAssertEqual(parsed.description, "A private place to save notes.")
        XCTAssertEqual(parsed.imageURL?.absoluteString, "https://mymind.com/og.png")
    }

    func testCacheRoundTripDoesNotTouchMarkdown() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try NoteLibrary(root: root)
        let note = try library.create(name: "Note", content: "# Hi\n")
        let url = URL(string: "https://example.com/a")!
        var preview = LinkPreview(title: "Example", description: "Hello", imageURL: "https://cdn.example/a.png", imageFile: nil, fetchedAt: Date(timeIntervalSince1970: 1))
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10])
        try library.savePreview(preview, for: url, imageData: png, type: "image/png")
        XCTAssertEqual(try library.read(note), "# Hi\n")
        let stored = try XCTUnwrap(library.preview(for: url))
        XCTAssertEqual(stored.title, "Example")
        XCTAssertEqual(stored.description, "Hello")
        XCTAssertEqual(library.previewImageData(for: url)?.prefix(4), png.prefix(4))
        XCTAssertEqual(try NoteLibrary(root: root).preview(for: url)?.title, "Example")
    }

    func testMissingPreviewIsNil() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNil(try NoteLibrary(root: root).preview(for: URL(string: "https://example.com")!))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash scripts/test.sh`

Expected: FAIL — `LinkPreviewing` not found.

- [ ] **Step 3: Implement `LinkPreview.swift` and library methods**

Keep HTML parsing string-based (no WebKit in NotesCore). Meta extraction: scan `<meta ...>` tags for `property`/`name` of `og:title`, `og:description`, `twitter:description`, `og:image`, `twitter:image`. Unescape `&amp;` `&quot;` `&#39;` in content.

Load existing index on `NoteLibrary.init` (optional `previews` property) or read from disk on each call — read-from-disk is simpler and matches `sidebar.json` already loaded in init. Add `var linkPreviews: [String: LinkPreview]` loaded from `.linear-notes/link-previews.json` if present; decode failures yield empty dictionary (do not throw from init beyond current behaviour).

- [ ] **Step 4: Run tests**

Run: `bash scripts/test.sh`

Expected: PASS (existing 8 + new preview tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/NotesCore/LinkPreview.swift Sources/NotesCore/Library.swift Tests/NotesCoreTests/LinkPreviewTests.swift
git commit -m "feat: cache rich-card previews beside sidebar metadata"
```

---

### Task 4: Editor card preview UI

**Files:**
- Modify: `Editor/src/editor.js` (`RichLink`, `loadDocument`)
- Modify: `Editor/src/editor.css`
- Test: `Editor/tests/editor.spec.js`

**Interfaces:**
- Consumes: `load({ id, markdown, mode, previews })` where `previews` is `{ [url]: { title, description, imageSrc } }`
- Produces: `window.notes.applyCardPreview({ url, title, description, imageSrc })`; `send('fetchCardPreview', { url })` after inserting a card; markdown serializer still only title+url+`"card"`
- Node attrs: `url`, `title`, `description` (default `''`), `imageSrc` (default `''`) — **not** written to Markdown

- [ ] **Step 1: Write the failing tests**

Use a 1×1 PNG data URL:

```javascript
const pixel = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

test('cached previews hydrate without fetching', async ({ page }) => {
  await page.goto(editorURL);
  await page.waitForFunction(() => window.notes);
  await page.evaluate(({ pixel }) => {
    window.messages = [];
    window.webkit = { messageHandlers: { notes: { postMessage: message => window.messages.push(message) } } };
    window.notes.load({
      id: 'test.md',
      markdown: '[mymind](<https://mymind.com> "card")\n',
      mode: 'live',
      previews: {
        'https://mymind.com/': {
          title: 'mymind is the extension for your mind.',
          description: 'A private place to save your most precious notes.',
          imageSrc: pixel
        }
      }
    });
  }, { pixel });
  await expect(page.locator('.rich-card')).toHaveClass(/has-preview/);
  await expect(page.locator('.card-title')).toHaveText('mymind is the extension for your mind.');
  await expect(page.locator('.card-description')).toContainText('A private place');
  await expect(page.locator('.rich-card img')).toHaveAttribute('src', pixel);
  expect(await page.evaluate(() => window.messages.filter(m => m.type === 'fetchCardPreview'))).toHaveLength(0);
  expect(await markdown(page)).toContain('[mymind](<https://mymind.com> "card")');
});

test('applyCardPreview upgrades a compact card and failed images stay compact', async ({ page }) => {
  await load(page, '[Example](<https://example.com/path> "card")\n');
  await expect(page.locator('.rich-card')).not.toHaveClass(/has-preview/);
  await page.evaluate(() => window.notes.applyCardPreview({
    url: 'https://example.com/path',
    title: 'Example',
    description: 'Hello there from the page.',
    imageSrc: ''
  }));
  await expect(page.locator('.card-description')).toHaveText('Hello there from the page.');
  await expect(page.locator('.rich-card img')).toHaveCount(0);
});
```

Adjust the `previews` key to whatever `normalizeURL` produces (`https://mymind.com` vs trailing slash). The editor should match cards by comparing `new URL(node.attrs.url).href` to keys, not require the caller to guess slash variants — native will send the normalized key; JS should apply when `URL` href matches after stripping trailing slash except root. Simplest: apply when `node.attrs.url` equals payload url OR both normalize equal in JS (`new URL`).

Also assert inserting via the dialog sends `fetchCardPreview`:

```javascript
test('inserting a rich card requests a native preview', async ({ page }) => {
  await load(page, '');
  await page.evaluate(() => window.notes.command('link'));
  await page.locator('#link-url').fill('https://example.com/path');
  await page.locator('#link-title').fill('Example');
  await page.getByRole('button', { name: 'Rich card', exact: true }).click();
  expect(await page.evaluate(() => window.messages.filter(m => m.type === 'fetchCardPreview'))).toEqual([
    { type: 'fetchCardPreview', url: 'https://example.com/path' }
  ]);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: FAIL — `applyCardPreview` missing; no `.card-description`.

- [ ] **Step 3: Implement node view layout**

Compact (no description and no imageSrc): existing icon + title + host + arrow.

Preview (`description` or `imageSrc`): `.rich-card.has-preview` — text column (`.card-title`, `.card-description` two-line clamp, `.card-domain` as `https://hostname` without `www.`), optional `<img alt="">` on the right (`object-fit: cover`). No broken `img` if `imageSrc` is empty.

Selected: `box-shadow: none; border-color: var(--accent); outline: 2px solid color-mix(in srgb, var(--accent) 35%, transparent);` — no lavender fill.

`loadDocument`: store `previews` map; when creating the editor, pass attrs into cards via a post-parse walk or `applyCardPreview` for each entry. Easiest: after `makeEditor`, call `applyCardPreview` for each preview.

`applyCardPreview`: walk `doc.descendants`; for `richLink` with matching URL, `setNodeMarkup` with new attrs (keep user title if it is not empty and not equal to hostname/url). **Do not** `notifyChange` if markdown is unchanged (attrs are not serialized).

Insert path (`link-dialog` card branch): after insert, `send('fetchCardPreview', { url })`.

User title rule: if dialog title is non-empty, keep it even when OG title arrives.

- [ ] **Step 4: `npm test && npm run build`**

Expected: PASS. Two-click tests still pass.

- [ ] **Step 5: Commit**

```bash
git add Editor/src/editor.js Editor/src/editor.css Editor/tests/editor.spec.js Sources/LinearNotes/Resources/Editor
git commit -m "feat: render cached rich-card summaries and images"
```

---

### Task 5: Native fetch and bridge

**Files:**
- Create: `Sources/LinearNotes/LinkPreviewFetcher.swift`
- Modify: `Sources/LinearNotes/EditorView.swift`
- Modify: `Sources/LinearNotes/NotebookStore.swift` if the selected library root is needed on the bridge (read `NotebookStore` for `library` / `root`)

**Interfaces:**
- Consumes: `NoteLibrary.preview(for:)`, `savePreview`, `previewImageData`; `LinkPreviewing.parseHTML`
- Produces: `EditorBridge` handles `fetchCardPreview`; `update()` load payload includes `previews` dict of `{ title, description, imageSrc }` with `imageSrc` a `data:` URL (`data:image/png;base64,...`) from cached bytes
- `LinkPreviewFetcher.fetch(url: URL) async -> (title: String, description: String, imageURL: URL?, imageData: Data?, type: String?)`  
  - `URLSession` with 5s `timeoutIntervalForRequest`  
  - GET HTML; if `Content-Type` is not HTML/text, return empty  
  - Do not apply HTML if the **final** response URL host+scheme differs from the request (redirect off-origin). Image URL may be another https host  
  - Image GET 5s, accept `image/*`, `count <= 2_000_000`  
  - User-Agent: `LinearNotes/0.1 (link-preview)`

- [ ] **Step 1: Inspect `NotebookStore` and wire `library` onto the bridge**

Read `Sources/LinearNotes/NotebookStore.swift`. The bridge must call `store.library` (or equivalent) for cache + root.

- [ ] **Step 2: Implement fetcher + message handler**

`didReceive` add:

```swift
case "fetchCardPreview":
    if let raw = data["url"] as? String { Task { await self.fetchCardPreview(raw) } }
```

`fetchCardPreview`:

1. `guard let url = LinkPreviewing.normalizeURL(raw) else { return }`
2. If cache exists, `apply` immediately (still OK to skip refetch — spec is fetch on insert; cache hit can apply without network).
3. Else `try await fetcher.fetch`; `try library.savePreview`; `apply`.
4. Failures: do nothing (compact card). Do not set `store.error` for a failed preview.

`apply`: `webView.callAsyncJavaScript("window.notes.applyCardPreview(payload)", arguments: ["payload": ["url": url.absoluteString, "title": title, "description": description, "imageSrc": dataURL]])`

`dataURL`: `"data:\(mime);base64," + data.base64EncodedString()`

`update()` payload:

```swift
var payload: [String: Any] = ["id": store.selected ?? "", "markdown": store.markdown, "mode": store.mode.rawValue]
payload["previews"] = store.cardPreviewsJSON()
```

`cardPreviewsJSON()`: for every `https` URL you can cheaply collect — **do not parse the whole note on the Swift side if avoidable**. Simpler: pass the entire `library` preview index converted to data URLs (keyed by normalized URL). Editor matches by URL. Fine for this slice (no eviction).

- [ ] **Step 3: No Swift UI test for live HTTP**

Parser/cache already tested. Optionally add a NotesCore test that `javascript:` never normalizes (already in Task 3).

- [ ] **Step 4: `bash scripts/test.sh`**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/LinearNotes/LinkPreviewFetcher.swift Sources/LinearNotes/EditorView.swift Sources/LinearNotes/NotebookStore.swift
git commit -m "feat: fetch rich-card previews on insert"
```

---

### Task 6: Product docs

**Files:**
- Modify: `docs/Linear Notes MVP - Changelog.md`
- Modify: `README.md`
- Modify: `docs/Linear Notes - Design Documentation.md` (decision log)
- Modify: `docs/VALIDATION.md` (test counts)

**Interfaces:** none.

- [ ] **Step 1: Changelog entry** using the template: Added chrome move, callout folds, insert-time local preview cache; privacy sentence; Limits (stale previews, blocked UA, no refresh).

- [ ] **Step 2: README** — “Included in v0.1” no longer claims a persistent formatting toolbar; mention selection popover; MVP boundaries: previews fetch on insert and cache locally; callouts can fold.

- [ ] **Step 3: Design decision log** (2026-09-07): page-primary chrome; local insert-time preview with privacy copy; folds in Live+Reading; data URLs; not Linear marketing tokens.

- [ ] **Step 4: VALIDATION.md** — update automated test counts to match `npm test` and `swift test`.

- [ ] **Step 5: Commit**

```bash
git add docs/Linear\ Notes\ MVP\ -\ Changelog.md README.md docs/Linear\ Notes\ -\ Design\ Documentation.md docs/VALIDATION.md
git commit -m "docs: record editor chrome, folds, and card previews"
```

---

## Manual check (after Task 5)

- Build with `bash scripts/build.sh`.
- Open a note, select a word: bubble only, no top format bar.
- Type `/` then Space: menu closes, `/ ` remains.
- Fold a callout; Source shows `-`.
- Paste `https://example.com`, choose Rich card: compact then preview or stays compact; file stays `[…]( "card")`.
- Light and dark; Reduce Motion.
- Native mode switcher still works.

## Spec coverage

| Spec | Task |
| --- | --- |
| Remove `#formatbar`; full bubble; Turn into H1–4 | 1 |
| Slash Space / filter / Escape | 1 |
| Privacy copy | 1 |
| Popover hairline, no shadow | 1, 4 |
| Callout fold UI + markdown | 2 |
| NotesCore cache + dotted-path rule | 3 |
| Card states, `data:` images, load hydrates | 4 |
| Fetch on insert, HTTPS, timeouts, no webview network | 5 |
| Changelog / README / decision log | 6 |
