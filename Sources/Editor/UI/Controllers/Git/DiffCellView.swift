import AppKit

/// Colors and fonts used by the diff views.
struct DiffTheme {
  static let addBg = Theme.diffAddBg
  static let delBg = Theme.diffDelBg
  static let addFg = Theme.diffAddFg
  static let delFg = Theme.diffDelFg
  static let gutterFg = Theme.diffGutterFg
  static let diffTextFg = Theme.diffTextFg
  static func font() -> NSFont { AppFont.mono(size: 12) }
}

/// One diff line cell: monospaced text on a full-cell background color, with optional syntax highlighting.
final class DiffCellView: NSView {
  private let field = NSTextField(labelWithString: "")
  private let gutterBar = NSView()

  init() {
    super.init(frame: .zero)
    wantsLayer = true

    gutterBar.wantsLayer = true
    gutterBar.translatesAutoresizingMaskIntoConstraints = false
    addSubview(gutterBar)

    field.font = DiffTheme.font()
    field.lineBreakMode = .byClipping
    field.allowsEditingTextAttributes = true
    field.translatesAutoresizingMaskIntoConstraints = false
    addSubview(field)

    NSLayoutConstraint.activate([
      gutterBar.leadingAnchor.constraint(equalTo: leadingAnchor),
      gutterBar.topAnchor.constraint(equalTo: topAnchor),
      gutterBar.bottomAnchor.constraint(equalTo: bottomAnchor),
      gutterBar.widthAnchor.constraint(equalToConstant: 3),

      field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      field.centerYAnchor.constraint(equalTo: centerYAnchor),
      field.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  func configure(
    prefixedText: String, lineText: String, fg: NSColor, bg: NSColor,
    highlighted: [(offset: Int, length: Int, color: NSColor)]? = nil
  ) {
    layer?.backgroundColor = bg.cgColor

    if bg == DiffTheme.addBg {
      gutterBar.layer?.backgroundColor = Theme.gitNew.cgColor
    } else if bg == DiffTheme.delBg {
      gutterBar.layer?.backgroundColor = Theme.gitDeleted.cgColor
    } else {
      gutterBar.layer?.backgroundColor = NSColor.clear.cgColor
    }

    let fullText = prefixedText + lineText
    guard let spans = highlighted, !spans.isEmpty else {
      field.attributedStringValue = NSAttributedString(
        string: fullText.isEmpty ? " " : fullText,
        attributes: [.font: DiffTheme.font(), .foregroundColor: fg])
      return
    }
    let attr = NSMutableAttributedString(
      string: fullText, attributes: [.font: DiffTheme.font(), .foregroundColor: fg])
    let prefixLen = prefixedText.utf16.count
    for span in spans {
      let start = prefixLen + span.offset
      let len = min(span.length, fullText.utf16.count - start)
      guard start >= 0, len > 0, start + len <= fullText.utf16.count else { continue }
      attr.addAttribute(
        .foregroundColor, value: span.color, range: NSRange(location: start, length: len))
    }
    field.attributedStringValue = attr
  }

  func configure(
    no: Int?, text: String, fg: NSColor, bg: NSColor,
    highlighted: [(offset: Int, length: Int, color: NSColor)]? = nil
  ) {
    let g =
      no.map { n -> String in
        let s = String(n)
        return String(repeating: " ", count: max(0, 4 - s.count)) + s
      } ?? "    "
    configure(prefixedText: "\(g)  ", lineText: text, fg: fg, bg: bg, highlighted: highlighted)
  }
}
