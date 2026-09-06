import { Editor, Node, Extension, mergeAttributes } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import { Markdown } from '@tiptap/markdown';
import Placeholder from '@tiptap/extension-placeholder';
import TaskList from '@tiptap/extension-task-list';
import TaskItem from '@tiptap/extension-task-item';
import { TableKit } from '@tiptap/extension-table';
import Image from '@tiptap/extension-image';

const $ = id => document.getElementById(id);
const send = (type, payload = {}) => window.webkit?.messageHandlers?.notes?.postMessage({ type, ...payload });
let documentID = '', currentMarkdown = '', frontmatter = '', mode = 'live', loading = false;
let editor, slashRange = null, slashIndex = 0, slashMatches = [], linkRange = null;
let applyingPreview = false, cardPreviews = new Map();
let linkDialogPreviewRequested = false;
const webURL = value => { try { const u = new URL(value); return ['https:', 'http:'].includes(u.protocol) ? u.href : null; } catch { return null; } };
const openURL = value => { const url = webURL(value); if (url) send('openLink', { url }); };
const escapeLabel = text => text.replace(/([\\\[\]])/g, '\\$1').replace(/\n/g, ' ');
const previewURLKey = value => {
  try {
    const url = new URL(value);
    url.hash = '';
    if (url.pathname !== '/') url.pathname = url.pathname.replace(/\/+$/, '') || '/';
    return url.href;
  } catch {
    return value;
  }
};
const previewForURL = value => cardPreviews.get(previewURLKey(value));
const previewImageSrc = value => typeof value === 'string' && value.trim().startsWith('data:') ? value.trim() : '';
const hostLabel = value => {
  try {
    const url = new URL(value);
    return url.hostname.replace(/^www\./, '') + (url.pathname !== '/' ? url.pathname : '');
  } catch {
    return value;
  }
};
const generatedTitleLabel = value => {
  try {
    return new URL(value).hostname.replace(/^www\./, '');
  } catch {
    return value;
  }
};
const hasCustomCardTitle = (title, url) => {
  const label = (title || '').trim();
  return Boolean(label) && ![url, previewURLKey(url), generatedTitleLabel(url)].includes(label);
};
const previewDomain = value => {
  try {
    const url = new URL(value);
    return `${url.protocol}//${url.hostname.replace(/^www\./, '')}`;
  } catch {
    return value;
  }
};

const Callout = Node.create({
  name: 'callout', group: 'block', content: 'block+', defining: true,
  addAttributes() { return { kind: { default: 'note' }, title: { default: '' }, fold: { default: '' } }; },
  parseHTML() { return [{ tag: 'aside[data-kind]' }]; },
  renderHTML({ node }) {
    return ['aside', mergeAttributes({ class: 'callout', 'data-kind': node.attrs.kind }, node.attrs.fold ? { 'data-fold': node.attrs.fold } : {}),
      ['button', { class: 'callout-heading', contenteditable: 'false', type: 'button' }, node.attrs.title || node.attrs.kind.charAt(0).toUpperCase() + node.attrs.kind.slice(1)],
      ['div', { class: 'callout-content' }, 0]];
  },
  markdownTokenizer: {
    name: 'callout', level: 'block', start: src => src.search(/^>\s*\[!/m),
    tokenize(src, _tokens, lexer) {
      const match = /^>\s*\[!([\w-]+)\]([+-]?)[ \t]*([^\n]*)(?:\n|$)((?:>[^\n]*(?:\n|$))*)/.exec(src);
      if (!match) return;
      const body = match[4].replace(/^> ?/gm, '');
      return { type: 'callout', raw: match[0], kind: match[1].toLowerCase(), fold: match[2], title: match[3], tokens: lexer.blockTokens(body) };
    }
  },
  parseMarkdown(token, h) { return { type: 'callout', attrs: { kind: token.kind, title: token.title, fold: token.fold }, content: h.parseChildren(token.tokens).length ? h.parseChildren(token.tokens) : [{ type: 'paragraph' }] }; },
  renderMarkdown(node, h) {
    const title = node.attrs.title ? ` ${node.attrs.title}` : '';
    return `> [!${node.attrs.kind.toUpperCase()}]${node.attrs.fold || ''}${title}\n` + h.renderChildren(node.content, '\n\n').trimEnd().split('\n').map(line => `> ${line}`).join('\n');
  },
  addKeyboardShortcuts() {
    return { Enter: () => {
      const { $from, empty } = this.editor.state.selection;
      if (empty && $from.parent.type.name === 'paragraph' && !$from.parent.textContent && this.editor.isActive('callout')) return this.editor.commands.lift('callout');
      return false;
    }};
  },
  addNodeView() {
    return ({ node, editor: ed, getPos }) => {
      const dom = document.createElement('aside');
      dom.className = 'callout';
      const heading = document.createElement('button');
      heading.type = 'button';
      heading.className = 'callout-heading';
      heading.contentEditable = 'false';
      const content = document.createElement('div');
      content.className = 'callout-content';
      const updateView = updated => {
        node = updated;
        dom.dataset.kind = updated.attrs.kind;
        if (updated.attrs.fold) dom.dataset.fold = updated.attrs.fold;
        else delete dom.dataset.fold;
        heading.textContent = updated.attrs.title || updated.attrs.kind.charAt(0).toUpperCase() + updated.attrs.kind.slice(1);
        heading.setAttribute('aria-expanded', String(updated.attrs.fold !== '-'));
      };
      heading.addEventListener('mousedown', e => e.preventDefault());
      heading.addEventListener('click', e => {
        e.preventDefault(); e.stopPropagation();
        const pos = getPos();
        if (typeof pos !== 'number') return;
        const current = ed.state.doc.nodeAt(pos);
        if (!current) return;
        const fold = current.attrs.fold === '-' ? '+' : '-';
        ed.chain().command(({ tr }) => { tr.setNodeMarkup(pos, undefined, { ...current.attrs, fold }); return true; }).run();
      });
      updateView(node);
      dom.append(heading, content);
      return {
        dom,
        contentDOM: content,
        stopEvent: event => heading.contains(event.target),
        update: updated => {
          if (updated.type !== node.type) return false;
          updateView(updated);
          return true;
        }
      };
    };
  }
});

const RichLink = Node.create({
  name: 'richLink', group: 'block', atom: true, selectable: true, draggable: true,
  addAttributes() { return { url: { default: '' }, title: { default: '' }, description: { default: '' }, imageSrc: { default: '' } }; },
  parseHTML() { return [{ tag: 'div[data-rich-link]', getAttrs: el => ({ url: el.dataset.url, title: el.dataset.title, description: el.dataset.description || '', imageSrc: el.dataset.imageSrc || '' }) }]; },
  renderHTML({ node }) { return ['div', { 'data-rich-link': '', 'data-url': node.attrs.url, 'data-title': node.attrs.title }, node.attrs.title]; },
  markdownTokenizer: {
    name: 'richLink', level: 'block', start: src => src.search(/^\[/m),
    tokenize(src) {
      const m = /^\[((?:\\.|[^\]\\])*)\]\((?:<([^>\n]+)>|([^\s]+)) "card"\)[ \t]*(?:\n|$)/.exec(src);
      if (!m || !webURL(m[2] || m[3])) return;
      return { type: 'richLink', raw: m[0], url: m[2] || m[3], title: m[1].replace(/\\(.)/g, '$1') };
    }
  },
  parseMarkdown: token => ({ type: 'richLink', attrs: { url: token.url, title: token.title } }),
  renderMarkdown: node => `[${escapeLabel(node.attrs.title)}](<${node.attrs.url.replace(/>/g, '%3E')}> "card")`,
  addNodeView() {
    return ({ node, editor: ed, getPos }) => {
      const dom = document.createElement('div'); dom.tabIndex = 0; dom.role = 'button';
      const render = updated => {
        node = updated;
        dom.dataset.previewKey = previewURLKey(updated.attrs.url);
        dom.dataset.url = updated.attrs.url;
        dom.dataset.title = updated.attrs.title;
        const preview = previewForURL(updated.attrs.url);
        const description = updated.attrs.description || preview?.description || '';
        const imageSrc = previewImageSrc(updated.attrs.imageSrc || preview?.imageSrc || '');
        const titleText = preview?.title && (preview.preferTitle || !hasCustomCardTitle(updated.attrs.title, updated.attrs.url)) ? preview.title : updated.attrs.title || preview?.title || updated.attrs.url;
        const hasPreview = Boolean(description || imageSrc);
        dom.className = `rich-card${hasPreview ? ' has-preview' : ''}${dom.classList.contains('selected') ? ' selected' : ''}`;
        dom.setAttribute('aria-label', `${titleText}. Click to select, click again to open.`);
        const icon = document.createElement('span'); icon.className = 'card-icon'; icon.textContent = '↗';
        const copy = document.createElement('span'); copy.className = 'card-copy';
        const title = document.createElement('span'); title.className = 'card-title'; title.textContent = titleText;
        const domain = document.createElement('span'); domain.className = 'card-domain'; domain.textContent = hasPreview ? previewDomain(updated.attrs.url) : hostLabel(updated.attrs.url);
        copy.append(title);
        if (description) {
          const summary = document.createElement('span'); summary.className = 'card-description'; summary.textContent = description;
          copy.append(summary);
        }
        copy.append(domain);
        const arrow = document.createElement('span'); arrow.className = 'card-arrow'; arrow.textContent = '↗';
        const children = hasPreview ? [copy] : [icon, copy, arrow];
        if (imageSrc) {
          const image = document.createElement('img');
          image.src = imageSrc;
          image.alt = '';
          children.push(image);
        }
        dom.replaceChildren(...children);
      };
      render(node);
      dom.addEventListener('mousedown', e => { e.preventDefault(); e.stopPropagation(); });
      dom.addEventListener('click', e => {
        e.preventDefault(); e.stopPropagation();
        if (dom.classList.contains('selected')) openURL(node.attrs.url);
        else { const pos = getPos(); if (typeof pos === 'number') ed.commands.setNodeSelection(pos); dom.focus(); }
      });
      dom.addEventListener('keydown', e => {
        if (e.key === 'Enter') { e.preventDefault(); openURL(node.attrs.url); }
        if ((e.key === 'Backspace' || e.key === 'Delete') && mode !== 'reading') { e.preventDefault(); ed.commands.deleteSelection(); ed.commands.focus(); }
        if (e.key === 'Escape') { const pos = getPos(); ed.commands.setTextSelection(Math.min(pos + node.nodeSize + 1, ed.state.doc.content.size)); ed.commands.focus(); }
      });
      return {
        dom,
        stopEvent: () => true,
        update: updated => {
          if (updated.type !== node.type) return false;
          const selected = dom.classList.contains('selected');
          render(updated);
          if (selected) dom.classList.add('selected');
          return true;
        },
        selectNode: () => { dom.classList.add('selected'); dom.setAttribute('aria-pressed', 'true'); },
        deselectNode: () => { dom.classList.remove('selected'); dom.setAttribute('aria-pressed', 'false'); }
      };
    };
  }
});

// Keep arbitrary HTML as visible, inert source instead of executing or silently dropping it.
const RawHTML = Node.create({
  name: 'rawHTML', group: 'block', atom: true,
  addAttributes() { return { source: { default: '' } }; },
  parseHTML() { return [{ tag: 'pre[data-raw]' }]; },
  renderHTML({ node }) { return ['pre', { class: 'raw-block', 'data-raw': '', title: 'Preserved HTML · edit in Source mode' }, node.attrs.source]; },
  markdownTokenName: 'html',
  parseMarkdown: token => ({ type: 'rawHTML', attrs: { source: token.raw || token.text } }),
  renderMarkdown: node => node.attrs.source
});

const SafeImage = Image.extend({
  addNodeView() { return ({ node }) => {
    const dom = document.createElement('div'); dom.className = 'image-placeholder';
    dom.textContent = `▧  ${node.attrs.alt || 'Image'} · ${node.attrs.src}`;
    dom.title = 'Image reference preserved. Inline image loading is planned for a later version.';
    return { dom };
  }; }
});

const LinearKeys = Extension.create({
  name: 'linearKeys', priority: 1100,
  addKeyboardShortcuts() { return {
    'Mod-e': () => this.editor.commands.toggleCode(),
    'Mod->': () => this.editor.commands.toggleItalic(),
    'Mod-Shift-s': () => this.editor.commands.toggleStrike(),
    'Mod-Shift-7': () => this.editor.commands.toggleTaskList(),
    'Mod-Shift-8': () => this.editor.commands.toggleBulletList(),
    'Mod-Shift-9': () => this.editor.commands.toggleOrderedList(),
    'Mod-Shift-\\': () => this.editor.commands.toggleCodeBlock(),
    'Mod-k': () => { showLink(); return true; },
    'Mod-Alt-0': () => this.editor.commands.setParagraph(),
    ...Object.fromEntries([1, 2, 3, 4].map(level => [`Mod-Alt-${level}`, () => this.editor.commands.toggleHeading({ level })]))
  }; }
});

function makeEditor(markdown) {
  const instance = new Editor({
    element: $('editor'),
    extensions: [StarterKit.configure({ heading: { levels: [1, 2, 3, 4, 5, 6] }, link: { openOnClick: false, autolink: true }, trailingNode: false }), Markdown, Placeholder.configure({ placeholder: 'Start writing, or type / for commands…' }), TaskList, TaskItem.configure({ nested: true, HTMLAttributes: { 'data-type': 'taskItem' } }), TableKit, SafeImage, Callout, RichLink, RawHTML, LinearKeys],
    content: markdown, contentType: 'markdown', editable: mode !== 'reading',
    editorProps: {
      attributes: { 'aria-label': mode === 'reading' ? 'Read document' : 'Edit document', spellcheck: 'true' },
      handlePaste(view, event) {
        if (mode !== 'live') return false;
        const text = event.clipboardData?.getData('text/plain')?.trim();
        if (webURL(text)) { event.preventDefault(); showLink(text); return true; }
        return false;
      },
      handleKeyDown(_view, event) {
        if (!$('slash').hidden) {
          if (event.key === ' ') { hideSlash(); return false; }
          if (['ArrowDown', 'ArrowUp'].includes(event.key)) { event.preventDefault(); slashIndex = (slashIndex + (event.key === 'ArrowDown' ? 1 : slashMatches.length - 1)) % slashMatches.length; drawSlash(); return true; }
          if (event.key === 'Enter' && slashMatches.length) { event.preventDefault(); chooseSlash(slashMatches[slashIndex]); return true; }
          if (event.key === 'Escape') { hideSlash(); return true; }
        }
        return false;
      }
    },
    onUpdate() { if (!loading && !applyingPreview) { currentMarkdown = frontmatter + instance.getMarkdown(); notifyChange(); updateSlash(); } },
    onSelectionUpdate() { if (!loading) { updateSlash(); updateBubble(); } }
  });
  return instance;
}

function splitFrontmatter(text) {
  const match = /^(\uFEFF?---\r?\n(?:[\s\S]*?\r?\n)?(?:---|\.\.\.)[ \t]*(?:\r?\n|$))/.exec(text);
  return match ? [match[0], text.slice(match[0].length)] : ['', text];
}
function propertiesText() { return frontmatter.replace(/^\uFEFF?---\r?\n/, '').replace(/(?:^|\r?\n)(?:---|\.\.\.)[ \t]*\r?\n?$/, ''); }
function drawProperties() {
  $('properties').replaceChildren();
  const text = propertiesText();
  for (const match of text.matchAll(/^(\w[\w -]*):[ \t]*(.*)$/gm)) {
    const button = document.createElement('button'); button.className = 'property';
    const key = document.createElement('span'); key.textContent = match[1];
    const value = document.createElement('span'); value.className = 'property-value'; value.textContent = match[2].replace(/^['"]|['"]$/g, '').replace(/^\[|\]$/g, '').replace(/,\s*/g, ' · ') || '…';
    button.append(key, value); button.onclick = showProperties; button.disabled = mode === 'reading'; $('properties').append(button);
  }
  if (mode === 'live') { const add = document.createElement('button'); add.className = 'property-add'; add.textContent = frontmatter ? '+ Property' : '+ Add properties'; add.onclick = showProperties; $('properties').append(add); }
}
function showProperties() { if (mode === 'reading') return; $('properties-source').value = propertiesText(); $('properties-dialog').showModal(); }
$('properties-dialog').addEventListener('close', () => {
  if ($('properties-dialog').returnValue !== 'save') return;
  const raw = $('properties-source').value.trim();
  const body = splitFrontmatter(currentMarkdown)[1]; frontmatter = raw ? `---\n${raw}\n---\n` : '';
  currentMarkdown = frontmatter + body; drawProperties(); notifyChange();
});

function notifyChange() { $('source').value = currentMarkdown; send('change', { id: documentID, markdown: currentMarkdown }); reportStats(); }
function reportStats() { const body = splitFrontmatter(currentMarkdown)[1]; send('stats', { id: documentID, words: body.trim().split(/\s+/).filter(Boolean).length }); }
function refreshTitleOnlyCardPreviews(key) {
  document.querySelectorAll(`.rich-card[data-preview-key="${CSS.escape(key)}"]`).forEach(card => {
    const preview = previewForURL(card.dataset.url || '');
    if (!preview?.title) return;
    const titleText = preview.preferTitle || !hasCustomCardTitle(card.dataset.title || '', card.dataset.url || '') ? preview.title : card.dataset.title || preview.title;
    card.querySelector('.card-title')?.replaceChildren(document.createTextNode(titleText));
    card.setAttribute('aria-label', `${titleText}. Click to select, click again to open.`);
  });
}
function applyCardPreview(payload, options = {}) {
  const key = previewURLKey(payload.url);
  const description = payload.description || '';
  const imageSrc = previewImageSrc(payload.imageSrc || '');
  cardPreviews.set(key, { title: payload.title || '', description, imageSrc, preferTitle: Boolean(options.preferTitle) });
  if (!editor) return;
  const tr = editor.state.tr;
  editor.state.doc.descendants((node, pos) => {
    if (node.type.name !== 'richLink' || previewURLKey(node.attrs.url) !== key) return;
    tr.setNodeMarkup(pos, undefined, { ...node.attrs, description, imageSrc });
  });
  if (!tr.docChanged) {
    refreshTitleOnlyCardPreviews(key);
    return;
  }
  tr.setMeta('addToHistory', false);
  applyingPreview = true;
  try {
    editor.view.dispatch(tr);
  } finally {
    applyingPreview = false;
  }
  refreshTitleOnlyCardPreviews(key);
}
function loadDocument(payload) {
  loading = true; documentID = payload.id; currentMarkdown = payload.markdown; mode = payload.mode || 'live';
  cardPreviews = new Map();
  [frontmatter] = splitFrontmatter(currentMarkdown);
  editor?.destroy(); $('editor').replaceChildren(); editor = makeEditor(splitFrontmatter(currentMarkdown)[1]);
  Object.entries(payload.previews || {}).forEach(([url, preview]) => applyCardPreview({ url, ...preview }));
  applyMode(); hideSlash(); hideBubble(); window.scrollTo(0, 0); loading = false; reportStats();
}
function applyMode() {
  document.body.dataset.mode = mode;
  $('source').hidden = mode !== 'source'; $('editor').hidden = mode === 'source';
  $('properties').hidden = mode === 'source';
  $('source').value = currentMarkdown; resizeSource(); editor.setEditable(mode === 'live', false); drawProperties();
  document.querySelectorAll('input[type=checkbox]').forEach(input => input.disabled = mode === 'reading');
}
function setMode(next) {
  if (!['source', 'reading', 'live'].includes(next) || next === mode) return;
  loading = true;
  if (mode === 'source') { [frontmatter] = splitFrontmatter(currentMarkdown); editor.destroy(); $('editor').replaceChildren(); editor = makeEditor(splitFrontmatter(currentMarkdown)[1]); }
  mode = next; applyMode(); hideSlash(); hideBubble(); loading = false;
}
function resizeSource() { const field = $('source'); field.style.height = 'auto'; field.style.height = `${Math.max(520, field.scrollHeight)}px`; }
$('source').addEventListener('input', () => { currentMarkdown = $('source').value; send('change', { id: documentID, markdown: currentMarkdown }); reportStats(); resizeSource(); });
$('source').addEventListener('keydown', e => { if (e.key === 'Tab') { e.preventDefault(); document.execCommand('insertText', false, '  '); } });

const slashCommands = [
  { id: 'paragraph', icon: 'T', name: 'Text', desc: 'Just start writing' },
  ...[1, 2, 3, 4].map(level => ({ id: `h${level}`, icon: `H${level}`, name: `Heading ${level}`, desc: ['A big, clear heading', 'A section heading', 'A smaller heading', 'A compact heading'][level - 1] })),
  { id: 'bullet', icon: '☷', name: 'Bulleted list', desc: 'A simple list of ideas' },
  { id: 'ordered', icon: '1.', name: 'Numbered list', desc: 'One thing after another' },
  { id: 'task', icon: '☑', name: 'Checklist', desc: 'Small things to get done' },
  { id: 'quote', icon: '❞', name: 'Quote', desc: 'Give a thought its own space' },
  { id: 'callout', icon: 'ⓘ', name: 'Callout', desc: 'Something worth remembering' },
  { id: 'tip', icon: '◇', name: 'Tip', desc: 'A helpful little suggestion' },
  { id: 'warning', icon: '△', name: 'Warning', desc: 'Something to keep in mind' },
  { id: 'codeBlock', icon: '‹›', name: 'Code block', desc: 'A snippet of code' },
  { id: 'divider', icon: '—', name: 'Divider', desc: 'A quiet break between ideas' },
  { id: 'link', icon: '↗', name: 'Link or rich card', desc: 'A reference to come back to' },
  { id: 'table', icon: '▦', name: 'Table', desc: 'Organise a few details' },
];
function updateSlash() {
  if (mode !== 'live' || !editor) return hideSlash();
  const { $from, empty } = editor.state.selection;
  if (!empty || $from.parent.type.name !== 'paragraph') return hideSlash();
  const before = $from.parent.textBetween(0, $from.parentOffset);
  const match = /^\/(\w*)$/.exec(before);
  if (!match) return hideSlash();
  slashRange = { from: $from.start(), to: $from.pos };
  slashMatches = slashCommands.filter(command => command.name.toLowerCase().includes(match[1].toLowerCase()));
  slashIndex = Math.min(slashIndex, Math.max(0, slashMatches.length - 1)); drawSlash();
}
function drawSlash() {
  const menu = $('slash'); menu.replaceChildren();
  if (!slashMatches.length) return hideSlash();
  const label = document.createElement('div'); label.className = 'slash-label'; label.textContent = 'Add to your document'; menu.append(label);
  slashMatches.forEach((command, index) => {
    const button = document.createElement('button'); button.className = `slash-option${index === slashIndex ? ' selected' : ''}`; button.role = 'option'; button.setAttribute('aria-selected', String(index === slashIndex));
    const icon = document.createElement('span'); icon.className = 'slash-icon'; icon.textContent = command.icon;
    const copy = document.createElement('span'); const name = document.createElement('span'); name.className = 'slash-name'; name.textContent = command.name;
    const desc = document.createElement('span'); desc.className = 'slash-description'; desc.textContent = command.desc;
    copy.append(name, desc); button.append(icon, copy); button.onmousedown = e => { e.preventDefault(); chooseSlash(command); }; menu.append(button);
  });
  const coords = editor.view.coordsAtPos(editor.state.selection.from); menu.hidden = false;
  menu.style.left = `${Math.min(Math.max(10, coords.left), innerWidth - 300)}px`;
  menu.style.top = `${Math.max(50, Math.min(coords.bottom + 8, innerHeight - Math.min(menu.scrollHeight, 330) - 12))}px`;
  menu.querySelector('.selected')?.scrollIntoView({ block: 'nearest' });
}
function hideSlash() { $('slash').hidden = true; slashRange = null; slashIndex = 0; }
function chooseSlash(command) { if (slashRange) editor.chain().focus().deleteRange(slashRange).run(); hideSlash(); execute(command.id); }

function showLink(url = '') {
  if (mode !== 'live') return;
  linkRange = { from: editor.state.selection.from, to: editor.state.selection.to };
  linkDialogPreviewRequested = false;
  $('link-url').value = url || editor.getAttributes('link').href || '';
  $('link-title').value = editor.state.doc.textBetween(linkRange.from, linkRange.to, ' ');
  $('link-dialog').showModal(); $('link-url').focus();
}
document.querySelector('#link-dialog button[value=card]').addEventListener('click', () => {
  const url = webURL($('link-url').value.trim());
  if (!url) return;
  linkDialogPreviewRequested = true;
  send('fetchCardPreview', { url });
});
$('link-dialog').addEventListener('close', () => {
  const result = $('link-dialog').returnValue;
  if (result === 'cancel' || !['link', 'card'].includes(result)) { editor.commands.focus(); return; }
  const url = webURL($('link-url').value.trim()); if (!url) return;
  const title = $('link-title').value.trim() || new URL(url).hostname.replace(/^www\./, '');
  const chain = editor.chain().focus().setTextSelection(linkRange);
  if (result === 'card') {
    chain.insertContent([{ type: 'richLink', attrs: { url, title } }, { type: 'paragraph' }]).run();
    if (!linkDialogPreviewRequested) send('fetchCardPreview', { url });
  }
  else {
    chain.insertContent({ type: 'text', text: title, marks: [{ type: 'link', attrs: { href: url } }] }).run();
    editor.view.dispatch(editor.state.tr.removeStoredMark(editor.schema.marks.link));
  }
});

function execute(command) {
  if (mode !== 'live') return;
  const chain = editor.chain().focus();
  if (/^h[1-4]$/.test(command)) return chain.toggleHeading({ level: Number(command[1]) }).run();
  switch (command) {
    case 'bold': return chain.toggleBold().run();
    case 'italic': return chain.toggleItalic().run();
    case 'strike': return chain.toggleStrike().run();
    case 'underline': return chain.toggleUnderline().run();
    case 'code': return chain.toggleCode().run();
    case 'paragraph': return chain.setParagraph().run();
    case 'text': return chain.setParagraph().run();
    case 'bullet': return chain.toggleBulletList().run();
    case 'ordered': return chain.toggleOrderedList().run();
    case 'task': return chain.toggleTaskList().run();
    case 'quote': return chain.toggleBlockquote().run();
    case 'codeBlock': return chain.toggleCodeBlock().run();
    case 'divider': return chain.setHorizontalRule().run();
    case 'table': return chain.insertTable({ rows: 3, cols: 3, withHeaderRow: true }).run();
    case 'callout': case 'tip': case 'warning': return chain.wrapIn('callout', { kind: command === 'callout' ? 'note' : command }).run();
    case 'link': return showLink();
    case 'undo': return editor.commands.undo();
    case 'redo': return editor.commands.redo();
  }
}
slashCommands[0].id = 'text';
document.querySelectorAll('[data-command]').forEach(button => {
  button.addEventListener('mousedown', e => e.preventDefault());
  button.addEventListener('click', e => {
    e.preventDefault();
    execute(button.dataset.command);
    if (button.closest('#turn-into')) $('turn-into').hidden = true;
  });
});
function hideBubble() { $('bubble').hidden = true; $('turn-into').hidden = true; }
function currentBlockLabel() {
  for (const level of [1, 2, 3, 4]) if (editor.isActive('heading', { level })) return `Heading ${level}`;
  return 'Text';
}
function setActiveButton(command, active) {
  document.querySelector(`#bubble [data-command="${command}"]`)?.classList.toggle('active', active);
}
function updateBubble() {
  const { from, to, empty } = editor.state.selection;
  const bubble = $('bubble');
  if (empty || mode !== 'live' || !$('slash').hidden || editor.state.selection.node) { hideBubble(); return; }
  $('turn-into-btn').firstChild.textContent = currentBlockLabel() + ' ';
  setActiveButton('bold', editor.isActive('bold'));
  setActiveButton('italic', editor.isActive('italic'));
  setActiveButton('strike', editor.isActive('strike'));
  setActiveButton('code', editor.isActive('code'));
  setActiveButton('link', editor.isActive('link'));
  setActiveButton('bullet', editor.isActive('bulletList'));
  setActiveButton('task', editor.isActive('taskList'));
  setActiveButton('quote', editor.isActive('blockquote'));
  const start = editor.view.coordsAtPos(from), end = editor.view.coordsAtPos(to);
  bubble.hidden = false; bubble.style.top = `${Math.max(46, start.top - 44)}px`; bubble.style.left = `${Math.max(12, Math.min((start.left + end.left) / 2 - 150, innerWidth - 330))}px`;
}
$('turn-into-btn').addEventListener('mousedown', e => e.preventDefault());
$('turn-into-btn').addEventListener('click', e => {
  e.preventDefault();
  const menu = $('turn-into'), button = $('turn-into-btn').getBoundingClientRect();
  menu.hidden = !menu.hidden;
  menu.style.left = `${Math.max(12, Math.min(button.left, innerWidth - 150))}px`;
  menu.style.top = `${Math.min(button.bottom + 7, innerHeight - Math.min(menu.scrollHeight, 220) - 12)}px`;
});
document.addEventListener('click', e => {
  const anchor = e.target.closest('a');
  if (anchor) { e.preventDefault(); if (mode === 'reading' || e.metaKey) openURL(anchor.getAttribute('href')); }
  if (!e.target.closest('#slash') && !e.target.closest('#bubble') && !e.target.closest('#turn-into')) { hideSlash(); $('turn-into').hidden = true; }
});
window.addEventListener('scroll', () => { hideBubble(); hideSlash(); }, { passive: true });
window.addEventListener('keydown', e => {
  if (e.key === 'Escape' && !$('turn-into').hidden) { e.preventDefault(); $('turn-into').hidden = true; $('turn-into-btn').focus(); return; }
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 's' && !e.shiftKey) { e.preventDefault(); send('save'); }
});

window.notes = { load: loadDocument, setMode, command: execute, applyCardPreview, getMarkdown: () => currentMarkdown, getJSON: () => editor.getJSON(), focus: () => mode === 'source' ? $('source').focus() : editor.commands.focus(), properties: showProperties };
send('ready');
// A browser harness loads only explicit fixtures; production content arrives from the native host.
loadDocument({ id: '', markdown: '', mode: 'live' });
