import AppKit
import STTextView

/// MIGRATION NOTE (STTextView): the old TextKit 1 editor did all edits with `NSRange` directly against
/// `NSTextStorage`. STTextView's `shouldChangeText`/`replaceCharacters` are TextKit 2 APIs that take
/// `NSTextRange` (an opaque, content-manager-relative range) rather than a plain character-offset
/// `NSRange`. These helpers translate between the two so the rest of the editor code (find/replace,
/// formatting, line-ending/indent conversion) can keep working in the `NSRange` terms the app already
/// uses everywhere else (status bar, TextFind, gutter line index).
extension STTextView {
  /// The document's full character range, as an `NSRange` (offsets into `text`/`attributedText`).
  var fullRange: NSRange {
    NSRange(location: 0, length: (text as NSString?)?.length ?? 0)
  }

  private func textRange(for range: NSRange) -> NSTextRange? {
    guard
      let start = textContentManager.location(
        textContentManager.documentRange.location, offsetBy: range.location),
      let end = textContentManager.location(start, offsetBy: range.length)
    else { return nil }
    return NSTextRange(location: start, end: end)
  }

  /// Replaces `range` with `replacement`, wrapped in `shouldChangeText`/`didChangeText` so it's a
  /// normal undoable edit — the direct equivalent of the old
  /// `textStorage?.replaceCharacters(in:with:); didChangeText()` pattern.
  @discardableResult
  func replaceCharacters(inRange range: NSRange, with replacement: String) -> Bool {
    guard let textRange = textRange(for: range) else { return false }
    guard shouldChangeText(in: textRange, replacementString: replacement) else { return false }
    replaceCharacters(in: textRange, with: replacement)
    return true
  }
}
