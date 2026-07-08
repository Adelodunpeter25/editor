import AppKit
import LineEnding

extension CodeTextView {
  var gutterWidth: CGFloat {
    let digits = max(2, String(cachedLineCount).count)
    let digitWidth = ("8" as NSString).size(withAttributes: [.font: font ?? .systemFont(ofSize: 12)]).width
    let gitPadding: CGFloat = 2 + 3 + 4 // gitBarLeading + gitBarWidth + 4
    return ceil(digitWidth * CGFloat(digits)) + 12 + gitPadding // leftPadding=6, rightPadding=6
  }

  func adjustTextContainerWidth() {
    if let container = textContainer {
      let expectedWidth = bounds.width - gutterWidth - 12
      if container.containerSize.width != expectedWidth {
        container.containerSize = NSSize(width: expectedWidth, height: container.containerSize.height)
      }
    }
  }

  func resetGutterCursorRect() {
    let gutterRect = NSRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
    addCursorRect(gutterRect, cursor: .arrow)
  }

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
    self.needsLayout = true
    self.needsDisplay = true
  }

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

  func lineColumn(at charIndex: Int) -> (line: Int, column: Int) {
    let line = lineNumber(for: charIndex)
    return (line, charIndex - lineStarts[line - 1] + 1)
  }

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

  func drawGutter(in dirtyRect: NSRect) {
    let gutterRect = NSRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
    guard dirtyRect.intersects(gutterRect) else { return }
    let currentGutterRect = dirtyRect.intersection(gutterRect)

    // Gutter background
    NSColor(white: 0.09, alpha: 1).setFill()
    currentGutterRect.fill()

    // Border on the right of the gutter
    NSColor(white: 0.18, alpha: 1).setFill()
    NSRect(x: gutterWidth - 1, y: currentGutterRect.minY, width: 1, height: currentGutterRect.height).fill()

    guard let lm = layoutManager, let tc = textContainer else { return }

    // Map visible rect from text view coordinates to text container coordinates.
    // The text container is offset by (gutterWidth, textContainerInset.height).
    let tcOriginX = gutterWidth
    let tcOriginY = textContainerInset.height
    let textContainerVisibleRect = visibleRect.offsetBy(dx: -tcOriginX, dy: -tcOriginY)
    let textRange = lm.glyphRange(forBoundingRect: textContainerVisibleRect, in: tc)

    let curLine = lineNumber(for: selectedRange().location)
    let inset = tcOriginY

    let rightPadding: CGFloat = 8
    let font = self.font ?? .systemFont(ofSize: 12)
    let numberColor = NSColor(white: 0.42, alpha: 1)
    let currentColor = NSColor(white: 0.78, alpha: 1)

    lm.enumerateLineFragments(forGlyphRange: textRange) { fragRect, _, _, range, _ in
      let characterIndex = lm.characterIndexForGlyph(at: range.location)
      let lineNum = self.lineNumber(for: characterIndex)

      if characterIndex == self.lineStarts[lineNum - 1] {
        let y = inset + fragRect.minY
        let n = lineNum

        self.drawGitMarker(for: n, y: y, height: fragRect.height)

        let attrs: [NSAttributedString.Key: Any] = [
          .font: font,
          .foregroundColor: n == curLine ? currentColor : numberColor,
        ]
        let s = String(n) as NSString
        let size = s.size(withAttributes: attrs)
        let drawX = self.gutterWidth - size.width - rightPadding
        let drawY = y + (fragRect.height - size.height) / 2
        s.draw(at: NSPoint(x: drawX, y: drawY), withAttributes: attrs)
      }
    }
  }
}
