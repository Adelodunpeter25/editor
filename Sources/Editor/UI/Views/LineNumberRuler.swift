import AppKit
import LineEnding

/// A VS Code-style line-number gutter for the editor, drawn as the scroll view's vertical `NSRulerView`.
///
/// Performance: only the lines intersecting the visible rect are drawn on each pass (not the whole
/// file). Line endings are tracked via `LineCounter` (from EditorCore), which lazily parses only up
/// to the visible region and caches the rest — so scrolling a 100k-line file stays cheap without
/// scanning the entire document on every text change. Wrapped logical lines show their number once
/// (on the first visual row), matching VS Code; a trailing empty line (file ends in a newline) gets
/// its own number too.
final class LineNumberRuler: NSRulerView {
  private weak var textView: NSTextView?
  private var lineCounter: LineCounter?
  private var lineStarts: [Int] = [0]  // char offset of each logical line start; always begins with 0
  private var lineStartsDirty = true
  /// The character index up to which `lineStarts` has been populated from `lineCounter`.
  private var lineStartsParsedUpTo = 0

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
    lineStartsDirty = true
    recomputeThickness()
    needsDisplay = true
  }

  /// Called when the document is replaced wholesale (initial load, retarget) without a text edit.
  func reload() {
    lineStartsDirty = true
    recomputeThickness()
    needsDisplay = true
  }

  // MARK: Line-start index (lazily built from LineCounter; rebuilt only on text change)

  /// Rebuild the `lineCounter` if the text changed, then ensure `lineStarts` covers at least up to
  /// the last visible character. LineCounter parses line endings lazily — only the range we ask for
  /// — and caches what it has already parsed, so a deep scroll only costs the newly-entered region.
  private func ensureLineStarts(upTo charIndex: Int) {
    if lineStartsDirty {
      lineStartsDirty = false
      let s = textView?.string ?? ""
      lineCounter = LineCounter(string: s)
      lineStarts = [0]
      lineStartsParsedUpTo = 0
    }
    guard let counter = lineCounter else { return }
    let target = min(charIndex + 1, counter.length)
    if target <= lineStartsParsedUpTo { return }

    // Use the public LineRangeCalculating API which lazily parses line endings internally.
    // Asking for the line number at the target index forces parsing up to that point.
    _ = counter.lineNumber(at: target)

    // Convert the cached line endings into line-start offsets, appending new ones.
    // lineEndings is sorted by location; each line ending's upperBound is the start of the next line.
    for le in counter.lineEndings {
      let start = le.upperBound
      if start > lineStarts.last! {
        lineStarts.append(start)
      }
    }
    lineStartsParsedUpTo = target
  }

  /// 1-based (line, column) for a character index — for the status bar. Reuses the cached line index.
  func lineColumn(at charIndex: Int) -> (line: Int, column: Int) {
    ensureLineStarts(upTo: charIndex)
    let line = lineNumber(for: charIndex)
    return (line, charIndex - lineStarts[line - 1] + 1)
  }

  /// Total line count (forces a full parse — used only for width sizing, which happens on text change).
  private var totalLineCount: Int {
    ensureLineStarts(upTo: lineCounter?.length ?? 0)
    return lineStarts.count
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
    let count = totalLineCount
    let digits = max(2, String(count).count)
    let sample = String(repeating: "8", count: digits)
    let w = sample.size(withAttributes: [.font: font]).width
    let gitPadding = gitBarLeading + gitBarWidth + 4
    ruleThickness = ceil(w) + leftPadding + rightPadding + gitPadding
  }

  // MARK: Drawing

  override func drawHashMarksAndLabels(in rect: NSRect) {
    guard let textView, let lm = textView.layoutManager,
      let tc = textView.textContainer
    else { return }

    // Ensure layout is complete for the visible region before reading fragment rects.
    let visible = textView.visibleRect
    let glyphRange = lm.glyphRange(forBoundingRect: visible, in: tc)
    lm.ensureLayout(forGlyphRange: glyphRange)

    TreeSitterTheme.background.setFill()
    bounds.fill()

    let ns = textView.string as NSString
    let inset = textView.textContainerInset.height

    // Ensure line starts are parsed up to the last visible character — only the visible region,
    // not the whole document.
    let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
    ensureLineStarts(upTo: charRange.upperBound)

    // Find the first visible line by asking the layout manager directly which glyph is at the
    // top of the viewport, then mapping that glyph back to a character index and line number.
    // This avoids the old binary search over fragmentRects which could probe lines outside the
    // laid-out range and return bogus rects (causing the first few line numbers to be skipped
    // when scrolling up from the bottom of a large file).
    let viewTop = visible.minY
    let topPoint = NSPoint(x: 0, y: viewTop)
    let topGlyphIndex = lm.glyphIndex(for: topPoint, in: tc)
    let topCharIndex = lm.characterIndexForGlyph(at: topGlyphIndex)
    let startLine = max(0, lineNumber(for: topCharIndex) - 1)

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
