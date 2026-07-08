import AppKit
import LineEnding

enum EditMode {
  case normal
  case insert
}

/// NSTextView subclass that intercepts Cmd+S to save and adds "Format Document" to the right-click menu.
/// Also implements a simplified vim mode: starts in normal mode (read-only), press 'i' to enter insert mode,
/// press Escape to return to normal mode. Prevents accidental edits while allowing navigation/selection.
/// Now also draws the line-number gutter directly inside the view to guarantee smooth GPU-accelerated scrolling.
final class CodeTextView: NSTextView {
  var onSave: (() -> Void)?
  var onFormat: (() -> Void)?
  var onModeChange: ((EditMode) -> Void)?
  
  var editMode: EditMode = .normal {
    didSet {
      updateCursor()
      onModeChange?(editMode)
    }
  }

  // MARK: - Gutter State & Properties
  var lineStarts: [Int] = [0]
  var cachedLineCount: Int = 1
  var gitAddedLines: Set<Int> = [] { didSet { needsDisplay = true } }
  var gitModifiedLines: Set<Int> = [] { didSet { needsDisplay = true } }
  var gitDeletedLines: Set<Int> = [] { didSet { needsDisplay = true } }

  var gutterWidth: CGFloat {
    let digits = max(2, String(cachedLineCount).count)
    let digitWidth = ("8" as NSString).size(withAttributes: [.font: font ?? .systemFont(ofSize: 12)]).width
    let gitPadding: CGFloat = 2 + 3 + 4 // gitBarLeading + gitBarWidth + 4
    return ceil(digitWidth * CGFloat(digits)) + 12 + gitPadding // leftPadding=6, rightPadding=6
  }

  override var textContainerOrigin: NSPoint {
    let origin = super.textContainerOrigin
    return NSPoint(x: gutterWidth, y: origin.y)
  }

  override func layout() {
    super.layout()
    if let container = textContainer {
      let expectedWidth = bounds.width - gutterWidth - 12 // 12 for right padding
      if container.containerSize.width != expectedWidth {
        container.containerSize = NSSize(width: expectedWidth, height: container.containerSize.height)
      }
    }
  }

  override func resetCursorRects() {
    super.resetCursorRects()
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

  /// 1-based (line, column) for a character index — for the status bar.
  func lineColumn(at charIndex: Int) -> (line: Int, column: Int) {
    let line = lineNumber(for: charIndex)
    return (line, charIndex - lineStarts[line - 1] + 1)
  }

  private func drawGitMarker(for line: Int, y: CGFloat, height: CGFloat) {
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

  override func didChangeText() {
    super.didChangeText()
    rebuildLineStarts()
  }

  override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
    super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    
    let gutterRect = NSRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
    if dirtyRect.intersects(gutterRect) {
      let currentGutterRect = dirtyRect.intersection(gutterRect)
      // Gutter background
      NSColor(white: 0.09, alpha: 1).setFill()
      currentGutterRect.fill()
      
      // Border on the right of the gutter
      NSColor(white: 0.18, alpha: 1).setFill()
      NSRect(x: gutterWidth - 1, y: currentGutterRect.minY, width: 1, height: currentGutterRect.height).fill()
      
      guard let lm = layoutManager, let tc = textContainer else { return }
      let visible = visibleRect
      let textRange = lm.glyphRange(forBoundingRect: visible, in: tc)
      let curLine = lineNumber(for: selectedRange().location)
      let inset = textContainerInset.height
      
      let rightPadding: CGFloat = 8
      let font = self.font ?? .systemFont(ofSize: 12)
      let numberColor = NSColor(white: 0.42, alpha: 1)
      let currentColor = NSColor(white: 0.78, alpha: 1)
      
      lm.enumerateLineFragments(forGlyphRange: textRange) { [weak self] fragRect, _, _, range, _ in
        guard let self else { return }
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

  override func menu(for event: NSEvent) -> NSMenu? {
    let menu = super.menu(for: event) ?? NSMenu()
    let item = NSMenuItem(
      title: "Format Document", action: #selector(formatFromMenu), keyEquivalent: "")
    item.target = self
    menu.insertItem(item, at: 0)
    menu.insertItem(.separator(), at: 1)
    return menu
  }
  @objc private func formatFromMenu() { onFormat?() }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.modifierFlags.contains(.command),
      event.charactersIgnoringModifiers?.lowercased() == "s"
    {
      onSave?()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
  
  override func keyDown(with event: NSEvent) {
    // Handle mode switching
    if editMode == .normal {
      // 'i' enters insert mode
      if event.charactersIgnoringModifiers?.lowercased() == "i" && 
         event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
        editMode = .insert
        return
      }
      
      // Escape does nothing in normal mode (already there)
      if event.keyCode == 53 { // Escape key
        return
      }
      
      // Allow navigation keys, selection, and standard editing shortcuts
      let isNavigation = (event.keyCode >= 123 && event.keyCode <= 126) || // Arrow keys
                         event.charactersIgnoringModifiers?.lowercased() == "h" ||
                         event.charactersIgnoringModifiers?.lowercased() == "j" ||
                         event.charactersIgnoringModifiers?.lowercased() == "k" ||
                         event.charactersIgnoringModifiers?.lowercased() == "l"
      
      let isSelection = event.modifierFlags.contains(.shift)
      let isStandardShortcut = event.modifierFlags.contains(.command) || 
                               event.modifierFlags.contains(.control)
      
      if isNavigation || isSelection || isStandardShortcut {
        super.keyDown(with: event)
        return
      }
      
      // Block all other character input in normal mode
      return
    }
    
    // In insert mode, handle Escape to return to normal mode
    if event.keyCode == 53 { // Escape key
      editMode = .normal
      return
    }
    
    // Normal typing in insert mode
    super.keyDown(with: event)
  }
  
  private func updateCursor() {
    insertionPointColor = .white
    // Force redraw of the insertion point
    setNeedsDisplay(visibleRect, avoidAdditionalLayout: false)
  }
  
  override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn: Bool) {
    if turnedOn {
      let blockColor = color.withAlphaComponent(0.5)
      blockColor.setFill()
      
      var blockRect = rect.integral
      let cellWidth = max(2, ceil(font?.maximumAdvancement.width ?? 8))
      let cellHeight = max(blockRect.height, ceil(layoutManager?.defaultLineHeight(for: font ?? .systemFont(ofSize: 12)) ?? 14))
      blockRect.size.width = cellWidth + 2
      blockRect.size.height = cellHeight
      NSBezierPath(rect: blockRect).fill()
      return
    }
    
    super.drawInsertionPoint(in: rect, color: color, turnedOn: turnedOn)
  }
}
