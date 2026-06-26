import AppKit

extension EditorViewController {

  // MARK: - Highlighting

  /// Tokenize off the main thread and apply the resulting colours back on main. A full-document
  /// re-highlight keeps multi-line regions (strings/comments spanning the edit) correct; running it
  /// off-main means even a large file never blocks typing or scrolling. Edits coalesce via a 150 ms
  /// debounce, and a sequence number drops any pass that a newer edit has superseded.
  ///
  /// Optimisation: the text snapshot is taken on main (AppKit requires it), then the entire
  /// async highlight pipeline is dispatched to the background — the main thread is free the
  /// moment the snapshot is captured, so even the very first file open feels instant.
  func requestHighlight(debounced: Bool) {
    guard let highlighter else { return }
    highlightSeq += 1
    let seq = highlightSeq
    rehighlightWork?.cancel()

    // Snapshot text on main now (AppKit string is main-thread-only).
    let content = textView.string

    let work = DispatchWorkItem { [weak self] in
      guard let self, self.highlightSeq == seq else { return }
      Task { [weak self, highlighter] in
        let spans = await highlighter.spans(for: content)
        await MainActor.run { [weak self] in
          guard let self, self.highlightSeq == seq else { return }  // a newer edit won
          self.applySpans(spans, expecting: content)
        }
      }
    }
    rehighlightWork = work
    // Both debounced and immediate paths run on the highlight queue, not on main.
    // This keeps main free for the first paint (plain text) while colours are computed.
    let delay: DispatchTimeInterval = debounced ? .milliseconds(150) : .milliseconds(0)
    EditorViewController.highlightQueue.asyncAfter(deadline: .now() + delay, execute: work)
  }

  /// Recolour the storage from computed spans (text/selection/undo untouched). Skipped if the text
  /// changed since these spans were computed — a newer pass is already queued to cover it.
  func applySpans(_ spans: [(NSRange, NSColor)], expecting content: String) {
    let length = textStorage.length
    guard (content as NSString).length == length else { return }
    textStorage.beginEditing()
    textStorage.addAttribute(
      .foregroundColor, value: TreeSitterTheme.base, range: NSRange(location: 0, length: length))
    for (range, color) in spans where NSMaxRange(range) <= length {
      textStorage.addAttribute(.foregroundColor, value: color, range: range)
    }
    textStorage.endEditing()
  }

  func applyFont(_ size: Double) {
    guard lastFontSize != size else { return }
    lastFontSize = size
    let f = mono(size)
    textView.font = f
    textView.typingAttributes[.font] = f
    lineRuler.font = f  // gutter tracks the editor font size
    // Resize runs in place — DON'T re-tokenize. Only swap each run's font to the new size,
    // preserving bold/italic via the font manager.
    textStorage.beginEditing()
    let full = NSRange(location: 0, length: textStorage.length)
    textStorage.enumerateAttribute(.font, in: full) { value, range, _ in
      let resized = (value as? NSFont).map { NSFontManager.shared.convert($0, toSize: size) } ?? f
      textStorage.addAttribute(.font, value: resized, range: range)
    }
    textStorage.endEditing()
  }

  func mono(_ s: Double) -> NSFont { AppFont.mono(size: s) }
}
