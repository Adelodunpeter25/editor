import AppKit

final class MinimapView: NSView {
  private weak var scrollView: NSScrollView?
  private weak var textView: NSTextView?

  override var isFlipped: Bool { true }

  init(scrollView: NSScrollView, textView: NSTextView) {
    self.scrollView = scrollView
    self.textView = textView
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = Theme.panelBg.cgColor

    scrollView.contentView.postsBoundsChangedNotifications = true
    let nc = NotificationCenter.default
    nc.addObserver(
      self, selector: #selector(invalidate),
      name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    nc.addObserver(
      self, selector: #selector(invalidate),
      name: NSText.didChangeNotification, object: textView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  deinit { NotificationCenter.default.removeObserver(self) }

  @objc private func invalidate() { needsDisplay = true }

  override func draw(_ dirtyRect: NSRect) {
    Theme.panelBg.setFill()
    bounds.fill()

    guard let textView, let scrollView else { return }
    let lines = textView.string.components(separatedBy: "\n")
    let lineCount = max(1, lines.count)
    let bucketCount = max(1, Int(bounds.height))
    let bucketSize = max(1, Int(ceil(Double(lineCount) / Double(bucketCount))))
    let availableWidth = max(8, bounds.width - 8)

    Theme.textDim.withAlphaComponent(0.55).setFill()
    for start in stride(from: 0, to: lineCount, by: bucketSize) {
      let end = min(lineCount, start + bucketSize)
      var maxChars = 0
      for i in start..<end { maxChars = max(maxChars, lines[i].count) }
      guard maxChars > 0 else { continue }
      let y = CGFloat(start) / CGFloat(lineCount) * bounds.height
      let h = max(1, CGFloat(end - start) / CGFloat(lineCount) * bounds.height)
      let w = max(2, min(availableWidth, availableWidth * min(CGFloat(maxChars) / 120, 1)))
      NSBezierPath(rect: NSRect(x: 4, y: y, width: w, height: h)).fill()
    }

    let docHeight = max(textView.bounds.height, scrollView.contentView.bounds.height)
    guard docHeight > 0 else { return }
    let visible = textView.visibleRect
    let viewportY = visible.minY / docHeight * bounds.height
    let viewportH = max(18, visible.height / docHeight * bounds.height)
    let viewport = NSRect(x: 1, y: viewportY, width: bounds.width - 2, height: min(bounds.height - viewportY, viewportH))
    Theme.activeRowBg.setFill()
    NSBezierPath(rect: viewport).fill()
    Theme.borderLight.withAlphaComponent(0.8).setStroke()
    NSBezierPath(rect: viewport.insetBy(dx: 0.5, dy: 0.5)).stroke()
  }

  override func mouseDown(with event: NSEvent) {
    scroll(to: convert(event.locationInWindow, from: nil).y)
  }

  override func mouseDragged(with event: NSEvent) {
    scroll(to: convert(event.locationInWindow, from: nil).y)
  }

  private func scroll(to y: CGFloat) {
    guard let textView, let scrollView else { return }
    let docHeight = max(textView.bounds.height, scrollView.contentView.bounds.height)
    let visibleHeight = scrollView.contentView.bounds.height
    guard docHeight > visibleHeight else { return }
    let ratio = max(0, min(1, y / max(1, bounds.height)))
    let targetY = max(0, min(docHeight - visibleHeight, ratio * docHeight - visibleHeight / 2))
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
    scrollView.reflectScrolledClipView(scrollView.contentView)
  }
}
