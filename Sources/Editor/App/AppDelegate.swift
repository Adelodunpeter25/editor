import AppKit
import Combine

extension Bundle {
    /// Dev build = bundle id ends in `.dev` (set by build.sh for the debug "Editor Dev" app). Used
    /// to gate the debug harness so a stray /tmp file can never affect a real/release Editor.
    var isDev: Bool { (bundleIdentifier ?? "").hasSuffix(".dev") }
}

/// The "new file / new terminal" actions, shared by the menu items, the key monitor (⌃⇧`), and the
/// debug harness so one implementation backs all three. Populated by `AppDelegate` at launch.
enum NewItemHook {
    static var newFile: (() -> Void)?             // new blank untitled editor tab (⌘N)
    static var newTerminal: (() -> Void)?         // ⌃⇧`: quick shell if the panel is open, else a terminal tab
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var windowController: MainWindowController!
    private var keyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var settingsWC: SettingsWindowController?
    private let resourceMonitor = ResourceMonitor()
    private var attentionItem: AttentionItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Snappier tooltips (default is ~2s). Registered so it doesn't clobber a user override.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 350])

        Env.bootstrap()                 // compute login PATH once, before anything spawns
        TerminalStore.shared.fontSize = model.settings.fontSize
        NSApp.appearance = NSAppearance(named: .darkAqua)
        buildMenu()

        windowController = MainWindowController(model: model)
        windowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        wireTerminalHandlers()
        installKeyMonitor()

        // New File / New Terminal actions — shared by the menu, the ⌃⇧` monitor, and the harness.
        NewItemHook.newFile = { [weak self] in self?.model.activeSession?.newUntitled() }
        NewItemHook.newTerminal = { [weak self] in
            guard let self else { return }
            if QuickTerminalController.current?.isShown == true {
                QuickTerminalController.current?.addShell()        // panel open → add a shell to it
            } else {
                self.model.activeSession?.addTab(Tab(kind: .terminal, title: "Terminal"))   // else a tab
            }
        }

        // Returning to Editor clears the attention flag on the tab you're now looking at.
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)

        // Menu-bar attention item: glanceable session status + jump, even while Editor is in the background.
        attentionItem = AttentionItem(model: model)
        attentionItem.onJump = { [weak self] sessionID, tabID in
            guard let self else { return }
            if let session = self.model.sessions.first(where: { $0.id == sessionID }) {
                self.model.activeSessionID = sessionID
                if let tabID { session.activate(tabID) }
            }
            NSApp.activate(ignoringOtherApps: true)
            self.windowController.showWindow(nil)
        }
        attentionItem.start()

        // Live resource usage of Editor's own process, shown in the bottom status bar (the bar reads the
        // setting to show/hide; only the *running* monitor produces updates).
        resourceMonitor.onUpdate = { memMB, cpu in ResourceStatus.onUpdate?(memMB, cpu) }
        // Off by default; toggling the setting starts/stops it live.
        model.settings.$showResourceMonitor
            .sink { [weak self] on in
                guard let self else { return }
                if on { self.resourceMonitor.start() } else { self.resourceMonitor.stop() }
            }
            .store(in: &cancellables)

        // Settings window on demand.
        model.$showSettings
            .filter { $0 }
            .sink { [weak self] _ in self?.showSettingsWindow() }
            .store(in: &cancellables)

        // Update check (release builds only — the dev build is always "behind" latest).
        if !Bundle.main.isDev {
            Updates.shared.detectBrew()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { Updates.shared.check() }
        }

        // "Manage Formatters…" (from the format prompt) → open Settings on the Formatters tab.
        FormatterPrompt.openManager = { [weak self] in
            self?.showSettingsWindow()
            self?.settingsWC?.showFormatters()
        }

        DebugHarness.start(model: model)   // dev-only (inert in release)
    }

    private func showSettingsWindow() {
        if settingsWC == nil { settingsWC = SettingsWindowController(settings: model.settings) }
        settingsWC?.showWindow(nil)
        settingsWC?.window?.makeKeyAndOrderFront(nil)
        model.showSettings = false
    }

    /// Wire terminal exit handling and font-size syncing.
    private func wireTerminalHandlers() {
        // A tab's process exited (typed `exit`) → flag it so the "Session ended" bar appears.
        TerminalStore.shared.onExit = { [weak self] tabID in
            guard let self else { return }
            for session in self.model.sessions where session.tabs.contains(where: { $0.id == tabID }) {
                session.markExited(tabID)
            }
        }
        model.settings.$fontSize
            .sink { TerminalStore.shared.applyFont(size: $0) }
            .store(in: &cancellables)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Quit (⌘Q, menu, or the red close button funnelled through here by MainWindowController): confirm
    /// before discarding unsaved edits across every session.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let dirty = model.sessions.flatMap { $0.tabs }.filter { $0.dirty }
        return UnsavedGuard.confirmCloseMany(dirty, verb: "quitting") ? .terminateNow : .terminateCancel
    }

    // MARK: - Key handling (Cmd+W close tab, Cmd+/- font)

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let mods = event.modifierFlags
            let key = event.charactersIgnoringModifiers?.lowercased()
            // ⇧⌥F → Format Document. AppKit won't fire a non-Command menu shortcut over the editor: Option is
            // the "compose a special character" modifier, so the keystroke is eaten as text input ("ï") before
            // the menu sees it. Intercept it here (only when an editor is focused, so terminals keep the key).
            if mods.contains(.option), mods.contains(.shift), !mods.contains(.command), key == "f",
               let ed = ActiveEditor.current {
                ed.formatDocument(); return nil
            }
            // ⌃` toggles the quick terminal; ⌃⇧` opens a new terminal (a shell in the panel if it's open,
            // else a terminal tab). Both are intercepted here — a focused terminal would otherwise eat the
            // Control-backtick before the responder chain/menu. (keyCode 50 = the grave/` key, so Shift's
            // remap of `→~ doesn't matter.)
            if mods.contains(.control), !mods.contains(.command), !mods.contains(.option), event.keyCode == 50 {
                if mods.contains(.shift) { NewItemHook.newTerminal?() } else { QuickTerminalHook.toggle?() }
                return nil
            }
            // Cmd+/- have no menu item, so handle here. (Cmd+W is the "Close Tab" menu item.)
            guard mods.contains(.command) else { return event }
            switch key {
            case "=", "+": self.model.settings.bumpFont(1); return nil
            case "-", "_": self.model.settings.bumpFont(-1); return nil
            default: return event
            }
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Editor",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let check = appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        check.target = self
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Editor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        let newProj = fileMenu.addItem(withTitle: "New Project…", action: #selector(newProject), keyEquivalent: "n")
        newProj.keyEquivalentModifierMask = [.command, .shift]
        newProj.target = self
        let open = fileMenu.addItem(withTitle: "Open Folder…", action: #selector(openFolder), keyEquivalent: "o")
        open.target = self
        fileMenu.addItem(.separator())
        let newFile = fileMenu.addItem(withTitle: "New File", action: #selector(newFileItem), keyEquivalent: "n")
        newFile.target = self
        // New Terminal. The ⌃⇧` key shows for discoverability but the key monitor fires it
        // (a focused terminal would otherwise eat Control-backtick), like Toggle Terminal in View.
        let newTerm = fileMenu.addItem(withTitle: "New Terminal", action: #selector(newTerminalItem), keyEquivalent: "`")
        newTerm.keyEquivalentModifierMask = [.control, .shift]
        newTerm.target = self
        fileMenu.addItem(.separator())
        let goToFile = fileMenu.addItem(withTitle: "Go to File…", action: #selector(goToFile), keyEquivalent: "p")
        goToFile.target = self
        let cmdPalette = fileMenu.addItem(withTitle: "Command Palette…", action: #selector(commandPalette), keyEquivalent: "p")
        cmdPalette.keyEquivalentModifierMask = [.command, .shift]
        cmdPalette.target = self
        let closeTab = fileMenu.addItem(withTitle: "Close Tab", action: #selector(closeActiveTab), keyEquivalent: "w")
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
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        // Format moves to ⇧⌥F (matching VS Code) so ⌘⇧F can open Find in Files below.
        let format = editMenu.addItem(withTitle: "Format Document", action: #selector(formatActiveDocument), keyEquivalent: "f")
        format.keyEquivalentModifierMask = [.shift, .option]
        format.target = self

        // Find submenu — routes to the active editor's custom find bar (UI/FindBar), which adds
        // match-case / whole-word / regex toggles the native NSTextFinder can't do.
        editMenu.addItem(.separator())
        let findItem = editMenu.addItem(withTitle: "Find", action: nil, keyEquivalent: "")
        let findMenu = NSMenu(title: "Find")
        findItem.submenu = findMenu
        for i in [findMenu.addItem(withTitle: "Find…", action: #selector(findInFile), keyEquivalent: "f"),
                  findMenu.addItem(withTitle: "Find Next", action: #selector(findNextMatch), keyEquivalent: "g"),
                  findMenu.addItem(withTitle: "Find Previous", action: #selector(findPrevMatch), keyEquivalent: "G"),
                  findMenu.addItem(withTitle: "Use Selection for Find", action: #selector(findUseSelection), keyEquivalent: "e")] {
            i.target = self
        }
        let replaceItem = findMenu.addItem(withTitle: "Find and Replace…", action: #selector(findReplace), keyEquivalent: "f")
        replaceItem.keyEquivalentModifierMask = [.command, .option]
        replaceItem.target = self
        findMenu.addItem(.separator())
        let findInFiles = findMenu.addItem(withTitle: "Find in Files…", action: #selector(findInFilesAction), keyEquivalent: "f")
        findInFiles.keyEquivalentModifierMask = [.command, .shift]
        findInFiles.target = self

        // View menu
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        // The ⌃` key equivalent shows here for discoverability; the key monitor actually fires it (the
        // focused terminal would otherwise eat Control-backtick), so this item's key never reaches the menu.
        let term = viewMenu.addItem(withTitle: "Toggle Terminal", action: #selector(toggleQuickTerminal), keyEquivalent: "`")
        term.keyEquivalentModifierMask = [.control]
        term.target = self
        let history = viewMenu.addItem(withTitle: "Toggle Git History", action: #selector(toggleGitHistory), keyEquivalent: "y")
        history.keyEquivalentModifierMask = [.command, .shift]
        history.target = self

        NSApp.mainMenu = mainMenu
    }

    @objc private func toggleQuickTerminal() { QuickTerminalHook.toggle?() }
    @objc private func toggleGitHistory() { CenterViewController.toggleHistoryHook?() }
    @objc private func newFileItem() { NewItemHook.newFile?() }
    @objc private func newTerminalItem() { NewItemHook.newTerminal?() }

    @objc private func appBecameActive() {
        // Reserved for future use (e.g. clearing badge counts when the app becomes active).
    }

    @objc private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url { model.openRepo(url.path) }
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
