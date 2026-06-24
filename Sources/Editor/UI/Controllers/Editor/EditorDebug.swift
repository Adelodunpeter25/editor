import AppKit

extension EditorViewController {

  // MARK: - DEV harness hooks

  /// Current editor text (for asserting load/edit/save without pixels).
  var debugText: String { textView?.string ?? "" }
  /// Scroll the editor down by `lines` (dev harness — to verify the gutter follows the scroll).
  func debugScroll(lines: Int) {
    guard let scroll = scrollView else { return }
    let clip = scroll.contentView
    let y = clip.bounds.origin.y + CGFloat(lines) * (lastFontSize + 4)
    clip.scroll(to: NSPoint(x: 0, y: max(0, y)))
    scroll.reflectScrolledClipView(clip)
  }
  var isDirty: Bool { (textView?.string ?? "") != saved }
  var debugIsFocused: Bool { textView?.window?.firstResponder === textView }
  /// Drive the custom find bar (dev harness — ⌘F + typing into the field is HID the harness can't synthesize).
  func debugFind(_ term: String) {
    showFind()
    findBar?.setQuery(term)
    findChanged()
  }
  func debugFindToggle(_ which: String) {
    findBar?.debugToggle(which)
    findChanged()
  }
  func debugFindNext() { findNext() }
  func debugReplaceShow() { showReplace() }
  func debugReplaceAll(_ with: String) {
    findBar?.setReplace(with)
    replaceAll()
  }
  func debugReplaceOne(_ with: String) {
    findBar?.setReplace(with)
    replaceCurrent()
  }
  var debugFindCount: Int { findMatches.count }
  var debugFindCurrent: Int { findCurrent }
  var debugHasCRLF: Bool { (textView?.string ?? "").contains("\r\n") }
  func debugConvertEol(_ eol: String) { convertLineEndings(to: eol) }
  /// The currently selected substring (dev harness — to verify a find landed on a match).
  var debugSelectedText: String {
    guard let tv = textView else { return "" }
    return (tv.string as NSString).substring(with: tv.selectedRange())
  }
  /// 1-based line of the caret/selection start (dev harness — to verify `:N` line jumps).
  var debugCaretLine: Int {
    guard let tv = textView else { return 0 }
    let ns = tv.string as NSString
    let loc = min(tv.selectedRange().location, ns.length)
    return (ns.substring(to: loc) as NSString).components(separatedBy: "\n").count
  }
  /// Append text (programmatic `.string` set doesn't fire the delegate, so flag dirty + re-highlight).
  func debugAppend(_ s: String) {
    textView.string += s
    onDirty(textView.string != saved)
    lineRuler.reload()  // programmatic `.string` set doesn't post NSText.didChangeNotification
    requestHighlight(debounced: true)
  }

  /// DEV: dump the applied foreground colour (hex) at the first non-blank char of each 1-based line in
  /// [from,to] — to diagnose highlighter scope desync (e.g. identifiers turning string-green).
  func debugLineColors(_ from: Int, _ to: Int) -> [String] {
    let ns = textView.string as NSString
    var out: [String] = []
    var lineNo = 0
    ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines]) {
      sub, range, _, stop in
      lineNo += 1
      guard lineNo >= from else { return }
      if lineNo > to {
        stop.pointee = true
        return
      }
      let line = sub ?? ""
      let lead = line.prefix { $0 == " " || $0 == "\t" }.count
      let loc = range.location + lead
      var hex = "(blank)"
      if loc < range.location + range.length,
        let col = self.textStorage.attribute(.foregroundColor, at: loc, effectiveRange: nil)
          as? NSColor,
        let s = col.usingColorSpace(.sRGB)
      {
        hex = String(
          format: "#%02X%02X%02X", Int(round(s.redComponent * 255)),
          Int(round(s.greenComponent * 255)), Int(round(s.blueComponent * 255)))
      }
      out.append("\(lineNo) \(hex)  \(line.trimmingCharacters(in: .whitespaces).prefix(34))")
    }
    return out
  }

  /// DEV: per-character colour runs for one 1-based line ("text⟦#hex⟧ …") — to see where a string opens.
  func debugColorRuns(_ line1: Int) -> String {
    let ns = textView.string as NSString
    var lineNo = 0
    var lineRange = NSRange(location: 0, length: 0)
    ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines]) {
      _, r, _, stop in
      lineNo += 1
      if lineNo == line1 {
        lineRange = r
        stop.pointee = true
      }
    }
    guard lineRange.length > 0 else { return "(no line \(line1))" }
    var runs: [String] = []
    var i = lineRange.location
    let end = NSMaxRange(lineRange)
    while i < end {
      var eff = NSRange()
      let col = textStorage.attribute(.foregroundColor, at: i, effectiveRange: &eff) as? NSColor
      let runEnd = min(NSMaxRange(eff), end)
      let txt = ns.substring(with: NSRange(location: i, length: runEnd - i))
      let hex =
        col.flatMap { $0.usingColorSpace(.sRGB) }.map {
          String(
            format: "#%02X%02X%02X", Int(round($0.redComponent * 255)),
            Int(round($0.greenComponent * 255)), Int(round($0.blueComponent * 255)))
        } ?? "none"
      runs.append("⟦\(txt)|\(hex)⟧")
      i = runEnd
    }
    return runs.joined()
  }
}
