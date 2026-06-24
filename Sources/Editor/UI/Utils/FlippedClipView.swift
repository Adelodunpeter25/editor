import AppKit

/// Flipped clip view so the stack lays out top-down inside a scroll view.
final class FlippedClipView: NSClipView {
  override var isFlipped: Bool { true }
}
