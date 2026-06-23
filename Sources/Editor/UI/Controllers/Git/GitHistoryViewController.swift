import AppKit

/// A bottom panel showing git commit history for the active repo. Looks like VS Code's Timeline —
/// a table with hash, message, author, and relative date. Click a commit to see its changed files.
final class GitHistoryViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let repo: String
    private var entries: [Git.LogEntry] = []
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private var onSelectCommit: ((Git.LogEntry) -> Void)?

    init(repo: String, onSelectCommit: ((Git.LogEntry) -> Void)? = nil) {
        self.repo = repo
        self.onSelectCommit = onSelectCommit
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(white: 0.10, alpha: 1).cgColor

        // Header
        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 8
        header.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        header.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "GIT HISTORY")
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        let refreshBtn = PointerButton()
        refreshBtn.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        refreshBtn.isBordered = false
        refreshBtn.contentTintColor = .secondaryLabelColor
        refreshBtn.target = self
        refreshBtn.action = #selector(refresh)
        refreshBtn.toolTip = "Refresh"
        refreshBtn.focusRingType = .none

        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(NSView()) // spacer
        header.addArrangedSubview(refreshBtn)

        // Table
        let hashCol = NSTableColumn(identifier: .init("hash"))
        hashCol.title = "Hash"; hashCol.width = 70; hashCol.minWidth = 50
        let msgCol = NSTableColumn(identifier: .init("message"))
        msgCol.title = "Message"; msgCol.width = 300; msgCol.minWidth = 100
        let authorCol = NSTableColumn(identifier: .init("author"))
        authorCol.title = "Author"; authorCol.width = 120; authorCol.minWidth = 60
        let dateCol = NSTableColumn(identifier: .init("date"))
        dateCol.title = "Date"; dateCol.width = 100; dateCol.minWidth = 60

        table.addTableColumn(hashCol)
        table.addTableColumn(msgCol)
        table.addTableColumn(authorCol)
        table.addTableColumn(dateCol)
        table.headerView = nil
        table.backgroundColor = NSColor(white: 0.10, alpha: 1)
        table.rowHeight = 22
        table.intercellSpacing = NSSize(width: 8, height: 0)
        table.selectionHighlightStyle = .regular
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        table.gridStyleMask = []

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(white: 0.10, alpha: 1)
        scroll.translatesAutoresizingMaskIntoConstraints = false

        // Divider at top
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(white: 0.20, alpha: 1).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(divider)
        root.addSubview(header)
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
            header.topAnchor.constraint(equalTo: divider.bottomAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadHistory()
    }

    @objc private func refresh() { loadHistory() }

    private func loadHistory() {
        let repo = self.repo
        DispatchQueue.global().async { [weak self] in
            let log = Git.log(repo)
            DispatchQueue.main.async {
                guard let self else { return }
                self.entries = log
                self.table.reloadData()
            }
        }
    }

    @objc private func rowClicked() {
        let row = table.clickedRow
        guard row >= 0, row < entries.count else { return }
        onSelectCommit?(entries[row])
    }

    // MARK: - DataSource

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    // MARK: - Delegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < entries.count else { return nil }
        let entry = entries[row]
        let id = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? {
            let c = NSTableCellView()
            c.identifier = id
            let tf = NSTextField(labelWithString: "")
            tf.font = AppFont.mono(size: 12)
            tf.lineBreakMode = .byTruncatingTail
            tf.translatesAutoresizingMaskIntoConstraints = false
            c.addSubview(tf)
            c.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: c.leadingAnchor),
                tf.trailingAnchor.constraint(equalTo: c.trailingAnchor),
                tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()

        switch tableColumn?.identifier.rawValue {
        case "hash":
            cell.textField?.stringValue = entry.hash
            cell.textField?.textColor = NSColor(srgbRed: 0.45, green: 0.62, blue: 0.96, alpha: 1)
        case "message":
            cell.textField?.stringValue = entry.message
            cell.textField?.textColor = Theme.textSecondary
        case "author":
            cell.textField?.stringValue = entry.author
            cell.textField?.textColor = Theme.textMuted
        case "date":
            cell.textField?.stringValue = entry.date
            cell.textField?.textColor = Theme.textDim
        default: break
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return GitHistoryRowView()
    }
}

/// Custom row view with subtle selection (no blue).
private final class GitHistoryRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { false }
        set {}
    }
    override func drawSelection(in dirtyRect: NSRect) {
        Theme.activeRowBg.setFill()
        bounds.fill()
    }
}
