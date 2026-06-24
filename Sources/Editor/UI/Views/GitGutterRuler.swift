import AppKit

/// Computes editor git gutter data and pushes it into the line-number ruler.
final class GitGutterRuler: NSObject {
  private weak var textView: NSTextView?
  private var filePath: String
  private var diffDirty = true
  var onChange: ((GitDiffResult) -> Void)?

  init(scrollView: NSScrollView, textView: NSTextView, filePath: String) {
    self.textView = textView
    self.filePath = filePath
    super.init()

    scrollView.contentView.postsBoundsChangedNotifications = true
    let nc = NotificationCenter.default
    nc.addObserver(
      self, selector: #selector(textDidChange),
      name: NSText.didChangeNotification, object: textView)

    recomputeDiff()
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  @objc private func textDidChange() {
    diffDirty = true
    recomputeDiff()
  }

  func reload() {
    diffDirty = true
    recomputeDiff()
  }

  func updatePath(_ newPath: String) {
    filePath = newPath
    reload()
  }

  private func recomputeDiff() {
    guard diffDirty else { return }
    diffDirty = false

    let path = filePath
    let currentText = textView?.string ?? ""
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let diff = GitDiffComputer.computeDiff(for: path, currentText: currentText)
      DispatchQueue.main.async {
        self?.onChange?(diff)
      }
    }
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
    guard let repoRoot = getGitRoot(for: path) else { return nil }
    let relativePath = path.hasPrefix(repoRoot) ? String(path.dropFirst(repoRoot.count + 1)) : path
    let gitPath = Env.resolve("git")
    let output = Shell.run(gitPath, ["-C", repoRoot, "show", "HEAD:\(relativePath)"])
    return output.isEmpty ? nil : output
  }

  private static func getGitRoot(for path: String) -> String? {
    let dir = (path as NSString).deletingLastPathComponent
    let gitPath = Env.resolve("git")
    let output = Shell.run(gitPath, ["-C", dir, "rev-parse", "--show-toplevel"])
    return output.isEmpty ? nil : output
  }
}
