import AppKit
import TextFind

/// Outline view with the system disclosure triangle hidden (`frameOfOutlineCell` → `.zero`) so every row's
/// content starts flush at the column's left edge — no reserved triangle column indenting the match rows.
/// The file cell draws its own chevron instead, and double clicking a file row toggles it (see `rowDoubleClicked`).
final class SearchOutlineView: PointerOutlineView {
  override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }
}

// MARK: - Cells

/// A file header row: a disclosure chevron (its own, so we control the gap to the name), filename
/// (bright) + dim parent dir + a right-aligned match count.
final class SearchFileCell: NSTableCellView {
  private let chevron = NSImageView()
  private let nameField = NSTextField(labelWithString: "")
  private let dirField = NSTextField(labelWithString: "")
  private let countField = NSTextField(labelWithString: "")

  override init(frame: NSRect) {
    super.init(frame: frame)
    chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
    chevron.contentTintColor = NSColor(white: 0.6, alpha: 1)
    chevron.setContentHuggingPriority(.required, for: .horizontal)
    nameField.font = .systemFont(ofSize: 12, weight: .medium)
    nameField.textColor = NSColor(white: 0.92, alpha: 1)
    nameField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    dirField.font = .systemFont(ofSize: 11)
    dirField.textColor = NSColor(white: 0.5, alpha: 1)
    dirField.lineBreakMode = .byTruncatingMiddle
    dirField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    countField.font = .systemFont(ofSize: 11)
    countField.textColor = NSColor(white: 0.55, alpha: 1)
    countField.alignment = .right
    countField.setContentHuggingPriority(.required, for: .horizontal)
    countField.setContentCompressionResistancePriority(.required, for: .horizontal)

    let stack = NSStackView(views: [chevron, nameField, dirField, NSView(), countField])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 6
    stack.setCustomSpacing(8, after: chevron)  // clear gap between the chevron and the name
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
      chevron.widthAnchor.constraint(equalToConstant: 9),
    ])
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  func configure(file: String, count: Int, expanded: Bool) {
    chevron.image = NSImage(
      systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
    nameField.stringValue = (file as NSString).lastPathComponent
    let dir = (file as NSString).deletingLastPathComponent
    dirField.stringValue = dir
    dirField.isHidden = dir.isEmpty
    countField.stringValue = "\(count)"
  }
}

/// A single matching line: dim 1-based line number + the source line with matched ranges highlighted.
final class SearchMatchCell: NSTableCellView {
  private let lineField = NSTextField(labelWithString: "")
  private let previewLabel = NSTextField(labelWithString: "")

  override init(frame: NSRect) {
    super.init(frame: frame)
    lineField.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    lineField.textColor = NSColor(white: 0.45, alpha: 1)
    lineField.alignment = .left  // flush-left so the match sits at the file row's left edge
    lineField.setContentHuggingPriority(.required, for: .horizontal)
    lineField.setContentCompressionResistancePriority(.required, for: .horizontal)
    previewLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    previewLabel.textColor = NSColor(white: 0.75, alpha: 1)
    previewLabel.lineBreakMode = .byTruncatingTail
    previewLabel.cell?.usesSingleLineMode = true

    let stack = NSStackView(views: [lineField, previewLabel])
    stack.orientation = .horizontal
    stack.alignment = .firstBaseline
    stack.spacing = 6  // tight gap: line number hugs, preview sits right after
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),  // flush with the file row's chevron
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  func configure(line: Int, preview: String, query: String, mode: TextFind.Mode) {
    lineField.stringValue = "\(line)"
    let s = NSMutableAttributedString(
      string: preview,
      attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor(white: 0.75, alpha: 1),
      ])
    if !query.isEmpty, let finder = try? TextFind(for: preview, findString: query, mode: mode) {
      let matches = (try? finder.matches) ?? []
      for range in matches where range.length > 0 {
        s.addAttributes(
          [
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.30),
          ],
          range: range)
      }
    }
    previewLabel.attributedStringValue = s
  }
}

/// Accent-tinted full-row selection (matches the command palette), forcing `.emphasized` so text stays
/// legible on the highlight even when the window isn't key (e.g. while the harness drives it).
final class SearchRowView: NSTableRowView {
  override var interiorBackgroundStyle: NSView.BackgroundStyle {
    isSelected ? .emphasized : .normal
  }
  override func drawSelection(in dirtyRect: NSRect) {
    guard isSelected else { return }
    NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
    bounds.fill()
  }
}
