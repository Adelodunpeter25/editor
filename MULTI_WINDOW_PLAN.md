# Multi-Window Support — Implementation Plan

## Goal

Move from a single shared workspace window to **one window per session** (one window = one project/repo). Each open repo gets its own `MainWindowController` bound to a single `Session`. Multiple projects can be open simultaneously in independent windows.

Branch: `multi-window-support`

## Design Principles

- **One window = one session.** A window is bound to exactly one `Session`; closing the window closes the session (after the unsaved-edits guard).
- **`AppModel` remains the source of truth** for all sessions and which window maps to which session.
- **No shared tab state across windows.** A session lives in exactly one window.
- **Global UI stays global.** Settings, Updates, Quick Terminal (floating mode), and shortcuts window remain app-wide. Per-window elements (command palette, status bar, sidebar, tab bar) move with their window.
- **Backwards-compatible persistence.** The existing `PersistedState` schema is extended, not replaced, so old states still restore.

---

## Phase 1 — Window/Session Mapping Foundation

Refactor the ownership model so `AppDelegate` manages a list of window controllers, each bound to a single session, instead of one window showing the active session.

### Tasks

- [ ] **1.1 Add `windowControllerFor(sessionID:)` to `AppDelegate`**
  - Replace the single `windowController: MainWindowController!` with `var windowControllers: [String: MainWindowController]` keyed by session id.
  - Add helper `func windowController(for sessionID: String) -> MainWindowController?`.

- [ ] **1.2 Refactor `MainWindowController` to take a single `Session`**
  - Change init from `init(model: AppModel)` to `init(model: AppModel, session: Session)`.
  - Store the bound `sessionID` on the controller.
  - Use a per-window frame autosave name derived from the session url (e.g. `EditorWindow-<hash>`), falling back to a default for the first window.

- [ ] **1.3 Update `WorkspaceViewController`, `CenterViewController`, `SidebarViewController`**
  - Each takes the bound `Session` (in addition to `AppModel` for settings/global hooks).
  - Replace `model.activeSession` lookups inside these controllers with the bound session reference.
  - `CenterViewController` keeps its `static weak var current` for the quick-terminal bottom dock — it tracks the key window's center VC.

- [ ] **1.4 Update `TabBarController`**
  - Take the bound `Session` directly instead of going through `model.activeSession`.
  - All tab actions (`onSelect`, `onClose`, `onPin`, etc.) operate on the bound session.

- [ ] **1.5 Update `AppDelegate.applicationDidFinishLaunching`**
  - On launch, restore sessions and create one `MainWindowController` per restored session.
  - If no sessions are restored, open the empty/welcome state in a single window.
  - Show all restored windows; make the active one key.

- [ ] **1.6 Handle `pendingOpenPaths` (Finder/`ed` open)**
  - Each pending path opens as a new session + new window (or focuses an existing window for that repo).

---

## Phase 2 — Session/Window Lifecycle

Wire open/close/activate so each session has its own window and the app stays alive with zero windows (optional) or quits when the last window closes (current behavior — keep it for now, revisit in Phase 5).

### Tasks

- [ ] **2.1 Update `AppModel.openRepo(_:)`**
  - After creating/focusing a session, notify `AppDelegate` to create or focus the corresponding window.
  - Add a published signal (e.g. `@Published var lastOpenedSessionID: String?`) or a callback `onSessionOpened: ((String) -> Void)?` that `AppDelegate` sinks to create/focus the window.

- [ ] **2.2 Update `AppModel.closeSession(_:)`**
  - Notify `AppDelegate` to close the corresponding window (after unsaved guard passes).
  - Remove the window controller from `windowControllers`.

- [ ] **2.3 Update `MainWindowController.windowShouldClose`**
  - Run the unsaved-edits guard for the bound session's tabs only (not all sessions).
  - On confirm, close the window and remove the session from `AppModel`.
  - Do NOT call `NSApp.terminate` — only terminate when the *last* window closes (gated by `applicationShouldTerminateAfterLastWindowClosed`).

- [ ] **2.4 Update `AppDelegate.applicationShouldTerminate`**
  - Aggregate dirty tabs across ALL sessions/windows for the quit guard (current behavior is correct, just verify it still works with multiple windows).

- [ ] **2.5 Update `AppDelegate.application(_:openFile:)`**
  - If a window for the repo already exists, focus it (`makeKeyAndOrderFront`).
  - Otherwise create a new session + window.

- [ ] **2.6 Window activation tracking**
  - On `windowDidBecomeKey`, update `AppModel.activeSessionID` to the bound session (so menus, command palette, and global hooks target the right session).
  - On `windowDidResignKey`, no change (active stays as last key).

---

## Phase 3 — Global UI & Hooks

Make sure global UI elements (command palette, quick terminal, menus, key monitors) target the *key window's* session, not a single shared instance.

### Tasks

- [ ] **3.1 Command palette per window**
  - Each `MainWindowController` owns its own `CommandPaletteController` attached to its root view (current behavior, just ensure it's per-window now).
  - `CommandPaletteHook.toggle/command/lineJump` route to the key window's palette. Implement by having `AppDelegate` resolve the key window's controller and forward.

- [ ] **3.2 Quick terminal**
  - Floating mode: keep as a single global panel (`QuickTerminalController.current`) — it's a separate window.
  - Centered/bottom mode: currently mounts into the main window's root. Move to mount into the *key window's* root. Track the key window via `windowDidBecomeKey` and re-attach as needed.
  - `QuickTerminalHook.toggle` routes to the key window's quick terminal (or the global floating one).

- [ ] **3.3 `NewItemHook.newFile` / `newTerminal`**
  - Route to the key window's session instead of `model.activeSession` (which is now kept in sync with the key window, so this may be a no-op — verify).

- [ ] **3.4 `ActiveEditor.current`**
  - Already a `weak static` set by `CenterViewController` — ensure it tracks the key window's editor. Add `windowDidBecomeKey` handling to refresh it.

- [ ] **3.5 `CenterViewController.current`**
  - Same — track the key window's center VC for the bottom-dock quick terminal.

- [ ] **3.6 Key monitor in `AppDelegate`**
  - Already app-wide via `NSEvent.addLocalMonitorForEvents`. Verify it routes to the key window's session/editor (it uses `ActiveEditor.current` and `model.activeSession`, both of which now track the key window).

- [ ] **3.7 Menu items (`AppMenu.swift`)**
  - Audit every menu action. Most use `model.activeSession` which now tracks the key window — verify this holds.
  - "Open Folder…" (⌘O) opens a new window.
  - "Open Recent" opens a new window (or focuses existing).
  - Add "New Window" (⌘⇧N) menu item to open a fresh empty window (welcome state) — optional, can defer to Phase 5.

---

## Phase 4 — Persistence

Extend persistence to remember which windows were open and their frames.

### Tasks

- [ ] **4.1 Extend `PersistedSession` with window frame**
  - Add `var windowFrame: CGRect?` (or `x, y, w, h` as doubles) to `PersistedSession`.
  - Encode/decode the saved frame per session.

- [ ] **4.2 Save window frame on resize/move**
  - `MainWindowController.windowDidResize` / `windowDidMove` save the frame into the bound session's `PersistedSession` entry (via `AppModel.scheduleSave`).
  - Use per-session autosave names as a cache, but also persist into `PersistedState` for cross-launch restore.

- [ ] **4.3 Restore window frames on launch**
  - When restoring sessions in `AppDelegate.applicationDidFinishLaunching`, apply the saved frame to each window.
  - Fall back to `window.center()` if no frame is saved.

- [ ] **4.4 Update `PersistedState.activeSessionIndex`**
  - Keep as-is — it determines which restored window becomes key on launch.

---

## Phase 5 — Polish & Edge Cases

Handle the long tail of multi-window edge cases and UX improvements.

### Tasks

- [ ] **5.1 Window title per session**
  - Set each window's title to the session's repo name (last path component) instead of the static "Editor".
  - Update title on branch change (e.g. `my-repo (main)`).

- [ ] **5.2 Window close behavior decision**
  - Decide: quit when last window closes (current) OR keep app alive with no windows (show dock icon, re-open welcome on activate).
  - Recommendation: keep "quit on last window close" for now (matches current UX); revisit if users want macOS-document-app behavior.

- [ ] **5.3 "New Window" menu item (⌘⇧N)**
  - Opens a fresh window with the welcome/empty state (no session).
  - User can then ⌘O to open a folder in that window.

- [ ] **5.4 Drag tab between windows (stretch goal)**
  - Move a tab from one session's window to another session's window.
  - Requires cross-session tab transfer API on `AppModel`.
  - Defer if time-boxed.

- [ ] **5.5 Single-instance guard for `ed` launcher**
  - `ed .` for an already-open repo should focus the existing window, not create a new one (handled by `openRepo` dedup in Phase 2, but verify end-to-end with the launcher).

- [ ] **5.6 Update `roadmap.md`**
  - Remove the completed `ed .` item.
  - Mark "Multi-window / multi-project support" as in-progress/done.
  - Remove the `ed .` line under Platform Integration.

---

## Phase 6 — Testing & Verification

### Tasks

- [ ] **6.1 Open multiple repos**
  - Open 2+ folders via ⌘O and `ed .`; verify each gets its own window.

- [ ] **6.2 Close window with unsaved edits**
  - Verify the unsaved guard only prompts for the closing window's session tabs.

- [ ] **6.3 Quit with unsaved edits across windows**
  - Verify the quit guard aggregates dirty tabs from all windows.

- [ ] **6.4 Restore on launch**
  - Close the app with 3 windows open; relaunch and verify all 3 restore with correct frames and active tabs.

- [ ] **6.5 Quick terminal across windows**
  - Floating: works globally regardless of key window.
  - Bottom/centered: docks into the key window; switch key window and verify it re-docks.

- [ ] **6.6 Command palette**
  - ⌘P in each window targets that window's session's files.

- [ ] **6.7 `ed .` focuses existing window**
  - Open a repo, then run `ed .` from a terminal in that repo — should focus the existing window, not create a new one.

- [ ] **6.8 Build and run**
  - `./build.sh debug` and `./build.sh release` both succeed.
  - Launch and verify no regressions in single-window usage.

---

## Out of Scope (Defer)

- Split editor panes within a window (separate feature).
- Tab drag between windows (stretch goal in Phase 5, may defer).
- macOS document-based app architecture (`NSDocument`/`NSDocumentController`) — too large a rewrite for now.
- Per-window settings overrides (settings stay global).
