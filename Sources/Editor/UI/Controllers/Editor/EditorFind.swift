import AppKit
import STTextView
import TextFind

extension EditorViewController {

  /// Show the find bar (⌘F) in its floating panel, seeding it from the current one-line selection.
  func showFind() {
    guard let win = view.window else { return }
    if findBar == nil {
      let bar = FindBar(
        matchCase: settings.findMatchCase,
        wholeWord: settings.findWholeWord, regex: settings.findRegex)
      bar.onChange = { [weak self] in self?.findChanged() }
      bar.onNext = { [weak self] in self?.findStep(1) }
      bar.onPrev = { [weak self] in self?.findStep(-1) }
      bar.onClose = { [weak self] in self?.hideFind() }
      bar.onReplace = { [weak self] in self?.replaceCurrent() }
      bar.onReplaceAll = { [weak self] in self?.replaceAll() }
      bar.onResize = { [weak self] in self?.positionFindPanel() }  // replace row toggled → refit
      findBar = bar

      let panel = FindPanel(
        contentRect: NSRect(x: 0, y: 0, width: 360, height: 44),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered, defer: true)
      panel.isFloatingPanel = true
      panel.hidesOnDeactivate = false
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = true
      panel.contentView = bar
      findPanel = panel
    }
    guard let panel = findPanel else { return }
    if panel.parent == nil { win.addChildWindow(panel, ordered: .above) }
    positionFindPanel()
    let sel = textView.textSelection
    if sel.length > 0 {
      let s = ((textView.text ?? "") as NSString).substring(with: sel)
      if !s.contains("\n") { findBar?.setQuery(s) }
    }
    panel.makeKeyAndOrderFront(nil)
    findBar?.focusField()
    observeWindowForReposition(win)
    recomputeMatches()
  }

  func hideFind() {
    if let panel = findPanel {
      panel.parent?.removeChildWindow(panel)
      panel.orderOut(nil)
    }
    removeFindObservers()
    clearFindHighlights()
    findMatches = []
    findCurrent = -1
    textView.textSelection = NSRange(location: 0, length: 0)  // clear selection
    view.window?.makeKeyAndOrderFront(nil)  // return key to the main window
    view.window?.makeFirstResponder(textView)
  }

  /// Close the find panel if it's open — called when this editor's tab stops being active (so a stray
  /// floating bar doesn't linger over another tab).
  func hideFindIfShown() { if findVisible { hideFind() } }

  /// Size the panel to the bar and pin it to the editor view's top-right (in screen coords).
  func positionFindPanel() {
    guard let panel = findPanel, let bar = findBar, let win = view.window else { return }
    let size = bar.fittingSize
    panel.setContentSize(size)
    let inScreen = win.convertToScreen(view.convert(view.bounds, to: nil))
    let margin: CGFloat = 12
    panel.setFrameOrigin(
      NSPoint(
        x: inScreen.maxX - size.width - margin,
        y: inScreen.maxY - size.height - margin))
  }

  func observeWindowForReposition(_ win: NSWindow) {
    removeFindObservers()
    let nc = NotificationCenter.default
    for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
      findObservers.append(
        nc.addObserver(forName: name, object: win, queue: .main) { [weak self] _ in
          self?.positionFindPanel()
        })
    }
  }

  func removeFindObservers() {
    findObservers.forEach { NotificationCenter.default.removeObserver($0) }
    findObservers = []
  }

  /// ⌘G / ⌘⇧G — open the bar if closed, else step. (Works from the editor, not just the find field.)
  func findNext() { findVisible ? findStep(1) : showFind() }
  func findPrevious() { findVisible ? findStep(-1) : showFind() }

  /// ⌥⌘F — open find with the Replace row expanded.
  func showReplace() {
    showFind()
    findBar?.expandReplace()
  }

  /// Replace the current match, then advance (textDidChange re-runs the search → highlights refresh).
  func replaceCurrent() {
    guard let bar = findBar, findMatches.indices.contains(findCurrent) else { return }
    let r = findMatches[findCurrent]

    let mode: TextFind.Mode
    if bar.regex {
      var opts: NSRegularExpression.Options = []
      if !bar.matchCase { opts.insert(.caseInsensitive) }
      mode = .regularExpression(options: opts, unescapesReplacement: true)
    } else {
      var opts: NSString.CompareOptions = []
      if !bar.matchCase { opts.insert(.caseInsensitive) }
      mode = .textual(options: opts, fullWord: bar.wholeWord)
    }

    do {
      let textFind = try TextFind(
        for: textView.text ?? "",
        findString: bar.query,
        mode: mode,
        inSelection: false,
        selectedRanges: [r]
      )
      if let replacement = textFind.replace(with: bar.replaceText) {
        textView.replaceCharacters(inRange: replacement.range, with: replacement.value)
      }
    } catch {
      // Fallback to literal replacement
      textView.replaceCharacters(inRange: r, with: bar.replaceText)
    }
  }

  /// Replace every match in a single undoable edit (reverse order keeps the earlier ranges valid).
  func replaceAll() {
    guard let bar = findBar, !findMatches.isEmpty else { return }

    let mode: TextFind.Mode
    if bar.regex {
      var opts: NSRegularExpression.Options = []
      if !bar.matchCase { opts.insert(.caseInsensitive) }
      mode = .regularExpression(options: opts, unescapesReplacement: true)
    } else {
      var opts: NSString.CompareOptions = []
      if !bar.matchCase { opts.insert(.caseInsensitive) }
      mode = .textual(options: opts, fullWord: bar.wholeWord)
    }

    do {
      let textFind = try TextFind(
        for: textView.text ?? "",
        findString: bar.query,
        mode: mode,
        inSelection: false,
        selectedRanges: [textView.fullRange]
      )
      let (replacementItems, _) = textFind.replaceAll(with: bar.replaceText) { _, _, _ in }

      // Apply replacements in reverse order to keep ranges valid
      for item in replacementItems.reversed() {
        textView.replaceCharacters(inRange: item.range, with: item.value)
      }
    } catch {
      // Fallback to manual replacement
      let ns = (textView.text ?? "") as NSString
      let result = NSMutableString(string: ns)
      for r in findMatches.reversed() {
        result.replaceCharacters(in: r, with: bar.replaceText)
      }
      textView.replaceCharacters(inRange: textView.fullRange, with: result as String)
    }
  }

  /// ⌘E — search for the current selection.
  func useSelectionForFind() {
    showFind()
    let sel = textView.textSelection
    if sel.length > 0 {
      findBar?.setQuery(((textView.text ?? "") as NSString).substring(with: sel))
      findChanged()
    }
  }

  func findChanged() {
    guard let bar = findBar else { return }
    settings.findMatchCase = bar.matchCase  // persist the toggles (remembered across files/launches)
    settings.findWholeWord = bar.wholeWord
    settings.findRegex = bar.regex
    recomputeMatches()
  }

  func findStep(_ delta: Int) {
    guard !findMatches.isEmpty else { return }
    findCurrent = (findCurrent + delta + findMatches.count) % findMatches.count
    focusCurrentMatch(selectAndScroll: true)
  }

  func recomputeMatches() {
    guard let bar = findBar else { return }
    clearFindHighlights()
    findMatches = []
    bar.setInvalid(false)
    let full = textView.text ?? ""
    let q = bar.query
    guard !q.isEmpty else {
      findCurrent = -1
      bar.setCount(current: 0, total: 0)
      return
    }

    let mode: TextFind.Mode
    if bar.regex {
      var opts: NSRegularExpression.Options = []
      if !bar.matchCase { opts.insert(.caseInsensitive) }
      mode = .regularExpression(options: opts, unescapesReplacement: true)
    } else {
      var opts: NSString.CompareOptions = []
      if !bar.matchCase { opts.insert(.caseInsensitive) }
      mode = .textual(options: opts, fullWord: bar.wholeWord)
    }

    do {
      let textFind = try TextFind(
        for: full,
        findString: q,
        mode: mode,
        inSelection: false,
        selectedRanges: [NSRange(location: 0, length: (full as NSString).length)]
      )
      findMatches = try textFind.matches
    } catch {
      bar.setInvalid(true)
      findCurrent = -1
      bar.setCount(current: 0, total: 0)
      return
    }

    if findMatches.isEmpty {
      findCurrent = -1
      bar.setCount(current: 0, total: 0)
    } else {
      let caret = textView.textSelection.location
      findCurrent = findMatches.firstIndex { $0.location >= caret } ?? 0
      focusCurrentMatch(selectAndScroll: false)
    }
  }

  /// Repaint every match (yellow) + the current one (orange), select & center it, update the counter.
  ///
  /// MIGRATION NOTE (STTextView): the old code used `NSLayoutManager`'s *temporary* attributes
  /// (background highlight that doesn't touch the undo-relevant text storage). STTextView doesn't
  /// expose a temporary-attribute API, so this now uses `setAttributes` for the highlight colour and
  /// restores the base foreground colour afterwards. Because this only ever touches `.backgroundColor`
  /// (added, not replacing existing attributes) it should not disturb syntax-highlighting foreground
  /// colours or trigger undo — but this is the highest-risk spot to verify visually after migration,
  /// since a background-color add is not guaranteed cheap/non-invasive on every STTextView version.
  func focusCurrentMatch(selectAndScroll: Bool) {
    guard let bar = findBar, findMatches.indices.contains(findCurrent) else { return }
    clearFindHighlights()
    for r in findMatches {
      textView.addAttributes([.backgroundColor: Self.findHL], range: r)
    }
    let r = findMatches[findCurrent]
    textView.addAttributes([.backgroundColor: Self.findHLCurrent], range: r)
    if selectAndScroll {
      textView.textSelection = r
      centerSelection()
    }
    bar.setCount(current: findCurrent + 1, total: findMatches.count)
    // If we changed selection, it made the text view first responder, stealing focus from the find bar's
    // search field. Restore focus so the user can keep typing their query.
    if selectAndScroll, findVisible, let panel = findPanel {
      panel.makeKeyAndOrderFront(nil)
      panel.makeFirstResponder(bar.field)
    }
  }

  func clearFindHighlights() {
    guard textView != nil else { return }
    textView.removeAttribute(.backgroundColor, range: textView.fullRange)
  }
}
