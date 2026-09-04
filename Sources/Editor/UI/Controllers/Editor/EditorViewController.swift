import AppKit
import Combine
import STTextView
import LineEnding
import TextEditing

/// DEV harness hook: the editor for the currently-active file tab (set by CenterViewController).
enum ActiveEditor { static weak var current: EditorViewController? }

/// A content view controller that hosts an editable source editor — directly (the plain-file editor) or
/// embedded behind a Preview/Image toggle (markdown, SVG). Lets `CenterViewController` find the live
/// editor uniformly (active-editor tracking, dev harness) and retarget it in place on rename (so unsaved
/// edits survive) regardless of the viewer wrapping it.
protocol SourceEditing: AnyObject {
  var sourceEditor: EditorViewController? { get }
  /// File renamed/moved while open: redirect saves to the new path, keeping unsaved edits.
  func retarget(to path: String)
}

/// A syntax-highlighted file editor: an `STTextView` (TextKit 2) coloured by our native TextMate
/// highlighter (no JavaScript engine). Cmd+S saves; edits flag the tab dirty and trigger a debounced
/// re-highlight that only repaints colours (text, cursor and undo are untouched). Font size tracks
/// Settings live; resizing swaps each run's font in place (no re-tokenize).
///
/// MIGRATION NOTE (STTextView): this replaces the previous `NSTextStorage`/`NSLayoutManager`/
/// `NSTextContainer` (TextKit 1) stack. STTextView owns its own `textLayoutManager`/`textContentManager`
/// internally, so there's no longer an externally-managed `NSTextStorage` — attribute mutation goes
/// through `addAttributes(_:range:)` / `setAttributes(_:range:)` (still `NSRange`-based) instead of
/// reaching into `.textStorage`. See STTextViewRangeUtil.swift for the `NSRange` <-> `NSTextRange` bridge
/// used by edits (find/replace, line-ending/indent conversion, formatting).
final class EditorViewController: NSViewController, STTextViewDelegate, SourceEditing {
  var sourceEditor: EditorViewController? { self }
  /// Current editor text (live, including unsaved edits) — used by preview re-render on toggle.
  var text: String { textView?.text ?? "" }

  /// Config for an unsaved "New File" tab: where to default the save panel, the suggested name, and a
  /// callback to run once it's saved (so the session/tab adopts the chosen path). Nil for real files.
  struct UntitledFile {
    let suggestedName: String
    let directory: String
    let onSavedAs: (String) -> Void
  }

  var path: String  // absolute file path (mutable: a rename retargets it in place; "" while untitled)
  var repoURL: String?  // repo root — strips prefix for the breadcrumb display
  private var untitled: UntitledFile?  // non-nil until a blank "New File" tab is first saved
  private(set) var lineEnding: LineEnding = .lf  // status bar — detected on load
  private(set) var indentStyle = "Spaces: 4"
  private var languageOverride: String?  // status-bar language picker (nil = auto-detect from extension)
  var settings: Settings
  var onDirty: (Bool) -> Void

  var textView: CodeTextView!
  var scrollView: NSScrollView!
  var gitGutter: GitGutterRuler?
  var highlighter: TreeSitterHighlighter?
  var saved = ""
  var lastFontSize: Double
  private var cancellables = Set<AnyCancellable>()
  var rehighlightWork: DispatchWorkItem?
  var highlightSeq = 0
  private var fileWatcher: FileChangeWatcher?
  private var suppressTextChangeCallbacks = false
  /// All tokenizing runs on one shared serial queue: it keeps the UI responsive on large files and
  /// serialises access to the shared (per-language) highlighter, whose regexes compile lazily.
  static let highlightQueue = DispatchQueue(label: "com.editor.highlight", qos: .userInitiated)

  // MARK: - Find (stored properties)

  var findBar: FindBar?
  var findPanel: FindPanel?  // floating child window hosting the find bar (top-right overlay)
  var findObservers: [NSObjectProtocol] = []  // reposition on window move/resize
  var findMatches: [NSRange] = []
  var findCurrent = -1
  var findVisible: Bool { findPanel?.isVisible ?? false }
  static let findHL = NSColor.systemYellow.withAlphaComponent(0.32)
  static let findHLCurrent = NSColor.systemOrange.withAlphaComponent(0.6)

  // MARK: - Formatting (stored properties)

  static let formatQueue = DispatchQueue(label: "com.editor.format", qos: .userInitiated)

  init(
    path: String, repoURL: String? = nil, settings: Settings,
    onDirty: @escaping (Bool) -> Void,
    untitled: UntitledFile? = nil
  ) {
    self.path = path
    self.repoURL = repoURL
    self.untitled = untitled
    self.settings = settings
    self.onDirty = onDirty
    self.lastFontSize = settings.fontSize
    self.highlighter = TreeSitterHighlighter.forPath(path)
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func loadView() {
    let fontSize = settings.fontSize

    // scrollableTextView() wires up the STTextView + NSScrollView pair the way STTextView expects
    // (documentView assigned before configuration) — see STTextView's Getting Started docs.
    let scroll = CodeTextView.scrollableTextView()
    guard let tv = scroll.documentView as? CodeTextView else {
      fatalError("CodeTextView.scrollableTextView() did not return a CodeTextView document view")
    }
    // isRichText is a `let` on STTextView (always rich) — no assignment needed.
    tv.allowsUndo = true
    tv.backgroundColor = TreeSitterTheme.background
    tv.isAutomaticQuoteSubstitutionEnabled = false
    tv.isAutomaticTextReplacementEnabled = false
    tv.isAutomaticSpellingCorrectionEnabled = false
    tv.isVerticallyResizable = true
    tv.isHorizontallyResizable = false  // wrap lines — matches the old widthTracksTextView behaviour
    // Line numbers + separator are now drawn natively by STTextView's gutter.
    tv.showsLineNumbers = true
    tv.highlightSelectedLine = false  // the app doesn't do current-line highlighting today
    tv.font = mono(fontSize)
    tv.typingAttributes = [.font: mono(fontSize), .foregroundColor: TreeSitterTheme.base]
    tv.textDelegate = self
    self.textView = tv

    let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    // Assign `saved` first and suppress the delegate: setting `attributedText` synchronously
    // fires `textViewDidChangeText` (STTextView routes it through replaceCharacters→didChangeText),
    // which would otherwise compare against the stale `saved == ""` and mark every non-empty
    // file dirty the moment it opens.
    saved = content
    suppressTextChangeCallbacks = true
    tv.attributedText = NSAttributedString(
      string: content,
      attributes: [.font: mono(fontSize), .foregroundColor: TreeSitterTheme.base])
    suppressTextChangeCallbacks = false
    tv.textSelection = NSRange(location: 0, length: 0)  // caret at the top on open
    lineEnding = LineEnding.detect(in: content) ?? .lf  // status bar (detected once on load)
    indentStyle = EditorViewController.detectIndent(content)
    tv.onSave = { [weak self] in self?.save() }
    tv.onFormat = { [weak self] in self?.formatDocument() }
    tv.editMode = .normal  // re-assert: fires didSet so the normal-mode caret applies from open
    tv.onModeChange = { _ in
      EditorStatus.onChange?()  // refresh status bar mode indicator
    }
    tv.rebuildLineStarts()
    tv.installGitGutterOverlay()
    requestHighlight(debounced: false)  // colours apply off-main; first paint shows plain text instantly

    // Legacy (always-visible) scroller, not the overlay one: the bar stays put instead of
    // appearing only mid-scroll, and it gets its own gutter so the text view's I-beam no longer
    // bleeds under it (the scroller area shows the normal arrow cursor).
    scroll.scrollerStyle = .legacy
    scroll.autohidesScrollers = false
    scroll.borderType = .noBorder
    scroll.drawsBackground = true
    scroll.backgroundColor = TreeSitterTheme.background

    // Git gutter (colored bars for added/modified/deleted lines)
    if !path.isEmpty {  // skip for untitled files
      let gutter = GitGutterRuler(scrollView: scroll, textView: tv, filePath: path)
      gutter.onChange = { [weak tv] diff in
        tv?.gitAddedLines = diff.addedLines
        tv?.gitModifiedLines = diff.modifiedLines
        tv?.gitDeletedLines = diff.deletedLines
      }
      gutter.reload()
      self.gitGutter = gutter
    }

    self.scrollView = scroll

    // Breadcrumb bar — shows the file's repo-relative path above the editor.
    // Hidden for untitled files (no path yet) since there's nothing meaningful to show.
    let breadcrumb = PathBreadcrumbView()
    if !path.isEmpty {
      breadcrumb.configure(path: path, relativeTo: repoURL)
    } else {
      breadcrumb.isHidden = true
    }

    // Wrap breadcrumb + scroll view in a vertical stack so the bar sits flush above the editor.
    let wrapper = NSView()
    wrapper.wantsLayer = true
    wrapper.layer?.backgroundColor = TreeSitterTheme.background.cgColor
    breadcrumb.translatesAutoresizingMaskIntoConstraints = false
    scroll.translatesAutoresizingMaskIntoConstraints = false
    wrapper.addSubview(breadcrumb)
    wrapper.addSubview(scroll)
    NSLayoutConstraint.activate([
      breadcrumb.topAnchor.constraint(equalTo: wrapper.topAnchor),
      breadcrumb.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
      breadcrumb.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: breadcrumb.bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
    ])

    // The find bar floats in its own child window (UI/FindBar in a FindPanel), pinned to the editor's
    // top-right (VS Code style) — a separate window has its own cursor-rect domain, so the bar's button
    // cursors don't conflict with the text view's I-beam the way a same-window overlay subview did.
    self.view = wrapper
    startWatchingExternalChanges()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    settings.$fontSize.dropFirst().sink { [weak self] in self?.applyFont($0) }.store(
      in: &cancellables)
  }

  deinit { stopWatchingExternalChanges() }

  override func viewDidLayout() {
    super.viewDidLayout()
    if findVisible { positionFindPanel() }  // keep the floating bar pinned through sidebar/split resizes
  }

  // MARK: - STTextViewDelegate

  func textViewDidChangeText(_ notification: Notification) {
    guard !suppressTextChangeCallbacks else { return }
    onDirty(textView.text != saved)
    NotificationCenter.default.post(
      name: .editorFileTextDidChange, object: self,
      userInfo: ["path": path, "text": textView.text ?? ""])
    textView.rebuildLineStarts()
    requestHighlight(debounced: true)
    if findBar?.isHidden == false { recomputeMatches() }  // keep find matches/highlights in sync with edits
  }

  func textViewDidChangeSelection(_ notification: Notification) {
    EditorStatus.onChange?()  // status bar Ln/Col follows the caret
  }

  // MARK: - Status bar info

  /// 1-based caret line + column (reuses the gutter's cached line index).
  func cursorLineColumn() -> (line: Int, column: Int) {
    guard let tv = textView else { return (1, 1) }
    let loc = min(tv.textSelection.location, (tv.text as NSString?)?.length ?? 0)
    return tv.lineColumn(at: loc)
  }

  /// Convert the document's line endings (status-bar LF/CRLF click). One undoable edit; marks dirty so
  /// it persists on save. Normalizes to LF first, then to CRLF if requested.
  func convertLineEndings(to eol: LineEnding) {
    guard let tv = textView, eol != lineEnding else { return }
    let converted = tv.text?.convertingLineEndings(to: eol) ?? ""
    guard tv.replaceCharacters(inRange: tv.fullRange, with: converted) else { return }
    lineEnding = eol
  }

  /// Override the syntax language for this open file (status-bar picker; nil = auto-detect). Non-
  /// destructive (re-highlights only, no dirty flag) and resets when the file is closed/reopened.
  func setLanguageOverride(_ key: String?) {
    languageOverride = key
    highlighter =
      key.map { TreeSitterHighlighter.forLanguage($0) } ?? TreeSitterHighlighter.forPath(path)
    if highlighter == nil {
      textView.addAttributes(
        [.foregroundColor: TreeSitterTheme.base], range: textView.fullRange)
    } else {
      requestHighlight(debounced: false)
    }
    EditorStatus.onChange?()  // refresh the status-bar language label
  }

  /// All bundled grammar keys + their display names, for the status-bar language menu.
  static func availableLanguages() -> [(key: String, name: String)] {
    TreeSitterHighlighter.availableLanguages.map {
      (key: $0, name: LanguageUtil.displayName(forKey: $0))
    }
  }

  /// Convert the file's existing indentation to tabs or N-wide spaces (status-bar click). One undoable
  /// edit; marks dirty. Heuristic: derives each line's indent *level* from the current style, re-emits
  /// it in the target — correct for consistent indentation, approximate for mixed tabs+spaces.
  func convertIndentation(to target: String) {
    guard let tv = textView, target != indentStyle else { return }
    let toTabs = target == "Tabs"
    let toWidth = Int(target.replacingOccurrences(of: "Spaces: ", with: "")) ?? 4
    let srcTabs = indentStyle == "Tabs"
    let srcWidth = max(1, Int(indentStyle.replacingOccurrences(of: "Spaces: ", with: "")) ?? 4)
    let converted = ((tv.text ?? "") as NSString).components(separatedBy: "\n").map {
      line -> String in
      let ws = line.prefix { $0 == " " || $0 == "\t" }
      guard !ws.isEmpty else { return line }
      let level =
        srcTabs ? ws.filter { $0 == "\t" }.count : ws.filter { $0 == " " }.count / srcWidth
      let newWS =
        toTabs
        ? String(repeating: "\t", count: level) : String(repeating: " ", count: level * toWidth)
      return newWS + line.dropFirst(ws.count)
    }.joined(separator: "\n")
    guard tv.replaceCharacters(inRange: tv.fullRange, with: converted) else { return }
    indentStyle = target
  }

  /// Display name for the language (override if set, else detected from extension); "Plain Text" if none.
  var languageDisplayName: String {
    guard let key = languageOverride ?? LanguageUtil.language(forPath: path) else {
      return "Plain Text"
    }
    return LanguageUtil.displayName(forKey: key)
  }

  /// Tabs vs spaces (+ unit) from the file's leading whitespace — delegates style detection to
  /// TextEditing.detectedIndentStyle, then derives the space width from the minimum indent.
  private static func detectIndent(_ s: String) -> String {
    guard let style = s.detectedIndentStyle else { return "Spaces: 4" }
    switch style {
    case .tab: return "Tabs"
    case .space:
      var unit = Int.max
      for line in s.split(separator: "\n", omittingEmptySubsequences: true).prefix(1000) {
        let n = line.prefix { $0 == " " }.count
        if n > 0 { unit = min(unit, n) }
      }
      return "Spaces: \(unit == Int.max ? 4 : min(unit, 8))"
    }
  }

  func save() {
    // A blank "New File" tab has no path yet → ask where to save (VS Code's untitled-save flow).
    if untitled != nil {
      _ = saveAs()
      return
    }
    // Format-on-save: if enabled and this file has an enabled formatter, format first, then write.
    // Never block the save — formatter errors / not-installed just save the unformatted text (no prompt).
    if settings.formatOnSave, let spec = Formatter.spec(forPath: path),
      settings.formatterEnabled(spec.id)
    {
      let text = textView.text ?? ""
      let p = path
      EditorViewController.formatQueue.async {
        let outcome = Formatter.format(text: text, path: p)
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          if case .formatted(let newText) = outcome, self.textView.text == text {
            self.replacePreservingCursor(with: newText)
          }
          self.writeToDisk()
        }
      }
    } else {
      writeToDisk()
    }
  }

  func writeToDisk() {
    let content = textView.text ?? ""
    try? content.write(toFile: path, atomically: true, encoding: .utf8)
    saved = content
    onDirty(false)
    gitGutter?.reload()  // refresh git diff after save
  }

  /// Synchronous, unconditional write — used by the unsaved-changes guard so "Save & Close" / quit always
  /// persists *now*, before the tab or app closes. (format-on-save's async path could otherwise run after
  /// this editor is torn down and silently drop the edits.) Returns `false` if a blank tab's save panel was
  /// cancelled, so the guard can abort the close instead of discarding the text.
  @discardableResult
  func saveImmediately() -> Bool {
    if untitled != nil { return saveAs() }
    writeToDisk()
    return true
  }

  /// Prompt for a location for a blank "New File" tab, then adopt it as a real file. Returns `false` if the
  /// panel was cancelled (the tab stays blank and dirty).
  @discardableResult
  private func saveAs() -> Bool {
    guard let cfg = untitled else {
      writeToDisk()
      return true
    }
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.nameFieldStringValue = cfg.suggestedName
    panel.directoryURL = URL(fileURLWithPath: cfg.directory, isDirectory: true)
    guard panel.runModal() == .OK, let url = panel.url else { return false }
    performSaveAs(to: url)
    return true
  }

  /// Adopt `url` as this editor's file: redirect saves there, re-pick the grammar for the new extension,
  /// write the current text, refresh the status bar, and tell the session (so the tab gets the new path +
  /// filename title). Shared by the save panel and the dev harness.
  func performSaveAs(to url: URL) {
    let onSavedAs = untitled?.onSavedAs
    untitled = nil  // it's a real file from here on (so `save()` writes directly next time)
    retarget(to: url.path)  // sets `path` + re-derives highlighter/language for the new extension
    writeToDisk()  // persist the current text to the chosen path
    EditorStatus.onChange?()  // refresh the status bar (language indicator)
    onSavedAs?(url.path)
  }

  /// Make the text view first responder — called when its tab becomes active so you can type / search /
  /// jump without clicking into it first.
  func focusText() { textView?.window?.makeFirstResponder(textView) }

  /// Jump to (and select) a 1-based line, centering it in the viewport — used by the command palette's
  /// `:123` line jump. Clamps to the valid range; no-op on an empty editor.
  func goToLine(_ line: Int) {
    guard let tv = textView else { return }
    let ns = (tv.text ?? "") as NSString
    guard ns.length > 0 else { return }
    var idx = 0
    var current = 1
    while current < line {
      let r = ns.range(of: "\n", range: NSRange(location: idx, length: ns.length - idx))
      if r.location == NSNotFound { break }
      idx = r.location + 1
      current += 1
    }
    let nl = ns.range(of: "\n", range: NSRange(location: idx, length: ns.length - idx))
    let end = nl.location == NSNotFound ? ns.length : nl.location
    tv.textSelection = NSRange(location: idx, length: end - idx)
    tv.window?.makeFirstResponder(tv)
    centerSelection()
    // Re-center next runloop: a just-opened (or just-focused) editor may not have completed layout /
    // sizing yet, so the first pass can mis-measure. The deferred pass runs against the settled view.
    DispatchQueue.main.async { [weak self] in self?.centerSelection() }
  }

  /// Scroll so the current selection sits vertically centered.
  ///
  /// MIGRATION NOTE (STTextView): the old implementation measured the selection's bounding rect via
  /// `NSLayoutManager.boundingRect(forGlyphRange:in:)`. STTextView's TextKit 2 equivalent is
  /// `NSTextLayoutManager.textSegmentFrame(in:type:)`, which returns view-relative frames directly (no
  /// manual `textContainerOrigin` offset needed).
  func centerSelection() {
    guard let tv = textView, let clip = scrollView?.contentView else { return }
    guard let range = NSTextRange(tv.textSelection, in: tv.textContentManager) else { return }
    guard
      let rect = tv.textLayoutManager.textSegmentFrame(
        in: range, type: .standard)
    else { return }
    let h = clip.bounds.height
    tv.scrollToVisible(NSRect(x: 0, y: rect.midY - h / 2, width: 1, height: h))
  }

  /// The file was renamed/moved on disk: redirect saves to the new path and re-pick the syntax
  /// grammar for the (possibly new) extension. Content, cursor, undo, and dirty state are untouched.
  func retarget(to newPath: String) {
    guard newPath != path else { return }
    stopWatchingExternalChanges()
    path = newPath
    languageOverride = nil  // new path → re-detect language
    highlighter = TreeSitterHighlighter.forPath(newPath)
    gitGutter?.updatePath(newPath)  // update git gutter for new path
    if highlighter == nil {
      // New extension has no grammar — clear stale colours from the old type (requestHighlight
      // early-returns when there's no highlighter, so it won't reset them itself).
      textView.addAttributes([.foregroundColor: TreeSitterTheme.base], range: textView.fullRange)
    } else {
      requestHighlight(debounced: false)
    }
    startWatchingExternalChanges()
  }

  private func startWatchingExternalChanges() {
    stopWatchingExternalChanges()
    guard !path.isEmpty else { return }
    fileWatcher = FileChangeWatcher(path: path) { [weak self] in
      self?.reloadFromDiskIfNeeded()
    }
    fileWatcher?.start()
  }

  private func stopWatchingExternalChanges() {
    fileWatcher?.stop()
    fileWatcher = nil
  }

  /// Pull in a clean on-disk change. Dirty editors keep their local buffer and ignore outside writes.
  private func reloadFromDiskIfNeeded() {
    guard !path.isEmpty, textView?.text == saved else { return }
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
    guard content != textView.text else { return }

    let selection = textView.textSelection
    suppressTextChangeCallbacks = true
    defer { suppressTextChangeCallbacks = false }
    textView.attributedText = NSAttributedString(
      string: content,
      attributes: [.font: mono(lastFontSize), .foregroundColor: TreeSitterTheme.base])
    saved = content
    textView.textSelection = NSRange(
      location: min(selection.location, (content as NSString).length), length: 0)
    lineEnding = LineEnding.detect(in: content) ?? .lf
    indentStyle = EditorViewController.detectIndent(content)
    textView.rebuildLineStarts()
    gitGutter?.reload()
    onDirty(false)
    requestHighlight(debounced: false)
    EditorStatus.onChange?()
    NotificationCenter.default.post(
      name: .editorFileTextDidChange, object: self,
      userInfo: ["path": path, "text": content])
  }
}
