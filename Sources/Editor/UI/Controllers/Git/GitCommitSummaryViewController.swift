import AppKit

final class GitCommitSummaryViewController: NSViewController, NSTableViewDataSource,
  NSTableViewDelegate
{
  private let repo: String
  private let commitHash: String
  private var summary: Git.CommitSummary?
  private var loaded = false

  private let tableView = NSTableView()
  private let scrollView = NSScrollView()
  private let loadingIndicator = NSTextField(labelWithString: "Loading commit summary...")

  private enum RowType {
    case header
    case sectionTitle
    case file(Git.FileStat)
  }
  private var rows: [RowType] = []

  init(repo: String, commitHash: String) {
    self.repo = repo
    self.commitHash = commitHash
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true
    root.layer?.backgroundColor = NSColor(white: 0.118, alpha: 1).cgColor

    tableView.headerView = nil
    tableView.backgroundColor = .clear
    tableView.intercellSpacing = .zero
    tableView.gridStyleMask = []
    tableView.selectionHighlightStyle = .regular
    tableView.dataSource = self
    tableView.delegate = self
    tableView.target = self
    tableView.doubleAction = #selector(rowDoubleClicked)

    let col = NSTableColumn(identifier: .init("summary"))
    col.resizingMask = .autoresizingMask
    tableView.addTableColumn(col)

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    loadingIndicator.font = .systemFont(ofSize: 12)
    loadingIndicator.textColor = Theme.textDim
    loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(scrollView)
    root.addSubview(loadingIndicator)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: root.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),

      loadingIndicator.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      loadingIndicator.centerYAnchor.constraint(equalTo: root.centerYAnchor),
    ])

    self.view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    load()
  }

  private func load() {
    let repo = self.repo
    let hash = self.commitHash
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let sum = Git.commitSummary(repo, hash: hash)
      DispatchQueue.main.async {
        guard let self else { return }
        self.summary = sum
        self.loadingIndicator.isHidden = true
        self.loaded = true
        self.rebuildRows()
      }
    }
  }

  private func rebuildRows() {
    guard let summary = summary else { return }
    var newRows: [RowType] = [.header, .sectionTitle]
    for file in summary.files {
      newRows.append(.file(file))
    }
    self.rows = newRows
    tableView.reloadData()
  }

  @objc private func rowDoubleClicked() {
    let row = tableView.clickedRow
    guard row >= 0, row < rows.count else { return }
    if case .file(let stat) = rows[row] {
      DiffNavigator.revealDiff?(stat.path, commitHash)
    }
  }

  // MARK: - Data Source & Delegate

  func numberOfRows(in tableView: NSTableView) -> Int {
    return rows.count
  }

  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    guard row < rows.count else { return 0 }
    switch rows[row] {
    case .header:
      // Measure size needed for the multiline commit message
      guard let summary = summary else { return 120 }
      let width = tableView.bounds.width > 0 ? tableView.bounds.width - 40 : 600
      let msgHeight = summary.message.boundingRect(
        with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: [.font: NSFont.systemFont(ofSize: 13)]
      ).height
      return max(130, 80 + msgHeight)
    case .sectionTitle:
      return 36
    case .file:
      return 26
    }
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard row < rows.count else { return nil }
    switch rows[row] {
    case .header:
      guard let summary = summary else { return nil }
      return CommitHeaderCardView(summary: summary)
    case .sectionTitle:
      guard let summary = summary else { return nil }
      let label = NSTextField(labelWithString: "CHANGED FILES (\(summary.files.count))")
      label.font = .systemFont(ofSize: 11, weight: .bold)
      label.textColor = Theme.textDim
      let stack = NSStackView(views: [label])
      stack.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 4, right: 20)
      return stack
    case .file(let stat):
      return FileStatRowView(stat: stat)
    }
  }
}

// MARK: - CommitHeaderCardView

private final class CommitHeaderCardView: NSView {
  private let summary: Git.CommitSummary

  init(summary: Git.CommitSummary) {
    self.summary = summary
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
    layer?.cornerRadius = 6
    layer?.borderWidth = 1
    layer?.borderColor = NSColor(white: 0.22, alpha: 1).cgColor

    let hashLabel = NSTextField(labelWithString: "commit \(summary.hash)")
    hashLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
    hashLabel.textColor = Theme.textSecondary

    let copyBtn = PointerButton()
    copyBtn.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
    copyBtn.bezelStyle = .inline
    copyBtn.isBordered = false
    copyBtn.controlSize = .small
    copyBtn.toolTip = "Copy full hash"
    copyBtn.target = self
    copyBtn.action = #selector(copyHashTapped)
    copyBtn.widthAnchor.constraint(equalToConstant: 20).isActive = true
    copyBtn.heightAnchor.constraint(equalToConstant: 20).isActive = true

    let hashStack = NSStackView(views: [copyBtn, hashLabel])
    hashStack.orientation = .horizontal
    hashStack.spacing = 6

    let authorLabel = NSTextField(
      labelWithString: "Author: \(summary.authorName) <\(summary.authorEmail)>")
    authorLabel.font = .systemFont(ofSize: 12)
    authorLabel.textColor = Theme.textDim

    let dateLabel = NSTextField(labelWithString: "Date:   \(summary.date)")
    dateLabel.font = .systemFont(ofSize: 12)
    dateLabel.textColor = Theme.textDim

    let messageField = NSTextField(labelWithString: summary.message)
    messageField.font = .systemFont(ofSize: 13)
    messageField.textColor = Theme.textPrimary
    messageField.isSelectable = true
    messageField.cell?.wraps = true

    let contentStack = NSStackView(views: [hashStack, authorLabel, dateLabel, messageField])
    contentStack.orientation = .vertical
    contentStack.alignment = .leading
    contentStack.spacing = 6
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(contentStack)

    NSLayoutConstraint.activate([
      contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
      contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
      contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  @objc private func copyHashTapped() {
    Clipboard.copy(summary.hash)
  }
}

// MARK: - FileStatRowView

private final class FileStatRowView: NSView {
  init(stat: Git.FileStat) {
    super.init(frame: .zero)
    wantsLayer = true

    let icon = NSImageView()
    icon.image = FileIcon.icon(forFilename: (stat.path as NSString).lastPathComponent, size: 12)
    icon.translatesAutoresizingMaskIntoConstraints = false
    icon.widthAnchor.constraint(equalToConstant: 14).isActive = true
    icon.heightAnchor.constraint(equalToConstant: 14).isActive = true

    let pathLabel = NSTextField(labelWithString: stat.path)
    pathLabel.font = .systemFont(ofSize: 12)
    pathLabel.textColor = Theme.textPrimary
    pathLabel.lineBreakMode = .byTruncatingMiddle

    let addLabel = NSTextField(labelWithString: "+\(stat.additions)")
    addLabel.font = .systemFont(ofSize: 11, weight: .bold)
    addLabel.textColor = Theme.gitNew
    addLabel.isHidden = stat.additions == 0

    let delLabel = NSTextField(labelWithString: "-\(stat.deletions)")
    delLabel.font = .systemFont(ofSize: 11, weight: .bold)
    delLabel.textColor = Theme.gitDeleted
    delLabel.isHidden = stat.deletions == 0

    let stack = NSStackView(views: [icon, pathLabel, NSView(), addLabel, delLabel])
    stack.orientation = .horizontal
    stack.spacing = 6
    stack.alignment = .centerY
    stack.edgeInsets = NSEdgeInsets(top: 2, left: 20, bottom: 2, right: 20)
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)

    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }
}
