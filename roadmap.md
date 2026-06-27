# Roadmap

Features are grouped by theme and tagged with rough sizing (S/M/L) and a priority tier (P1 = near-term, P2 = mid-term, P3 = long-term/explore).

## Platform Integration

- **CLI `ed .` to open current directory** [S, P1] — Still missing. Ship a tiny launcher binary that resolves the current directory and asks the app to open it, ideally reusing the same open-repo path as Finder / Dock / "Open Folder…".
- **macOS "open with" registration** [S, P1] — Partially done for folders already; extend the app bundle to register the file types we care about (`.db`, `.sqlite`, `.sqlite3`) so Finder offers Editor in "Open With" for those files too.
- **Multi-window / multi-project support** [L, P1] — Still a real architecture change. Needs a decision early because `ed .` and broader project workflow are much cleaner if the app can open multiple independent windows instead of one shared workspace.

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
