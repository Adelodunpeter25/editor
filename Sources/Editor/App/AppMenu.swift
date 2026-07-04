import AppKit

extension AppDelegate {
  func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    let recent = Persistence.recentProjects()
    guard !recent.isEmpty else { return nil }
    let menu = NSMenu()
    for path in recent {
      let item = NSMenuItem(
        title: (path as NSString).lastPathComponent,
        action: #selector(openRecentProjectFromDock(_:)),
        keyEquivalent: "")
      item.target = self
      item.representedObject = path
      item.toolTip = path
      // Use the real Finder folder icon for this path; fall back to the SF Symbol folder.
      let icon = NSWorkspace.shared.icon(forFile: path)
      icon.size = NSSize(width: 16, height: 16)
      item.image = icon
      menu.addItem(item)
    }
    return menu
  }

  func buildMenu() {
    let mainMenu = NSMenu()

    // App menu
    let appItem = NSMenuItem()
    mainMenu.addItem(appItem)
    let appMenu = NSMenu()
    appItem.submenu = appMenu
    appMenu.addItem(
      withTitle: "About Editor",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    let check = appMenu.addItem(
      withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
    check.target = self
    appMenu.addItem(.separator())
    let settings = appMenu.addItem(
      withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
    settings.target = self
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "Quit Editor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    // File menu
    let fileItem = NSMenuItem()
    mainMenu.addItem(fileItem)
    let fileMenu = NSMenu(title: "File")
    fileItem.submenu = fileMenu
    let newProj = fileMenu.addItem(
      withTitle: "New Project…", action: #selector(newProject), keyEquivalent: "n")
    newProj.keyEquivalentModifierMask = [.command, .shift]
    newProj.target = self
    let newWindow = fileMenu.addItem(
      withTitle: "New Window", action: #selector(newWindowItem), keyEquivalent: "n")
    newWindow.keyEquivalentModifierMask = [.command, .control]
    newWindow.target = self
    let open = fileMenu.addItem(
      withTitle: "Open Folder…", action: #selector(openFolder), keyEquivalent: "o")
    open.target = self
    // Open Recent submenu — dynamically populated via NSMenuDelegate (see `menuNeedsUpdate`).
    let openRecentItem = fileMenu.addItem(withTitle: "Open Recent", action: nil, keyEquivalent: "")
    let openRecentMenu = NSMenu(title: "Open Recent")
    openRecentItem.submenu = openRecentMenu
    openRecentMenu.delegate = self
    fileMenu.addItem(.separator())
    let newFile = fileMenu.addItem(
      withTitle: "New File", action: #selector(newFileItem), keyEquivalent: "n")
    newFile.target = self
    // New Terminal. The ⌃⇧` key shows for discoverability but the key monitor fires it
    // (a focused terminal would otherwise eat Control-backtick), like Toggle Terminal in View.
    let newTerm = fileMenu.addItem(
      withTitle: "New Terminal", action: #selector(newTerminalItem), keyEquivalent: "`")
    newTerm.keyEquivalentModifierMask = [.control, .shift]
    newTerm.target = self
    fileMenu.addItem(.separator())
    let goToFile = fileMenu.addItem(
      withTitle: "Go to File…", action: #selector(goToFile), keyEquivalent: "p")
    goToFile.target = self
    let cmdPalette = fileMenu.addItem(
      withTitle: "Command Palette…", action: #selector(commandPalette), keyEquivalent: "p")
    cmdPalette.keyEquivalentModifierMask = [.command, .shift]
    cmdPalette.target = self
    let closeTab = fileMenu.addItem(
      withTitle: "Close Tab", action: #selector(closeActiveTab), keyEquivalent: "w")
    closeTab.target = self

    // Edit menu (first-responder actions so text editing + copy/paste work in NSTextView/terminal)
    let editItem = NSMenuItem()
    mainMenu.addItem(editItem)
    let editMenu = NSMenu(title: "Edit")
    editItem.submenu = editMenu
    editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(
      withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editMenu.addItem(.separator())
    // Format moves to ⇧⌥F (matching VS Code) so ⌘⇧F can open Find in Files below.
    let format = editMenu.addItem(
      withTitle: "Format Document", action: #selector(formatActiveDocument), keyEquivalent: "f")
    format.keyEquivalentModifierMask = [.shift, .option]
    format.target = self

    // Find submenu — routes to the active editor's custom find bar (UI/FindBar), which adds
    // match-case / whole-word / regex toggles the native NSTextFinder can't do.
    editMenu.addItem(.separator())
    let findItem = editMenu.addItem(withTitle: "Find", action: nil, keyEquivalent: "")
    let findMenu = NSMenu(title: "Find")
    findItem.submenu = findMenu
    for i in [
      findMenu.addItem(withTitle: "Find…", action: #selector(findInFile), keyEquivalent: "f"),
      findMenu.addItem(
        withTitle: "Find Next", action: #selector(findNextMatch), keyEquivalent: "g"),
      findMenu.addItem(
        withTitle: "Find Previous", action: #selector(findPrevMatch), keyEquivalent: "G"),
      findMenu.addItem(
        withTitle: "Use Selection for Find", action: #selector(findUseSelection), keyEquivalent: "e"
      ),
    ] {
      i.target = self
    }
    let replaceItem = findMenu.addItem(
      withTitle: "Find and Replace…", action: #selector(findReplace), keyEquivalent: "f")
    replaceItem.keyEquivalentModifierMask = [.command, .option]
    replaceItem.target = self
    findMenu.addItem(.separator())
    let findInFiles = findMenu.addItem(
      withTitle: "Find in Files…", action: #selector(findInFilesAction), keyEquivalent: "f")
    findInFiles.keyEquivalentModifierMask = [.command, .shift]
    findInFiles.target = self

    // View menu
    let viewItem = NSMenuItem()
    mainMenu.addItem(viewItem)
    let viewMenu = NSMenu(title: "View")
    viewItem.submenu = viewMenu
    // The ⌃` key equivalent shows here for discoverability; the key monitor actually fires it (the
    // focused terminal would otherwise eat Control-backtick), so this item's key never reaches the menu.
    let term = viewMenu.addItem(
      withTitle: "Toggle Terminal", action: #selector(toggleQuickTerminal), keyEquivalent: "`")
    term.keyEquivalentModifierMask = [.control]
    term.target = self
    NSApp.mainMenu = mainMenu
  }

  @objc private func toggleQuickTerminal() { QuickTerminalHook.toggle?() }
  @objc private func newFileItem() { NewItemHook.newFile?() }
  @objc private func newTerminalItem() { NewItemHook.newTerminal?() }

  @objc private func openFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Open"
    if panel.runModal() == .OK, let url = panel.url { model.openRepo(url.path) }
  }

  @objc private func openRecentProjectFromDock(_ sender: NSMenuItem) {
    guard let path = sender.representedObject as? String else { return }
    model.openRepo(path)  // onSessionOpened → focus/create window
    NSApp.activate(ignoringOtherApps: true)
  }

  /// File > New Window — open a fresh welcome window (no project). The welcome window's
  /// "Open Folder…" button or ⌘O loads a project into a new session window.
  @objc private func newWindowItem() {
    showWelcomeWindow()
    NSApp.activate(ignoringOtherApps: true)
  }

  /// File > Open Recent → click a project. Asks "new window or current window?" first.
  /// If the project is already open, focuses its window regardless of the choice.
  @objc private func openRecentProject(_ sender: NSMenuItem) {
    guard let path = sender.representedObject as? String else { return }
    // Already open → just focus its window (no dialog needed).
    if model.sessions.contains(where: { $0.url == path }) {
      model.openRepo(path)  // focuses existing
      return
    }
    let name = (path as NSString).lastPathComponent
    let alert = NSAlert()
    alert.messageText = "Open “\(name)”"
    alert.informativeText = "Open in a new window, or replace the current window?"
    alert.addButton(withTitle: "New Window")
    alert.addButton(withTitle: "Current Window")
    alert.addButton(withTitle: "Cancel")
    alert.alertStyle = .informational
    let choice = alert.runModal()
    if choice == .alertThirdButtonReturn { return }  // Cancel
    if choice == .alertFirstButtonReturn {
      // New window — openRepo creates a session + window (via onSessionOpened).
      model.openRepo(path)
    } else {
      // Current window — close the key window's session, then open the repo. The new session
      // opens a new window; to make it feel like the same window, preserve the old frame.
      openInCurrentWindow(path)
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  /// Replace the key window's session with a new project, preserving the window frame.
  private func openInCurrentWindow(_ path: String) {
    guard let keyWindow = NSApp.keyWindow,
      let wc = windowControllers.values.first(where: { $0.window === keyWindow }),
      let oldSessionID = wc.sessionID
    else {
      // No key window (shouldn't happen) — fall back to a plain new-window open.
      model.openRepo(path)
      return
    }
    let oldFrame = keyWindow.frame
    // Close the old session (this closes its window via onClosed → windowDidClose).
    model.closeSession(oldSessionID)
    // Open the new repo (creates a session + window via onSessionOpened → showWindow).
    model.openRepo(path)
    // Apply the old frame to the new window so it feels like the same window.
    if let newSession = model.sessions.first(where: { $0.url == path }),
      let newWC = windowControllers[newSession.id]
    {
      newWC.window?.setFrame(oldFrame, display: true)
      newWC.window?.makeKeyAndOrderFront(nil)
    }
  }

  @objc private func newProject() { NewProject.present(model: model) }

  @objc private func openSettings() { model.showSettings = true }

  @objc private func checkForUpdates() { Updates.shared.check(force: true) }

  @objc private func closeActiveTab() {
    guard let s = model.activeSession, let tab = s.activeTab else { return }
    if UnsavedGuard.confirmClose(tab) { s.closeTab(tab.id) }
  }

  @objc private func formatActiveDocument() { ActiveEditor.current?.formatDocument() }

  @objc private func goToFile() { CommandPaletteHook.toggle?() }

  @objc private func commandPalette() { CommandPaletteHook.command?() }

  @objc private func findInFile() { ActiveEditor.current?.showFind() }
  @objc private func findNextMatch() { ActiveEditor.current?.findNext() }
  @objc private func findPrevMatch() { ActiveEditor.current?.findPrevious() }
  @objc private func findUseSelection() { ActiveEditor.current?.useSelectionForFind() }
  @objc private func findReplace() { ActiveEditor.current?.showReplace() }
  @objc private func findInFilesAction() { SidebarSearchHook.reveal?() }
}

extension AppDelegate: NSMenuDelegate {
  /// Populate the "Open Recent" submenu just before it's shown, so it always reflects the current
  /// recent-projects list (and drops entries for repos that no longer exist on disk).
  func menuNeedsUpdate(_ menu: NSMenu) {
    let recent = Persistence.recentProjects()
    menu.removeAllItems()
    if recent.isEmpty {
      let item = menu.addItem(withTitle: "No Recent Projects", action: nil, keyEquivalent: "")
      item.isEnabled = false
      return
    }
    for path in recent {
      let item = NSMenuItem(
        title: (path as NSString).lastPathComponent, action: #selector(openRecentProject(_:)),
        keyEquivalent: "")
      item.target = self
      item.representedObject = path
      item.toolTip = path
      let icon = NSWorkspace.shared.icon(forFile: path)
      icon.size = NSSize(width: 16, height: 16)
      item.image = icon
      menu.addItem(item)
    }
    menu.addItem(.separator())
    let clear = menu.addItem(
      withTitle: "Clear Recent Projects", action: #selector(clearRecentProjects), keyEquivalent: "")
    clear.target = self
  }

  @objc private func clearRecentProjects() {
    UserDefaults.standard[AppDefaults.recentProjects] = [String]()
  }
}
