# How Snippet Studio works

## Design decisions

| Decision | Choice | Why |
|---|---|---|
| Relationship to Espanso | A companion app that edits Espanso's YAML match files | Espanso already reloads its files when they change (`auto_restart`, on by default). Snippet Studio contains no Espanso code and doesn't link to it. |
| Platform and UI | macOS 15+, Swift 6, SwiftUI | A native look, menus, keyboard shortcuts, dark mode and accessibility; small and fast. |
| Data location | `~/Library/Application Support/espanso/match` | Espanso's standard macOS location. Subfolders (installed packages) are read too. |
| Descriptions | Espanso's own `label` field | No separate metadata store for snippet text. |
| YAML | [Yams](https://github.com/jpsim/Yams), pinned to an exact version | Swift has no built-in YAML parser. Yams is the only dependency. |
| Privacy | Fully local: no network access, no telemetry | Snippets often hold private or confidential text. |

## Code layout

- `Sources/SnippetCore` is the logic, with no UI.
  - `Library.swift` reads match files into `Snippet` values.
  - `Editing.swift` applies an add, update or delete to a file's text and verifies the result.
  - `Store.swift` handles saving, backups and restore.
  - `Preview.swift` renders "Try it" previews.
  - `Appearance.swift` stores color groups and icons.
- `Sources/SnippetStudio` is the SwiftUI app: the three views, the editor and the snippet builder.
- `Tests/SnippetCoreTests` holds the Swift Testing suite. All test data is invented.
- `make-app.sh` builds a release binary and wraps it as `~/Applications/Snippet Studio.app` with an ad-hoc signature.
- `demo/` is a sample library for trying the app (`SNIPPET_STUDIO_DEMO`).

## How saving works

- **Line-precise edits.** Only the edited snippet's lines are rewritten. Every other line, including all comments, stays byte-for-byte identical. Notes on their own `#` line inside an edited snippet are kept, moved to just after it. A `# note` at the end of one of the snippet's own lines is not kept.
- **Verification.** Before anything is written, the new text is parsed again and compared with the old. Exactly the requested change must be present, and nothing else may differ. Otherwise nothing is saved.
- **Backups.** Each save first copies the file to `~/Library/Application Support/Snippet Studio/Backups`, outside Espanso's folder so Espanso never loads them. **Restore a Backup…** backs up the current file before restoring, so a restore can be undone too. The newest 200 backups are kept.
- **Outside changes.** If the snippet on disk no longer matches what you opened, the save is refused and you're asked to reload.
- **Atomic writes.** The file is replaced in a single step. Symlinked match files are followed, so the real file is updated.
- **Windows line endings** are preserved.
- **Read-only cases.** Package files in subfolders are never edited, though they count toward duplicate-shortcut checks. Snippets that run commands (`shell`, `script`) can't be edited or deleted. Pattern-triggered (`regex:`) snippets can be deleted but not edited.

## Smart snippets

- The Insert buttons add `{{date}}`, `{{clipboard}}`, `$|$` (cursor) or a question's `{{form1.field}}` at the cursor. Saving adds whatever Espanso variables those need.
- All questions live in one form variable, one per line: `Prompt [[field]]`. Adding or removing a question changes only that question's line and field. Defaults, other field settings and extra layout text stay as they are.
- Snippets whose questions come from several places, such as two forms, a separate choice variable or Espanso's `form:` shorthand, keep their questions read-only. Their name, shortcut and text can still be edited.
- A date or clipboard variable is added only for a fill-in that is new in this edit, and never over a shared `global_vars` entry of the same name.
- "Try it" fills in sample answers and today's date in the snippet's own format. It never runs commands or reads the clipboard; those show as `[name]`.
- **Duplicate** builds the copy from the original's own YAML, so date formats, `markdown`/`html`, form defaults and settings like `word` carry over. Only the shortcut is new.

## Color groups and icons

- Groups have a name and one of Apple's 13 system colors. Each snippet can belong to one group and use one SF Symbol icon.
- They're stored in `~/Library/Application Support/Snippet Studio/appearance.json`, keyed by each snippet's first shortcut. No snippet text is stored there.
- Changing a shortcut inside the app moves its group and icon with it. Changing it by editing the YAML by hand leaves the snippet ungrouped.
- Deleting a group only ungroups its snippets.
- Each save keeps the previous version as `appearance (previous).json`. A file that can't be read is set aside under its own dated name rather than overwritten.
- "Recently Edited" lists snippets saved in the app during the last 30 days.

## Reading files safely

Match files are parsed with `Yams.compose`, and the app turns the result into plain text values itself. It never uses Yams's typed value converter, which can crash on some inputs a third-party package file could contain: a `!!int` base-60 value that overflows, or a mapping key that is itself a list. Values such as `yes`, `no` or `1:30` are kept as text. YAML merge keys (`<<:`) aren't expanded.

## Demo mode

Setting `SNIPPET_STUDIO_DEMO=<folder>` makes the app use `<folder>/match` for snippets and keep its backups and `appearance.json` inside `<folder>` too. Your real Espanso files and settings aren't touched.
