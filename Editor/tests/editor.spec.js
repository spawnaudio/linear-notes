import { test, expect } from '@playwright/test';
import { resolve } from 'node:path';

const editorURL = `file://${resolve('../Sources/LinearNotes/Resources/Editor/index.html')}`;
async function load(page, markdown, mode = 'live') {
  await page.goto(editorURL);
  await page.waitForFunction(() => window.notes);
  await page.evaluate(({ markdown, mode }) => {
    window.messages = [];
    window.webkit = { messageHandlers: { notes: { postMessage: message => window.messages.push(message) } } };
    window.notes.load({ id: 'test.md', markdown, mode });
  }, { markdown, mode });
}
const markdown = page => page.evaluate(() => window.notes.getMarkdown());
const json = page => page.evaluate(() => window.notes.getJSON());
const fixture = `---
status: Draft
tags: [ideas, writing]
extra:
  nested: preserved
---
# A little room to think

This is **bold**, *italic*, ~~struck~~, and \`code\`.

## Section

### Detail

#### Small heading

> [!NOTE] Remember this
> A **useful** callout.
>
> A second paragraph.

> A quiet quote.

[Linear documents](<https://linear.app/docs/documents> "card")

- [ ] Write something
- [x] Make space

| A | B |
| --- | --- |
| One | Two |

\`\`\`swift
let note = "hello"
\`\`\`
`;

test('renders supported Markdown and does not rewrite on mode switches', async ({ page }) => {
  await load(page, fixture);
  await expect(page.locator('.tiptap h1')).toHaveText('A little room to think');
  await expect(page.locator('.callout')).toContainText('Remember this');
  await expect(page.locator('.callout strong')).toHaveText('useful');
  await expect(page.locator('blockquote')).toHaveCSS('font-style', 'italic');
  await expect(page.locator('.rich-card')).toHaveCount(1);
  await expect(page.locator('.property')).toHaveCount(3);
  await expect(page.locator('table')).toHaveCount(1);
  await expect(page.locator('[data-type=taskItem]')).toHaveCount(2);
  for (const mode of ['reading', 'source', 'live']) await page.evaluate(mode => window.notes.setMode(mode), mode);
  expect(await markdown(page)).toBe(fixture);
  expect(await page.evaluate(() => window.messages.filter(m => m.type === 'change'))).toHaveLength(0);
});

test('editing round-trips callouts, quotes, cards, frontmatter, tasks and tables', async ({ page }) => {
  await load(page, fixture);
  await page.locator('.tiptap h1').click();
  await page.keyboard.press('End'); await page.keyboard.type(' today');
  const output = await markdown(page);
  expect(output).toContain('extra:\n  nested: preserved');
  expect(output).toContain('> [!NOTE] Remember this');
  expect(output).toContain('> A **useful** callout.');
  expect(output).toContain('> A second paragraph.');
  expect(output).toContain('> A quiet quote.');
  expect(output).toContain('[Linear documents](<https://linear.app/docs/documents> "card")');
  expect(output).toContain('- [x] Make space');
  expect(output).toContain('```swift');
  await load(page, output);
  await expect(page.locator('.callout')).toContainText('A second paragraph.');
  await expect(page.locator('.rich-card')).toHaveCount(1);
  await expect(page.locator('table')).toHaveCount(1);
});

test('a rich card selects on the first click and opens on the second', async ({ page }) => {
  await load(page, fixture);
  const card = page.locator('.rich-card');
  await card.click(); await expect(card).toHaveClass(/selected/);
  expect(await page.evaluate(() => window.messages.filter(m => m.type === 'openLink'))).toHaveLength(0);
  expect(await markdown(page)).toBe(fixture);
  await card.click();
  expect(await page.evaluate(() => window.messages.filter(m => m.type === 'openLink'))).toEqual([{ type: 'openLink', url: 'https://linear.app/docs/documents' }]);
  await page.locator('.tiptap h1').click();
  await card.click();
  expect(await page.evaluate(() => window.messages.filter(m => m.type === 'openLink'))).toHaveLength(1);
});

test('reading mode prevents typing and checkbox edits but keeps card selection', async ({ page }) => {
  await load(page, fixture, 'reading');
  await expect(page.locator('.tiptap')).toHaveAttribute('contenteditable', 'false');
  for (const input of await page.locator('input[type=checkbox]').all()) await expect(input).toBeDisabled();
  await page.locator('.tiptap h1').click(); await page.keyboard.type('no changes');
  expect(await markdown(page)).toBe(fixture);
  await page.locator('.rich-card').click(); await expect(page.locator('.rich-card')).toHaveClass(/selected/);
});

test('slash menu inserts an editable callout and supports keyboard choice', async ({ page }) => {
  await load(page, '');
  await page.locator('.tiptap').click(); await page.keyboard.type('/callout');
  await expect(page.locator('#slash')).toBeVisible();
  await page.keyboard.press('Enter'); await page.keyboard.type('Remember me');
  await expect(page.locator('.callout-content')).toContainText('Remember me');
  expect(await markdown(page)).toContain('> [!NOTE]\n> Remember me');
  await page.keyboard.press('Enter'); await page.keyboard.press('Enter'); await page.keyboard.type('Outside');
  await expect(page.locator('.tiptap > p').last()).toHaveText('Outside');
});

test('source edits are exact and live preview reflects them', async ({ page }) => {
  await load(page, fixture, 'source');
  const source = '# Changed\n\n> [!WARNING]\n> Be careful.\n';
  await page.locator('#source').fill(source);
  expect(await markdown(page)).toBe(source);
  await page.evaluate(() => window.notes.setMode('live'));
  await expect(page.locator('.tiptap h1')).toHaveText('Changed');
  await expect(page.locator('.callout')).toHaveAttribute('data-kind', 'warning');
  expect(await markdown(page)).toBe(source);
});

test('properties edit preserves the body', async ({ page }) => {
  await load(page, fixture);
  await page.locator('.property').first().click();
  await page.locator('#properties-source').fill('status: Ready\ntags: [writing]');
  await page.getByRole('button', { name: 'Save properties' }).click();
  await expect.poll(() => markdown(page)).toBe('---\nstatus: Ready\ntags: [writing]\n---\n' + fixture.split('---\n').slice(2).join('---\n'));
});

test('link dialog inserts a portable rich card and normal Markdown link', async ({ page }) => {
  await load(page, '');
  await page.locator('.tiptap').click();
  await page.evaluate(() => window.notes.command('link'));
  await page.locator('#link-url').fill('https://example.com/path');
  await page.locator('#link-title').fill('Example');
  await page.getByRole('button', { name: 'Rich card', exact: true }).click();
  await expect(page.locator('.rich-card')).toContainText('Example');
  expect(await markdown(page)).toContain('[Example](<https://example.com/path> "card")');
  await page.locator('.tiptap > p').last().click();
  await page.evaluate(() => window.notes.command('link'));
  await page.locator('#link-url').fill('https://example.com/inline');
  await page.locator('#link-title').fill('Inline');
  await page.getByRole('button', { name: 'Markdown link', exact: true }).click();
  await expect.poll(() => markdown(page)).toContain('[Inline](https://example.com/inline)');
});

test('typing Markdown and undo work, and document history is isolated', async ({ page }) => {
  await load(page, '');
  await page.locator('.tiptap').click(); await page.keyboard.type('## '); await page.keyboard.type('A heading');
  await expect(page.locator('.tiptap h2')).toHaveText('A heading');
  await page.keyboard.press('Meta+z');
  await page.evaluate(() => window.notes.load({ id: 'other.md', markdown: '# Other', mode: 'live' }));
  await page.locator('.tiptap').click(); await page.keyboard.press('Meta+z');
  expect(await markdown(page)).toBe('# Other');
});

test('HTML remains inert and preserved after a live edit', async ({ page }) => {
  await load(page, '# Safe\n\n<div onclick="alert(1)">Keep this HTML</div>\n');
  await expect(page.locator('.raw-block')).toContainText('Keep this HTML');
  await page.locator('.tiptap h1').click(); await page.keyboard.type('!');
  expect(await markdown(page)).toContain('<div onclick="alert(1)">Keep this HTML</div>');
  expect((await json(page)).content.some(n => n.type === 'rawHTML')).toBe(true);
});

test('editor fits a narrow window and renders both appearances', async ({ page }) => {
  await load(page, fixture);
  await page.screenshot({ path: '../artifacts/editor-light.png', fullPage: true });
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.screenshot({ path: '../artifacts/editor-dark.png', fullPage: true });
  await page.setViewportSize({ width: 500, height: 720 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(500);
});

test('empty and CRLF frontmatter survive editing without becoming document dividers', async ({ page }) => {
  for (const header of ['---\n---\n', '\uFEFF---\r\nstatus: Draft\r\n---\r\n']) {
    await load(page, header + '# Body\n\nHello');
    await expect(page.locator('.tiptap hr')).toHaveCount(0);
    await page.locator('.tiptap h1').click(); await page.keyboard.type('!');
    expect((await markdown(page)).startsWith(header)).toBe(true);
  }
});

test('pasting a URL offers both link forms and cancelling leaves the note unchanged', async ({ page }) => {
  await load(page, '# Paste\n\n');
  await page.locator('.tiptap > p').click();
  await page.locator('.tiptap').evaluate(el => {
    const data = new DataTransfer(); data.setData('text/plain', 'https://example.com/test');
    el.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true }));
  });
  await expect(page.locator('#link-dialog')).toBeVisible();
  await expect(page.locator('#link-url')).toHaveValue('https://example.com/test');
  await page.getByRole('button', { name: 'Cancel', exact: true }).click();
  expect(await markdown(page)).toBe('# Paste\n\n');
});

test('checkbox edits persist and source cannot open dangerous URLs as cards', async ({ page }) => {
  await load(page, '- [ ] Do the thing\n\n[Bad](<javascript:alert(1)> "card")\n');
  await page.locator('input[type=checkbox]').check();
  await expect.poll(() => markdown(page)).toContain('- [x] Do the thing');
  await expect(page.locator('.rich-card')).toHaveCount(0);
  expect(await page.evaluate(() => window.messages.filter(m => m.type === 'openLink'))).toHaveLength(0);
});


test('desktop design keeps readable metadata and removes formatting chrome in reading and source', async ({ page }) => {
  await load(page, fixture);
  for (const colorScheme of ['light', 'dark']) {
    await page.emulateMedia({ colorScheme });
    const contrast = await page.evaluate(() => {
      const css = getComputedStyle(document.documentElement);
      const luminance = token => {
        const raw = css.getPropertyValue(token).trim().slice(1);
        const hex = raw.length === 3 ? [...raw].map(x => x + x).join('') : raw;
        const channels = hex.match(/.{2}/g).map(x => parseInt(x, 16) / 255)
          .map(x => x <= 0.04045 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4);
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
      };
      const semantic = ['--info', '--tip', '--warning', '--important'].map(token => {
        const text = luminance(token), surface = luminance('--panel');
        return (Math.max(text, surface) + 0.05) / (Math.min(text, surface) + 0.05);
      });
      const text = luminance('--muted');
      return ['--bg', '--soft', '--panel'].map(token => {
        const surface = luminance(token);
        return (Math.max(text, surface) + 0.05) / (Math.min(text, surface) + 0.05);
      }).concat(semantic);
    });
    for (const ratio of contrast) expect(ratio).toBeGreaterThanOrEqual(4.5);
    await expect(page.locator('#formatbar')).toHaveCount(0);
    for (const mode of ['reading', 'source']) {
      await page.evaluate(mode => window.notes.setMode(mode), mode);
      await expect(page.locator('#formatbar')).toHaveCount(0);
      if (mode === 'reading') await expect(page.locator('.property').first()).toHaveCSS('opacity', '1');
      expect(await markdown(page)).toBe(fixture);
    }
    await page.evaluate(() => window.notes.setMode('live'));
  }
});


test('floating formatting keeps the selection and slash commands use compact grouped rows', async ({ page }) => {
  await load(page, '# Heading\n\nSelect these words');
  await page.locator('.tiptap > p').evaluate(el => {
    const range = document.createRange(); range.selectNodeContents(el);
    const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
  });
  await expect(page.locator('#bubble')).toBeVisible();
  await expect(page.locator('#formatbar')).toHaveCount(0);
  await page.locator('#bubble').getByRole('button', { name: 'Bold', exact: true }).click();
  await expect.poll(() => markdown(page)).toContain('**Select these words**');
  await page.locator('#bubble').getByRole('button', { name: 'Underline', exact: true }).click();
  await expect(page.locator('.tiptap u')).toHaveText('Select these words');
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.screenshot({ path: '../artifacts/floating-formatting.png' });
  await page.setViewportSize({ width: 420, height: 600 });
  await load(page, '# Heading\n\nSelect these words');
  await page.locator('.tiptap > p').evaluate(el => {
    const range = document.createRange(); range.selectNodeContents(el);
    const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
  });
  await expect(page.locator('#bubble')).toBeVisible();
  const bounds = await page.locator('#bubble').boundingBox();
  expect(bounds.x).toBeGreaterThanOrEqual(0);
  expect(bounds.x + bounds.width).toBeLessThanOrEqual(420);
  await page.evaluate(() => window.notes.setMode('reading'));
  await expect(page.locator('#bubble')).toBeHidden();
  await load(page, '');
  await page.locator('.tiptap').click(); await page.keyboard.type('/');
  await expect(page.locator('#slash')).toBeVisible();
  await expect(page.locator('.slash-shortcut').filter({ hasText: '⌘ ⌥ 1' })).toHaveCount(1);
  await expect(page.locator('.group-start')).toHaveCount(2);
  await page.screenshot({ path: '../artifacts/slash-menu.png' });
  await page.keyboard.press('Escape');
  await expect(page.locator('#slash')).toBeHidden();
});

test('expanded properties reach the native host after source edits and property edits', async ({ page }) => {
  await load(page, fixture, 'source');
  const latest = () => page.evaluate(() => window.messages.filter(m => m.type === 'properties').at(-1));
  expect((await latest()).text).toContain('extra:\n  nested: preserved');
  expect((await latest()).rows).toContainEqual({ name: 'extra', value: '\n  nested: preserved' });
  await page.locator('#source').fill('---\nstatus: Ready\n---\n# Body');
  expect((await latest()).text).toBe('status: Ready');
  await page.evaluate(() => window.notes.properties());
  await expect(page.locator('#properties-source')).toHaveValue('status: Ready');
  await page.locator('#properties-source').fill('status: Done\ntags: [writing]');
  await page.getByRole('button', { name: 'Save properties' }).click();
  await expect.poll(async () => (await latest()).text).toBe('status: Done\ntags: [writing]');
  expect(await markdown(page)).toBe('---\nstatus: Done\ntags: [writing]\n---\n# Body');
});

const pixel = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII=';

test('images render, edit alt text, survive modes, and reject executable references', async ({ page }) => {
  const original = `# Visual\n\n![Reference](data:image/png;base64,${pixel})\n`;
  await load(page, original);
  await expect(page.locator('.note-image img')).toBeVisible();
  expect(await page.locator('.note-image img').evaluate(img => img.naturalWidth)).toBe(1);
  await page.locator('.note-image img').click();
  await page.getByRole('button', { name: 'Alt text', exact: true }).click();
  await page.locator('#image-alt').fill('A tiny reference image');
  await page.locator('#image-dialog').getByRole('button', { name: 'Save', exact: true }).click();
  await expect(page.locator('.note-image img')).toHaveAttribute('alt', 'A tiny reference image');
  const saved = await markdown(page);
  expect(saved).toContain('![A tiny reference image]');
  await load(page, saved, 'reading');
  await expect(page.locator('.note-image img')).toHaveAttribute('alt', 'A tiny reference image');
  await expect(page.locator('.image-tools')).toBeHidden();
  for (const mode of ['source', 'live', 'reading']) await page.evaluate(mode => window.notes.setMode(mode), mode);
  expect(await markdown(page)).toBe(saved);
  await load(page, '![Unsafe](javascript:alert)\n\n![External file](file:///etc/passwd)');
  await expect(page.locator('.note-image img:visible')).toHaveCount(0);
  await load(page, `Before ![Inline](data:image/png;base64,${pixel} "card") after.`);
  await expect(page.locator('.note-image img')).toBeVisible();
  await page.locator('.tiptap').evaluate(el => el.editor.commands.insertContentAt(1, 'Still here. '));
  expect(await markdown(page)).toContain('Before'); expect(await markdown(page)).toContain('after.');
  await page.locator('.note-image img').click();
  await page.getByRole('button', { name: 'Remove', exact: true }).click();
  await expect(page.locator('.note-image')).toHaveCount(0);
});

test('image paste and drop use the native attachment bridge and discard stale replies', async ({ page }) => {
  await load(page, '# Images\n\n');
  await page.locator('.tiptap > p').click();
  await page.locator('.tiptap').evaluate((el, pixel) => {
    const bytes = Uint8Array.from(atob(pixel), c => c.charCodeAt(0));
    const data = new DataTransfer(); data.items.add(new File([bytes], 'Reference.png', { type: 'image/png' }));
    el.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true }));
  }, pixel);
  await expect.poll(() => page.evaluate(() => window.messages.filter(m => m.type === 'attachment').length)).toBe(1);
  const request = await page.evaluate(() => window.messages.find(m => m.type === 'attachment'));
  expect(request.data).toBe(pixel);
  await page.evaluate(({ request, pixel }) => window.notes.attachment({ id: request.id, request: request.request, src: `data:image/png;base64,${pixel}` }), { request, pixel });
  await expect(page.locator('.note-image img')).toBeVisible();
  await page.locator('.note-image img').click();
  const chooser = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Replace', exact: true }).click();
  await (await chooser).setFiles({ name: 'Replacement.png', mimeType: 'image/png', buffer: Buffer.from(pixel, 'base64') });
  await expect.poll(() => page.evaluate(() => window.messages.filter(m => m.type === 'attachment').length)).toBe(2);
  const replacement = await page.evaluate(() => window.messages.filter(m => m.type === 'attachment').at(-1));
  const gif = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';
  await page.evaluate(({ replacement, gif }) => window.notes.attachment({ id: replacement.id, request: replacement.request, src: gif }), { replacement, gif });
  await expect(page.locator('.note-image img')).toHaveAttribute('src', gif);
  await expect(page.locator('.note-image img')).toHaveAttribute('alt', 'Reference');
  await expect(page.locator('.note-image')).toHaveCount(1);
  await page.locator('.tiptap').evaluate((el, pixel) => {
    const data = new DataTransfer(); data.items.add(new File([Uint8Array.from(atob(pixel), c => c.charCodeAt(0))], 'Dropped.png', { type: 'image/png' }));
    const bounds = el.getBoundingClientRect();
    el.dispatchEvent(new DragEvent('drop', { dataTransfer: data, bubbles: true, cancelable: true, clientX: bounds.left + 20, clientY: bounds.top + 40 }));
  }, pixel);
  await expect.poll(() => page.evaluate(() => window.messages.filter(m => m.type === 'attachment').length)).toBe(3);
  const stale = await page.evaluate(() => window.messages.filter(m => m.type === 'attachment').at(-1));
  await page.evaluate(() => window.notes.load({ id: 'other.md', markdown: '# Other', mode: 'live' }));
  await page.evaluate(({ stale, pixel }) => window.notes.attachment({ id: stale.id, request: stale.request, src: `data:image/png;base64,${pixel}` }), { stale, pixel });
  expect(await markdown(page)).toBe('# Other');
  await expect(page.locator('.note-image')).toHaveCount(0);
});

test('callout colour and emoji round-trip with legacy titles, undo and reading protection', async ({ page }) => {
  await load(page, '> [!TIP]+ Existing title\n> Keep **this** content.\n');
  await page.getByRole('button', { name: 'Change callout style' }).click();
  await page.getByRole('button', { name: 'Green', exact: true }).click();
  await page.getByRole('button', { name: 'Pin', exact: true }).click();
  await page.getByRole('button', { name: 'Apply', exact: true }).click();
  await expect(page.locator('.callout-icon')).toHaveText('📌');
  const saved = await markdown(page);
  expect(saved).toContain('> [!TIP]+ Existing title <!--linear-notes-callout:');
  expect(saved).toContain('> Keep **this** content.');
  await expect(page.locator('.callout-icon')).toHaveText('📌');
  await page.evaluate(() => window.notes.command('undo'));
  await expect(page.locator('.callout-icon')).toHaveText('💡');
  await load(page, saved);
  await expect(page.locator('.callout-heading')).toHaveText('Existing title');
  await expect(page.locator('.callout-icon')).toHaveText('📌');
  expect((await json(page)).content[0].attrs.colour).toBe('#73c7a5');
  await page.evaluate(() => window.notes.setMode('reading'));
  await expect(page.locator('.callout-icon')).toBeDisabled();
  expect(await markdown(page)).toBe(saved);
  await load(page, '> [!NOTE]\n> No compulsory heading.');
  await expect(page.locator('.callout-heading')).toBeHidden();
  await load(page, '> [!NOTE] Literal <!--linear-notes-callout:null-->\n> Content stays.');
  await expect(page.locator('.callout-heading')).toContainText('Literal <!--linear-notes-callout:null-->');
});

test('outline reflects rendered headings, scroll position and modes; quick switching keeps the link shortcut', async ({ page }) => {
  const original = '# One\n\n' + 'Paragraph.\n\n'.repeat(35) + '## Two\n\n### Detail\n\n```md\n# Not a heading\n```';
  await load(page, original);
  const latest = () => page.evaluate(() => window.messages.filter(m => m.type === 'outline').at(-1));
  expect((await latest()).headings).toEqual([{ index: 0, level: 1, text: 'One' }, { index: 1, level: 2, text: 'Two' }, { index: 2, level: 3, text: 'Detail' }]);
  await page.evaluate(() => window.notes.jumpToHeading(1));
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBeGreaterThan(300);
  expect(await markdown(page)).toBe(original);
  await page.evaluate(() => window.notes.setMode('source'));
  expect((await latest()).headings).toEqual([]);
  await page.evaluate(() => window.notes.setMode('reading'));
  expect((await latest()).headings).toHaveLength(3);
  await page.keyboard.press('Meta+p');
  expect(await page.evaluate(() => window.messages.some(m => m.type === 'quickOpen'))).toBe(true);
  await page.evaluate(() => window.notes.setMode('live'));
  await page.locator('.tiptap h1').click(); await page.keyboard.press('Meta+k');
  await expect(page.locator('#link-dialog')).toBeVisible();
});
