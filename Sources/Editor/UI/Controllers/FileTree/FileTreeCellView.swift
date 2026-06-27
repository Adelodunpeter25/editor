import AppKit

/// Custom cell for the file tree with an icon (SF Symbol) and text label.
/// Folders use chevron/folder icons; files get an extension-based icon.
final class FileTreeCellView: NSTableCellView {
  private(set) var iconView: NSImageView?

  init(identifier: NSUserInterfaceItemIdentifier) {
    super.init(frame: .zero)
    self.identifier = identifier

    let iv = NSImageView()
    iv.imageScaling = .scaleProportionallyDown
    iv.translatesAutoresizingMaskIntoConstraints = false
    iv.setContentHuggingPriority(.required, for: .horizontal)
    addSubview(iv)
    self.iconView = iv

    let tf = NSTextField(labelWithString: "")
    tf.font = .systemFont(ofSize: 13)
    tf.lineBreakMode = .byTruncatingTail
    tf.translatesAutoresizingMaskIntoConstraints = false
    addSubview(tf)
    self.textField = tf

    NSLayoutConstraint.activate([
      iv.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
      iv.centerYAnchor.constraint(equalTo: centerYAnchor),
      iv.widthAnchor.constraint(equalToConstant: 16),
      iv.heightAnchor.constraint(equalToConstant: 16),
      tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 5),
      tf.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
      tf.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  /// Pick an appropriate SF Symbol icon for the node, pre-tinted with the file-type color.
  /// The color is baked in because contentTintColor is unreliable inside NSOutlineView cells
  /// (the row view's interiorBackgroundStyle interferes with view-level tinting).
  static func icon(for node: TreeNode, expanded: Bool) -> NSImage? {
    if node.isFolder || node.isDir { return FileIcon.tintedFolderIcon(expanded: false) }
    return FileIcon.tintedIcon(forFilename: node.name, color: FileIcon.color(forFilename: node.name))
  }
}
