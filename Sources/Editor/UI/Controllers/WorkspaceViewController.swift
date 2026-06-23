import AppKit
import Combine

/// Root layout: a horizontal split with the sidebar (files) on the left and the workspace (center)
/// on the right. A *plain* NSSplitView (not NSSplitViewController) so the divider drags reliably.
final class WorkspaceViewController: NSViewController, NSSplitViewDelegate {
    private let model: AppModel
    private let centerVC: CenterViewController
    private let sidebarVC: SidebarViewController
    private var didSizeOnce = false

    init(model: AppModel) {
        self.model = model
        self.centerVC = CenterViewController(model: model)
        self.sidebarVC = SidebarViewController(model: model)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let split = NSSplitView()
        split.isVertical = true                 // vertical divider → side-by-side
        split.dividerStyle = .thin
        split.autosaveName = "MulteeMainSplit"
        split.delegate = self
        addChild(sidebarVC)
        addChild(centerVC)
        split.addArrangedSubview(sidebarVC.view)
        split.addArrangedSubview(centerVC.view)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 0)  // sidebar keeps its width
        split.setHoldingPriority(.defaultLow, forSubviewAt: 1)   // center flexes
        self.view = split
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard let split = view as? NSSplitView, split.bounds.width > 100,
              split.arrangedSubviews.count > 1 else { return }
        let total = split.bounds.width
        let sidebarW = split.arrangedSubviews[0].frame.width
        // First layout: set the default sidebar width if nothing valid was restored.
        if !didSizeOnce {
            didSizeOnce = true
            if sidebarW < 120 || sidebarW > total - 200 {
                split.setPosition(320, ofDividerAt: 0)
            }
        } else if sidebarW < 120 {
            // Self-heal: the sidebar has no intrinsic width, so never let it collapse to nothing.
            split.setPosition(320, ofDividerAt: 0)
        }
    }

    // Keep both panes usable while dragging.
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat { 220 }
    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat { splitView.bounds.width - 360 }
    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        view !== sidebarVC.view   // on window resize, grow/shrink the center, keep the sidebar
    }
}

// MARK: - Sidebar (files/changes/search)

/// The sidebar: a segmented control (Files / Changes / Search) with file-actions toolbar above the
/// content pane (file tree, git changes list, or search panel).
final class SidebarViewController: NSViewController {
    static weak var current: SidebarViewController?   // for the debug harness (segment switching)
    private let model: AppModel
    private var cancellables = Set<AnyCancellable>()
    private var sessionRevealObservers: [String: AnyCancellable] = [:]   // per-session reveal refresh
    private let filesContainer = NSView()
    private var treeVC: FileTreeViewController?
    private var changesVC: ChangesViewController?
    private var searchVC: SearchViewController?
    private var store: RepoStore?            // one shared git poller for the tree + Changes
    private var branchBridge: AnyCancellable?   // store.branch → session.gitBranch
    private var currentRepo: String?
    private var lastRevealedPath: String?    // dedup auto-reveal of the active file in the tree
    private let filesModeSeg: PointerSegmentedControl = {
        let s = PointerSegmentedControl()
        s.segmentCount = 3
        func icon(_ name: String) -> NSImage? { NSImage(systemSymbolName: name, accessibilityDescription: nil) }
        s.setImage(icon("doc.on.doc"), forSegment: 0)
        s.setImage(icon("arrow.triangle.branch"), forSegment: 1)
        s.setImage(icon("magnifyingglass"), forSegment: 2)
        s.setToolTip("Files", forSegment: 0)
        s.setToolTip("Changes (git)", forSegment: 1)
        s.setToolTip("Search", forSegment: 2)
        s.trackingMode = .selectOne
        return s
    }()
    private enum SidebarMode: Int { case files = 0, changes = 1, search = 2 }
    private var sidebarMode: SidebarMode { SidebarMode(rawValue: filesModeSeg.selectedSegment) ?? .files }
    private var changesMode: Bool { sidebarMode == .changes }
    private var fileActionsBar: NSStackView?   // new file / new folder / collapse-all (Files mode only)
    private var sidebarEmptyView: NSView?    // "Open Folder" prompt when no project is open

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
        nc.addObserver(self, selector: #selector(appResignedActive), name: NSApplication.didResignActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(appBecameActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        refresh()
    }

    @objc private func appResignedActive() { store?.stop() }
    @objc private func appBecameActive() { if model.activeSession != nil { showSidebarContent() } }

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
              tab.kind == .file, let abs = tab.path else { return }
        let prefix = session.url.hasSuffix("/") ? session.url : session.url + "/"
        let rel = abs.hasPrefix(prefix) ? String(abs.dropFirst(prefix.count)) : abs
        guard rel != lastRevealedPath else { return }
        lastRevealedPath = rel
        treeVC.reveal(rel)
    }

    /// Re-observe each session so that when the active tab changes we auto-reveal the file in the tree.
    private func observeSessionReveal() {
        sessionRevealObservers = Dictionary(uniqueKeysWithValues: model.sessions.map { session in
            (session.id, session.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] in self?.revealActiveFile() })
        })
    }

    // FILES pane — a Files/Changes toggle over a container that holds the tree or the changes view.
    private func makeFilesPane() -> NSView {
        let pane = NSView()
        pane.wantsLayer = true
        pane.layer?.backgroundColor = NSColor(white: 0.145, alpha: 1).cgColor

        filesModeSeg.selectedSegment = max(0, min(2, UserDefaults.standard.integer(forKey: "rightMode")))
        filesModeSeg.target = self
        filesModeSeg.action = #selector(filesModeChanged)
        filesModeSeg.controlSize = .small
        filesModeSeg.segmentStyle = .rounded
        filesModeSeg.toolTip = "Files tree / Changes (git)"
        filesModeSeg.focusRingType = .none
        filesModeSeg.translatesAutoresizingMaskIntoConstraints = false
        filesContainer.translatesAutoresizingMaskIntoConstraints = false

        // Tree toolbar: new file / new folder / collapse-all (VS Code's Explorer actions). Files mode only.
        let iconSize: CGFloat = 13
        let newFile = ClosureButton(symbol: "doc.badge.plus", pointSize: iconSize) { [weak self] in self?.treeVC?.beginNewFile() }
        newFile.toolTip = "New file"; newFile.focusRingType = .none
        let newFolder = ClosureButton(symbol: "folder.badge.plus", pointSize: iconSize) { [weak self] in self?.treeVC?.beginNewFolder() }
        newFolder.toolTip = "New folder"; newFolder.focusRingType = .none
        let collapse = ClosureButton(symbol: "arrow.down.right.and.arrow.up.left", pointSize: iconSize) { [weak self] in self?.treeVC?.collapseAll() }
        collapse.toolTip = "Collapse all folders"; collapse.focusRingType = .none
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
            filesModeSeg.topAnchor.constraint(equalTo: pane.topAnchor, constant: 8),
            filesModeSeg.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 10),
            actions.centerYAnchor.constraint(equalTo: filesModeSeg.centerYAnchor),
            actions.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -8),
            actions.leadingAnchor.constraint(greaterThanOrEqualTo: filesModeSeg.trailingAnchor, constant: 8),
            filesContainer.topAnchor.constraint(equalTo: filesModeSeg.bottomAnchor, constant: 6),
            filesContainer.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            filesContainer.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            filesContainer.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
        ])
        return pane
    }

    @objc private func filesModeChanged() {
        UserDefaults.standard.set(filesModeSeg.selectedSegment, forKey: "rightMode")
        showSidebarContent()
    }

    /// Rebuild the tree + changes VCs when the active session changes, then show the one for the mode.
    private func syncFileTree() {
        guard let session = model.activeSession else {
            teardownSidebarVCs(); currentRepo = nil
            showSidebarEmpty()
            return
        }
        hideSidebarEmpty()
        if currentRepo != session.url {
            teardownSidebarVCs()
            currentRepo = session.url
            lastRevealedPath = nil          // new tree → reveal the active file afresh
            let store = RepoStore(repo: session.url, settings: model.settings)
            let tree = FileTreeViewController(store: store, settings: model.settings,
                onOpen: { [weak self] path in self?.model.activeSession?.openFile(path) },
                onRename: { [weak self] old, new in self?.model.activeSession?.fileRenamed(from: old, to: new) },
                onDelete: { [weak self] rel in self?.model.activeSession?.fileDeleted(rel) })
            let changes = ChangesViewController(store: store,
                onOpenDiff: { [weak self] path in self?.model.activeSession?.openDiff(path) },
                onOpenFile: { [weak self] path in self?.model.activeSession?.openFile(path) })
            let search = SearchViewController(repo: session.url,
                onOpen: { [weak self] rel, line in self?.openSearchResult(rel, line) })
            search.onOpenAsTab = { [weak self] query, options in
                SearchSeed.pending = (query, options)        // CenterViewController.render seeds the new tab
                let title = query.isEmpty ? "Search" : "Search: \(query)"
                self?.model.activeSession?.addTab(Tab(kind: .search, title: title))   // always a fresh tab (multiple allowed)
            }
            addChild(tree); addChild(changes); addChild(search)
            treeVC = tree; changesVC = changes; searchVC = search; self.store = store
            // Bridge the git poller's branch onto the session so the status bar can show it (no 2nd poller).
            branchBridge = store.$branch.sink { [weak session] in session?.gitBranch = $0 }
        }
        showSidebarContent()
    }

    private func showSidebarContent() {
        fileActionsBar?.isHidden = sidebarMode != .files   // tree actions only apply to the Files tree
        guard let treeVC, let changesVC, let searchVC, let store else { return }
        let panes: [(SidebarMode, NSViewController)] = [(.files, treeVC), (.changes, changesVC), (.search, searchVC)]
        for (mode, vc) in panes where mode != sidebarMode && vc.isViewLoaded { vc.view.removeFromSuperview() }
        let show = panes.first { $0.0 == sidebarMode }!.1
        if show.view.superview == nil {
            show.view.translatesAutoresizingMaskIntoConstraints = false
            filesContainer.addSubview(show.view)
            NSLayoutConstraint.activate([
                show.view.topAnchor.constraint(equalTo: filesContainer.topAnchor),
                show.view.bottomAnchor.constraint(equalTo: filesContainer.bottomAnchor),
                show.view.leadingAnchor.constraint(equalTo: filesContainer.leadingAnchor),
                show.view.trailingAnchor.constraint(equalTo: filesContainer.trailingAnchor),
            ])
        }
        // One shared watcher + git poll; fetch only what the visible mode needs (Search needs neither).
        store.start(tree: sidebarMode == .files, changes: sidebarMode == .changes)
        if sidebarMode == .files { lastRevealedPath = nil; revealActiveFile() }   // entering Files → reveal current file
        if sidebarMode == .search { DispatchQueue.main.async { [weak self] in self?.searchVC?.focusField() } }
    }

    private func showSidebarEmpty() {
        guard sidebarEmptyView == nil else { return }
        let label = NSTextField(labelWithString: "No project open")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabelColor
        label.alignment = .center

        let btn = PointerButton()
        btn.title = "Open Folder…"
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

    private func teardownSidebarVCs() {
        store?.stop(); store = nil
        treeVC?.view.removeFromSuperview(); treeVC?.removeFromParent(); treeVC = nil
        changesVC?.view.removeFromSuperview(); changesVC?.removeFromParent(); changesVC = nil
        // Search may never have been shown — only touch its view if it was actually loaded.
        if let sv = searchVC { if sv.isViewLoaded { sv.view.removeFromSuperview() }; sv.removeFromParent() }
        searchVC = nil
    }

    /// A search hit was clicked → open that file in the active session and jump to its line.
    private func openSearchResult(_ rel: String, _ line: Int) {
        FileNavigator.openAt?(rel, line)
    }

    /// Reveal the Search segment and focus its field (⌘⇧F / "Find in Files…").
    func revealSearch() {
        filesModeSeg.selectedSegment = SidebarMode.search.rawValue
        filesModeChanged()          // shows the search pane; showSidebarContent focuses the field
    }

    /// Debug harness: select a sidebar segment (0 Files / 1 Changes / 2 Search) as if clicked.
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

/// Flipped clip view so the stack lays out top-down inside a scroll view.
final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}
