import AppKit

/// Git commit history shown below the Changes list in the sidebar. A vertical split: commit list on
/// top, changed files for the selected commit below. Loads progressively (50 at a time, more on scroll).
final class GitHistoryViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let repo: String
    private var entries: [Git.LogEntry] = []
    private var selectedFiles: [String] = []
    private let onOpenDiff: (String) -> Void

    private let commitTable = NSTableView()
    private let commitScroll = NSScrollView()
    private let filesTable = NSTableView()
    private let filesScroll = NSScrollView()
    private let split = NSSplitView()

    private var batchSize = 50
    private var allLoaded = false

    init(repo: String, onOpenDiff: @escaping (String) -> Void) {
        self.repo = repo
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
        commitTable.rowHeight = 36
        commitTable.intercellSpacing = .zero
        commitTable.selectionHighlightStyle = .regular
        commitTable.dataSource = self
        commitTable.delegate = self
        commitTable.target = self
        commitTable.action = #selector(commitClicked)

        commitScroll.documentView = commitTable
        commitScroll.hasVerticalScroller = true
        commitScroll.drawsBackground = true
        commitScroll.backgroundColor = Theme.sidebarBg

        // Files table (shown when a commit is selected)
        let filesCol = NSTableColumn(identifier: .init("file"))
        filesCol.resizingMask = .autoresizingMask
        filesTable.addTableColumn(filesCol)
        filesTable.headerView = nil
        filesTable.backgroundColor = Theme.sidebarBg
        filesTable.rowHeight = 22
        filesTable.intercellSpacing = .zero
        filesTable.selectionHighlightStyle = .regular
        filesTable.dataSource = self
        filesTable.delegate = self
        filesTable.target = self
        filesTable.doubleAction = #selector(fileDoubleClicked)

        filesScroll.documentView = filesTable
        filesScroll.hasVerticalScroller = true
        filesScroll.drawsBackground = true
        filesScroll.backgroundColor = Theme.sidebarBg

        // Split: commits on top, files below
        split.isVertical = false
        split.dividerStyle = .thin
        split.addArrangedSubview(commitScroll)
        split.addArrangedSubview(filesScroll)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        split.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.sidebarBg.cgColor
        root.addSubview(header)
        root.addSubview(split)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            split.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            split.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadMore()

        // Progressive loading: detect when scrolled near the bottom
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification, object: commitScroll.contentView)
        commitScroll.contentView.postsBoundsChangedNotifications = true
    }

    // MARK: - Loading

    private func loadMore() {
        guard !allLoaded else { return }
        let repo = self.repo, offset = entries.count, batch = batchSize
        DispatchQueue.global().async { [weak self] in
            let log = Git.log(repo, limit: offset + batch)
            DispatchQueue.main.async {
                guard let self else { return }
                if log.count <= self.entries.count { self.allLoaded = true; return }
                self.entries = log
                self.commitTable.reloadData()
                if log.count < offset + batch { self.allLoaded = true }
            }
        }
    }

    func refresh() {
        entries = []
        allLoaded = false
        selectedFiles = []
        filesTable.reloadData()
        loadMore()
    }

    @objc private func scrolled() {
        let clip = commitScroll.contentView
        let docH = commitScroll.documentView?.frame.height ?? 0
        let visibleBottom = clip.bounds.origin.y + clip.bounds.height
        if visibleBottom > docH - 100 { loadMore() }
    }

    @objc private func commitClicked() {
        let row = commitTable.clickedRow
        guard row >= 0, row < entries.count else { return }
        let entry = entries[row]
        let repo = self.repo
        DispatchQueue.global().async { [weak self] in
            let files = Git.commitFiles(repo, hash: entry.fullHash)
            DispatchQueue.main.async {
                guard let self else { return }
                self.selectedFiles = files
                self.filesTable.reloadData()
            }
        }
    }

    @objc private func fileDoubleClicked() {
        let row = filesTable.clickedRow
        guard row >= 0, row < selectedFiles.count else { return }
        onOpenDiff(selectedFiles[row])
    }

    // MARK: - DataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === commitTable ? entries.count : selectedFiles.count
    }

    // MARK: - Delegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === commitTable {
            return makeCommitCell(row)
        } else {
            return makeFileCell(row)
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return HistoryRowView()
    }

    private func makeCommitCell(_ row: Int) -> NSView {
        guard row < entries.count else { return NSView() }
        let entry = entries[row]

        let msg = NSTextField(labelWithString: entry.message)
        msg.font = .systemFont(ofSize: 12)
        msg.textColor = Theme.textPrimary
        msg.lineBreakMode = .byTruncatingTail

        let detail = NSTextField(labelWithString: "\(entry.hash)  \(entry.author)  \(entry.date)")
        detail.font = .systemFont(ofSize: 10)
        detail.textColor = Theme.textDim
        detail.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [msg, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        return stack
    }

    private func makeFileCell(_ row: Int) -> NSView {
        guard row < selectedFiles.count else { return NSView() }
        let file = selectedFiles[row]

        let icon = NSImageView()
        icon.image = FileIcon.icon(forFilename: (file as NSString).lastPathComponent, size: 11)
        icon.contentTintColor = Theme.textMuted
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let label = NSTextField(labelWithString: file)
        label.font = .systemFont(ofSize: 11)
        label.textColor = Theme.textSecondary
        label.lineBreakMode = .byTruncatingMiddle

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 12, bottom: 2, right: 8)
        return stack
    }
}

/// Subtle selection row (no blue).
private final class HistoryRowView: NSTableRowView {
    override var isEmphasized: Bool { get { false } set {} }
    override func drawSelection(in dirtyRect: NSRect) {
        Theme.activeRowBg.setFill()
        bounds.fill()
    }
}
