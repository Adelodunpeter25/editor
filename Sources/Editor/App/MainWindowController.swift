import AppKit

/// One window bound to a single `Session` (one window = one repo). A nil session = the welcome
/// window (no folder open yet); opening a folder from it creates a new session window and closes
/// the welcome window. Window frame persists via a per-session autosave name.
final class MainWindowController: NSWindowController, NSWindowDelegate {
  private let model: AppModel
  private let palette: CommandPaletteController
  private let quickTerm: QuickTerminalController
  /// The session this window is bound to. Nil for the welcome window.
  let sessionID: String?
  /// Called after the window closes (session removed from model) so AppDelegate can drop it from
  /// its window map and show the welcome window if no windows remain.
  var onClosed: ((String?) -> Void)?

  init(model: AppModel, session: Session?) {
    self.model = model
    self.sessionID = session?.id

    let workspace = WorkspaceViewController(model: model, session: session)
    self.palette = CommandPaletteController(model: model)
    self.quickTerm = QuickTerminalController(model: model)

    // Root container: update banner (top, collapses to 0 height when hidden) + workspace. The status
    // bar lives at the bottom of the workspace's *center* pane (CenterViewController), not here, so it
    // covers only the file/Claude area and not the sidebar.
    let container = NSViewController()
    let root = NSView()
    let banner = UpdateBannerView(updates: Updates.shared, model: model)
    banner.translatesAutoresizingMaskIntoConstraints = false
    workspace.view.translatesAutoresizingMaskIntoConstraints = false
    container.addChild(workspace)
    root.addSubview(banner)
    root.addSubview(workspace.view)
    NSLayoutConstraint.activate([
      banner.topAnchor.constraint(equalTo: root.topAnchor),
      banner.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      banner.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      workspace.view.topAnchor.constraint(equalTo: banner.bottomAnchor),
      workspace.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      workspace.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      workspace.view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
    container.view = root

    let window = NSWindow(contentViewController: container)
    window.title = session?.name ?? "Editor"
    window.backgroundColor = NSColor(white: 0.11, alpha: 1)  // workspace backdrop (no layer on terminal ancestors)
    // NB: NOT .fullSizeContentView — that draws content under the title bar, hiding the tab bar
    // and the Files/Changes toggle behind it.
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.minSize = NSSize(width: 900, height: 600)
    // Per-repo autosave name so each window remembers its own frame across launches. Keyed by the
    // repo URL (not `session.id`): restored sessions get a freshly-generated random id on every
    // launch (see Persistence.swift), so keying on `id` would never match a previously saved frame
    // after a relaunch — the frame would only "stick" within a single running session.
    // NB: don't use `String.hashValue` here — Swift randomizes its seed per process, so it isn't
    // stable across launches either. Use the (sanitized) URL text itself instead.
    let autosaveName: String
    if let url = session?.url {
      autosaveName = "EditorWindow-" + url.replacingOccurrences(of: "/", with: "_")
    } else {
      autosaveName = "EditorMainWindow"
    }
    window.setFrameAutosaveName(autosaveName)
    let restored = window.setFrameUsingName(autosaveName)
    if !restored {
      window.setContentSize(NSSize(width: 1100, height: 720))
      window.center()
    }
    super.init(window: window)
    window.delegate = self

    // ⌘P quick-open overlays the whole content area (above the banner + workspace).
    palette.attach(to: root)

    // ⌃` quick terminal: the centered-overlay mode also mounts into root.
    quickTerm.attach(root: root)
    TerminalStore.shared.onQuickExit = { [weak quickTerm] quickID in
      quickTerm?.handleShellExit(quickID: quickID)
    }
  }

  // MARK: - Per-window actions (routed from AppDelegate via the key window)

  func togglePalette() { palette.toggle() }
  func toggleCommandPalette() { palette.toggleCommand() }
  func presentLineJump() { palette.presentLineJump() }
  func toggleQuickTerminal() { quickTerm.toggle() }
  func revealSearch() {
    let workspace = contentViewController?.children.first { $0 is WorkspaceViewController } as? WorkspaceViewController
    workspace?.sidebarVC.revealSearch()
  }

  /// This window's center view controller (for routing global hooks like DiffNavigator).
  var centerViewController: CenterViewController? {
    let container = contentViewController
    let workspace = container?.children.first { $0 is WorkspaceViewController } as? WorkspaceViewController
    return workspace?.centerVC
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

  /// Closing a window: confirm unsaved edits for THIS window's session only (not all sessions), then
  /// close the session. The app quits when the last window closes
  /// (`applicationShouldTerminateAfterLastWindowClosed`), which runs the full quit guard.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if let sessionID, let session = model.sessions.first(where: { $0.id == sessionID }) {
      let dirty = session.tabs.filter { $0.dirty }
      if !dirty.isEmpty {
        guard UnsavedGuard.confirmCloseMany(dirty, verb: "closing") else { return false }
      }
      model.closeSession(sessionID)
    }
    onClosed?(sessionID)
    return true
  }

  func windowDidBecomeKey(_ notification: Notification) {
    // Track the key window's session as the active one (menus, key monitor, global hooks target it).
    if let sessionID {
      model.activeSessionID = sessionID
    }
  }

  func windowDidResize(_ notification: Notification) {
    if let autosaveName = window?.frameAutosaveName { window?.saveFrame(usingName: autosaveName) }
  }

  func windowDidMove(_ notification: Notification) {
    if let autosaveName = window?.frameAutosaveName { window?.saveFrame(usingName: autosaveName) }
  }
}
