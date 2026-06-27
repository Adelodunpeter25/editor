import AppKit

/// A horizontal breadcrumb bar that renders a file path as segmented components:
/// folder segments appear dimmed, the filename appears brighter — making the path
/// immediately scannable without reading every character.
///
/// Usage:
/// ```swift
/// let crumb = PathBreadcrumbView()
/// crumb.configure(path: absolutePath, relativeTo: repoURL)          // editor
/// crumb.configure(path: repoRelativePath, commitHash: hash)         // diff (historic)
/// crumb.configure(path: repoRelativePath)                           // diff (working tree)
/// ```
final class PathBreadcrumbView: NSView {
  private let stack = NSStackView()
  private let border = NSView()

  override init(frame: NSRect) {
    super.init(frame: frame)
    setup()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  private func setup() {
    wantsLayer = true
    layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor  // slightly lighter than editor bg

    border.wantsLayer = true
    border.layer?.backgroundColor = Theme.border.cgColor
    border.translatesAutoresizingMaskIntoConstraints = false
    addSubview(border)

    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 3
    stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)

    NSLayoutConstraint.activate([
      // Stack fills the view, leaving 1pt at the bottom for the border
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),

      border.leadingAnchor.constraint(equalTo: leadingAnchor),
      border.trailingAnchor.constraint(equalTo: trailingAnchor),
      border.bottomAnchor.constraint(equalTo: bottomAnchor),
      border.heightAnchor.constraint(equalToConstant: 1),
    ])
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: 26)
  }

  // MARK: - Public API

  /// Render the breadcrumb for `path`.
  ///
  /// - Parameters:
  ///   - path: The file path to display — either absolute or repo-relative.
  ///   - repoURL: When provided, strips this prefix so only the repo-relative portion is shown.
  ///   - commitHash: When provided (historic diff), appends a short hash badge after the filename.
  func configure(path: String, relativeTo repoURL: String? = nil, commitHash: String? = nil) {
    stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

    guard !path.isEmpty else { return }

    // Compute the display path (strip repo prefix when available)
    let displayPath: String
    if let base = repoURL {
      let prefix = base.hasSuffix("/") ? base : base + "/"
      displayPath = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    } else {
      displayPath = path
    }

    // Full path as tooltip so truncated paths are always reachable
    self.toolTip = commitHash.map { "\(path)  @\(String($0.prefix(7)))" } ?? path

    let components = displayPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    guard !components.isEmpty else { return }

    for (index, component) in components.enumerated() {
      let isLast = index == components.count - 1

      // Separator chevron between components
      if index > 0 {
        stack.addArrangedSubview(separatorLabel())
      }

      let label = makeLabel(component, isFilename: isLast)
      stack.addArrangedSubview(label)
    }

    // Commit hash badge (historic diff only)
    if let hash = commitHash {
      stack.addArrangedSubview(separatorLabel("@"))
      let hashLabel = makeLabel(String(hash.prefix(7)), isFilename: false, isMono: true)
      stack.addArrangedSubview(hashLabel)
    }
  }

  // MARK: - Helpers

  private func separatorLabel(_ text: String = "›") -> NSTextField {
    let f = NSTextField(labelWithString: text)
    f.font = .systemFont(ofSize: 11, weight: .regular)
    f.textColor = Theme.textDim
    f.setContentHuggingPriority(.required, for: .horizontal)
    f.setContentCompressionResistancePriority(.required, for: .horizontal)
    return f
  }

  private func makeLabel(_ text: String, isFilename: Bool, isMono: Bool = false) -> NSTextField {
    let f = NSTextField(labelWithString: text)
    if isMono {
      f.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    } else {
      f.font = .systemFont(ofSize: 12, weight: isFilename ? .medium : .regular)
    }
    f.textColor = isFilename ? Theme.textSecondary : Theme.textMuted
    f.lineBreakMode = .byTruncatingTail

    // Folder segments can be squeezed hard; the filename holds its ground
    f.setContentCompressionResistancePriority(
      isFilename ? .defaultHigh : .defaultLow, for: .horizontal)
    f.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return f
  }
}
