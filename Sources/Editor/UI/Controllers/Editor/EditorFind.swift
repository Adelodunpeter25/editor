import AppKit

extension EditorViewController {

    /// Show the find bar (⌘F) in its floating panel, seeding it from the current one-line selection.
    func showFind() {
        guard let win = view.window else { return }
        if findBar == nil {
            let bar = FindBar(matchCase: settings.findMatchCase,
                              wholeWord: settings.findWholeWord, regex: settings.findRegex)
            bar.onChange = { [weak self] in self?.findChanged() }
            bar.onNext = { [weak self] in self?.findStep(1) }
            bar.onPrev = { [weak self] in self?.findStep(-1) }
            bar.onClose = { [weak self] in self?.hideFind() }
            bar.onReplace = { [weak self] in self?.replaceCurrent() }
            bar.onReplaceAll = { [weak self] in self?.replaceAll() }
            bar.onResize = { [weak self] in self?.positionFindPanel() }   // replace row toggled → refit
            findBar = bar

            let panel = FindPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 44),
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
        let sel = textView.selectedRange()
        if sel.length > 0 {
            let s = (textView.string as NSString).substring(with: sel)
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
        findMatches = []; findCurrent = -1
        view.window?.makeKeyAndOrderFront(nil)        // return key to the main window
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
        panel.setFrameOrigin(NSPoint(x: inScreen.maxX - size.width - margin,
                                     y: inScreen.maxY - size.height - margin))
    }

    func observeWindowForReposition(_ win: NSWindow) {
        removeFindObservers()
        let nc = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            findObservers.append(nc.addObserver(forName: name, object: win, queue: .main) { [weak self] _ in
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
    func showReplace() { showFind(); findBar?.expandReplace() }

    /// Replace the current match, then advance (textDidChange re-runs the search → highlights refresh).
    func replaceCurrent() {
        guard let bar = findBar, findMatches.indices.contains(findCurrent) else { return }
        let r = findMatches[findCurrent]
        let replacement = expandedReplacement(for: r, bar: bar)
        if textView.shouldChangeText(in: r, replacementString: replacement) {
            textView.textStorage?.replaceCharacters(in: r, with: replacement)
            textView.didChangeText()
        }
    }

    /// Replace every match in a single undoable edit (reverse order keeps the earlier ranges valid).
    func replaceAll() {
        guard let bar = findBar, !findMatches.isEmpty else { return }
        let ns = textView.string as NSString
        let result = NSMutableString(string: ns)
        for r in findMatches.reversed() {
            result.replaceCharacters(in: r, with: expandedReplacement(for: r, bar: bar))
        }
        let full = NSRange(location: 0, length: ns.length)
        if textView.shouldChangeText(in: full, replacementString: result as String) {
            textView.textStorage?.replaceCharacters(in: full, with: result as String)
            textView.didChangeText()
        }
    }

    /// In regex mode, expand `$1`-style templates against the matched text; otherwise a literal replacement.
    func expandedReplacement(for range: NSRange, bar: FindBar) -> String {
        guard bar.regex else { return bar.replaceText }
        var opts: NSRegularExpression.Options = []
        if !bar.matchCase { opts.insert(.caseInsensitive) }
        let pattern = bar.wholeWord ? "\\b(?:\(bar.query))\\b" : bar.query
        guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return bar.replaceText }
        let matched = (textView.string as NSString).substring(with: range)
        return re.stringByReplacingMatches(in: matched, range: NSRange(location: 0, length: (matched as NSString).length),
                                           withTemplate: bar.replaceText)
    }

    /// ⌘E — search for the current selection.
    func useSelectionForFind() {
        showFind()
        let sel = textView.selectedRange()
        if sel.length > 0 {
            findBar?.setQuery((textView.string as NSString).substring(with: sel))
            findChanged()
        }
    }

    func findChanged() {
        guard let bar = findBar else { return }
        settings.findMatchCase = bar.matchCase   // persist the toggles (remembered across files/launches)
        settings.findWholeWord = bar.wholeWord
        settings.findRegex = bar.regex
        recomputeMatches()
    }

    func findStep(_ delta: Int) {
        guard !findMatches.isEmpty else { return }
        findCurrent = (findCurrent + delta + findMatches.count) % findMatches.count
        focusCurrentMatch()
    }

    func recomputeMatches() {
        guard let bar = findBar else { return }
        clearFindHighlights()
        findMatches = []
        bar.setInvalid(false)
        let full = textView.string
        let ns = full as NSString
        let q = bar.query
        guard !q.isEmpty else { findCurrent = -1; bar.setCount(current: 0, total: 0); return }

        if bar.regex {
            var opts: NSRegularExpression.Options = []
            if !bar.matchCase { opts.insert(.caseInsensitive) }
            let pattern = bar.wholeWord ? "\\b(?:\(q))\\b" : q
            guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else {
                bar.setInvalid(true); findCurrent = -1; bar.setCount(current: 0, total: 0); return
            }
            re.enumerateMatches(in: full, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                if let r = m?.range, r.length > 0 { findMatches.append(r) }
            }
        } else {
            var opts: NSString.CompareOptions = []
            if !bar.matchCase { opts.insert(.caseInsensitive) }
            var from = 0
            while from < ns.length {
                let r = ns.range(of: q, options: opts, range: NSRange(location: from, length: ns.length - from))
                if r.location == NSNotFound { break }
                if !bar.wholeWord || isWholeWord(r, ns) { findMatches.append(r) }
                from = r.location + max(1, r.length)
            }
        }

        if findMatches.isEmpty {
            findCurrent = -1; bar.setCount(current: 0, total: 0)
        } else {
            let caret = textView.selectedRange().location
            findCurrent = findMatches.firstIndex { $0.location >= caret } ?? 0
            focusCurrentMatch()
        }
    }

    /// Repaint every match (yellow) + the current one (orange), select & center it, update the counter.
    func focusCurrentMatch() {
        guard let lm = textView.layoutManager, let bar = findBar,
              findMatches.indices.contains(findCurrent) else { return }
        lm.removeTemporaryAttribute(.backgroundColor,
            forCharacterRange: NSRange(location: 0, length: (textView.string as NSString).length))
        for r in findMatches { lm.addTemporaryAttribute(.backgroundColor, value: Self.findHL, forCharacterRange: r) }
        let r = findMatches[findCurrent]
        lm.addTemporaryAttribute(.backgroundColor, value: Self.findHLCurrent, forCharacterRange: r)
        textView.setSelectedRange(r)
        centerSelection()
        bar.setCount(current: findCurrent + 1, total: findMatches.count)
    }

    func clearFindHighlights() {
        guard let lm = textView?.layoutManager else { return }
        lm.removeTemporaryAttribute(.backgroundColor,
            forCharacterRange: NSRange(location: 0, length: (textView.string as NSString).length))
    }

    func isWholeWord(_ r: NSRange, _ s: NSString) -> Bool {
        func word(_ c: unichar) -> Bool {
            guard let u = UnicodeScalar(c) else { return false }
            return CharacterSet.alphanumerics.contains(u) || u == "_"
        }
        let before = r.location > 0 ? word(s.character(at: r.location - 1)) : false
        let afterIdx = r.location + r.length
        let after = afterIdx < s.length ? word(s.character(at: afterIdx)) : false
        return !before && !after
    }
}
