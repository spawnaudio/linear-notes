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
const pixel = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
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
  expect(await markdown(page)).toContain('[Example](<https://example.com/path> "card")');
  expect(await page.evaluate(() => window.messages.filter(m => m.type === 'change'))).toHaveLength(0);
});

test('applyCardPreview matches path trailing slash variants', async ({ page }) => {
  await load(page, '[Example](<https://example.com/path> "card")\n');
  await page.evaluate(() => window.notes.applyCardPreview({
    url: 'https://example.com/path/',
    title: 'Example',
    description: 'Trailing slash preview.',
    imageSrc: ''
  }));
  await expect(page.locator('.rich-card')).toHaveClass(/has-preview/);
  await expect(page.locator('.card-description')).toHaveText('Trailing slash preview.');
});

test('remote preview images are ignored', async ({ page }) => {
  await load(page, '[Example](<https://example.com/path> "card")\n');
  await page.evaluate(() => window.notes.applyCardPreview({
    url: 'https://example.com/path',
    title: 'Example',
    description: 'Description still creates a preview layout.',
    imageSrc: 'https://example.com/image.png'
  }));
  await expect(page.locator('.rich-card')).toHaveClass(/has-preview/);
  await expect(page.locator('.card-description')).toHaveText('Description still creates a preview layout.');
  await expect(page.locator('.rich-card img')).toHaveCount(0);
});

test('title-only previews refresh generated card titles', async ({ page }) => {
  await load(page, '[example.com](<https://example.com/path> "card")\n');
  await page.evaluate(() => window.notes.applyCardPreview({
    url: 'https://example.com/path',
    title: 'Example page',
    description: '',
    imageSrc: ''
  }));
  await expect(page.locator('.card-title')).toHaveText('Example page');
  await expect(page.locator('.rich-card')).not.toHaveClass(/has-preview/);
});

test('applyCardPreview replaces generated titles but keeps custom titles', async ({ page }) => {
  await load(page, '[example.com](<https://example.com/path> "card")\n\n[My Example](<https://custom.example/path> "card")\n');
  await page.evaluate(() => {
    window.notes.applyCardPreview({
      url: 'https://example.com/path',
      title: 'Example page',
      description: 'Generated title can upgrade.',
      imageSrc: ''
    });
    window.notes.applyCardPreview({
      url: 'https://custom.example/path',
      title: 'Custom page',
      description: 'Custom title stays.',
      imageSrc: ''
    });
  });
  await expect(page.locator('.rich-card').first().locator('.card-title')).toHaveText('Example page');
  await expect(page.locator('.rich-card').nth(1).locator('.card-title')).toHaveText('My Example');
  expect(await markdown(page)).toContain('[example.com](<https://example.com/path> "card")');
  expect(await markdown(page)).toContain('[My Example](<https://custom.example/path> "card")');
});

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
