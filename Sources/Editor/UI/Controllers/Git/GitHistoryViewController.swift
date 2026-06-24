import AppKit
import Combine

/// Git commit history shown below the Changes list in the sidebar. Renders commit list inline.
/// Clicking a commit expands it to show the changed files directly underneath it.
final class GitHistoryViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  private let store: RepoStore
  private let onOpenDiff: (String, String?) -> Void
  private var cancellables = Set<AnyCancellable>()

  private let commitTable = NSTableView()
  private let commitScroll = NSScrollView()

  private enum RowItem {
    case commit(Git.LogEntry, isExpanded: Bool)
    case file(path: String, commitHash: String)
  }

  private var commits: [Git.LogEntry] = []
  private var expandedCommits = Set<String>()
  private var fileCache: [String: [String]] = [:]
  private var rows: [RowItem] = []

  private var batchSize = 50
  private var allLoaded = false

  init(store: RepoStore, onOpenDiff: @escaping (String, String?) -> Void) {
    self.store = store
    self.onOpenDiff = onOpenDiff
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func loadView() {
    // Header
    let header = NSTextField(labelWithString: "HISTORY")
    header.font = .systemFont(ofSize: 11, weight: .semibold)
    header.textColor = .secondaryLabelColor
    header.translatesAutoresizingMaskIntoConstraints = false

    // Commit table
    let col = NSTableColumn(identifier: .init("commit"))
    col.resizingMask = .autoresizingMask
    commitTable.addTableColumn(col)
    commitTable.headerView = nil
    commitTable.backgroundColor = Theme.sidebarBg
    commitTable.intercellSpacing = .zero
    commitTable.selectionHighlightStyle = .regular
    commitTable.dataSource = self
    commitTable.delegate = self
    commitTable.target = self
    commitTable.action = #selector(rowClicked)

    commitScroll.documentView = commitTable
    commitScroll.hasVerticalScroller = true
    commitScroll.drawsBackground = true
    commitScroll.backgroundColor = Theme.sidebarBg
    commitScroll.translatesAutoresizingMaskIntoConstraints = false

    let root = NSView()
    root.wantsLayer = true
    root.layer?.backgroundColor = Theme.sidebarBg.cgColor
    root.addSubview(header)
    root.addSubview(commitScroll)

    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
      header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
      commitScroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
      commitScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      commitScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      commitScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
    self.view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    // Progressive loading: detect when scrolled near the bottom
    NotificationCenter.default.addObserver(
      self, selector: #selector(scrolled),
      name: NSView.boundsDidChangeNotification, object: commitScroll.contentView)
    commitScroll.contentView.postsBoundsChangedNotifications = true

    store.$lastCommitHash
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.refresh(clearCache: false)
      }
      .store(in: &cancellables)
  }

  /// Called by the sidebar when the Changes tab becomes visible. Loads history if not yet loaded.
  func loadIfNeeded() {
    if commits.isEmpty { loadMore() }
  }

  // MARK: - Loading

  private func loadMore() {
    guard !allLoaded else { return }
    let repo = self.store.repo
    let offset = commits.count
    let batch = batchSize
    DispatchQueue.global().async { [weak self] in
      let log = Git.log(repo, limit: offset + batch)
      DispatchQueue.main.async {
        guard let self else { return }
        if log.count <= self.commits.count {
          self.allLoaded = true
          return
        }
        self.commits = log
        self.rebuildRows()
        if log.count < offset + batch { self.allLoaded = true }
      }
    }
  }

  func refresh(clearCache: Bool = false) {
    if clearCache {
      expandedCommits.removeAll()
      fileCache.removeAll()
    }
    commits = []
    allLoaded = false
    rebuildRows()
    loadMore()
  }

  private func rebuildRows() {
    var newRows: [RowItem] = []
    for commit in commits {
      let expanded = expandedCommits.contains(commit.fullHash)
      newRows.append(.commit(commit, isExpanded: expanded))
      if expanded {
        let files = fileCache[commit.fullHash] ?? []
        for file in files {
          newRows.append(.file(path: file, commitHash: commit.fullHash))
        }
      }
    }
    self.rows = newRows
    self.commitTable.reloadData()
  }

  @objc private func scrolled() {
    let clip = commitScroll.contentView
    let docH = commitScroll.documentView?.frame.height ?? 0
    let visibleBottom = clip.bounds.origin.y + clip.bounds.height
    if visibleBottom > docH - 100 { loadMore() }
  }

  @objc private func rowClicked() {
    let clickedRow = commitTable.clickedRow
    guard clickedRow >= 0, clickedRow < rows.count else { return }

    switch rows[clickedRow] {
    case .commit(let entry, let isExpanded):
      let hash = entry.fullHash
      if isExpanded {
        expandedCommits.remove(hash)
        rebuildRows()
      } else {
        expandedCommits.insert(hash)
        if fileCache[hash] == nil {
          let repo = self.store.repo
          DispatchQueue.global().async { [weak self] in
            let files = Git.commitFiles(repo, hash: hash)
            DispatchQueue.main.async {
              guard let self else { return }
              self.fileCache[hash] = files
              self.rebuildRows()
            }
          }
        } else {
          rebuildRows()
        }
      }
    case .file(let path, let commitHash):
      onOpenDiff(path, commitHash)
    }
  }

  // MARK: - DataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    rows.count
  }

  // MARK: - Delegate

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    guard row < rows.count else { return 24 }
    switch rows[row] {
    case .commit:
      return 38
    case .file:
      return 22
    }
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard row < rows.count else { return nil }
    switch rows[row] {
    case .commit(let entry, let isExpanded):
      return makeCommitCell(entry, isExpanded: isExpanded)
    case .file(let path, _):
      return makeFileCell(path)
    }
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    return HistoryRowView()
  }

  private func makeCommitCell(_ entry: Git.LogEntry, isExpanded: Bool) -> NSView {
    // Chevron icon
    let chevron = NSImageView()
    chevron.translatesAutoresizingMaskIntoConstraints = false
    chevron.imageScaling = .scaleProportionallyDown
    let chevronSymbol = isExpanded ? "chevron.down" : "chevron.right"
    let chevImg = NSImage(systemSymbolName: chevronSymbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 8, weight: .semibold))
    chevron.image = chevImg
    chevron.contentTintColor = Theme.textDim
    chevron.setContentHuggingPriority(.required, for: .horizontal)
    chevron.widthAnchor.constraint(equalToConstant: 10).isActive = true
    chevron.heightAnchor.constraint(equalToConstant: 10).isActive = true

    // Git commit icon
    let gitIcon = NSImageView()
    gitIcon.translatesAutoresizingMaskIntoConstraints = false
    gitIcon.imageScaling = .scaleProportionallyDown
    let gitImg = NSImage(systemSymbolName: "git.commit", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
    gitIcon.image = gitImg
    gitIcon.contentTintColor = NSColor(srgbRed: 0.45, green: 0.62, blue: 0.96, alpha: 1)
    gitIcon.setContentHuggingPriority(.required, for: .horizontal)
    gitIcon.widthAnchor.constraint(equalToConstant: 14).isActive = true
    gitIcon.heightAnchor.constraint(equalToConstant: 14).isActive = true

    // Text labels (vertical stack)
    let msg = NSTextField(labelWithString: entry.message)
    msg.font = .systemFont(ofSize: 12)
    msg.textColor = Theme.textPrimary
    msg.lineBreakMode = .byTruncatingTail

    let detail = NSTextField(labelWithString: "\(entry.hash)  \(entry.author)  \(entry.date)")
    detail.font = .systemFont(ofSize: 10)
    detail.textColor = Theme.textDim
    detail.lineBreakMode = .byTruncatingTail

    let textStack = NSStackView(views: [msg, detail])
    textStack.orientation = .vertical
    textStack.alignment = .leading
    textStack.spacing = 2

    // Main horizontal stack
    let mainStack = NSStackView(views: [chevron, gitIcon, textStack])
    mainStack.orientation = .horizontal
    mainStack.alignment = .centerY
    mainStack.spacing = 4
    mainStack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 10)
    return mainStack
  }

  private func makeFileCell(_ path: String) -> NSView {
    // Spacer for indentation
    let spacer = NSView()
    spacer.translatesAutoresizingMaskIntoConstraints = false
    spacer.widthAnchor.constraint(equalToConstant: 18).isActive = true

    // File icon
    let icon = NSImageView()
    icon.translatesAutoresizingMaskIntoConstraints = false
    icon.imageScaling = .scaleProportionallyDown
    icon.image = FileIcon.icon(forFilename: (path as NSString).lastPathComponent, size: 11)
    icon.contentTintColor = Theme.textMuted
    icon.setContentHuggingPriority(.required, for: .horizontal)
    icon.widthAnchor.constraint(equalToConstant: 14).isActive = true
    icon.heightAnchor.constraint(equalToConstant: 14).isActive = true

    // Label
    let label = NSTextField(labelWithString: path)
    label.font = .systemFont(ofSize: 11)
    label.textColor = Theme.textSecondary
    label.lineBreakMode = .byTruncatingMiddle

    // Horizontal stack
    let stack = NSStackView(views: [spacer, icon, label])
    stack.orientation = .horizontal
    stack.spacing = 5
    stack.alignment = .centerY
    stack.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 8)
    return stack
  }
}

/// Subtle selection row (no blue).
private final class HistoryRowView: NSTableRowView {
  override var isEmphasized: Bool {
    get { false }
    set {}
  }
  override func drawSelection(in dirtyRect: NSRect) {
    Theme.activeRowBg.setFill()
    bounds.fill()
  }
}
