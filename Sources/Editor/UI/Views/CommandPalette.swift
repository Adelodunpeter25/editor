import AppKit

/// Global hook so ⌘P (an AppDelegate menu item) can reach the single palette owned by the window
/// controller — same static-hook pattern as `FormatterInstall` / `ActiveEditor`.
enum CommandPaletteHook {
  static var toggle: (() -> Void)?  // ⌘P — file quick-open
  static var command: (() -> Void)?  // ⌘⇧P — command mode
  static var lineJump: (() -> Void)?  // status-bar Ln/Col click — open in `:` line-jump mode
}

/// VS Code-style quick-open (⌘P): a top-centered overlay with a search field over a results list.
/// Type to fuzzy-match files in the active session's repo, ↑/↓ to move, Enter to open, Esc / click-out
/// to dismiss. Empty query lists the currently-open file tabs (quick switch). The file list is fetched
/// once per open via `Git.repoFiles` (off-main, gitignored dirs excluded) — no extra git poller, so it
/// costs nothing until you press ⌘P.
///
/// Glob patterns are supported: `*.swift`, `test*.py`, `src/*.swift`.
/// Search logic is delegated to `PaletteSearchEngine`.
final class CommandPaletteController: NSObject, NSTextFieldDelegate, NSTableViewDataSource,
  NSTableViewDelegate
{

  private let model: AppModel
  private weak var host: NSView?
  private let engine: PaletteSearchEngine

  private var result = PaletteSearchResult()
  private var selected = 0
  private var resultCount: Int {
    result.mode == .command ? result.commandHits.count : result.fileHits.count
  }
  private var loadToken = 0  // drops a stale async listing if the palette was reopened

  init(model: AppModel) {
    self.model = model
    self.engine = PaletteSearchEngine(model: model)
    super.init()
    engine.onEnterFileMode = { [weak self] in self?.enterFileMode() }
  }

  /// Remember where to mount the overlay (added only on present, removed on dismiss → zero idle cost).
  func attach(to host: NSView) { self.host = host }

  var isShown: Bool { overlay?.superview != nil }

  func toggle() { isShown ? dismiss() : present() }

  /// ⌘⇧P — open straight into command mode (or toggle off if already there).
  func toggleCommand() {
    if isShown && result.mode == .command {
      dismiss()
      return
    }
    if !isShown { present() }
    field.stringValue = "> "
    selected = 0
    applyFilter()
    host?.window?.makeFirstResponder(field)
    field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.count, length: 0)
  }

  /// Status-bar Ln/Col click — open in `:` line-jump mode, caret after the colon.
  func presentLineJump() {
    if !isShown { present() }
    field.stringValue = ":"
    selected = 0
    applyFilter()
    host?.window?.makeFirstResponder(field)
    field.currentEditor()?.selectedRange = NSRange(location: 1, length: 0)
  }

  // MARK: - Present / dismiss

  private var overlay: ScrimView?
  private let panel = NSView()
  private let field = NSTextField()
  private let table = NSTableView()
  private let scroll = NSScrollView()
  private let placeholder = NSTextField(labelWithString: "")
  private var listHeight: NSLayoutConstraint!

  private func present() {
    guard let host, model.activeSession != nil else { return }

    if overlay == nil { buildUI() }
    guard let overlay else { return }

    // Seed the open-tabs quick-switch list, then fetch the full repo listing.
    engine.refreshOpenFiles()
    loadFiles()

    overlay.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(overlay)
    NSLayoutConstraint.activate([
      overlay.topAnchor.constraint(equalTo: host.topAnchor),
      overlay.bottomAnchor.constraint(equalTo: host.bottomAnchor),
      overlay.leadingAnchor.constraint(equalTo: host.leadingAnchor),
      overlay.trailingAnchor.constraint(equalTo: host.trailingAnchor),
    ])

    field.stringValue = ""
    selected = 0
    applyFilter()
    host.window?.makeFirstResponder(field)
  }

  func dismiss() {
    overlay?.removeFromSuperview()
    loadToken += 1  // ignore any in-flight listing
  }

  private func loadFiles() {
    loadToken += 1
    let token = loadToken
    engine.loadRepoFiles { [weak self] in
      guard let self, token == self.loadToken else { return }  // reopened → drop stale result
      self.applyFilter()
    }
  }

  // MARK: - Filtering

  private func applyFilter() {
    result = engine.search(query: field.stringValue)
    selected = min(selected, max(0, resultCount - 1))
    table.reloadData()
    if resultCount > 0 { table.selectRowIndexes([selected], byExtendingSelection: false) }

    let rows = max(1, min(resultCount, 12))
    listHeight.constant = CGFloat(rows) * rowHeight
    placeholder.isHidden = resultCount > 0
    placeholder.stringValue = placeholderText()

    // Resolve the panel→scroll resize synchronously and re-tile the table to its new clip — otherwise
    // the scroll/table frames lag the constant change for a frame (a shrinking list paints a stretched
    // selection until the next pass).
    overlay?.layoutSubtreeIfNeeded()
    table.tile()
  }

  private func placeholderText() -> String {
    switch result.mode {
    case .command: return "No matching commands"
    case .line:
      return ActiveEditor.current == nil
        ? "Open a file first"
        : result.lineJump == nil ? "Type a line number" : "Go to line \(result.lineJump!)  ⏎"
    case .file:
      let query = field.stringValue.trimmingCharacters(in: .whitespaces)
      return query.isEmpty ? "No open files" : "No matching files"
    }
  }

  /// Switch back to file search from command mode (the "Go to File…" command).
  private func enterFileMode() {
    field.stringValue = ""
    selected = 0
    applyFilter()
    host?.window?.makeFirstResponder(field)
  }

  private func move(_ delta: Int) {
    guard resultCount > 0 else { return }
    selected = max(0, min(resultCount - 1, selected + delta))
    table.selectRowIndexes([selected], byExtendingSelection: false)
    table.scrollRowToVisible(selected)
  }

  private func openSelected() {
    switch result.mode {
    case .line:
      if let line = result.lineJump, let editor = ActiveEditor.current {
        dismiss()
        editor.goToLine(line)
      }
    case .command:
      guard result.commandHits.indices.contains(selected) else { return }
      let cmd = result.commandHits[selected]
      if cmd.keepsOpen {
        cmd.run()
      } else {
        dismiss()
        cmd.run()
      }  // Go to File… stays open
    case .file:
      guard result.fileHits.indices.contains(selected) else { return }
      let rel = result.fileHits[selected].rel
      dismiss()
      model.activeSession?.openFile(rel)
    }
  }

  // MARK: - NSControlTextEditingDelegate (drive the list from the field)

  func controlTextDidChange(_ obj: Notification) {
    selected = 0
    applyFilter()
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
    switch sel {
    case #selector(NSResponder.moveDown(_:)):
      move(1)
      return true
    case #selector(NSResponder.moveUp(_:)):
      move(-1)
      return true
    case #selector(NSResponder.insertNewline(_:)):
      openSelected()
      return true
    case #selector(NSResponder.cancelOperation(_:)):
      dismiss()
      return true
    default: return false
    }
  }

  // MARK: - Table

  private let rowHeight: CGFloat = 32

  func numberOfRows(in tableView: NSTableView) -> Int { resultCount }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let id = NSUserInterfaceItemIdentifier("paletteCell")
    let cell =
      (tableView.makeView(withIdentifier: id, owner: self) as? PaletteCellView)
      ?? {
        let c = PaletteCellView()
        c.identifier = id
        return c
      }()
    if result.mode == .command {
      let cmd = result.commandHits[row]
      cell.configure(
        name: cmd.title, dir: "", status: .none,
        nameMatches: Fuzzy.matches(result.commandQuery, cmd.title), dirMatches: [])
      return cell
    }
    let r = result.fileHits[row]
    let name = (r.rel as NSString).lastPathComponent
    let dir = (r.rel as NSString).deletingLastPathComponent

    // Glob results: no fuzzy highlight (the match is a regex, not a subsequence).
    if result.isGlob {
      cell.configure(name: name, dir: dir, status: r.status)
      return cell
    }

    // Map the full-path match positions onto the name (after the last "/") and dir segments so each
    // field bolds its own matched chars. The char at baseStart-1 is the "/" separator (never bolded).
    let query = field.stringValue.trimmingCharacters(in: .whitespaces)
    let baseStart = r.rel.count - name.count
    var nameMatches: [Int] = []
    var dirMatches: [Int] = []
    for m in Fuzzy.matches(query, r.rel) {
      if m >= baseStart {
        nameMatches.append(m - baseStart)
      } else if m < baseStart - 1 {
        dirMatches.append(m)
      }
    }
    cell.configure(
      name: name, dir: dir, status: r.status,
      nameMatches: nameMatches, dirMatches: dirMatches)
    return cell
  }

  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    PaletteRowView()
  }

  @objc private func rowClicked() {
    guard table.clickedRow >= 0 else { return }
    selected = table.clickedRow
    openSelected()
  }

  // MARK: - UI build

  private func buildUI() {
    let overlay = ScrimView()
    overlay.wantsLayer = true
    overlay.onClickOutside = { [weak self] point in
      guard let self else { return }
      if !self.panel.frame.contains(point) { self.dismiss() }
    }

    panel.translatesAutoresizingMaskIntoConstraints = false
    panel.wantsLayer = true
    panel.layer?.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
    panel.layer?.cornerRadius = 8
    panel.layer?.borderWidth = 1
    panel.layer?.borderColor = NSColor(white: 0.30, alpha: 1).cgColor
    panel.shadow = NSShadow()
    panel.layer?.shadowColor = .black
    panel.layer?.shadowOpacity = 0.4
    panel.layer?.shadowRadius = 16
    panel.layer?.shadowOffset = CGSize(width: 0, height: -4)
    overlay.addSubview(panel)

    field.translatesAutoresizingMaskIntoConstraints = false
    field.isBezeled = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = .systemFont(ofSize: 15)
    field.textColor = NSColor(white: 0.95, alpha: 1)
    field.placeholderString = "Search files by name (glob: *.swift, test*.py)"
    field.delegate = self
    panel.addSubview(field)

    let sep = NSView()
    sep.translatesAutoresizingMaskIntoConstraints = false
    sep.wantsLayer = true
    sep.layer?.backgroundColor = NSColor(white: 0.30, alpha: 1).cgColor
    panel.addSubview(sep)

    table.translatesAutoresizingMaskIntoConstraints = false
    table.headerView = nil
    table.backgroundColor = .clear
    // `.automatic` (the default on macOS 11+) inset-pads rows and draws a rounded, inset selection —
    // which stretched our single-row selection band. `.plain` = exact row height, full-width selection.
    if #available(macOS 11.0, *) { table.style = .plain }
    table.rowHeight = rowHeight
    table.intercellSpacing = .zero
    table.gridStyleMask = []
    table.selectionHighlightStyle = .regular
    table.dataSource = self
    table.delegate = self
    table.target = self
    table.action = #selector(rowClicked)
    let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
    col.resizingMask = .autoresizingMask
    table.addTableColumn(col)

    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    scroll.backgroundColor = .clear
    panel.addSubview(scroll)

    placeholder.translatesAutoresizingMaskIntoConstraints = false
    placeholder.font = .systemFont(ofSize: 12)
    placeholder.textColor = NSColor(white: 0.5, alpha: 1)
    placeholder.alignment = .center
    // On the panel (above the scroll), not inside it — NSScrollView clips/hides directly-added subviews.
    panel.addSubview(placeholder)

    listHeight = scroll.heightAnchor.constraint(equalToConstant: rowHeight)
    NSLayoutConstraint.activate([
      panel.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 80),
      panel.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
      panel.widthAnchor.constraint(equalToConstant: 560),

      field.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
      field.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
      field.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),

      sep.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 10),
      sep.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
      sep.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
      sep.heightAnchor.constraint(equalToConstant: 1),

      scroll.topAnchor.constraint(equalTo: sep.bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 4),
      scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -4),
      scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -4),
      listHeight,

      placeholder.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
      placeholder.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
    ])
    self.overlay = overlay
  }
}
