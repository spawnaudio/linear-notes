import { Editor, Node, Extension, InputRule, mergeAttributes } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import { Markdown } from '@tiptap/markdown';
import Placeholder from '@tiptap/extension-placeholder';
import TaskList from '@tiptap/extension-task-list';
import TaskItem from '@tiptap/extension-task-item';
import { TableKit } from '@tiptap/extension-table';
import Image from '@tiptap/extension-image';
import Paragraph from '@tiptap/extension-paragraph';
import CodeBlock from '@tiptap/extension-code-block';
import { Plugin, PluginKey, TextSelection } from '@tiptap/pm/state';
import { Decoration, DecorationSet } from '@tiptap/pm/view';
import { closeHistory } from '@tiptap/pm/history';

const $ = id => document.getElementById(id);
const send = (type, payload = {}) => window.webkit?.messageHandlers?.notes?.postMessage({ type, ...payload });
window.addEventListener('pointerdown', () => send('focus', { id: documentID }));
window.addEventListener('focusin', () => send('focus', { id: documentID }));
let documentID = '', currentMarkdown = '', frontmatter = '', mode = 'live', loading = false, assetBase = '';
let editor, slashRange = null, slashIndex = 0, slashMatches = [], linkRange = null;
let calloutPosition = null, calloutColour = '', imageAltPosition = null, uploadRange = null, imageRequest = 0, activeHeading = -1;
const imageRequests = new Map();
let noteLinks = [], positions = {}, viewTimer, printing = false;
let title = '', refocus = '', icons = {}, menuKind = 'slash', menuAnchor = null, menuQuery = '', outlineKey = '', toastTimer;
let findMatches = [], findIndex = 0;
const sourceVersions = new Map();
const sourceText = text => text.replace(/\r\n?/g, '\n');
// SF Symbols arrive from the native host as template masks; text glyphs stand in until then and in the browser harness.
function icon(name, fallback = '') {
  const element = document.createElement('span'); element.className = 'icon'; element.dataset.icon = name; element.dataset.fallback = fallback;
  element.setAttribute('aria-hidden', 'true'); drawIcon(element); return element;
}
function drawIcon(element) {
  const mask = icons[element.dataset.icon];
  element.classList.toggle('masked', Boolean(mask)); element.style.setProperty('--mask', mask ? `url("${mask}")` : '');
  element.textContent = mask ? '' : element.dataset.fallback || '';
}
function setIcons(next) {
  icons = Object.fromEntries(Object.entries(next || {}).filter(([name, url]) => /^[a-z.]+$/.test(name) && /^data:image\/png;base64,[a-z\d+/=]+$/i.test(url)));
  for (const [name, url] of Object.entries(icons)) document.documentElement.style.setProperty(`--icon-${name.replace(/\./g, '-')}`, `url("${url}")`);
  document.documentElement.classList.toggle('symbols', Object.keys(icons).length > 0);
  document.querySelectorAll('.icon[data-icon]').forEach(drawIcon);
}
document.querySelectorAll('.icon[data-icon]').forEach(drawIcon);
function copyText(text, message = 'Copied to clipboard') {
  if (window.webkit?.messageHandlers?.notes) send('copy', { text }); else navigator.clipboard?.writeText(text).catch(() => {});
  const toast = $('toast'); toast.textContent = message; toast.hidden = false;
  clearTimeout(toastTimer); toastTimer = setTimeout(() => { toast.hidden = true; }, 1600);
}
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
    const part = (character === '\n' && text[offset - 1] === '\r' ? '' : character === '\r' ? '\n' : character).normalize('NFD').replace(/\p{M}/gu, '').toLocaleLowerCase();
    for (let index = 0; index < part.length; index++) { starts.push(offset); ends.push(offset + character.length); }
    if (!part && ends.length) ends[ends.length - 1] = offset + character.length;
    value += part; offset += character.length;
  }
  return { value, starts, ends };
}
function refreshFind(jump = false) {
  const term = folded($('find-text').value).value;
  findMatches = [];
  const collect = (text, base) => {
    const haystack = folded(text);
    for (let index = 0; term && (index = haystack.value.indexOf(term, index)) !== -1; index += term.length) {
      findMatches.push({ from: base + haystack.starts[index], to: base + haystack.ends[index + term.length - 1] });
    }
  };
  if (!$('find').hidden && term) {
    if (mode === 'source') collect(currentMarkdown, 0);
    // shortcut: Live matches stay within textblocks; map block separators if cross-block search is needed.
    else editor.state.doc.descendants((node, pos) => { if (node.isTextblock) { collect(node.textBetween(0, node.content.size, '\n', leaf => leaf.type.name === 'hardBreak' ? '\n' : '\ufffc'), pos + 1); return false; } });
  }
  findIndex = Math.min(findIndex, Math.max(0, findMatches.length - 1));
  $('find-count').textContent = `${findMatches.length ? findIndex + 1 : 0} / ${findMatches.length}`;
  $('find-next').disabled = $('find-previous').disabled = !findMatches.length;
  $('find-toggle').disabled = $('replace-text').disabled = mode === 'reading';
  $('replace-current').disabled = $('replace-all').disabled = mode === 'reading' || !findMatches.length;
  editor.view.dispatch(editor.state.tr.setMeta('find', true));
  if (jump) jumpToMatch();
}
function jumpToMatch() {
  const match = findMatches[findIndex]; if (!match) return;
  if (mode === 'source') {
    $('source').setSelectionRange(sourceText(currentMarkdown.slice(0, match.from)).length, sourceText(currentMarkdown.slice(0, match.to)).length);
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
function toggleReplacement(visible = $('find-replacement').hidden) {
  $('find-replacement').hidden = !visible;
  $('find-toggle').setAttribute('aria-expanded', String(visible));
  $('find-toggle').setAttribute('aria-label', visible ? 'Hide replacement' : 'Show replacement');
}
function showFindAndReplace() { showFind(); if (mode !== 'reading') toggleReplacement(true); }
function replaceMatches(all = false) {
  if (mode === 'reading' || !findMatches.length) return;
  const matches = all ? [...findMatches] : [findMatches[findIndex]], replacement = $('replace-text').value;
  if (mode === 'source') {
    const from = matches[0].from, to = matches.at(-1).to;
    let next = currentMarkdown;
    for (const match of matches.reverse()) next = next.slice(0, match.from) + replacement + next.slice(match.to);
    // Textarea values normalize line endings; retain raw snapshots for native undo and redo.
    for (const version of [currentMarkdown, next]) if (version !== sourceText(version)) sourceVersions.set(sourceText(version), version);
    const insertion = next.slice(from, next.length - (currentMarkdown.length - to));
    const field = $('source'); field.focus();
    field.setSelectionRange(sourceText(currentMarkdown.slice(0, from)).length, sourceText(currentMarkdown.slice(0, to)).length);
    document.execCommand('insertText', false, sourceText(insertion));
  } else {
    const transaction = closeHistory(editor.state.tr);
    for (const match of matches.reverse()) {
      const start = transaction.doc.resolve(match.from), marks = start.nodeAfter?.marks || start.marks();
      const content = start.parent.type.spec.code ? (replacement ? editor.schema.text(replacement, marks) : []) : replacement.split('\n').flatMap((line, index) => [
        ...(index ? [editor.schema.nodes.hardBreak.create(null, null, marks)] : []), ...(line ? [editor.schema.text(line, marks)] : [])
      ]);
      transaction.replaceWith(match.from, match.to, content);
    }
    findMatches = [];
    editor.view.dispatch(transaction);
    editor.view.dispatch(closeHistory(editor.state.tr));
  }
  refreshFind(true); $('replace-text').focus();
}
$('find-toggle').onclick = () => toggleReplacement();
$('replace-current').onclick = () => replaceMatches(); $('replace-all').onclick = () => replaceMatches(true);
$('find-text').oninput = () => { findIndex = 0; refreshFind(true); };
function nextMatch(direction) { if (findMatches.length) { findIndex = (findIndex + direction + findMatches.length) % findMatches.length; refreshFind(true); } }
$('find-next').onclick = () => nextMatch(1); $('find-previous').onclick = () => nextMatch(-1); $('find-close').onclick = closeFind;
$('find').onkeydown = event => {
  if (event.key === 'Enter' && event.target === $('find-text') && !event.altKey) { event.preventDefault(); nextMatch(event.shiftKey ? -1 : 1); }
  if (event.key === 'Enter' && event.target === $('replace-text') && !event.shiftKey) { event.preventDefault(); replaceMatches(); }
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
        dom.style.setProperty('--custom-callout', colour || 'var(--callout-color)'); dom.dataset.custom = String(Boolean(colour));
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
      const badge = document.createElement('span'); badge.className = 'card-icon'; badge.append(icon('globe', '↗'));
      const copy = document.createElement('span'); copy.className = 'card-copy';
      const title = document.createElement('span'); title.className = 'card-title'; title.textContent = node.attrs.title || node.attrs.url;
      const domain = document.createElement('span'); domain.className = 'card-domain';
      try { const url = new URL(node.attrs.url); domain.textContent = url.hostname.replace(/^www\./, '') + (url.pathname !== '/' ? url.pathname : ''); } catch { domain.textContent = node.attrs.url; }
      const arrow = icon('arrow.up.right', '↗'); arrow.classList.add('card-arrow');
      copy.append(title, domain); dom.append(badge, copy, arrow);
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

// Collapsible sections are stored as HTML <details>, which other Markdown apps also render.
const escapeHTML = text => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const unescapeHTML = text => text.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&');
function detailsNode(schema, summary, blocks) {
  return schema.nodes.details.create({ open: true }, [
    schema.nodes.detailsSummary.create(null, summary ? schema.text(summary) : null),
    schema.nodes.detailsContent.create(null, blocks.length ? blocks : schema.nodes.paragraph.create())
  ]);
}
const DetailsSummary = Node.create({
  name: 'detailsSummary', content: 'text*', marks: '', defining: true, isolating: true, selectable: false,
  parseHTML() { return [{ tag: 'div[data-summary]' }]; },
  renderHTML() { return ['div', { class: 'details-summary', 'data-summary': '', 'data-placeholder': 'Collapsible section' }, 0]; }
});
const DetailsContent = Node.create({
  name: 'detailsContent', content: 'block+', defining: true, selectable: false,
  parseHTML() { return [{ tag: 'div[data-details-content]' }]; },
  renderHTML() { return ['div', { class: 'details-content', 'data-details-content': '' }, 0]; }
});
const Details = Node.create({
  name: 'details', group: 'block', content: 'detailsSummary detailsContent', defining: true,
  addAttributes() { return { open: { default: true } }; },
  parseHTML() { return [{ tag: 'div[data-details]' }]; },
  renderHTML() { return ['div', { class: 'details', 'data-details': '' }, 0]; },
  addNodeView() {
    return ({ node, editor: ed, getPos }) => {
      const dom = document.createElement('div'); dom.className = 'details';
      const toggle = document.createElement('button'); toggle.type = 'button'; toggle.className = 'details-toggle'; toggle.contentEditable = 'false';
      toggle.append(icon('chevron.right', '›'));
      const contentDOM = document.createElement('div'); contentDOM.className = 'details-body';
      let open = node.attrs.open, current = node;
      const draw = () => { dom.classList.toggle('open', open); toggle.setAttribute('aria-expanded', String(open)); toggle.setAttribute('aria-label', open ? 'Collapse section' : 'Expand section'); };
      toggle.onmousedown = event => event.preventDefault();
      // Live mode keeps the state in the file, as checkboxes do; Reading only changes the view.
      toggle.onclick = () => {
        open = !open; draw();
        if (mode === 'live' && typeof getPos() === 'number') ed.view.dispatch(ed.state.tr.setNodeMarkup(getPos(), undefined, { ...current.attrs, open }));
      };
      dom.append(toggle, contentDOM); draw();
      return { dom, contentDOM,
        update: next => { if (next.type.name !== 'details') return false; if (next.attrs.open !== current.attrs.open) { open = next.attrs.open; draw(); } current = next; return true; },
        stopEvent: event => toggle.contains(event.target), ignoreMutation: mutation => toggle.contains(mutation.target) || mutation.target === dom && mutation.type === 'attributes' };
    };
  },
  addInputRules() {
    return [new InputRule({ find: /^>>>\s$/, handler: ({ state, range }) => {
      const $start = state.doc.resolve(range.from);
      if ($start.parent.type.name !== 'paragraph' || $start.parent.textContent !== '>>>') return null;
      const from = $start.before(), tr = state.tr;
      if (!$start.node($start.depth - 1).canReplaceWith($start.index($start.depth - 1), $start.index($start.depth - 1) + 1, state.schema.nodes.details)) return null;
      tr.replaceWith(from, $start.after(), detailsNode(state.schema, '', [])); tr.setSelection(TextSelection.create(tr.doc, from + 2));
    } })];
  },
  addKeyboardShortcuts() {
    return { Enter: () => {
      const { state } = this.editor, { $from, empty } = state.selection;
      if (!empty || $from.parent.type.name !== 'detailsSummary') return false;
      const details = $from.node($from.depth - 1), position = $from.before($from.depth - 1), tr = state.tr;
      if (!details.attrs.open) tr.setNodeMarkup(position, undefined, { ...details.attrs, open: true });
      this.editor.view.dispatch(tr.setSelection(TextSelection.create(tr.doc, $from.after() + 2)).scrollIntoView()); return true;
    }};
  },
  markdownTokenizer: {
    name: 'details', level: 'block', start: src => src.search(/^<details[\s>]/m),
    tokenize(src, _tokens, lexer) {
      const opening = /^<details( open)?>\s*<summary>([^\n]*?)<\/summary>[ \t]*\n/.exec(src);
      if (!opening) return;
      const tags = /^<details[\s>]|^<\/details>[ \t]*$/gm; tags.lastIndex = opening[0].length;
      for (let depth = 1, tag; (tag = tags.exec(src));) {
        depth += tag[0].startsWith('</') ? -1 : 1;
        if (depth) continue;
        const end = src.indexOf('\n', tag.index);
        return { type: 'details', raw: src.slice(0, end === -1 ? src.length : end + 1), open: Boolean(opening[1]), summary: unescapeHTML(opening[2]),
          tokens: lexer.blockTokens(src.slice(opening[0].length, tag.index)) };
      }
    }
  },
  parseMarkdown(token, h) {
    const content = h.parseChildren(token.tokens);
    return { type: 'details', attrs: { open: token.open }, content: [
      { type: 'detailsSummary', content: token.summary ? [{ type: 'text', text: token.summary }] : [] },
      { type: 'detailsContent', content: content.length ? content : [{ type: 'paragraph' }] }
    ] };
  },
  renderMarkdown(node, h) {
    const [summary, content] = node.content || [];
    const text = (summary?.content || []).map(child => child.text || '').join('');
    return `<details${node.attrs?.open ? ' open' : ''}>\n<summary>${escapeHTML(text)}</summary>\n\n${h.renderChildren(content?.content || [], '\n\n').trimEnd()}\n\n</details>`;
  }
});
function insertDetails() {
  const { state } = editor, { $from, $to } = state.selection, range = $from.blockRange($to);
  if (!range || !range.parent.canReplaceWith(range.startIndex, range.endIndex, state.schema.nodes.details)) return;
  const blocks = []; for (let index = range.startIndex; index < range.endIndex; index++) blocks.push(range.parent.child(index));
  const [first, ...rest] = blocks, summary = first?.type.name === 'paragraph' || first?.type.name === 'heading' ? first.textContent : '';
  const tr = state.tr.replaceWith(range.start, range.end, detailsNode(state.schema, summary, first && (summary || !first.textContent) && first.isTextblock ? rest : blocks));
  editor.view.dispatch(tr.setSelection(TextSelection.create(tr.doc, range.start + 2 + summary.length)).scrollIntoView()); editor.commands.focus();
}

// Linear's code block: a quiet panel with the language and a copy button on hover.
const CodeBlockView = CodeBlock.extend({
  addNodeView() {
    return ({ node }) => {
      const dom = document.createElement('div'); dom.className = 'code-block';
      const tools = document.createElement('div'); tools.className = 'code-tools'; tools.contentEditable = 'false';
      const language = document.createElement('span'); language.className = 'code-language';
      const copy = document.createElement('button'); copy.type = 'button'; copy.className = 'code-copy'; copy.title = 'Copy code'; copy.setAttribute('aria-label', 'Copy code');
      copy.append(icon('doc.on.doc', '⧉'));
      const pre = document.createElement('pre'), code = document.createElement('code'); pre.append(code);
      let current = node;
      copy.onmousedown = event => event.preventDefault(); copy.onclick = () => copyText(current.textContent, 'Code copied');
      tools.append(language, copy); dom.append(tools, pre);
      const draw = next => { current = next; language.textContent = next.attrs.language || ''; code.className = next.attrs.language ? `language-${next.attrs.language}` : ''; };
      draw(node);
      return { dom, contentDOM: code, update: next => { if (next.type.name !== 'codeBlock') return false; draw(next); return true; },
        stopEvent: event => tools.contains(event.target), ignoreMutation: mutation => tools.contains(mutation.target) };
    };
  }
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
    'Mod-k': () => { if (mode === 'live' && !editor.state.selection.empty) showLink(); else send('quickOpen'); return true; },
    'Mod-Alt-0': () => this.editor.commands.setParagraph(),
    'Mod-Enter': () => toggleTask(false),
    'Mod-Shift-Enter': () => toggleTask(true),
    ...Object.fromEntries([1, 2, 3, 4].map(level => [`Mod-Alt-${level}`, () => this.editor.commands.toggleHeading({ level })]))
  }; },
  addInputRules() {
    return [new InputRule({ find: /^\|--\s$/, handler: ({ range, chain }) => { chain().deleteRange(range).insertTable({ rows: 3, cols: 3, withHeaderRow: true }).run(); } })];
  }
});
// ⌘↩ checks the current checklist item, as in Linear; ⌘⇧↩ also sets its nested items.
function toggleTask(nested) {
  if (mode !== 'live') return false;
  const { $from } = editor.state.selection;
  for (let depth = $from.depth; depth > 0; depth--) {
    const node = $from.node(depth);
    if (node.type.name !== 'taskItem') continue;
    const checked = !node.attrs.checked, start = $from.before(depth), tr = editor.state.tr.setNodeMarkup(start, undefined, { ...node.attrs, checked });
    if (nested) node.descendants((child, offset) => { if (child.type.name === 'taskItem') tr.setNodeMarkup(start + 1 + offset, undefined, { ...child.attrs, checked }); });
    editor.view.dispatch(tr); return true;
  }
  return false;
}

function makeEditor(markdown) {
  const instance = new Editor({
    element: $('editor'),
    extensions: [StarterKit.configure({ paragraph: false, codeBlock: false, heading: { levels: [1, 2, 3, 4, 5, 6] }, link: { openOnClick: false, autolink: true, isAllowedUri: (url, context) => context.defaultValidate(url) || relativeNote(url) }, trailingNode: false }), ImageParagraph, CodeBlockView, Markdown,
      Placeholder.configure({ includeChildren: true, showOnlyCurrent: false, placeholder: ({ node }) => node.type.name === 'detailsSummary' ? 'Collapsible section' : 'Start writing, or type / for commands…' }),
      TaskList, TaskItem.configure({ nested: true, HTMLAttributes: { 'data-type': 'taskItem' } }), TableKit, SafeImage.configure({ allowBase64: true }), Callout, RichLink, RawHTML, Details, DetailsSummary, DetailsContent, LinearKeys, FindHighlights],
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
        // As in Linear, moving up from the first line reaches the title.
        if (event.key === 'ArrowUp' && !event.shiftKey && !event.metaKey && editor.state.selection.$from.index(0) === 0 && _view.endOfTextblock('up') && $('title').isContentEditable) {
          event.preventDefault(); focusTitle(); return true;
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
  const text = propertiesText(), chips = [];
  for (const match of text.matchAll(/^(\w[\w -]*):[ \t]*(.*)$/gm)) {
    const button = document.createElement('button'); button.className = 'property';
    const key = document.createElement('span'); key.className = 'property-key'; key.textContent = match[1];
    const value = document.createElement('span'); value.className = 'property-value'; value.textContent = match[2].replace(/^['"]|['"]$/g, '').replace(/^\[|\]$/g, '').replace(/,\s*/g, ' · ') || '…';
    button.append(key, value); button.onclick = showProperties; button.disabled = mode === 'reading'; chips.push(button);
  }
  if (chips.length) { const label = document.createElement('span'); label.className = 'properties-label'; label.textContent = 'Properties'; $('properties').append(label, ...chips); }
  if (mode === 'live') {
    const add = document.createElement('button'); add.className = `property-add${chips.length ? '' : ' empty'}`; add.onclick = showProperties;
    add.setAttribute('aria-label', chips.length ? 'Add property' : 'Add properties'); add.title = add.getAttribute('aria-label');
    add.append(icon('plus', '+')); if (!chips.length) add.append('Add properties');
    $('properties').append(add);
  }
  drawIconTile();
}
// The tile shows an `icon:` property when it is an emoji or a bundled symbol name.
function drawIconTile() {
  const value = (propertyRows().find(row => row.name === 'icon')?.value || '').replace(/^['"]|['"]$/g, '').trim();
  const tile = $('doc-icon'); tile.replaceChildren();
  if (icons[value]) tile.append(icon(value)); else if (value && !/^[\w.]+$/.test(value) && cleanIcon(value)) { tile.textContent = cleanIcon(value); tile.classList.add('emoji'); return; }
  else tile.append(icon('doc.text.fill', '▤'));
  tile.classList.remove('emoji');
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
// The title is the note's file name, renamed in place through the native host as in Linear.
function drawTitle() {
  const field = $('title'), editable = Boolean(documentID) && mode !== 'reading';
  $('title-block').hidden = !documentID;
  if (document.activeElement !== field) field.textContent = title;
  field.classList.toggle('empty', !field.textContent);
  field.contentEditable = editable ? 'plaintext-only' : 'false'; field.setAttribute('aria-readonly', String(!editable));
}
function focusTitle(selectAll = false) {
  const field = $('title'); field.focus();
  const range = document.createRange(); range.selectNodeContents(field); if (!selectAll) range.collapse(false);
  const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
}
function focusBody() {
  if (mode === 'source') { $('source').focus(); $('source').setSelectionRange(frontmatter.length, frontmatter.length); }
  else if (mode === 'live') editor.commands.focus('start');
}
function commitTitle(moveToBody) {
  const field = $('title'), next = field.textContent.replace(/[\r\n\t]+/g, ' ').replace(/[\/:]/g, '-').replace(/^[\s.]+/, '').trim().slice(0, 200);
  if (!next || mode === 'reading' || !documentID) { field.textContent = title; field.classList.toggle('empty', !title); }
  else if (next !== title) { title = next; field.textContent = next; if (moveToBody) refocus = next; send('rename', { id: documentID, title: next }); }
  if (moveToBody) focusBody();
}
$('title').addEventListener('keydown', event => {
  if (event.isComposing) return;
  if (event.key === 'Enter' || event.key === 'ArrowDown' && window.getSelection().focusOffset >= ($('title').textContent || '').length) { event.preventDefault(); commitTitle(true); }
  if (event.key === 'Escape') { event.preventDefault(); $('title').textContent = title; focusBody(); }
});
$('title').addEventListener('blur', () => commitTitle(false));
$('title').addEventListener('input', () => $('title').classList.toggle('empty', !$('title').textContent));
$('title').addEventListener('paste', event => {
  event.preventDefault(); document.execCommand('insertText', false, (event.clipboardData?.getData('text/plain') || '').replace(/\s+/g, ' '));
});
function loadDocument(payload) {
  clearTimeout(viewTimer);
  if (document.activeElement === $('title')) $('title').blur();
  loading = true; documentID = payload.id; currentMarkdown = payload.markdown; mode = payload.mode || 'live';
  title = typeof payload.title === 'string' ? payload.title : decodeURIComponent(documentID.split('/').at(-1) || '').replace(/\.(md|markdown)$/i, '');
  positions = payload.state?.positions || {}; noteLinks = payload.notes || []; $('find').hidden = true; findMatches = []; sourceVersions.clear(); toggleReplacement(false);
  assetBase = payload.assetBase || ''; imageRequests.clear(); activeHeading = -1;
  for (const dialog of document.querySelectorAll('dialog[open]')) dialog.close('cancel');
  [frontmatter] = splitFrontmatter(currentMarkdown);
  editor?.destroy(); $('editor').replaceChildren(); editor = makeEditor(splitFrontmatter(currentMarkdown)[1]);
  applyMode(); hideSlash(); hideHeadingHandle(); $('bubble').hidden = true; textSize(payload.textSize || 15); restorePosition(positions[mode]); loading = false; reportStats(); reportOutline();
  if (payload.focus && /^Untitled( \d+)?$/.test(title) && mode !== 'reading') focusTitle(true);
  else if (payload.focus) editor.commands.focus('start');
  else if (refocus && refocus === title) window.notes.focus();
  refocus = '';
  if (payload.find) showFind(payload.find, false);
}
function applyMode() {
  document.body.dataset.mode = mode;
  $('source').hidden = mode !== 'source'; $('editor').hidden = mode === 'source';
  $('properties').hidden = mode === 'source';
  $('source').value = currentMarkdown; resizeSource(); editor.setEditable(mode === 'live', false); drawProperties(); drawTitle();
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
$('source').addEventListener('input', () => { currentMarkdown = sourceVersions.get($('source').value) ?? $('source').value; send('change', { id: documentID, markdown: currentMarkdown }); reportStats(); resizeSource(); refreshFind(); reportView(); });
$('source').addEventListener('select', reportView);
$('source').addEventListener('keydown', e => { if (e.key === 'Tab') { e.preventDefault(); document.execCommand('insertText', false, '  '); } });

const slashCommands = [
  { id: 'text', icon: 'textformat', fallback: 'T', name: 'Text', group: 'Text' },
  ...[1, 2, 3, 4].map(level => ({ id: `h${level}`, label: `H${level}`, name: `Heading ${level}`, group: 'Text', shortcut: `⌘ ⌥ ${level}` })),
  { id: 'bullet', icon: 'list.bullet', fallback: '•', name: 'Bulleted list', group: 'Text', shortcut: '⌘ ⇧ 8' },
  { id: 'ordered', icon: 'list.number', fallback: '1.', name: 'Numbered list', group: 'Text', shortcut: '⌘ ⇧ 9' },
  { id: 'task', icon: 'checklist', fallback: '☑', name: 'Checklist', group: 'Text', shortcut: '⌘ ⇧ 7' },
  { id: 'quote', icon: 'quote.opening', fallback: '❞', name: 'Quote', group: 'Text', shortcut: '>' },
  { id: 'collapsible', icon: 'chevron.right', fallback: '›', name: 'Collapsible section', group: 'Text', shortcut: '>>>' },
  { id: 'divider', icon: 'minus', fallback: '—', name: 'Divider', group: 'Text', shortcut: '---' },
  { id: 'codeBlock', icon: 'curlybraces', fallback: '{}', name: 'Code block', group: 'Insert', shortcut: '⌘ ⇧ \\' },
  { id: 'table', icon: 'tablecells', fallback: '▦', name: 'Table', group: 'Insert', shortcut: '|--' },
  { id: 'image', icon: 'photo', fallback: '▧', name: 'Image', group: 'Insert' },
  { id: 'callout', icon: 'info.circle', fallback: 'ⓘ', name: 'Callout', group: 'Insert' },
  { id: 'tip', icon: 'lightbulb', fallback: '◇', name: 'Tip', group: 'Insert' },
  { id: 'warning', icon: 'exclamationmark.triangle', fallback: '△', name: 'Warning', group: 'Insert' },
  { id: 'noteLink', icon: 'doc.text', fallback: '▤', name: 'Link to note', group: 'Insert', shortcut: '@' },
  { id: 'link', icon: 'link', fallback: '↗', name: 'Link or rich card', group: 'Insert' },
  { id: 'date', icon: 'calendar', fallback: '▦', name: 'Today’s date', group: 'Insert' },
  { id: 'linearImport', icon: 'square.and.arrow.down', fallback: '↓', name: 'Import from Linear…', group: 'Linear' },
  { id: 'linearRefresh', icon: 'arrow.clockwise', fallback: '↻', name: 'Refresh from Linear…', group: 'Linear', imported: true },
];
const styleCommands = slashCommands.slice(0, 5), listCommands = slashCommands.filter(command => ['bullet', 'ordered', 'task'].includes(command.id));
const linearImport = () => /^linearDocumentId:/m.test(propertiesText());
// One suggestion menu serves `/` blocks, `@` note mentions, and the toolbar's style and list menus.
function updateSlash() {
  if (mode !== 'live' || !editor) return hideSlash();
  if (menuKind === 'style' || menuKind === 'list') { if (!$('slash').hidden) return; }
  const { $from, empty } = editor.state.selection;
  if (!empty || !$from.parent.isTextblock || $from.parent.type.spec.code) return hideSlash();
  const before = $from.parent.textBetween(0, $from.parentOffset, null, '￼');
  const slash = $from.parent.type.name === 'paragraph' && /^\/([\w ]*)$/.exec(before), mention = /(?:^|\s)@([^\s@￼]{0,40})$/.exec(before);
  if (slash) {
    menuKind = 'slash'; slashRange = { from: $from.start(), to: $from.pos }; menuQuery = slash[1];
    slashMatches = slashCommands.filter(command => command.name.toLowerCase().includes(slash[1].toLowerCase()) && (!command.imported || linearImport()));
  } else if (mention) {
    menuKind = 'mention'; slashRange = { from: $from.pos - mention[1].length - 1, to: $from.pos }; menuQuery = mention[1];
    const query = folded(mention[1]).value;
    slashMatches = noteLinks.filter(note => folded(note.title).value.includes(query) || folded(note.path).value.includes(query)).slice(0, 8)
      .map(note => ({ id: 'mention', icon: 'doc.text', fallback: '▤', name: note.title, hint: note.path.split('/').slice(0, -1).join(' / '), note }));
  } else return hideSlash();
  slashIndex = Math.min(slashIndex, Math.max(0, slashMatches.length - 1)); drawSlash();
}
function showMenu(kind, commands, anchor) {
  menuKind = kind; menuAnchor = anchor; slashMatches = commands; slashIndex = 0; slashRange = null; $('bubble').hidden = true; drawSlash();
}
function drawSlash() {
  const menu = $('slash'); menu.replaceChildren(); menu.dataset.kind = menuKind;
  if (!slashMatches.length && menuKind !== 'mention') return hideSlash();
  if (menuKind === 'slash' || menuKind === 'mention') {
    const search = document.createElement('div'); search.className = 'menu-search'; search.setAttribute('aria-hidden', 'true');
    const query = document.createElement('span'); query.className = menuQuery ? 'menu-query' : 'menu-query empty';
    query.textContent = menuQuery || (menuKind === 'slash' ? 'Search blocks…' : 'Search notes…');
    search.append(icon('magnifyingglass', '⌕'), query); menu.append(search);
  }
  if (!slashMatches.length) { const none = document.createElement('div'); none.className = 'menu-empty'; none.textContent = 'No matching notes'; menu.append(none); }
  let group = slashMatches[0]?.group;
  slashMatches.forEach((command, index) => {
    if (menuKind === 'slash' && command.group && (index === 0 || command.group !== group)) {
      const label = document.createElement('div'); label.className = 'menu-label'; label.setAttribute('aria-hidden', 'true'); label.textContent = command.group; menu.append(label);
    }
    const button = document.createElement('button'); button.className = `slash-option${index === slashIndex ? ' selected' : ''}`; button.id = `slash-option-${index}`; button.role = 'option'; button.setAttribute('aria-selected', String(index === slashIndex));
    let glyph; if (command.label) { glyph = document.createElement('span'); glyph.className = 'icon text-icon'; glyph.setAttribute('aria-hidden', 'true'); glyph.textContent = command.label; } else glyph = icon(command.icon, command.fallback);
    const name = document.createElement('span'); name.className = 'slash-name'; name.textContent = command.name;
    const shortcut = document.createElement('span'); shortcut.className = command.hint ? 'slash-shortcut slash-hint' : 'slash-shortcut'; shortcut.textContent = command.hint ?? command.shortcut ?? '';
    button.append(glyph, name, shortcut);
    if (index && command.group !== slashMatches[index - 1].group) button.classList.add('group-start');
    group = command.group;
    button.onmousedown = e => { e.preventDefault(); chooseSlash(command); };
    button.onclick = e => { if (e.detail === 0) chooseSlash(command); };
    menu.append(button);
  });
  menu.hidden = false;
  editor.view.dom.setAttribute('aria-controls', 'slash'); editor.view.dom.setAttribute('aria-expanded', 'true');
  if (slashMatches.length) editor.view.dom.setAttribute('aria-activedescendant', `slash-option-${slashIndex}`); else editor.view.dom.removeAttribute('aria-activedescendant');
  const anchor = menuAnchor && (menuKind === 'style' || menuKind === 'list') ? menuAnchor.getBoundingClientRect() : null;
  const coords = anchor ? { left: anchor.left, bottom: anchor.bottom } : editor.view.coordsAtPos(slashRange?.from ?? editor.state.selection.from);
  menu.style.left = `${Math.min(Math.max(10, coords.left), innerWidth - menu.offsetWidth - 12)}px`;
  menu.style.top = `${Math.max(12, Math.min(coords.bottom + 6, innerHeight - menu.offsetHeight - 12))}px`;
  menu.querySelector('.selected')?.scrollIntoView({ block: 'nearest' });
}
function hideSlash() { $('slash').hidden = true; slashRange = null; slashIndex = 0; menuKind = 'slash'; menuAnchor = null; editor?.view.dom.setAttribute('aria-expanded', 'false'); editor?.view.dom.removeAttribute('aria-activedescendant'); }
function chooseSlash(command) {
  const range = slashRange; hideSlash();
  if (command.id === 'mention') return insertNoteLink(command.note, range);
  if (range) editor.chain().focus().deleteRange(range).run();
  execute(command.id);
}
function insertNoteLink(note, range) {
  editor.chain().focus().insertContentAt(range || editor.state.selection, [{ type: 'text', text: note.title, marks: [{ type: 'link', attrs: { href: note.reference } }] }, { type: 'text', text: ' ' }]).run();
  editor.view.dispatch(editor.state.tr.removeStoredMark(editor.schema.marks.link));
}

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
    case 'paragraph': return showMenu('style', styleCommands, document.querySelector('#bubble [data-command=paragraph]'));
    case 'lists': return showMenu('list', listCommands, document.querySelector('#bubble [data-command=lists]'));
    case 'collapsible': return insertDetails();
    case 'noteLink': return chain.insertContent(editor.state.selection.$from.parentOffset && !/\s$/.test(editor.state.selection.$from.parent.textBetween(0, editor.state.selection.$from.parentOffset)) ? ' @' : '@').run();
    case 'date': return chain.insertContent(new Date().toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' }) + ' ').run();
    case 'linearImport': send('linear', { id: documentID, action: 'import' }); return;
    case 'linearRefresh': send('linear', { id: documentID, action: 'refresh' }); return;
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
    const command = button.dataset.command;
    if (command === 'paragraph') continue;
    const active = command === 'lists' ? ['bulletList', 'orderedList', 'taskList'].some(name => editor.isActive(name))
      : editor.isActive({ quote: 'blockquote', collapsible: 'details' }[command] || command);
    button.classList.toggle('active', active);
    if (command !== 'lists') button.setAttribute('aria-pressed', String(active));
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
  if (!e.target.closest('#heading-menu') && !e.target.closest('#heading-handle')) { closeHeadingMenu(); hideHeadingHandle(); }
  if (!e.target.closest('#outline')) closeOutline();
});
window.addEventListener('resize', () => { $('bubble').hidden = true; hideSlash(); closeHeadingMenu(); hideHeadingHandle(); });
const headingElements = () => mode === 'source' ? [] : Array.from(document.querySelectorAll('.tiptap h1,.tiptap h2,.tiptap h3,.tiptap h4,.tiptap h5,.tiptap h6'));
function headingIndex(headings = headingElements()) {
  if (headings.length && window.scrollY > 0 && window.scrollY + innerHeight >= document.documentElement.scrollHeight - 2) return headings.length - 1;
  let active = headings.length ? 0 : -1;
  headings.forEach((heading, index) => { if (heading.getBoundingClientRect().top <= 110) active = index; });
  return active;
}
function reportOutline() {
  const headings = headingElements(); activeHeading = headingIndex(headings);
  const rows = headings.map((heading, index) => ({ index, level: Number(heading.tagName[1]), text: heading.textContent }));
  send('outline', { id: documentID, headings: rows, active: activeHeading });
  drawOutline(rows);
}
// Linear's outline: a dash per heading on the panel edge that opens into a list on hover.
function drawOutline(rows) {
  const top = Math.min(...rows.map(row => row.level)), shown = rows.length > 24 ? rows.filter(row => row.level === top) : rows;
  const key = JSON.stringify(shown);
  $('outline').hidden = shown.length < 2;
  if (key === outlineKey) return markOutline();
  outlineKey = key;
  $('outline-rail').replaceChildren(...shown.map(row => {
    const mark = document.createElement('span'); mark.className = 'outline-mark'; mark.dataset.index = row.index; mark.dataset.depth = String(Math.min(4, row.level - top + 1)); return mark;
  }));
  $('outline-list').replaceChildren(...shown.map(row => {
    const button = document.createElement('button'); button.className = 'outline-item'; button.dataset.index = row.index; button.dataset.depth = String(Math.min(4, row.level - top + 1));
    button.textContent = row.text || 'Untitled heading'; button.onclick = () => { jumpToHeading(row.index); closeOutline(); }; return button;
  }));
  markOutline();
}
function markOutline() {
  const marks = [...$('outline-list').children], current = marks.filter(mark => Number(mark.dataset.index) <= activeHeading).at(-1);
  for (const element of document.querySelectorAll('#outline [data-index]')) element.classList.toggle('active', Boolean(current) && element.dataset.index === current.dataset.index);
}
function closeOutline() { $('outline').classList.remove('open'); $('outline-rail').setAttribute('aria-expanded', 'false'); }
$('outline-rail').onclick = () => { const open = !$('outline').classList.contains('open'); $('outline').classList.toggle('open', open); $('outline-rail').setAttribute('aria-expanded', String(open)); if (open) $('outline-list').querySelector('.active, button')?.focus(); };
$('outline').addEventListener('keydown', event => {
  if (event.key === 'Escape') { event.preventDefault(); closeOutline(); $('outline-rail').focus(); }
  if (['ArrowDown', 'ArrowUp'].includes(event.key) && event.target.closest('#outline-list')) {
    event.preventDefault(); const items = [...$('outline-list').children], index = items.indexOf(event.target);
    items[(index + (event.key === 'ArrowDown' ? 1 : items.length - 1)) % items.length]?.focus();
  }
});
$('outline').addEventListener('focusout', event => { if (!$('outline').contains(event.relatedTarget)) closeOutline(); });

// Hovering a heading shows a handle in the gutter with Copy link and Make collapsible.
let handleHeading = null;
const headingSlug = text => text.toLocaleLowerCase().normalize('NFKD').replace(/\p{M}/gu, '').replace(/[^\p{L}\p{N}\s-]/gu, '').trim().replace(/\s+/g, '-');
function showHeadingHandle(heading) {
  if (mode === 'source' || !heading) return;
  handleHeading = heading;
  const rect = heading.getBoundingClientRect(), line = parseFloat(getComputedStyle(heading).lineHeight) || rect.height, handle = $('heading-handle');
  handle.hidden = false; handle.style.left = `${rect.left - 30}px`; handle.style.top = `${rect.top + Math.max(0, (line - 24) / 2)}px`;
}
function hideHeadingHandle() { if (!$('heading-menu').hidden) return; $('heading-handle').hidden = true; handleHeading = null; }
function closeHeadingMenu() { $('heading-menu').hidden = true; $('heading-handle').setAttribute('aria-expanded', 'false'); }
document.addEventListener('mousemove', event => {
  if (!$('heading-menu').hidden || event.target.closest('#heading-handle')) return;
  const heading = event.target.closest('.tiptap h1, .tiptap h2, .tiptap h3, .tiptap h4, .tiptap h5, .tiptap h6');
  if (heading) showHeadingHandle(heading); else hideHeadingHandle();
});
$('heading-handle').onmousedown = event => event.preventDefault();
$('heading-handle').onclick = () => {
  const menu = $('heading-menu'), rect = $('heading-handle').getBoundingClientRect();
  menu.querySelector('[data-heading-action=collapse]').hidden = mode !== 'live';
  menu.hidden = false; $('heading-handle').setAttribute('aria-expanded', 'true');
  menu.style.left = `${Math.max(12, Math.min(rect.left, innerWidth - menu.offsetWidth - 12))}px`; menu.style.top = `${Math.min(rect.bottom + 4, innerHeight - menu.offsetHeight - 12)}px`;
  menu.querySelector('button:not([hidden])').focus();
};
$('heading-menu').addEventListener('keydown', event => {
  if (event.key === 'Escape') { event.preventDefault(); closeHeadingMenu(); $('heading-handle').focus(); }
  if (['ArrowDown', 'ArrowUp'].includes(event.key)) {
    event.preventDefault(); const items = [...$('heading-menu').querySelectorAll('button:not([hidden])')], index = items.indexOf(document.activeElement);
    items[(index + (event.key === 'ArrowDown' ? 1 : items.length - 1)) % items.length]?.focus();
  }
});
document.querySelectorAll('[data-heading-action]').forEach(button => {
  button.onmousedown = event => event.preventDefault();
  button.onclick = () => {
    const heading = handleHeading; closeHeadingMenu(); hideHeadingHandle(); if (!heading) return;
    if (button.dataset.headingAction === 'link') {
      const file = encodeURI(documentID.split('/').at(-1) || '').replace(/\(/g, '%28').replace(/\)/g, '%29');
      copyText(`[${escapeLabel(heading.textContent)}](${file}#${encodeURIComponent(headingSlug(heading.textContent))})`, 'Link copied');
    } else makeCollapsible(heading);
  };
});
function makeCollapsible(heading) {
  if (mode !== 'live') return;
  const $pos = editor.state.doc.resolve(editor.view.posAtDOM(heading, 0)), node = $pos.parent;
  if (node.type.name !== 'heading') return;
  const container = $pos.node($pos.depth - 1), index = $pos.index($pos.depth - 1), from = $pos.before(), blocks = [];
  let to = $pos.after();
  for (let next = index + 1; next < container.childCount; next++) {
    const block = container.child(next);
    if (block.type.name === 'heading' && block.attrs.level <= node.attrs.level) break;
    blocks.push(block); to += block.nodeSize;
  }
  if (!container.canReplaceWith(index, index + blocks.length + 1, editor.schema.nodes.details)) return;
  const tr = editor.state.tr.replaceWith(from, to, detailsNode(editor.schema, node.textContent, blocks));
  editor.view.dispatch(tr.setSelection(TextSelection.create(tr.doc, from + 2 + node.textContent.length)).scrollIntoView()); editor.commands.focus();
}
function jumpToHeading(index) {
  const heading = headingElements()[index]; if (!heading) return;
  heading.scrollIntoView({ block: 'start', behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth' });
}
window.addEventListener('scroll', () => {
  reportView();
  $('bubble').hidden = true; hideSlash(); closeHeadingMenu(); hideHeadingHandle();
  const next = headingIndex(); if (next !== activeHeading) { activeHeading = next; send('headingActive', { id: documentID, active: next }); markOutline(); }
}, { passive: true });
window.addEventListener('keydown', e => {
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'f') { e.preventDefault(); if (e.altKey) showFindAndReplace(); else showFind(); }
  if (e.key === 'Enter' && e.target.closest('a') && (mode === 'reading' || e.metaKey)) { e.preventDefault(); openReference(e.target.closest('a').getAttribute('href')); }
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 's' && !e.shiftKey) { e.preventDefault(); send('save'); }
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'p' && !e.shiftKey) { e.preventDefault(); send('quickOpen'); }
  // As in Linear: ⌘K links a selection, otherwise it opens the command menu.
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k' && !e.shiftKey && !e.altKey && !e.defaultPrevented) {
    e.preventDefault();
    const source = $('source');
    const selected = mode === 'source' ? source.selectionStart !== source.selectionEnd : mode === 'live' && !editor.state.selection.empty;
    if (selected) execute('link'); else send('quickOpen');
  }
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
  find: term => showFind(term, false), showFind, showFindAndReplace, viewState, textSize, setNotes: notes => { noteLinks = notes; }, setIcons, preparePrint, finishPrint };
send('ready');
// A browser harness loads only explicit fixtures; production content arrives from the native host.
loadDocument({ id: '', markdown: '', mode: 'live' });
