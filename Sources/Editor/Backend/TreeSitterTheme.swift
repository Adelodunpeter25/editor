import AppKit
import SyntaxFormat

/// Color palette for tree-sitter highlights. Uses the same atom-one-dark colors as `TMTheme`
/// so the visual result is consistent between the TextMate and tree-sitter paths.
enum TreeSitterTheme {
  static let background = NSColor(white: 0.11, alpha: 1)  // matches the content area
  static let base = NSColor(srgbRed: 0.671, green: 0.698, blue: 0.749, alpha: 1)  // #ABB2BF

  private static func c(_ hex: UInt32) -> NSColor {
    NSColor(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
  }

  private static let gray = c(0x5C6370), green = c(0x98C379), orange = c(0xD19A66)
  private static let purple = c(0xC678DD), blue = c(0x61AFEF), teal = c(0x56B6C2)
  private static let yellow = c(0xE5C07B), red = c(0xE06C75)

  /// Map a `SyntaxType` (the coarse-grained category tree-sitter highlights resolve to) to a color.
  static func color(for type: SyntaxType) -> NSColor? {
    switch type {
    case .keywords: return purple
    case .commands: return blue
    case .types: return yellow
    case .attributes: return yellow
    case .variables: return base
    case .values: return orange
    case .numbers: return orange
    case .strings: return green
    case .characters: return orange
    case .comments: return gray
    }
  }
}
