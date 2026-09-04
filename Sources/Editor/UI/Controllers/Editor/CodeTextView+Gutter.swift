import AppKit
import STTextView
import LineEnding

/// Line-index bookkeeping for CodeTextView, extracted into its own file.
///
/// MIGRATION NOTE (STTextView): line-number rendering and the gutter separator are now native
/// (`showsLineNumbers` on the text view — see EditorViewController.loadView). What remains here is:
///  - `lineStarts`/`lineNumber(for:)`/`lineColumn(at:)`: still used by the status bar (Ln/Col) and by
///    `centerSelection`, so kept as a lightweight character-offset index maintained on every edit.
///  - Git added/modified/deleted markers: STTextView's gutter doesn't expose a raw per-line draw hook
///    the way the old TextKit 1 `draw(_:)` override did, so they're painted by a small overlay view
///    (`GitGutterOverlayView`) docked to the left edge of `gutterView`.
extension CodeTextView {

  /// Pre-computed line-start character offsets (0-based). Index 0 is always 0.
  private static var lineStartsKey: UInt8 = 0
  private static var cachedLineCountKey: UInt8 = 0

  var lineStarts: [Int] {
    get { (objc_getAssociatedObject(self, &Self.lineStartsKey) as? [Int]) ?? [0] }
    set { objc_setAssociatedObject(self, &Self.lineStartsKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
  }

  var cachedLineCount: Int { lineStarts.count }

  /// Rebuilds the `lineStarts` array from scratch. Called after every text change and on initial load.
  func rebuildLineStarts() {
    let s = self.text ?? ""
    let counter = LineCounter(string: s)
    _ = counter.lineRange(at: s.utf16.count)
    var starts = [0]
    starts.reserveCapacity(counter.lineEndings.count + 1)
    for ending in counter.lineEndings {
      starts.append(ending.upperBound)
    }
    self.lineStarts = starts
    gutterOverlay?.needsDisplay = true
  }

  /// Binary-search for the 1-based line number that contains `charIndex`.
  func lineNumber(for charIndex: Int) -> Int {
    let starts = lineStarts
    var lo = 0
    var hi = starts.count - 1
    var ans = 0
    while lo <= hi {
      let mid = (lo + hi) / 2
      if starts[mid] <= charIndex {
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
}

/// Thin strip docked to the leading edge of STTextView's native gutter, painting the added/
/// modified/deleted bars that the old TextKit 1 gutter drew inline. Reads git line sets straight off
/// the owning `CodeTextView` and repaints when they, or the text layout, change.
final class GitGutterOverlayView: NSView {
  private weak var textView: CodeTextView?

  init(textView: CodeTextView) {
    self.textView = textView
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func draw(_ dirtyRect: NSRect) {
    guard let tv = textView, let gutter = tv.gutterView else { return }
    let barLeading: CGFloat = 1
    let barWidth: CGFloat = 3

    // Ask the gutter for the visible line fragments it already computed — reuse its layout pass
    // rather than re-querying the text layout manager, since STGutterView draws per visible line.
    tv.textLayoutManager.enumerateTextLayoutFragments(
      from: tv.textLayoutManager.documentRange.location, options: [.ensuresLayout]
    ) { fragment in
      let fragFrameInTextView = fragment.layoutFragmentFrame
      let fragFrameInGutter = self.convert(fragFrameInTextView, from: tv)
      guard fragFrameInGutter.maxY >= self.visibleRect.minY,
        fragFrameInGutter.minY <= self.visibleRect.maxY
      else {
        return fragFrameInGutter.minY <= self.visibleRect.maxY
      }

      let charRange = NSRange(fragment.rangeInElement, in: tv.textContentManager)
      let line = tv.lineNumber(for: charRange.location)
      let y = fragFrameInGutter.minY
      let h = fragFrameInGutter.height

      if tv.gitAddedLines.contains(line) {
        Theme.gitNew.setFill()
        NSBezierPath(rect: NSRect(x: barLeading, y: y, width: barWidth, height: h)).fill()
      } else if tv.gitModifiedLines.contains(line) {
        Theme.gitModified.setFill()
        NSBezierPath(rect: NSRect(x: barLeading, y: y, width: barWidth, height: h)).fill()
      } else if tv.gitDeletedLines.contains(line) {
        Theme.gitDeleted.setFill()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: barLeading, y: y))
        path.line(to: NSPoint(x: barLeading + barWidth, y: y + 3))
        path.line(to: NSPoint(x: barLeading, y: y + 6))
        path.close()
        path.fill()
      }
      return true
    }
  }
}
