import AppKit
import Combine

/// One repo's file tree. NSOutlineView gives native disclosure, row virtualization, and correct
/// cursors. Polls git every 1.5s; only reloads when the visible set actually changes (signature),
/// preserving expansion across reloads by path.
final class FileTreeViewController: NSViewController, NSOutlineViewDataSource,
  NSOutlineViewDelegate, NSTextFieldDelegate, NSMenuDelegate
{
  let store: RepoStore
  let settings: Settings
  let onOpen: (String) -> Void
  let onRename: (String, String) -> Void
  let onDelete: (String) -> Void

  let outline = PointerOutlineView()
  let scroll = NSScrollView()
  var roots: [TreeNode] = []
  var expandedPaths = Set<String>()
  var restoring = false
  var cancellables = Set<AnyCancellable>()

  // Inline create / rename state
  enum EditKind { case newFile, newFolder, rename }
  var editKind: EditKind?
  var editingNode: TreeNode?
  var draftParentId = ""
  var renameOriginalId = ""
  var editCancelled = false
  var menuTargetNode: TreeNode?
  var pendingFiles: [FileEntry]?
  var pendingEmptyDirs = Set<String>()
  var isEditing: Bool { editingNode != nil }
  static let draftId = "\u{1}draft"

  /// The live tree VC (for the dev harness to drive). Only one is mounted at a time.
  static weak var current: FileTreeViewController?

  init(
    store: RepoStore, settings: Settings,
    onOpen: @escaping (String) -> Void,
    onRename: @escaping (String, String) -> Void = { _, _ in },
    onDelete: @escaping (String) -> Void = { _ in }
  ) {
    self.store = store
    self.settings = settings
    self.onOpen = onOpen
    self.onRename = onRename
    self.onDelete = onDelete
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func loadView() {
    let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
    col.resizingMask = .autoresizingMask
    outline.addTableColumn(col)
    outline.outlineTableColumn = col
    outline.headerView = nil
    outline.rowSizeStyle = .custom
    outline.rowHeight = settings.fontSize + 9
    outline.indentationPerLevel = 12
    outline.autoresizesOutlineColumn = false
    outline.selectionHighlightStyle = .regular
    outline.backgroundColor = Theme.sidebarBg
    outline.dataSource = self
    outline.delegate = self
    outline.target = self
    outline.action = #selector(rowClicked)
    outline.autoresizingMask = [.width, .height]
    let menu = NSMenu()
    menu.delegate = self
    outline.menu = menu

    scroll.documentView = outline
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = true
    scroll.backgroundColor = Theme.sidebarBg
    self.view = scroll
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    Self.current = self
    loadEmptyDirs()
    store.$files
      .sink { [weak self] files in self?.applyFiles(files) }
      .store(in: &cancellables)
    settings.$fontSize
      .dropFirst()
      .sink { [weak self] size in
        guard let self else { return }
        self.outline.rowHeight = size + 9
        self.outline.reloadData()
        self.restoreExpansion(self.roots)
      }
      .store(in: &cancellables)
  }

  // MARK: - File updates

  func applyFiles(_ files: [FileEntry]) {
    if isEditing {
      pendingFiles = files
      return
    }
    let before = pendingEmptyDirs
    pendingEmptyDirs = pendingEmptyDirs.filter { dir in
      FileManager.default.fileExists(atPath: (store.repo as NSString).appendingPathComponent(dir))
        && !files.contains { $0.path == dir || $0.path.hasPrefix(dir + "/") }
    }
    if pendingEmptyDirs != before { persistEmptyDirs() }
    let tracked = pendingEmptyDirs
    let repo = store.repo
    DispatchQueue.global().async { [weak self] in
      // Only scan for empty dirs if the user has tracked some — skip the expensive disk walk otherwise
      let emptyDirs: Set<String>
      if tracked.isEmpty {
        emptyDirs = []
      } else {
        emptyDirs = tracked  // just use tracked set, skip full disk scan for speed
      }
      let augmented =
        emptyDirs.isEmpty
        ? files
        : files + emptyDirs.map { FileEntry(path: $0, status: .none, isDir: true) }
      let tree = buildTree(augmented)
      for dir in emptyDirs { Self.markEmptyFolder(dir, in: tree) }
      DispatchQueue.main.async {
        guard let self else { return }
        if self.isEditing {
          self.pendingFiles = files
          return
        }
        self.roots = tree
        self.restoring = true
        self.outline.reloadData()
        self.restoreExpansion(self.roots)
        self.restoring = false
        self.applyReveal(scroll: false)
      }
    }
  }

  // MARK: - Reveal

  private var revealPath: String?

  func reveal(_ relPath: String) {
    revealPath = relPath.isEmpty ? nil : relPath
    applyReveal(scroll: true)
  }

  func applyReveal(scroll: Bool) {
    guard let rel = revealPath else { return }
    let comps = rel.split(separator: "/").map(String.init)
    if comps.count > 1 {
      restoring = true
      var prefix = ""
      for comp in comps.dropLast() {
        prefix = prefix.isEmpty ? comp : prefix + "/" + comp
        if let folder = findNode(prefix, in: roots), folder.isFolder {
          outline.expandItem(folder)
          expandedPaths.insert(prefix)
        }
      }
      restoring = false
    }
    guard let node = findNode(rel, in: roots) else { return }
    let row = outline.row(forItem: node)
    guard row >= 0 else { return }
    outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    if scroll { outline.scrollRowToVisible(row) }
  }

  // MARK: - Helpers

  func findNode(_ id: String, in nodes: [TreeNode]) -> TreeNode? {
    for n in nodes {
      if n.id == id { return n }
      if let c = n.children, let f = findNode(id, in: c) { return f }
    }
    return nil
  }

  func removeNode(_ node: TreeNode) {
    func rm(_ arr: inout [TreeNode]) -> Bool {
      if let i = arr.firstIndex(where: { $0 === node }) {
        arr.remove(at: i)
        return true
      }
      for n in arr {
        if var c = n.children, rm(&c) {
          n.children = c
          return true
        }
      }
      return false
    }
    _ = rm(&roots)
  }

  func restoreExpansion(_ nodes: [TreeNode]) {
    for n in nodes where n.isFolder && expandedPaths.contains(n.id) {
      outline.expandItem(n)
      restoreExpansion(n.children ?? [])
    }
  }

  @objc func rowClicked() {
    let row = outline.clickedRow
    guard row >= 0, let node = outline.item(atRow: row) as? TreeNode else { return }
    if node.isFolder {
      if outline.isItemExpanded(node) {
        outline.collapseItem(node)
      } else {
        outline.expandItem(node)
      }
    } else if !node.isDir {
      onOpen(node.id)
    }
  }

  func collapseAll() {
    restoring = true
    outline.collapseItem(nil, collapseChildren: true)
    expandedPaths.removeAll()
    restoring = false
    outline.window?.invalidateCursorRects(for: outline)
  }

  static func diskEmptyDirs(_ repo: String) -> Set<String> {
    let fm = FileManager.default
    var result = Set<String>()
    let skip = GitIgnoreUtil.ignoredDirectories
    func scan(_ path: String, _ rel: String) {
      guard let entries = try? fm.contentsOfDirectory(atPath: path) else { return }
      if entries.isEmpty {
        if !rel.isEmpty { result.insert(rel) }
        return
      }
      for name in entries where !skip.contains(name) {
        let full = (path as NSString).appendingPathComponent(name)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
          scan(full, rel.isEmpty ? name : rel + "/" + name)
        }
      }
    }
    scan(repo, "")
    return result
  }

  static func markEmptyFolder(_ id: String, in nodes: [TreeNode]) {
    for n in nodes {
      if n.id == id {
        if n.children == nil { n.children = [] }
        return
      }
      if let c = n.children, !c.isEmpty { markEmptyFolder(id, in: c) }
    }
  }

  // Empty dirs persistence
  var emptyDirsKey: String { "editor.emptyDirs:" + store.repo }

  func loadEmptyDirs() {
    let saved = (UserDefaults.standard.array(forKey: emptyDirsKey) as? [String]) ?? []
    pendingEmptyDirs = Set(
      saved.filter { dir in
        var isDir: ObjCBool = false
        let abs = (store.repo as NSString).appendingPathComponent(dir)
        return FileManager.default.fileExists(atPath: abs, isDirectory: &isDir) && isDir.boolValue
      })
  }

  func persistEmptyDirs() {
    if pendingEmptyDirs.isEmpty {
      UserDefaults.standard.removeObject(forKey: emptyDirsKey)
    } else {
      UserDefaults.standard.set(Array(pendingEmptyDirs), forKey: emptyDirsKey)
    }
  }

  func reloadAfterEdit() {
    restoring = true
    outline.reloadData()
    restoreExpansion(roots)
    restoring = false
    if let files = pendingFiles {
      pendingFiles = nil
      applyFiles(files)
    }
  }

  func warn(_ msg: String) {
    guard let window = outline.window else { return }
    let alert = NSAlert()
    alert.messageText = msg
    alert.alertStyle = .warning
    alert.beginSheetModal(for: window, completionHandler: nil)
  }

  // MARK: - Data source

  func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    (item as? TreeNode)?.children?.count ?? (item == nil ? roots.count : 0)
  }
  func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    if let node = item as? TreeNode { return node.children![index] }
    return roots[index]
  }
  func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool {
    (item as? TreeNode)?.isFolder ?? false
  }

  // MARK: - Delegate

  func outlineView(_ ov: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    guard let node = item as? TreeNode else { return nil }
    let id = NSUserInterfaceItemIdentifier("cell")
    let cell =
      (ov.makeView(withIdentifier: id, owner: self) as? FileTreeCellView)
      ?? FileTreeCellView(identifier: id)
    cell.textField?.font = .systemFont(ofSize: settings.fontSize)

    // Draft row being named inline: editable field, no status styling.
    if node === editingNode, let field = cell.textField {
      field.isEditable = true
      field.isSelectable = true
      field.delegate = self
      field.drawsBackground = true
      field.backgroundColor = Theme.inlineEditBg
      field.isBordered = true
      field.textColor = Theme.inlineEditText
      field.stringValue = node.name
      field.placeholderString = editKind == .newFolder ? "Folder name" : "File name"
      cell.iconView?.isHidden = true
      return cell
    }
    if let field = cell.textField {
      field.isEditable = false
      field.isSelectable = false
      field.delegate = nil
      field.drawsBackground = false
      field.isBordered = false
      field.placeholderString = nil
    }

    // Icon
    cell.iconView?.isHidden = false
    cell.iconView?.image = FileTreeCellView.icon(for: node, expanded: ov.isItemExpanded(node))
    cell.iconView?.contentTintColor = nsStatusColor(node.status).withAlphaComponent(0.8)

    let title = node.name + ((node.isDir && !node.isFolder) ? "/" : "")
    let color = nsStatusColor(node.status)
    if node.status == .deleted {
      cell.textField?.attributedStringValue = NSAttributedString(
        string: title,
        attributes: [
          .foregroundColor: color,
          .strikethroughStyle: NSUnderlineStyle.single.rawValue,
        ])
    } else {
      cell.textField?.stringValue = title
      cell.textField?.textColor = color
    }
    return cell
  }

  func outlineView(_ ov: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
    let level = ov.level(forItem: item)
    return TreeIndentRowView(indentLevel: level, indentWidth: ov.indentationPerLevel)
  }

  func outlineViewItemDidExpand(_ notification: Notification) {
    guard !restoring, let node = notification.userInfo?["NSObject"] as? TreeNode else { return }
    expandedPaths.insert(node.id)
  }
  func outlineViewItemDidCollapse(_ notification: Notification) {
    guard !restoring, let node = notification.userInfo?["NSObject"] as? TreeNode else { return }
    expandedPaths.remove(node.id)
  }
}

/// Custom row view that draws vertical indentation guide lines at each level and a subtle
/// transparent selection highlight instead of the system blue.
private final class TreeIndentRowView: NSTableRowView {
  private let indentLevel: Int
  private let indentWidth: CGFloat
  private static let lineColor = NSColor(white: 0.25, alpha: 1)

  init(indentLevel: Int, indentWidth: CGFloat) {
    self.indentLevel = indentLevel
    self.indentWidth = indentWidth
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override var isEmphasized: Bool {
    get { false }
    set {}
  }

  override var interiorBackgroundStyle: NSView.BackgroundStyle { .emphasized }

  override func drawSelection(in dirtyRect: NSRect) {
    Theme.activeRowBg.setFill()
    bounds.fill()
  }

  override func drawDraggingDestinationFeedback(in dirtyRect: NSRect) {
    // no-op: suppress the default rounded drag/menu highlight
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard indentLevel > 0 else { return }
    Self.lineColor.setStroke()
    let path = NSBezierPath()
    path.lineWidth = 1
    let baseOffset: CGFloat = 8
    for level in 0..<indentLevel {
      let x = baseOffset + CGFloat(level) * indentWidth + indentWidth / 2
      path.move(to: NSPoint(x: x, y: 0))
      path.line(to: NSPoint(x: x, y: bounds.height))
    }
    path.stroke()
  }
}
