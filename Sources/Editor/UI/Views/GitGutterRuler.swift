import AppKit

/// Git gutter indicators (VS Code-style): colored bars in the left margin showing added/modified/deleted
/// lines relative to HEAD. Green = added, blue = modified, red = deleted (triangle marker).
final class GitGutterRuler: NSRulerView {
    private weak var textView: NSTextView?
    private var filePath: String
    private var gitDiff: GitDiffResult?
    private var diffDirty = true
    
    private static let barWidth: CGFloat = 3
    
    init(scrollView: NSScrollView, textView: NSTextView, filePath: String) {
        self.textView = textView
        self.filePath = filePath
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 5
        
        // Redraw on scroll and text changes
        scrollView.contentView.postsBoundsChangedNotifications = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(viewDidScroll),
                       name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        nc.addObserver(self, selector: #selector(textDidChange),
                       name: NSText.didChangeNotification, object: textView)
        
        // Initial diff computation
        recomputeDiff()
    }
    
    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }
    
    deinit { NotificationCenter.default.removeObserver(self) }
    
    @objc private func viewDidScroll() { needsDisplay = true }
    @objc private func textDidChange() {
        diffDirty = true
        needsDisplay = true
    }
    
    /// Called when the file is saved or reloaded
    func reload() {
        diffDirty = true
        recomputeDiff()
        needsDisplay = true
    }
    
    /// Update the file path (for retargeting on rename)
    func updatePath(_ newPath: String) {
        filePath = newPath
        reload()
    }
    
    private func recomputeDiff() {
        guard diffDirty else { return }
        diffDirty = false
        
        // Run git diff off-main to avoid blocking
        let path = filePath
        let currentText = textView?.string ?? ""
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let diff = GitDiffComputer.computeDiff(for: path, currentText: currentText)
            DispatchQueue.main.async {
                self?.gitDiff = diff
                self?.needsDisplay = true
            }
        }
    }
    
    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let lm = textView.layoutManager,
              let diff = gitDiff else { return }
        
        TMTheme.background.setFill()
        bounds.fill()
        
        let visible = textView.visibleRect
        let inset = textView.textContainerInset.height
        let ns = textView.string as NSString
        
        // Draw added lines
        for lineNum in diff.addedLines {
            if let y = lineY(for: lineNum, lm: lm, ns: ns, visible: visible, inset: inset) {
                Theme.gitNew.setFill()
                NSBezierPath(rect: NSRect(x: 0, y: y, width: Self.barWidth, height: lineHeight(for: lineNum, lm: lm, ns: ns))).fill()
            }
        }
        
        // Draw modified lines
        for lineNum in diff.modifiedLines {
            if let y = lineY(for: lineNum, lm: lm, ns: ns, visible: visible, inset: inset) {
                Theme.gitModified.setFill()
                NSBezierPath(rect: NSRect(x: 0, y: y, width: Self.barWidth, height: lineHeight(for: lineNum, lm: lm, ns: ns))).fill()
            }
        }
        
        // Draw deleted line markers (small triangles)
        for lineNum in diff.deletedLines {
            if let y = lineY(for: lineNum, lm: lm, ns: ns, visible: visible, inset: inset) {
                Theme.gitDeleted.setFill()
                let path = NSBezierPath()
                path.move(to: NSPoint(x: 0, y: y))
                path.line(to: NSPoint(x: Self.barWidth, y: y + 3))
                path.line(to: NSPoint(x: 0, y: y + 6))
                path.close()
                path.fill()
            }
        }
    }
    
    /// Get the viewport Y coordinate for a 1-based line number
    private func lineY(for lineNum: Int, lm: NSLayoutManager, ns: NSString, visible: NSRect, inset: CGFloat) -> CGFloat? {
        guard lineNum > 0 else { return nil }
        let charIndex = charIndexForLine(lineNum, ns: ns)
        guard charIndex < ns.length else { return nil }
        
        let glyphIndex = lm.glyphIndexForCharacter(at: charIndex)
        let fragRect = lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let y = inset + fragRect.minY - visible.minY
        
        // Only draw if visible
        guard y >= -fragRect.height && y <= visible.height else { return nil }
        return y
    }
    
    /// Get line height for a 1-based line number
    private func lineHeight(for lineNum: Int, lm: NSLayoutManager, ns: NSString) -> CGFloat {
        guard lineNum > 0 else { return 0 }
        let charIndex = charIndexForLine(lineNum, ns: ns)
        guard charIndex < ns.length else { return lm.extraLineFragmentRect.height }
        
        let glyphIndex = lm.glyphIndexForCharacter(at: charIndex)
        return lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil).height
    }
    
    /// Convert 1-based line number to character index
    private func charIndexForLine(_ lineNum: Int, ns: NSString) -> Int {
        var idx = 0
        var current = 1
        while current < lineNum && idx < ns.length {
            let r = ns.range(of: "\n", range: NSRange(location: idx, length: ns.length - idx))
            if r.location == NSNotFound { break }
            idx = r.location + 1
            current += 1
        }
        return idx
    }
}

/// Git diff result: which lines are added/modified/deleted
struct GitDiffResult {
    var addedLines: Set<Int> = []
    var modifiedLines: Set<Int> = []
    var deletedLines: Set<Int> = []  // line number where deletion occurred
}

/// Computes git diff for a file
enum GitDiffComputer {
    static func computeDiff(for path: String, currentText: String) -> GitDiffResult {
        var result = GitDiffResult()
        
        // Get the HEAD version of the file
        guard let headContent = getHeadContent(for: path) else { return result }
        
        // Split into lines
        let headLines = headContent.components(separatedBy: "\n")
        let currentLines = currentText.components(separatedBy: "\n")
        
        // Simple line-by-line diff (this is a basic implementation)
        // For production, you'd want to use a proper diff algorithm like Myers
        let maxLines = max(headLines.count, currentLines.count)
        
        for i in 0..<maxLines {
            let lineNum = i + 1
            
            if i >= headLines.count {
                // Line added
                result.addedLines.insert(lineNum)
            } else if i >= currentLines.count {
                // Line deleted
                result.deletedLines.insert(lineNum)
            } else if headLines[i] != currentLines[i] {
                // Line modified
                result.modifiedLines.insert(lineNum)
            }
        }
        
        return result
    }
    
    private static func getHeadContent(for path: String) -> String? {
        // Get git repo root
        guard let repoRoot = getGitRoot(for: path) else { return nil }
        
        // Get relative path from repo root
        let relativePath = path.hasPrefix(repoRoot) ? String(path.dropFirst(repoRoot.count + 1)) : path
        
        // Run git show HEAD:path
        let task = Process()
        task.currentDirectoryURL = URL(fileURLWithPath: repoRoot)
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["show", "HEAD:\(relativePath)"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            
            guard task.terminationStatus == 0 else { return nil }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
    
    private static func getGitRoot(for path: String) -> String? {
        let dir = (path as NSString).deletingLastPathComponent
        let task = Process()
        task.currentDirectoryURL = URL(fileURLWithPath: dir)
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["rev-parse", "--show-toplevel"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            
            guard task.terminationStatus == 0 else { return nil }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
