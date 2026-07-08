import AppKit
import LineEnding

/// A VS Code-style line-number gutter for the editor, drawn as the scroll view's vertical `NSRulerView`.
///
/// Performance: only the lines intersecting the visible rect are drawn on each pass (not the whole
/// file). Line endings are tracked via `LineCounter` (from EditorCore) which is pre-computed on load/edit.
/// This ensures scrolling a large file is extremely fast and smooth, with zero delay or popping-in
/// of line numbers since layout manager status does not block line-start detection.
final class LineNumberRuler: NSRulerView {
  private weak var textView: NSTextView?
  private var lineCounter: LineCounter?
  private var lineStarts: [Int] = [0]  // char offset of each logical line start; always begins with 0
  private var cachedLineCount: Int = 1

  private static let numberColor = Theme.gutterNumber
  private static let currentColor = Theme.gutterCurrent
  private let rightPadding: CGFloat = 8
  private let leftPadding: CGFloat = 6
  private let gitBarWidth: CGFloat = 3
  private let gitBarLeading: CGFloat = 2

  var gitAddedLines: Set<Int> = [] { didSet { needsDisplay = true } }
  var gitModifiedLines: Set<Int> = [] { didSet { needsDisplay = true } }
  var gitDeletedLines: Set<Int> = [] { didSet { needsDisplay = true } }

  init(scrollView: NSScrollView, textView: NSTextView) {
    self.textView = textView
    super.init(scrollView: scrollView, orientation: .verticalRuler)
    clientView = textView
    ruleThickness = 40

    // Redraw on scroll (the document clip view moves) and on text/selection changes.
    scrollView.contentView.postsBoundsChangedNotifications = true
    let nc = NotificationCenter.default
    nc.addObserver(
      self, selector: #selector(viewDidScroll),
      name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    nc.addObserver(
      self, selector: #selector(textDidChange),
      name: NSText.didChangeNotification, object: textView)
    nc.addObserver(
      self, selector: #selector(selectionDidChange),
      name: NSTextView.didChangeSelectionNotification, object: textView)
  }

  @available(*, unavailable)
  required init(coder: NSCoder) { fatalError() }

  deinit { NotificationCenter.default.removeObserver(self) }

  /// Editor font changed (Cmd +/−): the gutter font and width track it.
  var font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular) {
    didSet {
      recomputeThickness()
      needsDisplay = true
    }
  }

  @objc private func viewDidScroll() { needsDisplay = true }
  @objc private func selectionDidChange() { needsDisplay = true }
  @objc private func textDidChange() {
    rebuildLineStarts()
    needsDisplay = true
  }

  /// Called when the document is replaced wholesale (initial load, retarget) without a text edit.
  func reload() {
    rebuildLineStarts()
    needsDisplay = true
  }

  // MARK: - Line-start index pre-computation

  private func rebuildLineStarts() {
    let s = textView?.string ?? ""
    let counter = LineCounter(string: s)
    // Force a complete parse of the entire string by checking the line number at the last character index.
    if s.utf16.count > 0 {
      _ = counter.lineNumber(at: s.utf16.count - 1)
    }
    self.lineCounter = counter

    var starts = [0]
    starts.reserveCapacity(counter.lineEndings.count + 1)
    for ending in counter.lineEndings {
      starts.append(ending.upperBound)
    }
    self.lineStarts = starts
    self.cachedLineCount = starts.count
    recomputeThickness()
  }

  /// 1-based (line, column) for a character index — for the status bar.
  func lineColumn(at charIndex: Int) -> (line: Int, column: Int) {
    let line = lineNumber(for: charIndex)
    return (line, charIndex - lineStarts[line - 1] + 1)
  }

  /// 1-based line number containing `charIndex` (binary search for the greatest start ≤ charIndex).
  private func lineNumber(for charIndex: Int) -> Int {
    var lo = 0
    var hi = lineStarts.count - 1
    var ans = 0
    while lo <= hi {
      let mid = (lo + hi) / 2
      if lineStarts[mid] <= charIndex {
        ans = mid
        lo = mid + 1
      } else {
        hi = mid - 1
      }
    }
    return ans + 1
  }

  private func recomputeThickness() {
    let digits = max(2, String(cachedLineCount).count)
    // Font is monospaced: measure one digit and multiply — avoids a string alloc per recompute.
    let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
    let gitPadding = gitBarLeading + gitBarWidth + 4
    let newThickness = ceil(digitWidth * CGFloat(digits)) + leftPadding + rightPadding + gitPadding
    if newThickness != ruleThickness { ruleThickness = newThickness }  // skip layout if unchanged
  }

  // MARK: Drawing

  override func drawHashMarksAndLabels(in rect: NSRect) {
    guard let textView, let lm = textView.layoutManager,
      let tc = textView.textContainer
    else { return }

    // Force layout (glyph generation included) for the visible region *before* asking which
    // glyphs live in it.
    let visible = textView.visibleRect
    lm.ensureLayout(forBoundingRect: visible, in: tc)

    TreeSitterTheme.background.setFill()
    rect.fill() // Fill only the dirty rect, not bounds

    let ns = textView.string as NSString
    let inset = textView.textContainerInset.height

    // Find the first visible line by asking the layout manager directly which glyph is at the
    // top of the viewport, then mapping that glyph back to a character index and line number.
    let viewTop = visible.minY
    let topPoint = NSPoint(x: 0, y: viewTop)
    let topGlyphIndex = lm.glyphIndex(for: topPoint, in: tc)
    
    let startLine: Int
    if topGlyphIndex == NSNotFound {
      startLine = 0
    } else {
      let topCharIndex = lm.characterIndexForGlyph(at: topGlyphIndex)
      startLine = max(0, lineNumber(for: topCharIndex) - 1)
    }

    let curLine = lineNumber(for: textView.selectedRange().location)

    // Walk forward from the first visible line, drawing each line's number at its fragment rect.
    // Stop when we pass the bottom of the viewport.
    var line = startLine
    while line < lineStarts.count {
      let fragRect = fragmentRect(forLine: line, lm: lm, ns: ns)
      let y = inset + fragRect.minY - visible.minY
      if y > visible.height { break }  // below the viewport bottom — done
      if y + fragRect.height >= 0 {  // intersects the viewport — draw it
        let n = line + 1
        drawGitMarker(for: n, y: y, height: fragRect.height)
        let attrs: [NSAttributedString.Key: Any] = [
          .font: font,
          .foregroundColor: n == curLine ? Self.currentColor : Self.numberColor,
        ]
        let s = String(n) as NSString
        let size = s.size(withAttributes: attrs)
        let drawX = ruleThickness - size.width - rightPadding
        let drawY = y + (fragRect.height - size.height) / 2
        s.draw(at: NSPoint(x: drawX, y: drawY), withAttributes: attrs)
      }
      line += 1
    }
  }

  private func drawGitMarker(for line: Int, y: CGFloat, height: CGFloat) {
    if gitAddedLines.contains(line) {
      Theme.gitNew.setFill()
      NSBezierPath(rect: NSRect(x: gitBarLeading, y: y, width: gitBarWidth, height: height)).fill()
      return
    }
    if gitModifiedLines.contains(line) {
      Theme.gitModified.setFill()
      NSBezierPath(rect: NSRect(x: gitBarLeading, y: y, width: gitBarWidth, height: height)).fill()
      return
    }
    if gitDeletedLines.contains(line) {
      Theme.gitDeleted.setFill()
      let path = NSBezierPath()
      path.move(to: NSPoint(x: gitBarLeading, y: y))
      path.line(to: NSPoint(x: gitBarLeading + gitBarWidth, y: y + 3))
      path.line(to: NSPoint(x: gitBarLeading, y: y + 6))
      path.close()
      path.fill()
    }
  }

  /// Layout rect of a logical line's first visual row (or the extra fragment for an empty trailing line).
  private func fragmentRect(forLine i: Int, lm: NSLayoutManager, ns: NSString) -> NSRect {
    let startChar = lineStarts[i]
    guard startChar < ns.length else { return lm.extraLineFragmentRect }
    return lm.lineFragmentRect(
      forGlyphAt: lm.glyphIndexForCharacter(at: startChar), effectiveRange: nil)
  }
}
