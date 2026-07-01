import AppKit

/// Lets project-search results (which live in the sidebar / a search tab, away from the editors) ask the
/// workspace to open a file at a line. Same static-hook pattern as `ActiveEditor` / `CommandPaletteHook`.
enum FileNavigator {
  static var openAt: ((_ relPath: String, _ line: Int) -> Void)?
}

/// Reveal the right sidebar's Search section (select the segment + focus the field). Driven by ⌘⇧F and the
/// "Find in Files…" palette command — VS Code-style, the shortcut takes you to the search section, and a
/// button there promotes it to a tab.
enum SidebarSearchHook {
  static var reveal: (() -> Void)?
}

/// Hands a query + toggle state to the next standalone search tab that opens, so "Open as Tab" carries the
/// sidebar's current search over. Consumed by `CenterViewController.render` when the search tab is active.
enum SearchSeed {
  static var pending: (query: String, options: ProjectSearch.Options)?
}

/// VS Code-style project search: a query field with Match-Case / Whole-Word / Regex toggles over a results
/// tree (file → matching lines, matches highlighted). Scoped to one repo (the active session's). Reused by
/// the right sidebar's "Search" segment and (later) a standalone search tab. Runs `git grep` (via
/// `ProjectSearch`) debounced + off-main, so it costs nothing until you type.
final class SearchViewController: NSViewController, NSSearchFieldDelegate, NSOutlineViewDataSource,
  NSOutlineViewDelegate
{
  /// The sidebar instance, exposed for static access (e.g. sidebar reveal hooks).
  static weak var current: SearchViewController?

  private let repo: String
  private let fff: FffInstance?
  private let isPrimary: Bool
  private let onOpen: (String, Int) -> Void
  private var options = ProjectSearch.Options()

  // Result model — classes so the outline view has stable item identity across reloads.
  private final class FileNode {
    let file: String
    let matches: [MatchNode]
    init(_ f: String, _ m: [MatchNode]) {
      file = f
      matches = m
    }
  }
  private final class MatchNode {
    let file: String
    let line: Int
    let preview: String
    init(_ f: String, _ l: Int, _ p: String) {
      file = f
      line = l
      preview = p
    }
  }

  private var nodes: [FileNode] = []
  private var failed = false
  private var highlightRegex: NSRegularExpression?

  private let field = NSSearchField()
  private let replaceField = NSSearchField()
  private let replaceToggleBtn = PointerButton()
  private let replaceAllBtn = PointerButton()
  private let caseBtn = PointerButton()
  private let wordBtn = PointerButton()
  private let regexBtn = PointerButton()
  private let openAsTabBtn = PointerButton()
  private let summary = NSTextField(labelWithString: "")
  private let outline = SearchOutlineView()
  private let scroll = NSScrollView()
  private let replaceBar = NSView()  // container for replaceField + Replace All button (hidden by default)

  /// Sidebar-only: promote the current search to a standalone tab (carrying query + toggles).
  var onOpenAsTab: ((String, ProjectSearch.Options) -> Void)?

  private var runToken = 0
  private var debounce: DispatchWorkItem?

  init(
    repo: String, fff: FffInstance?, isPrimary: Bool = true, onOpen: @escaping (String, Int) -> Void
  ) {
    self.repo = repo
    self.fff = fff
    self.isPrimary = isPrimary
    self.onOpen = onOpen
    super.init(nibName: nil, bundle: nil)
    if isPrimary {
      SearchViewController.current = self
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  deinit {
    if SearchViewController.current === self { SearchViewController.current = nil }
  }

  // MARK: - View

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true
    root.layer?.backgroundColor = NSColor(white: 0.145, alpha: 1).cgColor  // match the Files pane

    field.placeholderString = "Search"
    field.font = .systemFont(ofSize: 12)
    field.focusRingType = .none
    field.delegate = self
    field.sendsWholeSearchString = false
    field.sendsSearchStringImmediately = false
    field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    field.translatesAutoresizingMaskIntoConstraints = false

    // Replace toggle (chevron) — shows/hides the replace field.
    replaceToggleBtn.image = NSImage(
      systemSymbolName: "chevron.right", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
    replaceToggleBtn.isBordered = false
    replaceToggleBtn.contentTintColor = NSColor(white: 0.6, alpha: 1)
    replaceToggleBtn.toolTip = "Toggle replace"
    replaceToggleBtn.target = self
    replaceToggleBtn.action = #selector(toggleReplace)
    replaceToggleBtn.setContentHuggingPriority(.required, for: .horizontal)
    replaceToggleBtn.translatesAutoresizingMaskIntoConstraints = false

    openAsTabBtn.image = NSImage(
      systemSymbolName: "arrow.up.right.square", accessibilityDescription: "Open as tab")?
      .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
    openAsTabBtn.imagePosition = .imageOnly
    openAsTabBtn.isBordered = false
    openAsTabBtn.contentTintColor = NSColor(white: 0.7, alpha: 1)
    openAsTabBtn.toolTip = "Open search in a tab"
    openAsTabBtn.target = self
    openAsTabBtn.action = #selector(openAsTabTapped)
    openAsTabBtn.setContentHuggingPriority(.required, for: .horizontal)
    openAsTabBtn.isHidden = !isPrimary  // only the sidebar instance promotes to a tab
    openAsTabBtn.translatesAutoresizingMaskIntoConstraints = false

    let fieldRow = NSStackView(views: [replaceToggleBtn, field, openAsTabBtn])
    fieldRow.orientation = .horizontal
    fieldRow.spacing = 6
    fieldRow.alignment = .centerY
    fieldRow.translatesAutoresizingMaskIntoConstraints = false

    // Replace field + Replace All button (hidden by default).
    replaceField.placeholderString = "Replace"
    replaceField.font = .systemFont(ofSize: 12)
    replaceField.focusRingType = .none
    replaceField.sendsWholeSearchString = false
    replaceField.sendsSearchStringImmediately = false
    replaceField.setContentHuggingPriority(.defaultLow, for: .horizontal)
    replaceField.translatesAutoresizingMaskIntoConstraints = false

    replaceAllBtn.title = "Replace All"
    replaceAllBtn.bezelStyle = .rounded
    replaceAllBtn.font = .systemFont(ofSize: 11)
    replaceAllBtn.toolTip = "Replace all matches in all files"
    replaceAllBtn.target = self
    replaceAllBtn.action = #selector(replaceAllTapped)
    replaceAllBtn.setContentHuggingPriority(.required, for: .horizontal)
    replaceAllBtn.translatesAutoresizingMaskIntoConstraints = false

    let replaceRow = NSStackView(views: [replaceField, replaceAllBtn])
    replaceRow.orientation = .horizontal
    replaceRow.spacing = 6
    replaceRow.alignment = .centerY
    replaceRow.translatesAutoresizingMaskIntoConstraints = false

    replaceBar.addSubview(replaceRow)
    replaceBar.translatesAutoresizingMaskIntoConstraints = false
    replaceBar.isHidden = true  // hidden by default

    configToggle(caseBtn, "Aa", "Match Case")
    configToggle(wordBtn, "ab", "Whole Word")
    configToggle(regexBtn, ".*", "Regular Expression")
    let toggles = NSStackView(views: [caseBtn, wordBtn, regexBtn])
    toggles.orientation = .horizontal
    toggles.spacing = 4
    toggles.translatesAutoresizingMaskIntoConstraints = false

    summary.font = .systemFont(ofSize: 11)
    summary.textColor = NSColor(white: 0.55, alpha: 1)
    summary.lineBreakMode = .byTruncatingTail
    summary.translatesAutoresizingMaskIntoConstraints = false
    summary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
    col.resizingMask = .autoresizingMask
    outline.addTableColumn(col)
    outline.outlineTableColumn = col
    outline.headerView = nil
    outline.backgroundColor = .clear
    outline.indentationPerLevel = 0  // match rows align flush, not nested under the file
    outline.rowSizeStyle = .custom
    outline.gridStyleMask = []
    outline.selectionHighlightStyle = .regular
    outline.autoresizesOutlineColumn = false
    outline.dataSource = self
    outline.delegate = self
    outline.target = self
    outline.doubleAction = #selector(rowDoubleClicked)

    scroll.documentView = outline
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    scroll.translatesAutoresizingMaskIntoConstraints = false

    root.addSubview(fieldRow)
    root.addSubview(replaceBar)
    root.addSubview(summary)
    root.addSubview(toggles)
    root.addSubview(scroll)
    NSLayoutConstraint.activate([
      fieldRow.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
      fieldRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
      fieldRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),

      replaceBar.topAnchor.constraint(equalTo: fieldRow.bottomAnchor, constant: 4),
      replaceBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
      replaceBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
      replaceRow.topAnchor.constraint(equalTo: replaceBar.topAnchor),
      replaceRow.bottomAnchor.constraint(equalTo: replaceBar.bottomAnchor),
      replaceRow.leadingAnchor.constraint(equalTo: replaceBar.leadingAnchor),
      replaceRow.trailingAnchor.constraint(equalTo: replaceBar.trailingAnchor),

      toggles.topAnchor.constraint(equalTo: replaceBar.bottomAnchor, constant: 6),
      toggles.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
      summary.centerYAnchor.constraint(equalTo: toggles.centerYAnchor),
      summary.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
      summary.trailingAnchor.constraint(lessThanOrEqualTo: toggles.leadingAnchor, constant: -8),

      scroll.topAnchor.constraint(equalTo: toggles.bottomAnchor, constant: 6),
      scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
    self.view = root
    updateSummary()
  }

  /// Focus the field — called when the sidebar reveals the Search segment.
  func focusField() { view.window?.makeFirstResponder(field) }

  private func configToggle(_ b: NSButton, _ title: String, _ tip: String) {
    b.title = title
    b.bezelStyle = .recessed
    b.setButtonType(.pushOnPushOff)
    b.showsBorderOnlyWhileMouseInside = false
    b.state = .off
    b.toolTip = tip
    b.font = .systemFont(ofSize: 11, weight: .semibold)
    b.target = self
    b.action = #selector(toggleChanged)
    b.setContentHuggingPriority(.required, for: .horizontal)
    b.translatesAutoresizingMaskIntoConstraints = false
    b.widthAnchor.constraint(equalToConstant: 26).isActive = true
  }

  // MARK: - Searching

  @objc private func toggleChanged() {
    options = ProjectSearch.Options(
      matchCase: caseBtn.state == .on,
      wholeWord: wordBtn.state == .on,
      regex: regexBtn.state == .on)
    runSearch(debounced: false)
  }

  @objc private func openAsTabTapped() { onOpenAsTab?(field.stringValue, options) }

  @objc private func toggleReplace() {
    replaceBar.isHidden.toggle()
    let chevronName = replaceBar.isHidden ? "chevron.right" : "chevron.down"
    replaceToggleBtn.image = NSImage(
      systemSymbolName: chevronName, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
    if !replaceBar.isHidden {
      view.window?.makeFirstResponder(replaceField)
    }
  }

  @objc private func replaceAllTapped() {
    let q = field.stringValue
    guard !q.isEmpty, !nodes.isEmpty else { return }
    let replacement = replaceField.stringValue

    // Confirm before modifying files.
    let matchCount = nodes.reduce(0) { $0 + $1.matches.count }
    let alert = NSAlert()
    alert.messageText = "Replace all?"
    alert.informativeText =
      "Replace \(matchCount) match\(matchCount == 1 ? "" : "es") in \(nodes.count) file\(nodes.count == 1 ? "" : "s") with \"\(replacement)\"?"
    alert.addButton(withTitle: "Replace All")
    alert.addButton(withTitle: "Cancel")
    alert.alertStyle = .warning
    guard alert.runModal() == .alertFirstButtonReturn else { return }

    // Run the replace off-main, then re-search to refresh results.
    let opts = options
    let repo = self.repo
    let fileHits = nodes.map { ProjectSearch.FileHits(file: $0.file, matches: []) }
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let changed = ProjectSearch.replaceAll(
        q, with: replacement, in: repo, options: opts, files: fileHits)
      DispatchQueue.main.async {
        guard let self else { return }
        if changed > 0 {
          // Notify any open diff views that file content changed on disk.
          NotificationCenter.default.post(name: .editorFileTextDidChange, object: nil)
          // Re-run the search to refresh results (matches may have changed).
          self.runSearch(debounced: false)
        }
      }
    }
  }

  /// Apply a query + toggle state and search — used to seed a standalone tab from the sidebar's "Open as Tab".
  func seed(_ query: String, _ options: ProjectSearch.Options) {
    self.options = options
    caseBtn.state = options.matchCase ? .on : .off
    wordBtn.state = options.wholeWord ? .on : .off
    regexBtn.state = options.regex ? .on : .off
    field.stringValue = query
    runSearch(debounced: false)
  }

  private func runSearch(debounced: Bool) {
    debounce?.cancel()
    let q = field.stringValue
    if q.isEmpty {  // clear immediately, no subprocess
      runToken += 1
      nodes = []
      failed = false
      highlightRegex = nil
      reloadResults()
      return
    }
    let work: () -> Void = { [weak self] in self?.performSearch(q) }
    if debounced {
      let item = DispatchWorkItem(block: work)
      debounce = item
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: item)
    } else {
      work()
    }
  }

  private func performSearch(_ q: String) {
    runToken += 1
    let token = runToken
    let opts = options
    let repo = self.repo
    let fff = self.fff
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result = ProjectSearch.run(q, in: repo, fff: fff, options: opts)
      DispatchQueue.main.async {
        guard let self, token == self.runToken else { return }  // a newer query superseded this one
        self.applyResult(result, query: q)
      }
    }
  }

  private func applyResult(_ result: ProjectSearch.Result, query: String) {
    highlightRegex = buildHighlightRegex(query)
    nodes = result.files.map { fh in
      FileNode(fh.file, fh.matches.map { MatchNode(fh.file, $0.line, $0.preview) })
    }
    failed = result.failed
    reloadResults()
  }

  private func buildHighlightRegex(_ query: String) -> NSRegularExpression? {
    guard !query.isEmpty else { return nil }
    var pattern = options.regex ? query : NSRegularExpression.escapedPattern(for: query)
    if options.wholeWord { pattern = "\\b" + pattern + "\\b" }
    let opts: NSRegularExpression.Options = options.matchCase ? [] : [.caseInsensitive]
    return try? NSRegularExpression(pattern: pattern, options: opts)
  }

  private func reloadResults() {
    outline.reloadData()
    outline.expandItem(nil, expandChildren: true)  // every file's matches expanded by default
    for n in nodes { outline.reloadItem(n) }  // refresh chevrons now expansion state is settled
    updateSummary()
  }

  private func updateSummary() {
    if failed {
      // A non-regex search only errors when grep can't run (e.g. not a git repo) — don't cry "invalid".
      summary.stringValue = options.regex ? "Invalid pattern" : "No results"
      summary.textColor =
        options.regex
        ? NSColor(red: 1, green: 0.45, blue: 0.45, alpha: 1)
        : NSColor(white: 0.55, alpha: 1)
      return
    }
    summary.textColor = NSColor(white: 0.55, alpha: 1)
    if field.stringValue.isEmpty {
      summary.stringValue = ""
      return
    }
    let m = nodes.reduce(0) { $0 + $1.matches.count }
    if m == 0 {
      summary.stringValue = "No results"
    } else {
      let f = nodes.count
      summary.stringValue = "\(m) result\(m == 1 ? "" : "s") in \(f) file\(f == 1 ? "" : "s")"
    }
  }

  // MARK: - Field events

  func controlTextDidChange(_ obj: Notification) { /* No real-time search - only search on Enter */
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
    if sel == #selector(NSResponder.insertNewline(_:)) {
      runSearch(debounced: false)
      return true
    }
    return false
  }

  // MARK: - Clicks

  @objc private func rowDoubleClicked() {
    let row = outline.clickedRow
    guard row >= 0, let item = outline.item(atRow: row) else { return }
    if let m = item as? MatchNode {
      onOpen(m.file, m.line)
    } else if let f = item as? FileNode {  // double click a file header → toggle its matches
      if outline.isItemExpanded(f) { outline.collapseItem(f) } else { outline.expandItem(f) }
      outline.reloadItem(f)  // refresh the chevron direction
    }
  }

  // MARK: - NSOutlineView data source

  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    if item == nil { return nodes.count }
    return (item as? FileNode)?.matches.count ?? 0
  }
  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    if item == nil { return nodes[index] }
    return (item as! FileNode).matches[index]
  }
  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    item is FileNode
  }

  // MARK: - NSOutlineView delegate

  func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
    item is FileNode ? 26 : 22
  }

  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any)
    -> NSView?
  {
    if let f = item as? FileNode {
      let id = NSUserInterfaceItemIdentifier("fileCell")
      let cell =
        (outlineView.makeView(withIdentifier: id, owner: self) as? SearchFileCell)
        ?? {
          let c = SearchFileCell()
          c.identifier = id
          return c
        }()
      cell.configure(file: f.file, count: f.matches.count, expanded: outlineView.isItemExpanded(f))
      return cell
    }
    let m = item as! MatchNode
    let id = NSUserInterfaceItemIdentifier("matchCell")
    let cell =
      (outlineView.makeView(withIdentifier: id, owner: self) as? SearchMatchCell)
      ?? {
        let c = SearchMatchCell()
        c.identifier = id
        return c
      }()
    cell.configure(line: m.line, preview: m.preview, highlight: highlightRegex)
    return cell
  }

  func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
    SearchRowView()
  }
}

/// Outline view with the system disclosure triangle hidden (`frameOfOutlineCell` → `.zero`) so every row's
/// content starts flush at the column's left edge — no reserved triangle column indenting the match rows.
/// The file cell draws its own chevron instead, and double clicking a file row toggles it (see `rowDoubleClicked`).
private final class SearchOutlineView: PointerOutlineView {
  override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }
}

// MARK: - Cells

/// A file header row: a disclosure chevron (its own, so we control the gap to the name), filename
/// (bright) + dim parent dir + a right-aligned match count.
private final class SearchFileCell: NSTableCellView {
  private let chevron = NSImageView()
  private let nameField = NSTextField(labelWithString: "")
  private let dirField = NSTextField(labelWithString: "")
  private let countField = NSTextField(labelWithString: "")

  override init(frame: NSRect) {
    super.init(frame: frame)
    chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
    chevron.contentTintColor = NSColor(white: 0.6, alpha: 1)
    chevron.setContentHuggingPriority(.required, for: .horizontal)
    nameField.font = .systemFont(ofSize: 12, weight: .medium)
    nameField.textColor = NSColor(white: 0.92, alpha: 1)
    nameField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    dirField.font = .systemFont(ofSize: 11)
    dirField.textColor = NSColor(white: 0.5, alpha: 1)
    dirField.lineBreakMode = .byTruncatingMiddle
    dirField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    countField.font = .systemFont(ofSize: 11)
    countField.textColor = NSColor(white: 0.55, alpha: 1)
    countField.alignment = .right
    countField.setContentHuggingPriority(.required, for: .horizontal)
    countField.setContentCompressionResistancePriority(.required, for: .horizontal)

    let stack = NSStackView(views: [chevron, nameField, dirField, NSView(), countField])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 6
    stack.setCustomSpacing(8, after: chevron)  // clear gap between the chevron and the name
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      chevron.widthAnchor.constraint(equalToConstant: 9),
    ])
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  func configure(file: String, count: Int, expanded: Bool) {
    chevron.image = NSImage(
      systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
    nameField.stringValue = (file as NSString).lastPathComponent
    let dir = (file as NSString).deletingLastPathComponent
    dirField.stringValue = dir
    dirField.isHidden = dir.isEmpty
    countField.stringValue = "\(count)"
  }
}

/// A single matching line: dim 1-based line number + the source line with matched ranges highlighted.
private final class SearchMatchCell: NSTableCellView {
  private let lineField = NSTextField(labelWithString: "")
  private let previewLabel = NSTextField(labelWithString: "")

  override init(frame: NSRect) {
    super.init(frame: frame)
    lineField.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    lineField.textColor = NSColor(white: 0.45, alpha: 1)
    lineField.alignment = .left  // flush-left so the match sits at the file row's left edge
    lineField.setContentHuggingPriority(.required, for: .horizontal)
    lineField.setContentCompressionResistancePriority(.required, for: .horizontal)
    previewLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    previewLabel.textColor = NSColor(white: 0.75, alpha: 1)
    previewLabel.lineBreakMode = .byTruncatingTail
    previewLabel.cell?.usesSingleLineMode = true

    let stack = NSStackView(views: [lineField, previewLabel])
    stack.orientation = .horizontal
    stack.alignment = .firstBaseline
    stack.spacing = 6  // tight gap: line number hugs, preview sits right after
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),  // flush with the file row's chevron
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  func configure(line: Int, preview: String, highlight: NSRegularExpression?) {
    lineField.stringValue = "\(line)"
    let s = NSMutableAttributedString(
      string: preview,
      attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor(white: 0.75, alpha: 1),
      ])
    if let rx = highlight {
      let full = NSRange(location: 0, length: (preview as NSString).length)
      for m in rx.matches(in: preview, options: [], range: full) where m.range.length > 0 {
        s.addAttributes(
          [
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.30),
          ],
          range: m.range)
      }
    }
    previewLabel.attributedStringValue = s
  }
}

/// Accent-tinted full-row selection (matches the command palette), forcing `.emphasized` so text stays
/// legible on the highlight even when the window isn't key (e.g. while the harness drives it).
private final class SearchRowView: NSTableRowView {
  override var interiorBackgroundStyle: NSView.BackgroundStyle {
    isSelected ? .emphasized : .normal
  }
  override func drawSelection(in dirtyRect: NSRect) {
    guard isSelected else { return }
    NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
    bounds.fill()
  }
}
