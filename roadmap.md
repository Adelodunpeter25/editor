# Roadmap

Features are grouped by theme and tagged with rough sizing (S/M/L) and a priority tier (P1 = near-term, P2 = mid-term, P3 = long-term/explore).

## Platform Integration

- **CLI `ed .` to open current directory** [S, P1] — Ship a small launcher binary and add it to `PATH`. Pairs naturally with the "open with" registration below.
- **macOS "open with" registration** [S, P1] — Register support for developer file types (including `.db`, `.sqlite`, `.sqlite3`) so the editor shows up in Finder's "open with" dropdown.
- **Multi-window / multi-project support** [L, P1] — Architecturally significant; should be decided early before the codebase hardens around single-window assumptions. Affects document model, workspace state, and most controllers.

## Editor Capabilities

- **Editor minimap** [M, P2] — Standard feature users expect. Effort depends on the text view stack; verify whether the current text view exposes what's needed (line metrics, glyph cache).
- **Editor autocomplete** [M/L, P2] — Needs scope: LSP integration vs. snippets vs. language-specific. Recommend starting with a snippet + word-completion baseline, then LSP as a follow-up.
- **Vim mode** [L, P3] — Expensive to do well. Explore integrating an existing vim engine before building from scratch.
- **View `.db` / `.sqlite` / `.sqlite3` files** [M, P2] — Start with read-only browsing (tables, schema, row preview). Full SQL editing is a separate, larger effort and can be deferred.

## Git

- **Add file to `.gitignore`** [S, P1] — Create the file if it doesn't exist. Small, high-value.
- **Pull** [S/M, P2] — Straightforward once the existing git plumbing is wired up.
- **Multiple remotes** [M, P2] — UI to list, add, remove remotes and choose which to push/pull.
- **Submodules / worktrees** [L, P3] — Clarify intent: the current "multiple `.git` files" bullet likely means submodules or worktrees. Both are non-trivial; pick one first.

## Extensibility

- **Extension API** [L, P3] — Large and cross-cutting. Benefits from the editor's internal API surface being stable first. Defer until P1/P2 items land, then scope a minimal plugin contract (commands, text manipulation, sidebar items) before expanding.

## Notes

- Items tagged **P3 / explore** (vim mode, extension API, autocomplete strategy) have a build-vs-integrate decision to make before committing.
- Multi-window is called out as P1 despite being large because retrofitting it later is painful — it's a "decide early" item, not necessarily a "ship early" one.
