import { Editor, Node, Extension, mergeAttributes } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import { Markdown } from '@tiptap/markdown';
import Placeholder from '@tiptap/extension-placeholder';
import TaskList from '@tiptap/extension-task-list';
import TaskItem from '@tiptap/extension-task-item';
import { TableKit } from '@tiptap/extension-table';
import Image from '@tiptap/extension-image';
import Paragraph from '@tiptap/extension-paragraph';
import { Plugin, PluginKey } from '@tiptap/pm/state';
import { Decoration, DecorationSet } from '@tiptap/pm/view';

const $ = id => document.getElementById(id);
const send = (type, payload = {}) => window.webkit?.messageHandlers?.notes?.postMessage({ type, ...payload });
window.addEventListener('pointerdown', () => send('focus', { id: documentID }));
window.addEventListener('focusin', () => send('focus', { id: documentID }));
let documentID = '', currentMarkdown = '', frontmatter = '', mode = 'live', loading = false, assetBase = '';
let editor, slashRange = null, slashIndex = 0, slashMatches = [], linkRange = null;
let calloutPosition = null, calloutColour = '', imageAltPosition = null, uploadRange = null, imageRequest = 0, activeHeading = -1;
const imageRequests = new Map();
let noteLinks = [], positions = {}, viewTimer, printing = false;
let findMatches = [], findIndex = 0;
const FindHighlights = Extension.create({
  name: 'findHighlights',
  addProseMirrorPlugins() { return [new Plugin({ key: new PluginKey('findHighlights'), props: {
    decorations(state) { return mode === 'source' || $('find').hidden ? null : DecorationSet.create(state.doc,
      findMatches.map((match, index) => Decoration.inline(match.from, match.to, { class: index === findIndex ? 'find-match find-current' : 'find-match' }))); }
  } })]; }
});
function folded(text) {
  let value = '', starts = [], ends = [], offset = 0;
  for (const character of text) {
    const part = character.normalize('NFD').replace(/\p{M}/gu, '').toLocaleLowerCase();
    for (let index = 0; index < part.length; index++) { starts.push(offset); ends.push(offset + character.length); }
    if (!part && ends.length) ends[ends.length - 1] = offset + character.length;
    value += part; offset += character.length;
  }
  return { value, starts, ends };
}
function refreshFind(jump = false) {
  const term = folded($('find-text').value.trim()).value;
  findMatches = [];
  const collect = (text, base) => {
    const haystack = folded(text);
    for (let index = 0; term && (index = haystack.value.indexOf(term, index)) !== -1; index += term.length) {
      findMatches.push({ from: base + haystack.starts[index], to: base + haystack.ends[index + term.length - 1] });
    }
  };
  if (!$('find').hidden && term) {
    if (mode === 'source') collect(currentMarkdown, 0);
    else editor.state.doc.descendants((node, pos) => { if (node.isTextblock) { collect(node.textBetween(0, node.content.size, '\n', '\ufffc'), pos + 1); return false; } });
  }
  findIndex = Math.min(findIndex, Math.max(0, findMatches.length - 1));
  $('find-count').textContent = `${findMatches.length ? findIndex + 1 : 0} / ${findMatches.length}`;
  $('find-next').disabled = $('find-previous').disabled = !findMatches.length;
  editor.view.dispatch(editor.state.tr.setMeta('find', true));
  if (jump) jumpToMatch();
}
function jumpToMatch() {
  const match = findMatches[findIndex]; if (!match) return;
  if (mode === 'source') {
    $('source').setSelectionRange(match.from, match.to);
    const line = currentMarkdown.slice(0, match.from).split('\n').length - 1;
    window.scrollTo(0, $('source').offsetTop + line * parseFloat(getComputedStyle($('source')).lineHeight) - innerHeight / 3);
  } else {
    editor.commands.setTextSelection(match);
    const rect = editor.view.coordsAtPos(match.from);
    window.scrollTo(0, window.scrollY + rect.top - innerHeight / 3);
  }
}
function showFind(term, focus = true) {
  $('find').hidden = false; $('bubble').hidden = true; hideSlash();
  if (typeof term === 'string') $('find-text').value = term;
  findIndex = 0; refreshFind(true);
  if (focus) { $('find-text').focus(); $('find-text').select(); }
}
function closeFind() { $('find').hidden = true; refreshFind(); if (mode !== 'reading') window.notes.focus(); }
$('find-text').oninput = () => { findIndex = 0; refreshFind(true); };
function nextMatch(direction) { if (findMatches.length) { findIndex = (findIndex + direction + findMatches.length) % findMatches.length; refreshFind(true); } }
$('find-next').onclick = () => nextMatch(1); $('find-previous').onclick = () => nextMatch(-1); $('find-close').onclick = closeFind;
$('find').onkeydown = event => {
  if (event.key === 'Enter') { event.preventDefault(); nextMatch(event.shiftKey ? -1 : 1); }
  if (event.key === 'Escape') { event.preventDefault(); closeFind(); }
};
function viewState() {
  const selection = mode === 'source' ? { from: $('source').selectionStart, to: $('source').selectionEnd } : editor.state.selection;
  positions[mode] = { from: selection.from, to: selection.to, scroll: window.scrollY };
  return { mode, positions };
}
function reportView() { clearTimeout(viewTimer); if (!loading && !printing) viewTimer = setTimeout(() => send('viewState', { id: documentID, state: viewState() }), 100); }
function restorePosition(position) {
  const size = mode === 'source' ? currentMarkdown.length : editor.state.doc.content.size;
  const clamp = value => Math.min(size, Math.max(mode === 'source' ? 0 : 1, Number.isFinite(value) ? Math.trunc(value) : 1));
  if (position) {
    const from = clamp(position.from), to = Math.max(from, clamp(position.to));
    if (mode === 'source') $('source').setSelectionRange(from, to); else editor.commands.setTextSelection({ from, to });
  }
  window.scrollTo(0, Number.isFinite(position?.scroll) ? Math.max(0, position.scroll) : 0);
}
function textSize(size) { document.documentElement.style.setProperty('--document-scale', String(Math.min(24, Math.max(12, Number(size) || 15)) / 15)); resizeSource(); }
const webURL = value => { try { const u = new URL(value); return ['https:', 'http:'].includes(u.protocol) ? u.href : null; } catch { return null; } };
const openURL = value => { const url = webURL(value); if (url) send('openLink', { url }); };
const openReference = href => relativeNote(href) ? send('openNote', { id: documentID, reference: href }) : openURL(href);
const escapeLabel = text => text.replace(/([\\\[\]])/g, '\\$1').replace(/\n/g, ' ');

const Callout = Node.create({
  name: 'callout', group: 'block', content: 'block+', defining: true,
  addAttributes() { return { kind: { default: 'note' }, title: { default: '' }, fold: { default: '' }, colour: { default: '' }, icon: { default: '' } }; },
  parseHTML() { return [{ tag: 'aside[data-kind]' }]; },
  renderHTML({ node }) {
    return ['aside', { class: 'callout', 'data-kind': node.attrs.kind },
      ['div', { class: 'callout-heading', contenteditable: 'false' }, node.attrs.title],
      ['div', { class: 'callout-content' }, 0]];
  },
  addNodeView() {
    return ({ node, getPos }) => {
      const dom = document.createElement('aside'); dom.className = 'callout';
      const icon = document.createElement('button'); icon.className = 'callout-icon'; icon.type = 'button'; icon.contentEditable = 'false';
      icon.setAttribute('aria-label', 'Change callout style'); icon.onclick = () => showCallout(getPos(), icon);
      const title = document.createElement('div'); title.className = 'callout-heading'; title.contentEditable = 'false';
      const contentDOM = document.createElement('div'); contentDOM.className = 'callout-content'; dom.append(icon, title, contentDOM);
      const draw = next => {
        dom.dataset.kind = next.attrs.kind;
        const colour = /^#[\da-f]{6}$/i.test(next.attrs.colour) ? next.attrs.colour : '';
        dom.style.setProperty('--custom-callout', colour || 'var(--callout-color)');
        icon.textContent = next.attrs.icon || ({ tip: '💡', warning: '⚠', caution: '⚠', important: '★' })[next.attrs.kind] || 'ⓘ';
        icon.disabled = mode !== 'live'; title.textContent = next.attrs.title; title.hidden = !next.attrs.title;
      };
      draw(node);
      return { dom, contentDOM, update: next => { if (next.type.name !== 'callout') return false; draw(next); return true; }, stopEvent: event => icon.contains(event.target) };
    };
  },
  markdownTokenizer: {
    name: 'callout', level: 'block', start: src => src.search(/^>\s*\[!/m),
    tokenize(src, _tokens, lexer) {
      const match = /^>\s*\[!([\w-]+)\]([+-]?)[ \t]*([^\n]*)(?:\n|$)((?:>[^\n]*(?:\n|$))*)/.exec(src);
      if (!match) return;
      const body = match[4].replace(/^> ?/gm, '');
      let title = match[3], metadata = {};
      const custom = /\s*<!--linear-notes-callout:([^>]+)-->\s*$/.exec(title);
      if (custom) {
        try {
          const decoded = JSON.parse(decodeURIComponent(custom[1]));
          if (decoded && typeof decoded === 'object' && !Array.isArray(decoded)) { metadata = decoded; title = title.slice(0, custom.index); }
        } catch { }
      }
      return { type: 'callout', raw: match[0], kind: match[1].toLowerCase(), fold: match[2], title,
        colour: /^#[\da-f]{6}$/i.test(metadata.colour) ? metadata.colour : '', icon: cleanIcon(metadata.icon), tokens: lexer.blockTokens(body) };
    }
  },
  parseMarkdown(token, h) { return { type: 'callout', attrs: { kind: token.kind, title: token.title, fold: token.fold, colour: token.colour, icon: token.icon }, content: h.parseChildren(token.tokens).length ? h.parseChildren(token.tokens) : [{ type: 'paragraph' }] }; },
  renderMarkdown(node, h) {
    const title = node.attrs.title ? ` ${node.attrs.title}` : '';
    const custom = node.attrs.colour || node.attrs.icon ? ` <!--linear-notes-callout:${encodeURIComponent(JSON.stringify({ colour: node.attrs.colour, icon: node.attrs.icon }))}-->` : '';
    return `> [!${node.attrs.kind.toUpperCase()}]${node.attrs.fold || ''}${title}${custom}\n` + h.renderChildren(node.content, '\n\n').trimEnd().split('\n').map(line => `> ${line}`).join('\n');
  },
  addKeyboardShortcuts() {
    return { Enter: () => {
      const { $from, empty } = this.editor.state.selection;
      if (empty && $from.parent.type.name === 'paragraph' && !$from.parent.textContent && this.editor.isActive('callout')) return this.editor.commands.lift('callout');
      return false;
    }};
  }
});

const RichLink = Node.create({
  name: 'richLink', group: 'block', atom: true, selectable: true, draggable: true,
  addAttributes() { return { url: { default: '' }, title: { default: '' } }; },
  parseHTML() { return [{ tag: 'div[data-rich-link]', getAttrs: el => ({ url: el.dataset.url, title: el.dataset.title }) }]; },
  renderHTML({ node }) { return ['div', { 'data-rich-link': '', 'data-url': node.attrs.url, 'data-title': node.attrs.title }, node.attrs.title]; },
  markdownTokenizer: {
    name: 'richLink', level: 'block', start: src => {
      const match = /^\[(?:\\.|[^\]\\])*\]\([^\n]+ "card"\)[ \t]*(?:\n|$)/m.exec(src);
      // Marked calls start after the first character: do not split an image's leading !.
      return match && match.index > 0 ? match.index : -1;
    },
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
      const dom = document.createElement('div'); dom.className = 'rich-card'; dom.tabIndex = 0; dom.role = 'button';
      dom.setAttribute('aria-label', `${node.attrs.title}. Click to select, click again to open.`);
      const icon = document.createElement('span'); icon.className = 'card-icon'; icon.textContent = '↗';
      const copy = document.createElement('span'); copy.className = 'card-copy';
      const title = document.createElement('span'); title.className = 'card-title'; title.textContent = node.attrs.title || node.attrs.url;
      const domain = document.createElement('span'); domain.className = 'card-domain';
      try { const url = new URL(node.attrs.url); domain.textContent = url.hostname.replace(/^www\./, '') + (url.pathname !== '/' ? url.pathname : ''); } catch { domain.textContent = node.attrs.url; }
      const arrow = document.createElement('span'); arrow.className = 'card-arrow'; arrow.textContent = '↗';
      copy.append(title, domain); dom.append(icon, copy, arrow);
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
      return { dom, stopEvent: () => true, selectNode: () => { dom.classList.add('selected'); dom.setAttribute('aria-pressed', 'true'); }, deselectNode: () => { dom.classList.remove('selected'); dom.setAttribute('aria-pressed', 'false'); } };
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

function imageURL(src) {
  if (typeof src !== 'string') return null;
  if (/^data:image\/(png|jpeg|gif|webp);base64,[a-z\d+/=\r\n]+$/i.test(src) && src.length <= 28 * 1024 * 1024) return src;
  const remote = webURL(src);
  if (remote && remote.startsWith('https:')) return assetBase && new URL(remote).hostname === 'uploads.linear.app' ? `${assetBase}//image?note=${encodeURIComponent(documentID)}&src=${encodeURIComponent(remote)}` : remote;
  if (!src || src.startsWith('/') || /[:\\\x00-\x1f]/.test(src)) return null;
  return assetBase ? `${assetBase}//image?note=${encodeURIComponent(documentID)}&src=${encodeURIComponent(src)}` : src;
}
const SafeImage = Image.extend({
  renderMarkdown(node) {
    const src = (node.attrs.src || '').replace(/</g, '%3C').replace(/>/g, '%3E').replace(/[\r\n]/g, '');
    const title = node.attrs.title ? ` "${String(node.attrs.title).replace(/[\\"]/g, '\\$&').replace(/[\r\n]/g, ' ')}"` : '';
    return `![${escapeLabel(node.attrs.alt || '')}](<${src}>${title})`;
  },
  addNodeView() { return ({ node, editor: ed, getPos }) => {
    const dom = document.createElement('figure'); dom.className = 'note-image'; dom.tabIndex = 0;
    dom.setAttribute('aria-label', 'Image; press Enter to show image actions');
    const image = document.createElement('img'); const fallback = document.createElement('div'); fallback.className = 'image-placeholder';
    const tools = document.createElement('div'); tools.className = 'image-tools'; tools.contentEditable = 'false';
    let current = node;
    const button = (label, action) => { const button = document.createElement('button'); button.type = 'button'; button.textContent = label; button.onclick = action; tools.append(button); };
    button('Replace', () => { const pos = getPos(); uploadRange = { from: pos, to: pos + current.nodeSize, replace: true }; $('image-file').click(); });
    button('Alt text', () => { imageAltPosition = getPos(); $('image-alt').value = current.attrs.alt || ''; $('image-dialog').showModal(); });
    button('Remove', () => { const pos = getPos(); ed.chain().focus().deleteRange({ from: pos, to: pos + current.nodeSize }).run(); });
    dom.append(image, fallback, tools);
    image.onclick = () => { if (mode === 'live') ed.commands.setNodeSelection(getPos()); };
    dom.onkeydown = event => {
      if (event.key === 'Enter' && event.target === dom && mode === 'live') { event.preventDefault(); ed.commands.setNodeSelection(getPos()); tools.querySelector('button').focus(); }
      if (event.key === 'Escape') { event.preventDefault(); ed.commands.focus(); }
    };
    const draw = next => {
      current = next; image.alt = next.attrs.alt || 'Image'; image.title = next.attrs.title || '';
      const src = imageURL(next.attrs.src); fallback.textContent = `Image unavailable · ${next.attrs.alt || next.attrs.src}`;
      fallback.hidden = Boolean(src); image.hidden = !src;
      if (src) { image.onload = () => { fallback.hidden = true; image.hidden = false; }; image.onerror = () => { fallback.hidden = false; image.hidden = true; }; if (image.getAttribute('src') !== src) image.src = src; }
      else image.removeAttribute('src');
    };
    draw(node);
    return { dom, update: next => { if (next.type.name !== 'image') return false; draw(next); return true; }, stopEvent: event => tools.contains(event.target),
      selectNode: () => dom.classList.add('selected'), deselectNode: () => dom.classList.remove('selected') };
  }; }
});

const ImageParagraph = Paragraph.extend({
  parseMarkdown(token, helpers) {
    if (!token.tokens?.some(t => t.type === 'image')) return this.parent(token, helpers);
    const blocks = []; let inline = [];
    for (const node of helpers.parseInline(token.tokens)) {
      if (node.type === 'image') { if (inline.length) blocks.push(helpers.createNode('paragraph', undefined, inline)); inline = []; blocks.push(node); }
      else inline.push(node);
    }
    if (inline.length) blocks.push(helpers.createNode('paragraph', undefined, inline));
    return blocks;
  }
});

function uploadImage(file, range = editor.state.selection) {
  if (mode !== 'live' || !file) return;
  if (!['image/png', 'image/jpeg', 'image/gif', 'image/webp'].includes(file.type) || file.size > 20 * 1024 * 1024) {
    $('image-error').textContent = 'Choose a PNG, JPEG, GIF, or WebP image under 20 MB.'; $('image-error').hidden = false; return;
  }
  const request = String(++imageRequest), instance = editor;
  imageRequests.set(request, { id: documentID, editor: instance, from: range.from, to: range.to, replace: range.replace === true, alt: file.name.replace(/\.[^.]+$/, '') });
  const reader = new FileReader();
  reader.onload = () => {
    const pending = imageRequests.get(request);
    if (!pending || instance !== editor || mode !== 'live') { imageRequests.delete(request); return; }
    send('attachment', { id: pending.id, request, data: String(reader.result).split(',')[1] });
  };
  reader.onerror = () => { imageRequests.delete(request); $('image-error').textContent = 'This image could not be read.'; $('image-error').hidden = false; };
  reader.readAsDataURL(file);
}
function receiveAttachment(payload) {
  const pending = imageRequests.get(payload.request); imageRequests.delete(payload.request);
  if (!pending || pending.editor !== editor || pending.id !== documentID || payload.id !== documentID || mode !== 'live') return;
  if (payload.error) { $('image-error').textContent = payload.error; $('image-error').hidden = false; return; }
  if (!imageURL(payload.src) || (pending.replace && editor.state.doc.nodeAt(pending.from)?.type.name !== 'image')) return;
  const chain = editor.chain().focus();
  if (pending.replace) {
    const node = editor.state.doc.nodeAt(pending.from);
    chain.setNodeSelection(pending.from).updateAttributes('image', { ...node.attrs, src: payload.src }).run();
  } else chain.setTextSelection({ from: pending.from, to: Math.max(pending.from, pending.to) }).setImage({ src: payload.src, alt: pending.alt }).run();
  $('image-error').hidden = true;
}
$('image-file').addEventListener('change', () => { uploadImage($('image-file').files[0], uploadRange || editor.state.selection); uploadRange = null; $('image-file').value = ''; });
$('image-dialog').addEventListener('close', () => {
  if ($('image-dialog').returnValue === 'save' && mode === 'live' && editor.state.doc.nodeAt(imageAltPosition)?.type.name === 'image') {
    editor.chain().focus().setNodeSelection(imageAltPosition).updateAttributes('image', { alt: $('image-alt').value.trim() }).run();
  }
});
function cleanIcon(value) {
  if (typeof value !== 'string') return '';
  return [...new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(value.replace(/[\x00-\x1f]/g, '').trim())][0]?.segment || '';
}
function showCallout(position, anchor) {
  if (mode !== 'live') return;
  const node = editor.state.doc.nodeAt(position); if (node?.type.name !== 'callout') return;
  calloutPosition = position; calloutColour = node.attrs.colour;
  $('callout-colour').value = node.attrs.colour || '#8794f5'; $('callout-icon').value = node.attrs.icon;
  const dialog = $('callout-dialog'); dialog.showModal();
  const rect = anchor.getBoundingClientRect();
  dialog.style.left = `${Math.max(12, Math.min(rect.left, innerWidth - dialog.offsetWidth - 12))}px`;
  dialog.style.top = `${Math.max(12, Math.min(rect.bottom + 8, innerHeight - dialog.offsetHeight - 12))}px`;
}
$('callout-colour').addEventListener('input', () => { calloutColour = $('callout-colour').value; });
document.querySelectorAll('[data-callout-colour]').forEach(button => button.onclick = () => { calloutColour = button.dataset.calloutColour; $('callout-colour').value = calloutColour || '#8794f5'; });
document.querySelectorAll('[data-callout-icon]').forEach(button => button.onclick = () => { $('callout-icon').value = button.dataset.calloutIcon; });
$('callout-dialog').addEventListener('close', () => {
  const node = editor.state.doc.nodeAt(calloutPosition);
  if ($('callout-dialog').returnValue === 'save' && mode === 'live' && node?.type.name === 'callout') {
    editor.view.dispatch(editor.state.tr.setNodeMarkup(calloutPosition, undefined, { ...node.attrs, colour: calloutColour, icon: cleanIcon($('callout-icon').value) }));
  }
  editor.commands.focus(); calloutPosition = null;
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
    extensions: [StarterKit.configure({ paragraph: false, heading: { levels: [1, 2, 3, 4, 5, 6] }, link: { openOnClick: false, autolink: true, isAllowedUri: (url, context) => context.defaultValidate(url) || relativeNote(url) }, trailingNode: false }), ImageParagraph, Markdown, Placeholder.configure({ placeholder: 'Start writing, or type / for commands…' }), TaskList, TaskItem.configure({ nested: true, HTMLAttributes: { 'data-type': 'taskItem' } }), TableKit, SafeImage.configure({ allowBase64: true }), Callout, RichLink, RawHTML, LinearKeys, FindHighlights],
    content: markdown, contentType: 'markdown', editable: mode !== 'reading',
    editorProps: {
      attributes: { 'aria-label': mode === 'reading' ? 'Read document' : 'Edit document', role: 'textbox', 'aria-multiline': 'true', spellcheck: 'true', tabindex: '0' },
      handlePaste(view, event) {
        if (mode !== 'live') return false;
        const image = Array.from(event.clipboardData?.files || []).find(file => file.type.startsWith('image/'));
        if (image) { event.preventDefault(); uploadImage(image, view.state.selection); return true; }
        const text = event.clipboardData?.getData('text/plain')?.trim();
        if (webURL(text)) { event.preventDefault(); showLink(text); return true; }
        return false;
      },
      handleDrop(view, event, _slice, moved) {
        if (mode !== 'live' || moved) return false;
        const image = Array.from(event.dataTransfer?.files || []).find(file => file.type.startsWith('image/'));
        if (!image) return false;
        const pos = view.posAtCoords({ left: event.clientX, top: event.clientY })?.pos ?? view.state.selection.from;
        event.preventDefault(); uploadImage(image, { from: pos, to: pos }); return true;
      },
      handleKeyDown(_view, event) {
        if (!$('slash').hidden) {
          if (['ArrowDown', 'ArrowUp'].includes(event.key)) { event.preventDefault(); slashIndex = (slashIndex + (event.key === 'ArrowDown' ? 1 : slashMatches.length - 1)) % slashMatches.length; drawSlash(); return true; }
          if (event.key === 'Enter' && slashMatches.length) { event.preventDefault(); chooseSlash(slashMatches[slashIndex]); return true; }
          if (event.key === 'Escape') { hideSlash(); return true; }
        }
        return false;
      }
    },
    onUpdate() { if (!loading) { currentMarkdown = frontmatter + instance.getMarkdown(); notifyChange(); updateSlash(); reportOutline(); refreshFind(); reportView(); } },
    onTransaction({ transaction }) {
      for (const pending of imageRequests.values()) {
        if (pending.editor !== instance) continue;
        const mapped = transaction.mapping.mapResult(pending.from, 1);
        pending.from = mapped.pos; pending.to = transaction.mapping.map(pending.to, -1);
        if (pending.replace && mapped.deleted) pending.editor = null;
      }
    },
    onSelectionUpdate() { if (!loading) { updateSlash(); updateBubble(); reportView(); } }
  });
  return instance;
}

function splitFrontmatter(text) {
  const match = /^(\uFEFF?---\r?\n(?:[\s\S]*?\r?\n)?(?:---|\.\.\.)[ \t]*(?:\r?\n|$))/.exec(text);
  return match ? [match[0], text.slice(match[0].length)] : ['', text];
}
function propertiesText() { return splitFrontmatter(currentMarkdown)[0].replace(/^\uFEFF?---\r?\n/, '').replace(/(?:^|\r?\n)(?:---|\.\.\.)[ \t]*\r?\n?$/, ''); }
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
function propertyRows() {
  // ponytail: preview simple top-level keys; the property editor preserves the complete source for complex YAML.
  const rows = [];
  for (const line of propertiesText().split('\n')) {
    const match = /^(\w[\w -]*):[ \t]*(.*)$/.exec(line);
    if (match) rows.push({ name: match[1], value: match[2] });
    else if (rows.length && line.trim()) rows.at(-1).value += `\n${line}`;
  }
  return rows;
}
function reportStats() { send('properties', { id: documentID, text: propertiesText(), rows: propertyRows() }); const body = splitFrontmatter(currentMarkdown)[1]; send('stats', { id: documentID, words: body.trim().split(/\s+/).filter(Boolean).length }); }
function loadDocument(payload) {
  clearTimeout(viewTimer);
  loading = true; documentID = payload.id; currentMarkdown = payload.markdown; mode = payload.mode || 'live';
  positions = payload.state?.positions || {}; noteLinks = payload.notes || []; $('find').hidden = true; findMatches = [];
  assetBase = payload.assetBase || ''; imageRequests.clear(); activeHeading = -1;
  for (const dialog of document.querySelectorAll('dialog[open]')) dialog.close('cancel');
  [frontmatter] = splitFrontmatter(currentMarkdown);
  editor?.destroy(); $('editor').replaceChildren(); editor = makeEditor(splitFrontmatter(currentMarkdown)[1]);
  applyMode(); hideSlash(); $('bubble').hidden = true; textSize(payload.textSize || 15); restorePosition(positions[mode]); loading = false; reportStats(); reportOutline();
  if (payload.focus) editor.commands.focus('start'); if (payload.find) showFind(payload.find, false);
}
function applyMode() {
  document.body.dataset.mode = mode;
  $('source').hidden = mode !== 'source'; $('editor').hidden = mode === 'source';
  $('properties').hidden = mode === 'source';
  $('source').value = currentMarkdown; resizeSource(); editor.setEditable(mode === 'live', false); drawProperties();
  editor.view.dom.setAttribute('aria-label', mode === 'reading' ? 'Read document' : 'Edit document');
  editor.view.dom.setAttribute('aria-readonly', String(mode === 'reading'));
  document.querySelectorAll('input[type=checkbox]').forEach(input => input.disabled = mode === 'reading');
  document.querySelectorAll('.callout-icon').forEach(button => button.disabled = mode !== 'live');
}
function setMode(next) {
  if (!['source', 'reading', 'live'].includes(next) || next === mode) return;
  viewState(); loading = true;
  if (mode === 'source') { [frontmatter] = splitFrontmatter(currentMarkdown); editor.destroy(); $('editor').replaceChildren(); editor = makeEditor(splitFrontmatter(currentMarkdown)[1]); }
  mode = next; applyMode(); hideSlash(); $('bubble').hidden = true; restorePosition(positions[mode]); loading = false; reportOutline(); refreshFind(); reportView();
}
function resizeSource() { const field = $('source'); field.style.height = 'auto'; field.style.height = `${Math.max(520, field.scrollHeight)}px`; }
$('source').addEventListener('input', () => { currentMarkdown = $('source').value; send('change', { id: documentID, markdown: currentMarkdown }); reportStats(); resizeSource(); refreshFind(); reportView(); });
$('source').addEventListener('select', reportView);
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
  { id: 'image', icon: '▧', name: 'Image', desc: 'Insert a local image' },
];
function updateSlash() {
  if (mode !== 'live' || !editor) return hideSlash();
  const { $from, empty } = editor.state.selection;
  if (!empty || $from.parent.type.name !== 'paragraph') return hideSlash();
  const before = $from.parent.textBetween(0, $from.parentOffset);
  const match = /^\/([\w ]*)$/.exec(before);
  if (!match) return hideSlash();
  slashRange = { from: $from.start(), to: $from.pos };
  slashMatches = slashCommands.filter(command => command.name.toLowerCase().includes(match[1].toLowerCase()));
  slashIndex = Math.min(slashIndex, Math.max(0, slashMatches.length - 1)); drawSlash();
}
function drawSlash() {
  const menu = $('slash'); menu.replaceChildren();
  if (!slashMatches.length) return hideSlash();
  slashMatches.forEach((command, index) => {
    const button = document.createElement('button'); button.className = `slash-option${index === slashIndex ? ' selected' : ''}`; button.id = `slash-option-${index}`; button.role = 'option'; button.setAttribute('aria-selected', String(index === slashIndex));
    const icon = document.createElement('span'); icon.className = 'slash-icon'; icon.textContent = command.icon;
    const copy = document.createElement('span'); const name = document.createElement('span'); name.className = 'slash-name'; name.textContent = command.name;
    button.title = command.desc;
    const shortcut = document.createElement('span'); shortcut.className = 'slash-shortcut'; shortcut.textContent = command.shortcut || '';
    copy.append(name); button.append(icon, copy, shortcut);
    if (index && command.group !== slashMatches[index - 1].group) button.classList.add('group-start');
    button.onmousedown = e => { e.preventDefault(); chooseSlash(command); };
    button.onclick = e => { if (e.detail === 0) chooseSlash(command); };
    menu.append(button);
  });
  const coords = editor.view.coordsAtPos(editor.state.selection.from); menu.hidden = false;
  editor.view.dom.setAttribute('aria-controls', 'slash'); editor.view.dom.setAttribute('aria-expanded', 'true'); editor.view.dom.setAttribute('aria-activedescendant', `slash-option-${slashIndex}`);
  menu.style.left = `${Math.min(Math.max(10, coords.left), innerWidth - menu.offsetWidth - 12)}px`;
  menu.style.top = `${Math.max(12, Math.min(coords.bottom + 8, innerHeight - menu.offsetHeight - 12))}px`;
  menu.querySelector('.selected')?.scrollIntoView({ block: 'nearest' });
}
function hideSlash() { $('slash').hidden = true; slashRange = null; slashIndex = 0; editor?.view.dom.setAttribute('aria-expanded', 'false'); editor?.view.dom.removeAttribute('aria-activedescendant'); }
function chooseSlash(command) { if (slashRange) editor.chain().focus().deleteRange(slashRange).run(); hideSlash(); execute(command.id); }

function showLink(url = '') {
  if (mode !== 'live') return;
  linkRange = { from: editor.state.selection.from, to: editor.state.selection.to };
  $('link-url').value = url || editor.getAttributes('link').href || '';
  $('link-title').value = editor.state.doc.textBetween(linkRange.from, linkRange.to, ' ');
  $('note-query').value = ''; drawNoteLinks(); validateLink();
  $('link-dialog').showModal(); $('link-url').focus();
}
function relativeNote(url) {
  if (!url || /^[\/]|[:\\\x00-\x1f]/.test(url)) return false;
  try { return /\.(md|markdown)$/i.test(decodeURIComponent(url.split(/[?#]/)[0])); } catch { return false; }
}
function validateLink() {
  const value = $('link-url').value.trim();
  $('link-url').setCustomValidity(webURL(value) || relativeNote(value) ? '' : 'Choose a note or enter an http(s) URL.');
  $('link-form').querySelector('[value=card]').disabled = !webURL(value);
}
$('link-url').oninput = validateLink;
function drawNoteLinks() {
  const query = folded($('note-query').value).value; $('note-links').replaceChildren();
  for (const note of noteLinks.filter(note => folded(note.path).value.includes(query)).slice(0, 8)) {
    const button = document.createElement('button'); button.type = 'button'; button.textContent = note.title;
    const path = document.createElement('small'); path.textContent = note.path; button.append(path);
    button.onclick = () => { $('link-url').value = note.reference; if (!$('link-title').value.trim()) $('link-title').value = note.title; validateLink(); $('link-form').querySelector('[value=link]').focus(); };
    $('note-links').append(button);
  }
}
$('note-query').oninput = drawNoteLinks;
$('link-dialog').addEventListener('close', () => {
  const result = $('link-dialog').returnValue;
  if (result === 'cancel' || !['link', 'card'].includes(result)) { editor.commands.focus(); return; }
  const value = $('link-url').value.trim(), url = webURL(value) || (relativeNote(value) ? value : null); if (!url) return;
  const title = $('link-title').value.trim() || (webURL(url) ? new URL(url).hostname.replace(/^www\./, '') : decodeURIComponent(url.split('/').at(-1)).replace(/\.(md|markdown)$/i, ''));
  const chain = editor.chain().focus().setTextSelection(linkRange);
  if (result === 'card' && webURL(url)) chain.insertContent([{ type: 'richLink', attrs: { url, title } }, { type: 'paragraph' }]).run();
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
    case 'paragraph': {
      $('bubble').hidden = true; slashMatches = slashCommands.slice(0, 5); slashIndex = 0; slashRange = null; drawSlash(); return;
    }
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
    case 'image': uploadRange = { from: editor.state.selection.from, to: editor.state.selection.to }; $('image-file').click(); return;
    case 'undo': return editor.commands.undo();
    case 'redo': return editor.commands.redo();
  }
}
slashCommands[0].id = 'text';
for (const command of slashCommands) {
  command.group = ['text', 'h1', 'h2', 'h3', 'h4'].includes(command.id) ? 0 : ['bullet', 'ordered', 'task'].includes(command.id) ? 1 : 2;
  command.shortcut = /^h[1-4]$/.test(command.id) ? `⌘ ⌥ ${command.id[1]}` : ({ bullet: '⌘ ⇧ 8', ordered: '⌘ ⇧ 9', task: '⌘ ⇧ 7', codeBlock: '⌘ ⇧ \\' })[command.id];
}
document.querySelectorAll('[data-command]').forEach(button => {
  button.addEventListener('mousedown', e => { e.preventDefault(); execute(button.dataset.command); updateBubble(); });
  button.addEventListener('click', e => { if (e.detail === 0) { execute(button.dataset.command); updateBubble(); } });
});
function updateBubble() {
  const { from, to, empty } = editor.state.selection;
  const bubble = $('bubble');
  if (empty || mode !== 'live' || !$('slash').hidden || !$('find').hidden || editor.state.selection.node) { bubble.hidden = true; return; }
  const start = editor.view.coordsAtPos(from), end = editor.view.coordsAtPos(to);
  bubble.hidden = false;
  bubble.style.top = `${Math.max(12, start.top - bubble.offsetHeight - 8)}px`;
  bubble.style.left = `${Math.max(12, Math.min((start.left + end.left) / 2 - bubble.offsetWidth / 2, innerWidth - bubble.offsetWidth - 12))}px`;
  for (const button of bubble.querySelectorAll('[data-command]')) {
    const mark = { strike: 'strike', codeBlock: 'codeBlock', bullet: 'bulletList', task: 'taskList', quote: 'blockquote' }[button.dataset.command] || button.dataset.command;
    const active = editor.isActive(mark);
    button.classList.toggle('active', active);
    button.setAttribute('aria-pressed', String(active));
  }
}
document.addEventListener('click', e => {
  const anchor = e.target.closest('a');
  if (anchor) {
    e.preventDefault();
    if (mode === 'reading' || e.metaKey) {
      openReference(anchor.getAttribute('href'));
    }
  }
  if (!e.target.closest('#slash') && !e.target.closest('#bubble')) hideSlash();
});
window.addEventListener('resize', () => { $('bubble').hidden = true; hideSlash(); });
const headingElements = () => mode === 'source' ? [] : Array.from(document.querySelectorAll('.tiptap h1,.tiptap h2,.tiptap h3,.tiptap h4,.tiptap h5,.tiptap h6'));
function headingIndex(headings = headingElements()) {
  if (headings.length && window.scrollY > 0 && window.scrollY + innerHeight >= document.documentElement.scrollHeight - 2) return headings.length - 1;
  let active = headings.length ? 0 : -1;
  headings.forEach((heading, index) => { if (heading.getBoundingClientRect().top <= 110) active = index; });
  return active;
}
function reportOutline() {
  const headings = headingElements(); activeHeading = headingIndex(headings);
  send('outline', { id: documentID, headings: headings.map((heading, index) => ({ index, level: Number(heading.tagName[1]), text: heading.textContent })), active: activeHeading });
}
function jumpToHeading(index) {
  const heading = headingElements()[index]; if (!heading) return;
  heading.scrollIntoView({ block: 'start', behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth' });
}
window.addEventListener('scroll', () => {
  reportView();
  $('bubble').hidden = true; hideSlash();
  const next = headingIndex(); if (next !== activeHeading) { activeHeading = next; send('headingActive', { id: documentID, active: next }); }
}, { passive: true });
window.addEventListener('keydown', e => {
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'f') { e.preventDefault(); showFind(); }
  if (e.key === 'Enter' && e.target.closest('a') && (mode === 'reading' || e.metaKey)) { e.preventDefault(); openReference(e.target.closest('a').getAttribute('href')); }
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 's' && !e.shiftKey) { e.preventDefault(); send('save'); }
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'p' && !e.shiftKey) { e.preventDefault(); send('quickOpen'); }
});

let printState;
async function preparePrint() {
  printState = viewState(); printing = true; clearTimeout(viewTimer); setMode('reading');
  await Promise.race([Promise.allSettled(Array.from(document.querySelectorAll('.note-image img')).map(image => image.decode())), new Promise(resolve => setTimeout(resolve, 5000))]);
  for (const image of document.querySelectorAll('.note-image img')) {
    if (!image.complete || !image.naturalWidth) { image.hidden = true; image.parentElement.querySelector('.image-placeholder').hidden = false; }
  }
}
function finishPrint() { if (printState) { positions = printState.positions; setMode(printState.mode); restorePosition(positions[mode]); printState = null; } printing = false; }
window.notes = { load: loadDocument, setMode, command: execute, getMarkdown: () => currentMarkdown, getJSON: () => editor.getJSON(), focus: () => mode === 'source' ? $('source').focus() : editor.commands.focus(), properties: showProperties, attachment: receiveAttachment, jumpToHeading,
  find: term => showFind(term, false), showFind, viewState, textSize, setNotes: notes => { noteLinks = notes; }, preparePrint, finishPrint };
send('ready');
// A browser harness loads only explicit fixtures; production content arrives from the native host.
loadDocument({ id: '', markdown: '', mode: 'live' });
