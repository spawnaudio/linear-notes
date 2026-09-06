# Editor guide

## Writing

| Action | Shortcut |
| --- | --- |
| Bold | ⌘B |
| Italic | ⌘I |
| Underline | ⌘U |
| Strikethrough | ⌘⇧S |
| Inline code | ⌘E |
| Link or card | ⌘K |
| Checklist | ⌘⇧7 |
| Bullet list | ⌘⇧8 |
| Numbered list | ⌘⇧9 |
| Heading 1–4 | ⌘⌥1–4 |

## Organising

Right-click a file or folder to rename, pin, bookmark, or move it to Trash. Pins stay inside their parent folder. Bookmarks appear in their own section.

Drag near the top or bottom of a row to reorder. Drop in the middle of a folder to move inside it. Drop on **Notes** to move back to the root. Drag onto **Bookmarks** to add a shortcut there.

## Markdown conventions

Callouts use GitHub and Obsidian notation:

```markdown
> [!TIP] A useful thought
> Keep it simple.
```

Rich cards use a normal Markdown link with a title marker:

```markdown
[A useful reference](<https://example.com> "card")
```

Properties are YAML frontmatter. Click a pill to edit the properties, or use Source mode. Nested YAML stays in the file; the pills show top-level values.
