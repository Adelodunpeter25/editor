import AppKit

/// Computes editor git gutter data and pushes it into the line-number ruler.
final class GitGutterRuler: NSObject {
  private weak var textView: NSTextView?
  private var filePath: String
  private var diffDirty = true
  private var recomputeWork: DispatchWorkItem?
  private var diffSeq = 0
  private var headContent: String?
  var onChange: ((GitGutterChangeSet) -> Void)?

  init(scrollView: NSScrollView, textView: NSTextView, filePath: String) {
    self.textView = textView
    self.filePath = filePath
    super.init()

    scrollView.contentView.postsBoundsChangedNotifications = true
    let nc = NotificationCenter.default
    nc.addObserver(
      self, selector: #selector(textDidChange),
      name: NSText.didChangeNotification, object: textView)

    scheduleRecompute(debounced: false)
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  @objc private func textDidChange() {
    diffDirty = true
    scheduleRecompute(debounced: true)
  }

  func reload() {
    diffDirty = true
    scheduleRecompute(debounced: false)
  }

  func updatePath(_ newPath: String) {
    filePath = newPath
    headContent = nil
    reload()
  }

  private func scheduleRecompute(debounced: Bool) {
    recomputeWork?.cancel()
    diffSeq += 1
    let seq = diffSeq
    let work = DispatchWorkItem { [weak self] in self?.recomputeDiff(seq: seq) }
    recomputeWork = work
    if debounced {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    } else {
      DispatchQueue.main.async(execute: work)
    }
  }

  private func recomputeDiff(seq: Int) {
    guard diffDirty else { return }
    diffDirty = false

    let path = filePath
    let currentText = textView?.string ?? ""
    let cachedHead = headContent
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let head = cachedHead ?? Git.headText(forAbsolutePath: path)
      let diff = GitDiff.gutterChanges(head: head, current: currentText)
      DispatchQueue.main.async {
        guard let self, seq == self.diffSeq else { return }
        if self.headContent == nil { self.headContent = head }
        self.onChange?(diff)
      }
    }
  }
}
