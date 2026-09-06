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
