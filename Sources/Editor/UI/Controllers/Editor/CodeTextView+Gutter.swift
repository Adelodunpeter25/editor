import AppKit
import LineEnding

/// All line-number gutter logic for CodeTextView, extracted into its own file.
/// The gutter is drawn directly inside the text view's `draw(_:)` pass so it
/// scrolls in lock-step with the text on the GPU — no separate ruler view.
extension CodeTextView {

  // MARK: - Gutter width

  /// Computes the ideal gutter width from the current line count and font.
  func computeGutterWidth() -> CGFloat {
    let digits = max(2, String(cachedLineCount).count)
    let digitWidth = ("8" as NSString).size(withAttributes: [.font: font ?? .systemFont(ofSize: 12)]).width
    let gitPadding: CGFloat = 9  // 2 (leading) + 3 (bar) + 4 (gap)
    return ceil(digitWidth * CGFloat(digits)) + 12 + gitPadding
  }

  /// Recalculates `_cachedGutterWidth` and updates the text container inset
  /// if the width actually changed.  Called from `rebuildLineStarts()` and
  /// `applyFont`.
  func updateGutterWidthIfNeeded() {
    let newWidth = computeGutterWidth()
    guard newWidth != _cachedGutterWidth else { return }
    _cachedGutterWidth = newWidth
    applyGutterInset()
  }

  /// Pushes the text container to the right by setting `textContainerInset`
  /// so that the gutter area is left empty for us to draw into.
  /// The right-side inset is kept at a small constant so text isn't glued
  /// to the trailing edge.
  func applyGutterInset() {
    // textContainerInset.width is applied symmetrically by AppKit's default
    // textContainerOrigin, but we override textContainerOrigin to use
    // _cachedGutterWidth on the left.  We still set the inset so AppKit's
    // automatic container-width calculation (widthTracksTextView) subtracts
    // the right amount:  containerWidth = viewWidth - 2 * inset.width.
    // Keeping a modest inset gives us a small right margin too.
    let insetW = _cachedGutterWidth / 2  // half, because AppKit doubles it
    textContainerInset = NSSize(width: insetW, height: 8)
    needsDisplay = true
  }

  // MARK: - Cursor rect

  func resetGutterCursorRect() {
    let gutterRect = NSRect(x: 0, y: 0, width: _cachedGutterWidth, height: bounds.height)
    addCursorRect(gutterRect, cursor: .arrow)
  }

  // MARK: - Line index

  /// Rebuilds the `lineStarts` array from scratch.
  /// Called after every text change and on initial load.
  func rebuildLineStarts() {
    let s = self.string
    let counter = LineCounter(string: s)
    if s.utf16.count > 0 {
      _ = counter.lineNumber(at: s.utf16.count - 1)
    }
    var starts = [0]
    starts.reserveCapacity(counter.lineEndings.count + 1)
    for ending in counter.lineEndings {
      starts.append(ending.upperBound)
    }
    self.lineStarts = starts
    self.cachedLineCount = starts.count
    updateGutterWidthIfNeeded()
    needsDisplay = true
  }

  /// Binary-search for the 1-based line number that contains `charIndex`.
  func lineNumber(for charIndex: Int) -> Int {
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

  /// 1-based (line, column) for a character index — for the status bar.
  func lineColumn(at charIndex: Int) -> (line: Int, column: Int) {
    let line = lineNumber(for: charIndex)
    return (line, charIndex - lineStarts[line - 1] + 1)
  }

  // MARK: - Git markers

  func drawGitMarker(for line: Int, y: CGFloat, height: CGFloat) {
    let gitBarLeading: CGFloat = 2
    let gitBarWidth: CGFloat = 3
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

  // MARK: - Gutter drawing

  /// Paints the gutter background, line numbers, and git markers for the
  /// visible portion of the view.  Called from `draw(_:)` after super.
  ///
  /// NOTE: We use `visibleRect` rather than `dirtyRect` for the gutter area
  /// because NSTextView often only invalidates the text container region
  /// (starting at textContainerOrigin.x), which excludes the gutter margin.
  func drawGutter(in dirtyRect: NSRect) {
    let gw = _cachedGutterWidth
    guard gw > 0 else { return }

    // Always draw the full visible height of the gutter.
    let gutterDrawRect = NSRect(x: 0, y: visibleRect.minY, width: gw, height: visibleRect.height)

    // Gutter background
    NSColor(white: 0.09, alpha: 1).setFill()
    gutterDrawRect.fill()

    // Border on the right of the gutter
    NSColor(white: 0.18, alpha: 1).setFill()
    NSRect(x: gw - 1, y: gutterDrawRect.minY, width: 1, height: gutterDrawRect.height).fill()

    guard let lm = layoutManager, let tc = textContainer else { return }

    // Convert the visible rect from view coordinates into text-container
    // coordinates.  Clamp to non-negative values because
    // glyphRange(forBoundingRect:in:) returns an empty range for negative rects.
    let tcY = textContainerInset.height
    let containerVisibleRect = NSRect(
      x: 0,
      y: max(0, visibleRect.minY - tcY),
      width: tc.containerSize.width,
      height: visibleRect.height
    )
    let textRange = lm.glyphRange(forBoundingRect: containerVisibleRect, in: tc)
    guard textRange.length > 0 else { return }

    let curLine = lineNumber(for: selectedRange().location)

    let rightPadding: CGFloat = 8
    let font = self.font ?? .systemFont(ofSize: 12)
    let numberColor = NSColor(white: 0.42, alpha: 1)
    let currentColor = NSColor(white: 0.78, alpha: 1)

    lm.enumerateLineFragments(forGlyphRange: textRange) { fragRect, _, _, range, _ in
      let characterIndex = lm.characterIndexForGlyph(at: range.location)
      let lineNum = self.lineNumber(for: characterIndex)

      // Only draw the number for the first fragment of each logical line.
      if characterIndex == self.lineStarts[lineNum - 1] {
        let y = tcY + fragRect.minY
        let n = lineNum

        self.drawGitMarker(for: n, y: y, height: fragRect.height)

        let attrs: [NSAttributedString.Key: Any] = [
          .font: font,
          .foregroundColor: n == curLine ? currentColor : numberColor,
        ]
        let s = String(n) as NSString
        let size = s.size(withAttributes: attrs)
        let drawX = gw - size.width - rightPadding
        let drawY = y + (fragRect.height - size.height) / 2
        s.draw(at: NSPoint(x: drawX, y: drawY), withAttributes: attrs)
      }
    }
  }
}
