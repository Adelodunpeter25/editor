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
    let open = fileMenu.addItem(
      withTitle: "Open Folder…", action: #selector(openFolder), keyEquivalent: "o")
    open.target = self
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
    model.openRepo(path)
    windowController.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
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
