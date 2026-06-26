import AppKit

// MARK: - ScrimView

/// Full-host click catcher: a click outside the panel dismisses (handled by the controller).
final class ScrimView: NSView {
  var onClickOutside: ((NSPoint) -> Void)?
  override func mouseDown(with event: NSEvent) {
    onClickOutside?(convert(event.locationInWindow, from: nil))
  }
}

// MARK: - PaletteRowView

/// Accent-tinted selection that fills the row (and forces `.emphasized` so cell text brightens even when
/// the window isn't key).
final class PaletteRowView: NSTableRowView {
  override var interiorBackgroundStyle: NSView.BackgroundStyle {
    isSelected ? .emphasized : .normal
  }
  override func drawSelection(in dirtyRect: NSRect) {
    guard isSelected else { return }
    NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
    bounds.fill()
  }
}

// MARK: - PaletteCellView

/// One result row: filename (git-status tinted) + a dim parent dir, vertically centered. Colors brighten
/// when selected so the dim dir text stays legible on the accent-blue background (`backgroundStyle`
/// flips to `.emphasized`, driven by the row view's `interiorBackgroundStyle` below).
final class PaletteCellView: NSTableCellView {
  private let nameField = NSTextField(labelWithString: "")
  private let dirField = NSTextField(labelWithString: "")
  private var status: GitStatus = .none
  private var name = "", dir = ""
  private var nameMatches: Set<Int> = [], dirMatches: Set<Int> = []

  override init(frame: NSRect) {
    super.init(frame: frame)
    nameField.setContentCompressionResistancePriority(.required, for: .horizontal)
    dirField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let stack = NSStackView(views: [nameField, dirField])
    stack.orientation = .horizontal
    stack.alignment = .firstBaseline
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  func configure(
    name: String, dir: String, status: GitStatus, nameMatches: [Int], dirMatches: [Int]
  ) {
    self.name = name
    self.dir = dir
    self.status = status
    self.nameMatches = Set(nameMatches)
    self.dirMatches = Set(dirMatches)
    dirField.isHidden = dir.isEmpty
    applyColors()
  }

  /// When no match highlighting is needed (e.g. glob results).
  func configure(name: String, dir: String, status: GitStatus) {
    self.name = name
    self.dir = dir
    self.status = status
    self.nameMatches = []
    self.dirMatches = []
    dirField.isHidden = dir.isEmpty
    applyColors()
  }

  override var backgroundStyle: NSView.BackgroundStyle { didSet { applyColors() } }

  /// Rebuilds both labels' attributed text: base color from selection + git status, with matched chars
  /// brightened and bold. Re-run on selection change so the highlight tracks the accent background.
  private func applyColors() {
    let selected = backgroundStyle == .emphasized
    nameField.attributedStringValue = styled(
      name, size: 13, truncate: .byTruncatingTail,
      base: selected ? NSColor(white: 1, alpha: 0.85) : nsStatusColor(status),
      match: .white, matches: nameMatches)
    dirField.attributedStringValue = styled(
      dir, size: 11, truncate: .byTruncatingMiddle,
      base: selected ? NSColor(white: 1, alpha: 0.75) : NSColor(white: 0.5, alpha: 1),
      match: selected ? .white : NSColor(white: 0.85, alpha: 1), matches: dirMatches)
  }

  private func styled(
    _ s: String, size: CGFloat, truncate: NSLineBreakMode,
    base: NSColor, match: NSColor, matches: Set<Int>
  ) -> NSAttributedString {
    let para = NSMutableParagraphStyle()
    para.lineBreakMode = truncate
    let a = NSMutableAttributedString(
      string: s,
      attributes: [
        .foregroundColor: base, .font: NSFont.systemFont(ofSize: size), .paragraphStyle: para,
      ])
    if !matches.isEmpty {
      let bold = NSFont.systemFont(ofSize: size, weight: .bold)
      var u16 = 0  // matched indices are Character offsets; map each to its UTF-16 range
      for (ci, ch) in s.enumerated() {
        let len = String(ch).utf16.count
        if matches.contains(ci) {
          a.addAttributes(
            [.font: bold, .foregroundColor: match],
            range: NSRange(location: u16, length: len))
        }
        u16 += len
      }
    }
    return a
  }
}
