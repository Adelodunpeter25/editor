import AppKit
import Combine
import LineEnding

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

/// A syntax-highlighted file editor: a plain `NSTextView`/`NSTextStorage` coloured by our native
/// TextMate highlighter (no JavaScript engine). Cmd+S saves; edits flag the tab dirty and trigger a
/// debounced re-highlight that only repaints colours (text, cursor and undo are untouched). Font size
/// tracks Settings live; resizing swaps each run's font in place (no re-tokenize).
final class EditorViewController: NSViewController, NSTextViewDelegate, SourceEditing {
  var sourceEditor: EditorViewController? { self }
  /// Current editor text (live, including unsaved edits) — used by preview re-render on toggle.
  var text: String { textView?.string ?? "" }

  /// Config for an unsaved "New File" tab: where to default the save panel, the suggested name, and a
  /// callback to run once it's saved (so the session/tab adopts the chosen path). Nil for real files.
  struct UntitledFile {
    let suggestedName: String
    let directory: String
    let onSavedAs: (String) -> Void
  }

  var path: String  // absolute file path (mutable: a rename retargets it in place; "" while untitled)
  private var untitled: UntitledFile?  // non-nil until a blank "New File" tab is first saved
  private(set) var lineEnding: LineEnding = .lf  // status bar — detected on load
  private(set) var indentStyle = "Spaces: 4"
  private var languageOverride: String?  // status-bar language picker (nil = auto-detect from extension)
  var settings: Settings
  var onDirty: (Bool) -> Void

  var textView: CodeTextView!
  var scrollView: NSScrollView!
  var textStorage: NSTextStorage!
  var lineRuler: LineNumberRuler!
  var gitGutter: GitGutterRuler?
  var highlighter: TreeSitterHighlighter?
  var saved = ""
  var lastFontSize: Double
  private var cancellables = Set<AnyCancellable>()
  var rehighlightWork: DispatchWorkItem?
  var highlightSeq = 0
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
    path: String, settings: Settings, onDirty: @escaping (Bool) -> Void,
    untitled: UntitledFile? = nil
  ) {
    self.path = path
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
    let storage = NSTextStorage()
    self.textStorage = storage

    let layoutManager = NSLayoutManager()
    storage.addLayoutManager(layoutManager)
    let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = true
    layoutManager.addTextContainer(container)

    let tv = CodeTextView(frame: .zero, textContainer: container)
    tv.isRichText = false
    tv.allowsUndo = true
    tv.backgroundColor = TreeSitterTheme.background
    tv.insertionPointColor = .white
    tv.isAutomaticQuoteSubstitutionEnabled = false
    tv.isAutomaticDashSubstitutionEnabled = false
    tv.isAutomaticSpellingCorrectionEnabled = false
    tv.isVerticallyResizable = true
    tv.isHorizontallyResizable = false
    tv.minSize = NSSize(width: 0, height: 0)
    tv.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    tv.autoresizingMask = NSView.AutoresizingMask.width
    tv.textContainerInset = NSSize(width: 6, height: 8)
    tv.font = mono(fontSize)
    tv.typingAttributes = [.font: mono(fontSize), .foregroundColor: TreeSitterTheme.base]
    tv.delegate = self
    self.textView = tv

    let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    textStorage.setAttributedString(
      NSAttributedString(
        string: content,
        attributes: [.font: mono(fontSize), .foregroundColor: TreeSitterTheme.base]))
    saved = content
    tv.setSelectedRange(NSRange(location: 0, length: 0))  // caret at the top on open (setAttributedString parks it at the end)
    lineEnding = LineEnding.detect(in: content) ?? .lf  // status bar (detected once on load)
    indentStyle = EditorViewController.detectIndent(content)
    tv.onSave = { [weak self] in self?.save() }
    tv.onFormat = { [weak self] in self?.formatDocument() }
    requestHighlight(debounced: false)  // colours apply off-main; first paint shows plain text instantly

    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    // Legacy (always-visible) scroller, not the overlay one: the bar stays put instead of
    // appearing only mid-scroll, and it gets its own gutter so the text view's I-beam no longer
    // bleeds under it (the scroller area shows the normal arrow cursor).
    scroll.scrollerStyle = .legacy
    scroll.autohidesScrollers = false
    scroll.borderType = .noBorder
    scroll.drawsBackground = true
    scroll.backgroundColor = TreeSitterTheme.background
    scroll.documentView = tv

    // Line-number gutter (VS Code-style), drawn as the scroll view's vertical ruler.
    let ruler = LineNumberRuler(scrollView: scroll, textView: tv)
    ruler.font = mono(fontSize)
    scroll.verticalRulerView = ruler
    scroll.hasVerticalRuler = true
    scroll.rulersVisible = true
    ruler.reload()  // build the line index for the just-loaded content
    self.lineRuler = ruler

    // Git gutter (colored bars for added/modified/deleted lines), drawn inside the line-number ruler.
    if !path.isEmpty {  // skip for untitled files
      let gutter = GitGutterRuler(scrollView: scroll, textView: tv, filePath: path)
      gutter.onChange = { [weak ruler] diff in
        ruler?.gitAddedLines = diff.addedLines
        ruler?.gitModifiedLines = diff.modifiedLines
        ruler?.gitDeletedLines = diff.deletedLines
      }
      gutter.reload()
      self.gitGutter = gutter
    }

    self.scrollView = scroll

    // The find bar floats in its own child window (UI/FindBar in a FindPanel), pinned to the editor's
    // top-right (VS Code style) — a separate window has its own cursor-rect domain, so the bar's button
    // cursors don't conflict with the text view's I-beam the way a same-window overlay subview did.
    self.view = scroll
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    settings.$fontSize.dropFirst().sink { [weak self] in self?.applyFont($0) }.store(
      in: &cancellables)
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    if findVisible { positionFindPanel() }  // keep the floating bar pinned through sidebar/split resizes
  }

  func textDidChange(_ notification: Notification) {
    onDirty(textView.string != saved)
    NotificationCenter.default.post(
      name: .editorFileTextDidChange, object: self,
      userInfo: ["path": path, "text": textView.string])
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
    let loc = min(tv.selectedRange().location, (tv.string as NSString).length)
    return lineRuler.lineColumn(at: loc)
  }

  /// Convert the document's line endings (status-bar LF/CRLF click). One undoable edit; marks dirty so
  /// it persists on save. Normalizes to LF first, then to CRLF if requested.
  func convertLineEndings(to eol: LineEnding) {
    guard let tv = textView, eol != lineEnding else { return }
    let converted = tv.string.convertingLineEndings(to: eol)
    let full = NSRange(location: 0, length: (tv.string as NSString).length)
    if tv.shouldChangeText(in: full, replacementString: converted) {
      tv.textStorage?.replaceCharacters(in: full, with: converted)
      tv.didChangeText()
    }
    lineEnding = eol
  }

  /// Override the syntax language for this open file (status-bar picker; nil = auto-detect). Non-
  /// destructive (re-highlights only, no dirty flag) and resets when the file is closed/reopened.
  func setLanguageOverride(_ key: String?) {
    languageOverride = key
    highlighter =
      key.map { TreeSitterHighlighter.forLanguage($0) } ?? TreeSitterHighlighter.forPath(path)
    if highlighter == nil {
      textStorage.addAttribute(
        .foregroundColor, value: TreeSitterTheme.base,
        range: NSRange(location: 0, length: textStorage.length))
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
    let converted = (tv.string as NSString).components(separatedBy: "\n").map { line -> String in
      let ws = line.prefix { $0 == " " || $0 == "\t" }
      guard !ws.isEmpty else { return line }
      let level =
        srcTabs ? ws.filter { $0 == "\t" }.count : ws.filter { $0 == " " }.count / srcWidth
      let newWS =
        toTabs
        ? String(repeating: "\t", count: level) : String(repeating: " ", count: level * toWidth)
      return newWS + line.dropFirst(ws.count)
    }.joined(separator: "\n")
    let full = NSRange(location: 0, length: (tv.string as NSString).length)
    if tv.shouldChangeText(in: full, replacementString: converted) {
      tv.textStorage?.replaceCharacters(in: full, with: converted)
      tv.didChangeText()
    }
    indentStyle = target
  }

  /// Display name for the language (override if set, else detected from extension); "Plain Text" if none.
  var languageDisplayName: String {
    guard let key = languageOverride ?? LanguageUtil.language(forPath: path) else {
      return "Plain Text"
    }
    return LanguageUtil.displayName(forKey: key)
  }

  /// Tabs vs spaces (+ unit) from the file's leading whitespace — a quick heuristic over the first lines.
  private static func detectIndent(_ s: String) -> String {
    var tabLines = 0
    var spaceLines = 0
    var unit = Int.max
    for line in s.split(separator: "\n", omittingEmptySubsequences: true).prefix(1000) {
      if line.first == "\t" {
        tabLines += 1
      } else {
        let n = line.prefix { $0 == " " }.count
        if n > 0 {
          spaceLines += 1
          unit = min(unit, n)
        }
      }
    }
    if tabLines > spaceLines { return "Tabs" }
    return spaceLines == 0 ? "Spaces: 4" : "Spaces: \(min(unit, 8))"
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
      let text = textView.string
      let p = path
      EditorViewController.formatQueue.async {
        let outcome = Formatter.format(text: text, path: p)
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          if case .formatted(let newText) = outcome, self.textView.string == text {
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
    let content = textView.string
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
    panel.directoryURL = URL(fileURLWithPath: cfg.directory)
    panel.nameFieldStringValue = cfg.suggestedName
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

  /// DEV harness: run the save-as transition with a fixed path (the real `NSSavePanel` is modal/HID).
  func debugSaveAs(_ path: String) { performSaveAs(to: URL(fileURLWithPath: path)) }

  /// Make the text view first responder — called when its tab becomes active so you can type / search /
  /// jump without clicking into it first.
  func focusText() { textView?.window?.makeFirstResponder(textView) }

  /// Jump to (and select) a 1-based line, centering it in the viewport — used by the command palette's
  /// `:123` line jump. Clamps to the valid range; no-op on an empty editor.
  func goToLine(_ line: Int) {
    guard let tv = textView else { return }
    let ns = tv.string as NSString
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
    tv.setSelectedRange(NSRange(location: idx, length: end - idx))
    tv.window?.makeFirstResponder(tv)
    centerSelection()
    // Re-center next runloop: a just-opened (or just-focused) editor may not have completed layout /
    // sizing yet, so the first pass can mis-measure. The deferred pass runs against the settled view.
    DispatchQueue.main.async { [weak self] in self?.centerSelection() }
  }

  /// Scroll so the current selection sits vertically centered. Uses `scrollToVisible` with a
  /// viewport-tall rect centered on the line — `NSView` handles the clip's (non-standard, ruler-offset)
  /// coordinate space, which manual `clip.scroll(to:)` got wrong (sending the view past the text).
  /// Forces layout up to the selection first, since `NSLayoutManager` is lazy and an un-laid-out range
  /// mis-measures.
  func centerSelection() {
    guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer,
      let clip = scrollView?.contentView
    else { return }
    let range = tv.selectedRange()
    lm.ensureLayout(forCharacterRange: NSRange(location: 0, length: NSMaxRange(range)))
    let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
    var rect = lm.boundingRect(forGlyphRange: glyphs, in: tc)
    rect.origin.y += tv.textContainerOrigin.y
    let h = clip.bounds.height
    tv.scrollToVisible(NSRect(x: 0, y: rect.midY - h / 2, width: 1, height: h))
  }

  /// The file was renamed/moved on disk: redirect saves to the new path and re-pick the syntax
  /// grammar for the (possibly new) extension. Content, cursor, undo, and dirty state are untouched.
  func retarget(to newPath: String) {
    guard newPath != path else { return }
    path = newPath
    languageOverride = nil  // new path → re-detect language
    highlighter = TreeSitterHighlighter.forPath(newPath)
    gitGutter?.updatePath(newPath)  // update git gutter for new path
    if highlighter == nil {
      // New extension has no grammar — clear stale colours from the old type (requestHighlight
      // early-returns when there's no highlighter, so it won't reset them itself).
      textStorage.addAttribute(
        .foregroundColor, value: TreeSitterTheme.base,
        range: NSRange(location: 0, length: textStorage.length))
    } else {
      requestHighlight(debounced: false)
    }
  }
}
