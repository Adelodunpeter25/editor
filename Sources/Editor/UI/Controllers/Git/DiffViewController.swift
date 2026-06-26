import AppKit
import Defaults

extension Notification.Name {
  static let editorFileTextDidChange = Notification.Name("EditorFileTextDidChange")
}

enum DiffNavigator {
  static var revealDiff: ((_ path: String, _ commitHash: String?) -> Void)?
}

enum LiveFileText {
  static var current: ((_ absolutePath: String) -> String?)?
}

struct UnifiedLine {
  let oldNo: Int?
  let newNo: Int?
  let sign: String
  let text: String
  let bg: NSColor
  let fg: NSColor
}

/// Renders a file's diff, unified or split. Built from `computeDiff` rows. One row per line;
/// full-width row background carries add/del color. Split shows old | new columns.
final class DiffViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  let repo: String  // repo root
  let path: String  // repo-relative path
  let commitHash: String?
  private let onOpenFile: () -> Void

  private var rows: [DiffRow] = []
  private var unified: [UnifiedLine] = []
  private var split: Bool
  private var loaded = false
  private var reloadWork: DispatchWorkItem?
  private var loadSeq = 0
  private var highlighter: TreeSitterHighlighter?
  private var newSpans: [(NSRange, NSColor)] = []  // syntax spans for the new file content
  private var oldSpans: [(NSRange, NSColor)] = []  // syntax spans for the old file content
  private var newLineOffsets: [Int] = []  // char offset of each line start in the new text
  private var oldLineOffsets: [Int] = []  // char offset of each line start in the old text

  private let table = NSTableView()
  private let scroll = NSScrollView()
  private let emptyLabel = NSTextField(labelWithString: "No changes vs HEAD")
  private let seg: PointerSegmentedControl = {
    let s = PointerSegmentedControl()
    s.segmentCount = 2
    s.setLabel("Unified", forSegment: 0)
    s.setLabel("Split", forSegment: 1)
    s.trackingMode = .selectOne
    return s
  }()

  init(repo: String, path: String, commitHash: String? = nil, onOpenFile: @escaping () -> Void) {
    self.repo = repo
    self.path = path
    self.commitHash = commitHash
    self.onOpenFile = onOpenFile
    self.split = UserDefaults.standard[AppDefaults.diffSplit]
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true
    root.layer?.backgroundColor = NSColor(white: 0.118, alpha: 1).cgColor

    // Header: path + Unified/Split + open-to-edit.
    let pathLabel = NSTextField(labelWithString: path)
    pathLabel.font = .systemFont(ofSize: 12)
    pathLabel.textColor = NSColor(white: 0.8, alpha: 1)
    pathLabel.lineBreakMode = .byTruncatingMiddle

    seg.selectedSegment = split ? 1 : 0
    seg.target = self
    seg.action = #selector(toggleSplit)
    seg.segmentStyle = .rounded
    seg.controlSize = .small
    seg.toolTip = "Unified / Split view"

    let openBtn = PointerButton()
    openBtn.title = "Edit"
    openBtn.target = self
    openBtn.action = #selector(openTapped)
    openBtn.bezelStyle = .inline
    openBtn.controlSize = .small
    openBtn.toolTip = "Open file to edit"

    let header = NSStackView(views: [pathLabel, NSView(), seg, openBtn])
    header.orientation = .horizontal
    header.spacing = 8
    header.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
    header.translatesAutoresizingMaskIntoConstraints = false

    table.headerView = nil
    table.backgroundColor = NSColor(white: 0.118, alpha: 1)
    table.intercellSpacing = .zero
    table.gridStyleMask = []
    table.selectionHighlightStyle = .none
    table.rowHeight = 17
    table.dataSource = self
    table.delegate = self
    table.target = self
    table.doubleAction = #selector(openTapped)
    configureColumns()

    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.drawsBackground = true
    scroll.backgroundColor = NSColor(white: 0.118, alpha: 1)
    scroll.translatesAutoresizingMaskIntoConstraints = false

    emptyLabel.font = .systemFont(ofSize: 12)
    emptyLabel.textColor = NSColor(white: 0.45, alpha: 1)
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false
    emptyLabel.isHidden = true

    root.addSubview(header)
    root.addSubview(scroll)
    root.addSubview(emptyLabel)
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: root.topAnchor),
      header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
      emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
    ])
    self.view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    if commitHash == nil {
      NotificationCenter.default.addObserver(
        self, selector: #selector(editorFileTextDidChange(_:)),
        name: .editorFileTextDidChange, object: nil)
    }
    load()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func editorFileTextDidChange(_ note: Notification) {
    guard commitHash == nil,
      let changedPath = note.userInfo?["path"] as? String,
      changedPath == URL(fileURLWithPath: repo).appendingPathComponent(path).path
    else { return }
    reloadWork?.cancel()
    let text = note.userInfo?["text"] as? String
    let work = DispatchWorkItem { [weak self] in self?.load(liveNewText: text) }
    reloadWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
  }

  private func configureColumns() {
    for c in table.tableColumns { table.removeTableColumn(c) }
    if split {
      let old = NSTableColumn(identifier: .init("old"))
      old.width = 500
      old.minWidth = 120
      let new = NSTableColumn(identifier: .init("new"))
      new.width = 500
      new.minWidth = 120
      table.addTableColumn(old)
      table.addTableColumn(new)
    } else {
      let u = NSTableColumn(identifier: .init("u"))
      u.width = 1000
      u.minWidth = 200
      table.addTableColumn(u)
    }
  }

  private func load(liveNewText: String? = nil) {
    loadSeq += 1
    let seq = loadSeq
    let repo = self.repo
    let path = self.path
    let commitHash = self.commitHash
    let hl = TreeSitterHighlighter.forPath(path)
    Task { [weak self] in
      let v: (old: String, new: String)
      if let commitHash {
        v = Git.versions(repo, path, commitHash: commitHash)
      } else if let liveNewText {
        v = Git.workingTreeVersions(repo, path, liveNewText: liveNewText)
      } else {
        let absolute = URL(fileURLWithPath: repo).appendingPathComponent(path).path
        v = Git.workingTreeVersions(repo, path, liveNewText: LiveFileText.current?(absolute))
      }
      let rows = computeDiff(old: v.old, new: v.new)

      // tree-sitter parsing is async (actor); run both in parallel
      async let oSpansAsync = hl?.spans(for: v.old) ?? []
      async let nSpansAsync = hl?.spans(for: v.new) ?? []
      let oSpans = await oSpansAsync
      let nSpans = await nSpansAsync

      let oOffsets = Self.lineOffsets(v.old)
      let nOffsets = Self.lineOffsets(v.new)
      await MainActor.run { [weak self] in
        guard let self, seq == self.loadSeq else { return }
        self.highlighter = hl
        self.rows = rows
        self.unified = Self.flatten(rows)
        self.oldSpans = oSpans
        self.newSpans = nSpans
        self.oldLineOffsets = oOffsets
        self.newLineOffsets = nOffsets
        self.loaded = true
        self.emptyLabel.isHidden = !rows.isEmpty
        self.table.reloadData()
        self.table.layoutSubtreeIfNeeded()
        if self.view.window != nil && self.view.bounds.width > 0 {
          self.didScrollToFirstChange = true
          DispatchQueue.main.async { [weak self] in
            self?.scrollToFirstChange()
          }
        }
      }
    }
  }

  private var didScrollToFirstChange = false

  override func viewDidLayout() {
    super.viewDidLayout()
    if loaded && !didScrollToFirstChange && view.bounds.width > 0 {
      didScrollToFirstChange = true
      DispatchQueue.main.async { [weak self] in
        self?.scrollToFirstChange()
      }
    }
  }

  func forceScrollToFirstChange() {
    if loaded {
      scrollToFirstChange()
    }
  }

  /// Build line-start offsets (char index of each line's first character).
  private static func lineOffsets(_ text: String) -> [Int] {
    guard !text.isEmpty else { return [] }
    var offsets: [Int] = [0]
    var i = text.startIndex
    while i < text.endIndex {
      if text[i] == "\n" {
        let next = text.index(after: i)
        offsets.append(text.distance(from: text.startIndex, to: next))
      }
      i = text.index(after: i)
    }
    return offsets
  }

  /// Scroll to the first changed line so the user sees the diff immediately.
  private func scrollToFirstChange() {
    table.layoutSubtreeIfNeeded()
    let firstChangeRow: Int
    if split {
      firstChangeRow =
        rows.firstIndex(where: {
          if case .equal = $0 { return false }
          return true
        }) ?? 0
    } else {
      firstChangeRow = unified.firstIndex(where: { $0.sign != " " }) ?? 0
    }
    guard firstChangeRow >= 0, firstChangeRow < table.numberOfRows else { return }
    // Scroll a few lines above the change for context
    let targetRow = max(0, firstChangeRow - 3)
    let rowRect = table.rect(ofRow: targetRow)
    if rowRect.origin.y >= 0 {
      scroll.contentView.scroll(to: NSPoint(x: 0, y: rowRect.origin.y))
      scroll.reflectScrolledClipView(scroll.contentView)
    }
  }

  private static func flatten(_ rows: [DiffRow]) -> [UnifiedLine] {
    var out: [UnifiedLine] = []
    for row in rows {
      switch row {
      case .equal(let o, let n, let t):
        out.append(
          UnifiedLine(oldNo: o, newNo: n, sign: " ", text: t, bg: .clear, fg: DiffTheme.diffTextFg))
      case .del(let o, let t):
        out.append(
          UnifiedLine(
            oldNo: o, newNo: nil, sign: "-", text: t, bg: DiffTheme.delBg, fg: DiffTheme.delFg))
      case .ins(let n, let t):
        out.append(
          UnifiedLine(
            oldNo: nil, newNo: n, sign: "+", text: t, bg: DiffTheme.addBg, fg: DiffTheme.addFg))
      case .change(let o, let n, let ot, let nt):
        out.append(
          UnifiedLine(
            oldNo: o, newNo: nil, sign: "-", text: ot, bg: DiffTheme.delBg, fg: DiffTheme.delFg))
        out.append(
          UnifiedLine(
            oldNo: nil, newNo: n, sign: "+", text: nt, bg: DiffTheme.addBg, fg: DiffTheme.addFg))
      }
    }
    return out
  }

  @objc private func toggleSplit() {
    split = seg.selectedSegment == 1
    UserDefaults.standard[AppDefaults.diffSplit] = split
    configureColumns()
    table.reloadData()
  }

  @objc private func openTapped() { onOpenFile() }

  // MARK: Table

  func numberOfRows(in tableView: NSTableView) -> Int { split ? rows.count : unified.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let cell = DiffCellView()
    if split {
      guard row < rows.count else { return cell }
      let (old, new) = Self.sides(rows[row])
      let side = tableColumn?.identifier.rawValue == "old" ? old : new
      let isOld = tableColumn?.identifier.rawValue == "old"
      let lineNo = side.no.map { $0 - 1 }  // 0-based
      let highlighted = lineNo.flatMap { highlightedLine($0, isOld: isOld) }
      cell.configure(
        no: side.no, text: side.text, fg: side.fg, bg: side.bg, highlighted: highlighted)
    } else {
      guard row < unified.count else { return cell }
      let l = unified[row]
      let prefix = "\(gut(l.oldNo)) \(gut(l.newNo)) \(l.sign) "
      let isOld = l.newNo == nil
      let lineNo = (isOld ? l.oldNo : l.newNo).map { $0 - 1 }
      let highlighted = lineNo.flatMap { highlightedLine($0, isOld: isOld) }
      cell.configure(
        prefixedText: prefix, lineText: l.text, fg: l.fg, bg: l.bg, highlighted: highlighted)
    }
    return cell
  }

  /// Get syntax-highlighted attributed string for a line's text (0-based line index).
  private func highlightedLine(_ lineIndex: Int, isOld: Bool) -> [(
    offset: Int, length: Int, color: NSColor
  )]? {
    let offsets = isOld ? oldLineOffsets : newLineOffsets
    let spans = isOld ? oldSpans : newSpans
    guard !spans.isEmpty, lineIndex < offsets.count else { return nil }
    let lineStart = offsets[lineIndex]
    let lineEnd = (lineIndex + 1 < offsets.count) ? offsets[lineIndex + 1] : lineStart + 10000

    // Find spans that overlap this line and remap to line-local offsets
    var result: [(offset: Int, length: Int, color: NSColor)] = []
    for (range, color) in spans {
      let sEnd = range.location + range.length
      guard range.location < lineEnd, sEnd > lineStart else { continue }
      let localStart = max(0, range.location - lineStart)
      let localEnd = min(lineEnd - lineStart, sEnd - lineStart)
      let len = localEnd - localStart
      if len > 0 { result.append((localStart, len, color)) }
    }
    return result.isEmpty ? nil : result
  }

  private func gut(_ n: Int?) -> String {
    let s = n.map(String.init) ?? ""
    return String(repeating: " ", count: max(0, 4 - s.count)) + s
  }

  private static func sides(_ row: DiffRow) -> (
    old: (no: Int?, text: String, fg: NSColor, bg: NSColor),
    new: (no: Int?, text: String, fg: NSColor, bg: NSColor)
  ) {
    switch row {
    case .equal(let o, let n, let t):
      return ((o, t, DiffTheme.diffTextFg, .clear), (n, t, DiffTheme.diffTextFg, .clear))
    case .del(let o, let t):
      return ((o, t, DiffTheme.delFg, DiffTheme.delBg), (nil, "", DiffTheme.diffTextFg, .clear))
    case .ins(let n, let t):
      return ((nil, "", DiffTheme.diffTextFg, .clear), (n, t, DiffTheme.addFg, DiffTheme.addBg))
    case .change(let o, let n, let ot, let nt):
      return ((o, ot, DiffTheme.delFg, DiffTheme.delBg), (n, nt, DiffTheme.addFg, DiffTheme.addBg))
    }
  }
}
