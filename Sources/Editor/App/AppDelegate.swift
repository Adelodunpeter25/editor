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
  static var newFile: (() -> Void)?  // new blank untitled editor tab (⌘N)
  static var newTerminal: (() -> Void)?  // ⌃⇧`: quick shell if the panel is open, else a terminal tab
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  let model = AppModel()
  var windowController: MainWindowController!
  private var keyMonitor: Any?
  private var cancellables = Set<AnyCancellable>()
  private var settingsWC: SettingsWindowController?
  private let resourceMonitor = ResourceMonitor()
  private var pendingOpenPaths: [String] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Snappier tooltips (default is ~2s). Registered so it doesn't clobber a user override.
    UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 350])

    Env.bootstrap()  // compute login PATH once, before anything spawns
    TerminalStore.shared.fontSize = model.settings.fontSize
    NSApp.appearance = NSAppearance(named: .darkAqua)
    buildMenu()

    windowController = MainWindowController(model: model)

    if !pendingOpenPaths.isEmpty {
      for path in pendingOpenPaths {
        model.openRepo(path)
      }
      pendingOpenPaths.removeAll()
    }

    windowController.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)

    wireTerminalHandlers()
    installKeyMonitor()

    // New File / New Terminal actions — shared by the menu, the ⌃⇧` monitor, and the harness.
    NewItemHook.newFile = { [weak self] in self?.model.activeSession?.newUntitled() }
    NewItemHook.newTerminal = { [weak self] in
      guard let self else { return }
      if QuickTerminalController.current?.isShown == true {
        QuickTerminalController.current?.addShell()  // panel open → add a shell to it
      } else {
        self.model.activeSession?.addTab(Tab(kind: .terminal, title: "Terminal"))  // else a tab
      }
    }

    // Returning to Editor clears the attention flag on the tab you're now looking at.
    NotificationCenter.default.addObserver(
      self, selector: #selector(appBecameActive),
      name: NSApplication.didBecomeActiveNotification, object: nil)

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

    // Pre-warm the tree-sitter grammars in the background so the first file
    // open is instant. LanguageRegistry.configuration() reads + compiles query files from
    // the bundle on the first call (cold); subsequent calls return the cached result.
    // Running this early means the cache is hot before the user clicks any file.
    EditorViewController.highlightQueue.async {
      for lang in TreeSitterHighlighter.availableLanguages {
        _ = TreeSitterHighlighter.forLanguage(lang)
      }
    }
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
        let ed = ActiveEditor.current
      {
        ed.formatDocument()
        return nil
      }
      // ⌃` toggles the quick terminal; ⌃⇧` opens a new terminal (a shell in the panel if it's open,
      // else a terminal tab). Both are intercepted here — a focused terminal would otherwise eat the
      // Control-backtick before the responder chain/menu. (keyCode 50 = the grave/` key, so Shift's
      // remap of `→~ doesn't matter.)
      if mods.contains(.control), !mods.contains(.command), !mods.contains(.option),
        event.keyCode == 50
      {
        if mods.contains(.shift) { NewItemHook.newTerminal?() } else { QuickTerminalHook.toggle?() }
        return nil
      }
      // Cmd+/- have no menu item, so handle here. (Cmd+W is the "Close Tab" menu item.)
      guard mods.contains(.command) else { return event }
      switch key {
      case "=", "+":
        self.model.settings.bumpFont(1)
        return nil
      case "-", "_":
        self.model.settings.bumpFont(-1)
        return nil
      default: return event
      }
    }
  }

  @objc private func appBecameActive() {
    // Reserved for future use (e.g. clearing badge counts when the app becomes active).
  }

  /// macOS calls this when the app is launched (or re-activated) via a dock "Open Recent" item or
  /// via Finder → Open With. Opens the folder as a new session, just like File → Open Folder.
  func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: filename, isDirectory: &isDir), isDir.boolValue
    else { return false }
    if let windowController {
      model.openRepo(filename)
      windowController.showWindow(nil)
      NSApp.activate(ignoringOtherApps: true)
    } else {
      pendingOpenPaths.append(filename)
    }
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    model.saveNow()
  }

}
