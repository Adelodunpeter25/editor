import AppKit
import Combine

/// The sidebar: a segmented control (Files / Changes / Search) with file-actions toolbar above the
/// content pane (file tree, git changes list, or search panel).
final class SidebarViewController: NSViewController {
  static weak var current: SidebarViewController?  // for the debug harness (segment switching)
  private let model: AppModel
  private var cancellables = Set<AnyCancellable>()
  private var sessionRevealObservers: [String: AnyCancellable] = [:]  // per-session reveal refresh
  private let filesContainer = NSView()
  private var treeVC: FileTreeViewController?
  private var changesVC: ChangesViewController?
  private var historyVC: GitHistoryViewController?
  private var changesSplit: NSSplitView?  // vertical split: changes on top, history below
  private var searchVC: SearchViewController?
  private var store: RepoStore?  // one shared git poller for the tree + Changes
  private var branchBridge: AnyCancellable?  // store.branch → session.gitBranch
  private var currentRepo: String?
  private var lastRevealedPath: String?  // dedup auto-reveal of the active file in the tree
  private var didSizeChangesSplit = false
  private let filesModeSeg: PointerSegmentedControl = {
    let s = PointerSegmentedControl()
    s.segmentCount = 3
    func icon(_ name: String) -> NSImage? {
      NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
    s.setImage(icon("doc.on.doc"), forSegment: 0)
    s.setImage(icon("arrow.triangle.branch"), forSegment: 1)
    s.setImage(icon("magnifyingglass"), forSegment: 2)
    s.setToolTip("Files", forSegment: 0)
    s.setToolTip("Changes (git)", forSegment: 1)
    s.setToolTip("Search", forSegment: 2)
    s.trackingMode = .selectOne
    return s
  }()
  private enum SidebarMode: Int {
    case files = 0
    case changes = 1
    case search = 2
  }
  private var sidebarMode: SidebarMode {
    SidebarMode(rawValue: filesModeSeg.selectedSegment) ?? .files
  }
  private var changesMode: Bool { sidebarMode == .changes }
  private var fileActionsBar: NSStackView?  // new file / new folder / collapse-all (Files mode only)
  private var sidebarEmptyView: NSView?  // "Open Folder" prompt when no project is open

  init(model: AppModel) {
    self.model = model
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func loadView() {
    self.view = makeFilesPane()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    SidebarViewController.current = self
    SidebarSearchHook.reveal = { [weak self] in self?.revealSearch() }
    model.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] in self?.refresh() }
      .store(in: &cancellables)
    // Pause git polling while the app is in the background.
    let nc = NotificationCenter.default
    nc.addObserver(
      self, selector: #selector(appResignedActive), name: NSApplication.didResignActiveNotification,
      object: nil)
    nc.addObserver(
      self, selector: #selector(appBecameActive), name: NSApplication.didBecomeActiveNotification,
      object: nil)
    refresh()
  }

  @objc private func appResignedActive() { store?.stop() }
  @objc private func appBecameActive() { if model.activeSession != nil { showSidebarContent() } }

  override func viewDidLayout() {
    super.viewDidLayout()
    if let changesSplit, !didSizeChangesSplit, changesSplit.bounds.height > 100 {
      didSizeChangesSplit = true
      let targetY = changesSplit.bounds.height * 0.6
      changesSplit.setPosition(targetY, ofDividerAt: 0)
    }
  }

  private func refresh() {
    syncFileTree()
    observeSessionReveal()
    revealActiveFile()
  }

  /// Auto-reveal the active file in the tree (VS Code-style): when the active tab is a file, expand to
  /// it, select it, scroll it in. Files mode only; deduped so we don't fight manual scrolling.
  private func revealActiveFile() {
    guard sidebarMode == .files, let treeVC,
      let session = model.activeSession, let tab = session.activeTab,
      tab.kind == .file, let abs = tab.path
    else { return }
    let prefix = session.url.hasSuffix("/") ? session.url : session.url + "/"
    let rel = abs.hasPrefix(prefix) ? String(abs.dropFirst(prefix.count)) : abs
    guard rel != lastRevealedPath else { return }
    lastRevealedPath = rel
    treeVC.reveal(rel)
  }

  /// Re-observe each session so that when the active tab changes we auto-reveal the file in the tree.
  private func observeSessionReveal() {
    sessionRevealObservers = Dictionary(
      uniqueKeysWithValues: model.sessions.map { session in
        (
          session.id,
          session.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.revealActiveFile() }
        )
      })
  }

  // MARK: - Layout

  private func makeFilesPane() -> NSView {
    let pane = NSView()
    pane.wantsLayer = true
    pane.layer?.backgroundColor = Theme.sidebarBg.cgColor

    filesModeSeg.selectedSegment = max(
      0, min(2, UserDefaults.standard.integer(forKey: "rightMode")))
    filesModeSeg.target = self
    filesModeSeg.action = #selector(filesModeChanged)
    filesModeSeg.controlSize = .regular
    filesModeSeg.segmentStyle = .rounded
    filesModeSeg.toolTip = "Files tree / Changes (git)"
    filesModeSeg.focusRingType = .none
    filesModeSeg.translatesAutoresizingMaskIntoConstraints = false
    filesContainer.translatesAutoresizingMaskIntoConstraints = false

    // Tree toolbar: new file / new folder / collapse-all. Files mode only.
    let iconSize: CGFloat = 13
    let newFile = ClosureButton(symbol: "doc.badge.plus", pointSize: iconSize) { [weak self] in
      self?.treeVC?.beginNewFile()
    }
    newFile.toolTip = "New file"
    newFile.focusRingType = .none
    let newFolder = ClosureButton(symbol: "folder.badge.plus", pointSize: iconSize) { [weak self] in
      self?.treeVC?.beginNewFolder()
    }
    newFolder.toolTip = "New folder"
    newFolder.focusRingType = .none
    let collapse = ClosureButton(symbol: "arrow.down.right.and.arrow.up.left", pointSize: iconSize)
    { [weak self] in self?.treeVC?.collapseAll() }
    collapse.toolTip = "Collapse all folders"
    collapse.focusRingType = .none
    let actions = NSStackView(views: [newFile, newFolder, collapse])
    actions.orientation = .horizontal
    actions.spacing = 8
    actions.translatesAutoresizingMaskIntoConstraints = false
    actions.isHidden = sidebarMode != .files
    fileActionsBar = actions

    pane.addSubview(filesModeSeg)
    pane.addSubview(actions)
    pane.addSubview(filesContainer)
    NSLayoutConstraint.activate([
      filesModeSeg.topAnchor.constraint(equalTo: pane.topAnchor, constant: 12),
      filesModeSeg.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 10),
      actions.centerYAnchor.constraint(equalTo: filesModeSeg.centerYAnchor),
      actions.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -8),
      actions.leadingAnchor.constraint(
        greaterThanOrEqualTo: filesModeSeg.trailingAnchor, constant: 8),
      filesContainer.topAnchor.constraint(equalTo: filesModeSeg.bottomAnchor, constant: 10),
      filesContainer.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
      filesContainer.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
      filesContainer.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
    ])
    return pane
  }

  // MARK: - Mode switching

  @objc private func filesModeChanged() {
    let newSegment = filesModeSeg.selectedSegment

    // If switching to search, directly add a search tab instead of showing inline
    if newSegment == SidebarMode.search.rawValue {
      // Switch back to the previous mode (before the click)
      let previousMode = UserDefaults.standard.integer(forKey: "rightMode")
      filesModeSeg.selectedSegment = previousMode

      // Add a new search tab
      let title = "Search"
      model.activeSession?.addTab(Tab(kind: .search, title: title))
      return
    }

    UserDefaults.standard.set(newSegment, forKey: "rightMode")
    showSidebarContent()
  }

  /// Rebuild the tree + changes VCs when the active session changes, then show the one for the mode.
  private func syncFileTree() {
    guard let session = model.activeSession else {
      teardownSidebarVCs()
      currentRepo = nil
      showSidebarEmpty()
      return
    }
    hideSidebarEmpty()
    if currentRepo != session.url {
      teardownSidebarVCs()
      currentRepo = session.url
      lastRevealedPath = nil  // new tree → reveal the active file afresh
      let store = RepoStore(repo: session.url, settings: model.settings)
      let tree = FileTreeViewController(
        store: store, settings: model.settings,
        onOpen: { [weak self] path in self?.model.activeSession?.openFile(path) },
        onRename: { [weak self] old, new in
          self?.model.activeSession?.fileRenamed(from: old, to: new)
        },
        onDelete: { [weak self] rel in self?.model.activeSession?.fileDeleted(rel) })
      let changes = ChangesViewController(
        store: store,
        onOpenDiff: { [weak self] path in
          if let reveal = DiffNavigator.revealDiff {
            reveal(path, nil)
          } else {
            self?.model.activeSession?.openDiff(path)
          }
        },
        onOpenFile: { [weak self] path in self?.model.activeSession?.openFile(path) })
      let history = GitHistoryViewController(
        store: store,
        onOpenDiff: { [weak self] path, commitHash in
          if let reveal = DiffNavigator.revealDiff {
            reveal(path, commitHash)
          } else {
            self?.model.activeSession?.openDiff(path, commitHash: commitHash)
          }
        },
        onOpenCommitSummary: { [weak self] hash in
          self?.model.activeSession?.openCommitSummary(hash)
        })
      let search = SearchViewController(
        repo: session.url, fff: session.fff,
        onOpen: { [weak self] rel, line in self?.openSearchResult(rel, line) })
      search.onOpenAsTab = { [weak self] query, options in
        SearchSeed.pending = (query, options)
        let title = query.isEmpty ? "Search" : "Search: \(query)"
        self?.model.activeSession?.addTab(Tab(kind: .search, title: title))
      }
      addChild(tree)
      addChild(changes)
      addChild(history)
      addChild(search)
      treeVC = tree
      changesVC = changes
      historyVC = history
      searchVC = search
      self.store = store
      branchBridge = store.$branch.sink { [weak session] in session?.gitBranch = $0 }
    }
    showSidebarContent()
  }

  private func showSidebarContent() {
    fileActionsBar?.isHidden = sidebarMode != .files
    guard let treeVC, let changesVC, let historyVC, let searchVC, let store else { return }

    // Build the changes split once and reuse it
    if changesSplit == nil {
      let split = NSSplitView()
      split.isVertical = false
      split.dividerStyle = .thin
      split.delegate = self
      split.addArrangedSubview(changesVC.view)
      split.addArrangedSubview(historyVC.view)
      split.setHoldingPriority(.defaultLow, forSubviewAt: 0)
      split.setHoldingPriority(.defaultLow, forSubviewAt: 1)
      changesSplit = split
    }

    // Show the correct pane, hide the others
    let panes: [(SidebarMode, NSView)] = [
      (.files, treeVC.view),
      (.changes, changesSplit!),
      (.search, searchVC.view),
    ]
    for (mode, paneView) in panes {
      if mode == sidebarMode {
        if paneView.superview == nil {
          paneView.translatesAutoresizingMaskIntoConstraints = false
          filesContainer.addSubview(paneView)
          NSLayoutConstraint.activate([
            paneView.topAnchor.constraint(equalTo: filesContainer.topAnchor),
            paneView.bottomAnchor.constraint(equalTo: filesContainer.bottomAnchor),
            paneView.leadingAnchor.constraint(equalTo: filesContainer.leadingAnchor),
            paneView.trailingAnchor.constraint(equalTo: filesContainer.trailingAnchor),
          ])
        }
        paneView.isHidden = false
      } else {
        paneView.isHidden = true
      }
    }

    store.start(tree: sidebarMode == .files, changes: sidebarMode == .changes)
    if sidebarMode == .files {
      lastRevealedPath = nil
      revealActiveFile()
    }
    if sidebarMode == .search {
      DispatchQueue.main.async { [weak self] in self?.searchVC?.focusField() }
    }
    if sidebarMode == .changes { historyVC.loadIfNeeded() }
  }

  // MARK: - Empty state

  private func showSidebarEmpty() {
    guard sidebarEmptyView == nil else { return }
    let label = NSTextField(labelWithString: "No project open")
    label.font = .systemFont(ofSize: 12)
    label.textColor = .tertiaryLabelColor
    label.alignment = .center

    let btn = PointerButton()
    btn.title = "Open Folder\u{2026}"
    btn.bezelStyle = .rounded
    btn.focusRingType = .none
    btn.target = self
    btn.action = #selector(openRepoFromSidebar)

    let stack = NSStackView(views: [label, btn])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false
    filesContainer.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: filesContainer.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: filesContainer.centerYAnchor),
    ])
    sidebarEmptyView = stack
    fileActionsBar?.isHidden = true
    filesModeSeg.isHidden = true
  }

  private func hideSidebarEmpty() {
    sidebarEmptyView?.removeFromSuperview()
    sidebarEmptyView = nil
    filesModeSeg.isHidden = false
  }

  @objc private func openRepoFromSidebar() { openRepo() }

  // MARK: - Teardown & helpers

  private func teardownSidebarVCs() {
    store?.stop()
    store = nil
    changesSplit?.removeFromSuperview()
    changesSplit = nil
    treeVC?.view.removeFromSuperview()
    treeVC?.removeFromParent()
    treeVC = nil
    changesVC?.view.removeFromSuperview()
    changesVC?.removeFromParent()
    changesVC = nil
    historyVC?.view.removeFromSuperview()
    historyVC?.removeFromParent()
    historyVC = nil
    if let sv = searchVC {
      if sv.isViewLoaded { sv.view.removeFromSuperview() }
      sv.removeFromParent()
    }
    searchVC = nil
    didSizeChangesSplit = false
  }

  private func openSearchResult(_ rel: String, _ line: Int) {
    FileNavigator.openAt?(rel, line)
  }

  func revealSearch() {
    filesModeSeg.selectedSegment = SidebarMode.search.rawValue
    filesModeChanged()
  }

  func debugSelectMode(_ index: Int) {
    filesModeSeg.selectedSegment = max(0, min(2, index))
    filesModeChanged()
  }

  private func openRepo() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Open"
    if panel.runModal() == .OK, let url = panel.url { model.openRepo(url.path) }
  }

  static func header(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 11, weight: .semibold)
    label.textColor = .secondaryLabelColor
    return label
  }
}

extension SidebarViewController: NSSplitViewDelegate {
  func splitView(
    _ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat,
    ofSubviewAt dividerIndex: Int
  ) -> CGFloat {
    if splitView === changesSplit {
      return 80
    }
    return proposedMinimumPosition
  }

  func splitView(
    _ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat,
    ofSubviewAt dividerIndex: Int
  ) -> CGFloat {
    if splitView === changesSplit {
      return splitView.bounds.height - 80
    }
    return proposedMaximumPosition
  }
}
