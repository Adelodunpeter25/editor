import AppKit
import Combine
import LineEnding

/// Controller for the status bar - handles all business logic including git operations,
/// menu handling, and coordination with the editor. The view (StatusBarView) is purely
/// for rendering and delegates all actions here.
final class StatusBarController {
  let model: AppModel
  private let session: Session?
  private var cancellables = Set<AnyCancellable>()
  private var sessionObserver: AnyCancellable?
  
  // Callbacks for view actions
  var onBranchChange: (() -> Void)?
  var onEditorStatusChange: (() -> Void)?
  var onResourceUpdate: ((Double, Double) -> Void)?
  
  // Resource monitor state
  private var lastMem = 0.0
  private var lastCpu = 0.0
  
  init(model: AppModel, session: Session?) {
    self.model = model
    self.session = session
    setupBindings()
  }
  
  // MARK: - Setup
  
  private func setupBindings() {
    // Track font size changes
    model.settings.$fontSize.receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.onBranchChange?()
        self?.onEditorStatusChange?()
      }
      .store(in: &cancellables)
    
    // Resource monitor updates
    ResourceStatus.onUpdate = { [weak self] mem, cpu in
      self?.lastMem = mem
      self?.lastCpu = cpu
      self?.onResourceUpdate?(mem, cpu)
    }
    
    // Resource monitor visibility
    model.settings.$showResourceMonitor.receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.onResourceUpdate?(self?.lastMem ?? 0, self?.lastCpu ?? 0)
      }
      .store(in: &cancellables)
    
    // Session changes
    observeSession()
    
    // Editor status changes
    EditorStatus.onChange = { [weak self] in
      self?.onEditorStatusChange?()
    }
  }
  
  private func observeSession() {
    sessionObserver = session?.objectWillChange
      .receive(on: RunLoop.main).sink { [weak self] in
        self?.onBranchChange?()
        self?.onEditorStatusChange?()
      }
  }
  
  // MARK: - Data Access
  
  var isHidden: Bool {
    session == nil
  }
  
  var branchName: String? {
    session?.gitBranch
  }
  
  var showResourceMonitor: Bool {
    model.settings.showResourceMonitor
  }
  
  var resourceText: String {
    String(format: "%.0f MB · %.1f%% CPU", lastMem, lastCpu)
  }
  
  var editorInfo: EditorInfo? {
    guard let ed = ActiveEditor.current else { return nil }
    let lc = ed.cursorLineColumn()
    return EditorInfo(
      lineColumn: "Ln \(lc.line), Col \(lc.column)",
      indentStyle: ed.indentStyle,
      lineEnding: ed.lineEnding.label,
      language: ed.languageDisplayName,
      editMode: ed.textView.editMode == .normal ? "NORMAL" : "INSERT"
    )
  }
  
  struct EditorInfo {
    let lineColumn: String
    let indentStyle: String
    let lineEnding: String
    let language: String
    let editMode: String
  }
  
  // MARK: - Actions
  
  func handleBranchClick() -> NSMenu? {
    guard let repo = session?.url else { return nil }
    let current = session?.gitBranch
    let branches = Git.localBranches(repo)
    let menu = NSMenu()
    
    for b in branches {
      let item = menu.addItem(
        withTitle: b, 
        action: b == current ? nil : #selector(checkoutBranch(_:)), 
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = b
      item.state = b == current ? .on : .off
    }
    
    menu.addItem(.separator())
    
    let create = menu.addItem(
      withTitle: "Create New Branch…", 
      action: #selector(createBranchClicked), 
      keyEquivalent: ""
    )
    create.target = self
    
    let del = menu.addItem(withTitle: "Delete Branch…", action: nil, keyEquivalent: "")
    let delMenu = NSMenu()
    
    for b in branches where b != current {
      let di = delMenu.addItem(
        withTitle: b, 
        action: #selector(deleteBranchClicked(_:)), 
        keyEquivalent: ""
      )
      di.target = self
      di.representedObject = b
    }
    
    if delMenu.items.isEmpty {
      delMenu.addItem(withTitle: "No other branches", action: nil, keyEquivalent: "")
    }
    
    del.submenu = delMenu
    return menu
  }
  
  @objc private func checkoutBranch(_ item: NSMenuItem) {
    guard let b = item.representedObject as? String, let repo = session?.url else { return }
    runGit({ Git.checkout(repo, b) }, failTitle: "Couldn't switch to \"\(b)\"")
  }
  
  @objc private func createBranchClicked() {
    guard let repo = session?.url else { return }
    let alert = NSAlert()
    alert.messageText = "Create New Branch"
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    field.placeholderString = "branch name"
    alert.accessoryView = field
    alert.addButton(withTitle: "Create")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = field
    
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    let name = field.stringValue.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }
    
    runGit({ Git.createBranch(repo, name) }, failTitle: "Couldn't create \"\(name)\"")
  }
  
  @objc private func deleteBranchClicked(_ item: NSMenuItem) {
    guard let b = item.representedObject as? String, let repo = session?.url else { return }
    
    DispatchQueue.global().async {
      let merged = Git.isMerged(repo, b)
      DispatchQueue.main.async { [weak self] in
        let a = NSAlert()
        a.messageText = "Delete branch \"\(b)\"?"
        a.alertStyle = .warning
        
        if !merged {
          a.informativeText =
            "\"\(b)\" isn't fully merged — deleting it may discard commits that aren't on any other branch."
        }
        
        a.addButton(withTitle: "Delete")
        a.addButton(withTitle: "Cancel")
        
        guard a.runModal() == .alertFirstButtonReturn else { return }
        self?.runGit(
          { Git.deleteBranch(repo, b, force: !merged).error }, 
          failTitle: "Couldn't delete \"\(b)\""
        )
      }
    }
  }
  
  private func runGit(_ op: @escaping () -> String?, failTitle: String) {
    DispatchQueue.global().async {
      let err = op()
      DispatchQueue.main.async { [weak self] in
        if let err, !err.isEmpty { 
          self?.showError(failTitle, err) 
        }
        self?.refreshBranch()
      }
    }
  }
  
  private func refreshBranch() {
    guard let repo = session?.url else { return }
    DispatchQueue.global().async {
      let b = Git.branch(repo)
      DispatchQueue.main.async { [weak self] in
        self?.session?.gitBranch = b
        self?.onBranchChange?()
      }
    }
  }
  
  private func showError(_ title: String, _ detail: String) {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = detail
    a.alertStyle = .warning
    a.addButton(withTitle: "OK")
    a.runModal()
  }
  
  // MARK: - Editor Actions
  
  func handleGoToLineClick() {
    CommandPaletteHook.lineJump?()
  }
  
  func handleIndentClick() -> NSMenu? {
    guard let ed = ActiveEditor.current else { return nil }
    return createMenu(
      options: ["Tabs", "Spaces: 2", "Spaces: 4", "Spaces: 8"], 
      current: ed.indentStyle,
      action: #selector(indentPicked(_:))
    )
  }
  
  @objc private func indentPicked(_ item: NSMenuItem) {
    ActiveEditor.current?.convertIndentation(to: item.representedObject as! String)
    onEditorStatusChange?()
  }
  
  func handleEolClick() -> NSMenu? {
    guard let ed = ActiveEditor.current else { return nil }
    let options = [LineEnding.lf, LineEnding.crlf]
    let current = ed.lineEnding
    let menu = NSMenu()
    
    for opt in options {
      let item = menu.addItem(
        withTitle: opt.label, 
        action: #selector(eolPicked(_:)), 
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = opt
      item.state = opt.rawValue == current.rawValue ? .on : .off
    }
    
    return menu
  }
  
  @objc private func eolPicked(_ item: NSMenuItem) {
    ActiveEditor.current?.convertLineEndings(to: item.representedObject as! LineEnding)
    onEditorStatusChange?()
  }
  
  func handleLangClick() -> NSMenu? {
    guard let ed = ActiveEditor.current else { return nil }
    let menu = NSMenu()
    
    let auto = menu.addItem(
      withTitle: "Auto-detect", 
      action: #selector(langPicked(_:)), 
      keyEquivalent: ""
    )
    auto.target = self
    auto.representedObject = ""
    menu.addItem(.separator())
    
    for lang in EditorViewController.availableLanguages() {
      let item = menu.addItem(
        withTitle: lang.name, 
        action: #selector(langPicked(_:)), 
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = lang.key
      item.state = ed.languageDisplayName == lang.name ? .on : .off
    }
    
    return menu
  }
  
  @objc private func langPicked(_ item: NSMenuItem) {
    let key = item.representedObject as? String
    ActiveEditor.current?.setLanguageOverride((key?.isEmpty ?? true) ? nil : key)
    // Persist the extension → language mapping so it applies to all files with that extension.
    if let editor = ActiveEditor.current {
      let ext = (editor.path as NSString).pathExtension
      if !ext.isEmpty {
        if let langKey = key, !langKey.isEmpty {
          Settings.setLanguageOverride(forExtension: ext, language: langKey)
        } else {
          // "Auto-detect" selected → remove the override for this extension.
          Settings.removeLanguageOverride(forExtension: ext)
        }
      }
    }
    onEditorStatusChange?()
  }
  
  private func createMenu(options: [String], current: String, action: Selector) -> NSMenu {
    let menu = NSMenu()
    for opt in options {
      let item = menu.addItem(withTitle: opt, action: action, keyEquivalent: "")
      item.target = self
      item.representedObject = opt
      item.state = opt == current ? .on : .off
    }
    return menu
  }
  
  func handleShortcutsClick() {
    ShortcutsWindowController.shared.show()
  }
}