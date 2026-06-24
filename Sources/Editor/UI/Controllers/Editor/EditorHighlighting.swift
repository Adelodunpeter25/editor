import AppKit

extension EditorViewController {

  // MARK: - Highlighting

  /// Tokenize off the main thread and apply the resulting colours back on main. A full-document
  /// re-highlight keeps multi-line regions (strings/comments spanning the edit) correct; running it
  /// off-main means even a large file never blocks typing or scrolling. Edits coalesce via a 150 ms
  /// debounce, and a sequence number drops any pass that a newer edit has superseded.
  func requestHighlight(debounced: Bool) {
    guard let highlighter else { return }
    highlightSeq += 1
    let seq = highlightSeq
    rehighlightWork?.cancel()
    // Initial open of a small file: tokenize synchronously so it appears already-coloured (no
    // plain-text flash). Safe on main because the grammar's regexes are precompiled. Large files
    // and all edits go off-main below.
    if !debounced, (textView.string as NSString).length <= 20_000 {
      let content = textView.string
      applySpans(highlighter.spans(for: content), expecting: content)
      return
    }
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      let content = self.textView.string
      EditorViewController.highlightQueue.async {
        let spans = highlighter.spans(for: content)
        DispatchQueue.main.async { [weak self] in
          guard let self, self.highlightSeq == seq else { return }  // a newer edit won
          self.applySpans(spans, expecting: content)
        }
      }
    }
    rehighlightWork = work
    if debounced {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    } else {
      work.perform()
    }
  }

  /// Recolour the storage from computed spans (text/selection/undo untouched). Skipped if the text
  /// changed since these spans were computed — a newer pass is already queued to cover it.
  func applySpans(_ spans: [(NSRange, NSColor)], expecting content: String) {
    let length = textStorage.length
    guard (content as NSString).length == length else { return }
    textStorage.beginEditing()
    textStorage.addAttribute(
      .foregroundColor, value: TMTheme.base, range: NSRange(location: 0, length: length))
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
