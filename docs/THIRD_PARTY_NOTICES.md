# Third-party notices

The visual references are Linear Documents and Pluk's Markdown Preview. This app is independently implemented; no source or artwork was copied from either product.

The editor bundles these open-source projects and their transitive dependencies:

- [Tiptap](https://github.com/ueberdosis/tiptap), MIT; core, StarterKit, Markdown, Placeholder, TaskList, TaskItem, TableKit, and Image extensions.
- [ProseMirror](https://github.com/ProseMirror), MIT; the document and editing engine used by Tiptap.
- [Marked](https://github.com/markedjs/marked), MIT; Markdown tokenization used by Tiptap Markdown.
- [esbuild](https://github.com/evanw/esbuild), MIT; development bundler.
- [Playwright](https://github.com/microsoft/playwright), Apache-2.0; development-only browser tests.

Exact dependency versions are pinned in `Editor/package-lock.json`. Full bundled dependency license texts are included in `Sources/LinearNotes/Resources/Editor/THIRD_PARTY_LICENSES.txt`.
