import AppKit

extension EditorViewController {

  /// Format the current file with its configured formatter (⇧⌥F / right-click). Runs off-main; applies
  /// the result preserving the cursor + a single undo, or surfaces a not-installed / error prompt.
  func formatDocument() {
    let p = path
    if let spec = Formatter.spec(forPath: p), !settings.formatterEnabled(spec.id) {
      FormatterPrompt.disabled(spec)
      return
    }
    let text = textView.string
    EditorViewController.formatQueue.async {
      let outcome = Formatter.format(text: text, path: p)
      DispatchQueue.main.async { [weak self] in self?.applyFormat(outcome, expecting: text) }
    }
  }

  func applyFormat(_ outcome: Formatter.Outcome, expecting original: String) {
    // The user may have typed while the formatter ran — don't clobber newer edits.
    guard textView.string == original else { return }
    switch outcome {
    case .formatted(let newText): replacePreservingCursor(with: newText)
    case .unchanged: break
    case .noFormatter(let ext): FormatterPrompt.noFormatter(ext: ext)
    case .notInstalled(let spec): FormatterPrompt.notInstalled(spec)
    case .failed(let message): FormatterPrompt.failed(message)
    }
  }

  /// Replace the whole document with `newText` but only edit the changed middle (common prefix/suffix
  /// preserved), so the cursor stays put and it's one undo step.
  func replacePreservingCursor(with newText: String) {
    let old = textView.string as NSString
    let new = newText as NSString
    let maxPrefix = min(old.length, new.length)
    var prefix = 0
    while prefix < maxPrefix, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
    var suffix = 0
    while suffix < (maxPrefix - prefix),
      old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix)
    { suffix += 1 }

    let replaceRange = NSRange(location: prefix, length: old.length - prefix - suffix)
    let replacement = new.substring(
      with: NSRange(location: prefix, length: new.length - prefix - suffix))
    guard textView.shouldChangeText(in: replaceRange, replacementString: replacement) else {
      return
    }
    textView.textStorage?.replaceCharacters(in: replaceRange, with: replacement)
    textView.didChangeText()  // fires textDidChange → dirty flag, re-highlight, gutter reload

    // Keep the caret sensible: before the edit → unchanged; after it → shift by the length delta;
    // inside it → land at the edit's end.
    let delta = (replacement as NSString).length - replaceRange.length
    var loc = textView.selectedRange().location
    if loc >= NSMaxRange(replaceRange) {
      loc += delta
    } else if loc > replaceRange.location {
      loc = replaceRange.location + (replacement as NSString).length
    }
    textView.setSelectedRange(NSRange(location: max(0, min(loc, new.length)), length: 0))
  }
}
