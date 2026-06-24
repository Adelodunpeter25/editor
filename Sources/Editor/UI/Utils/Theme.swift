import AppKit

/// Centralized color palette for the app's dark UI. All raw NSColor(white:…) calls should reference
/// these constants so the theme is consistent and easy to tweak.
enum Theme {
  // MARK: - Backgrounds
  static let editorBg = TMTheme.background  // #282C34
  static let sidebarBg = NSColor(white: 0.145, alpha: 1)
  static let panelBg = NSColor(white: 0.118, alpha: 1)
  static let contentBg = NSColor(white: 0.11, alpha: 1)
  static let settingsBg = NSColor(white: 0.16, alpha: 1)
  static let tabBarBg = NSColor(white: 0.09, alpha: 1)
  static let cardBg = NSColor(white: 0.17, alpha: 1)
  static let overlayScrim = NSColor(white: 0, alpha: 0.30)

  // MARK: - Borders / Dividers
  static let border = NSColor(white: 0.20, alpha: 1)
  static let borderLight = NSColor(white: 0.30, alpha: 1)
  static let borderSubtle = NSColor(white: 0.22, alpha: 1)

  // MARK: - Text
  static let textPrimary = NSColor(white: 0.95, alpha: 1)
  static let textSecondary = NSColor(white: 0.82, alpha: 1)
  static let textTertiary = NSColor(white: 0.70, alpha: 1)
  static let textMuted = NSColor(white: 0.55, alpha: 1)
  static let textDim = NSColor(white: 0.45, alpha: 1)
  static let textFaint = NSColor(white: 0.40, alpha: 1)

  // MARK: - Active / Selection
  static let activeRowBg = NSColor(white: 1, alpha: 0.08)
  static let hoverBg = NSColor(white: 1, alpha: 0.07)
  static let chipBorder = NSColor(white: 1, alpha: 0.14)

  // MARK: - Gutter (line numbers)
  static let gutterNumber = NSColor(white: 0.42, alpha: 1)
  static let gutterCurrent = NSColor(white: 0.78, alpha: 1)

  // MARK: - Diff
  static let diffAddBg = NSColor(red: 0.16, green: 0.30, blue: 0.18, alpha: 1)
  static let diffDelBg = NSColor(red: 0.34, green: 0.16, blue: 0.16, alpha: 1)
  static let diffAddFg = NSColor(red: 0.60, green: 0.86, blue: 0.62, alpha: 1)
  static let diffDelFg = NSColor(red: 0.92, green: 0.62, blue: 0.60, alpha: 1)
  static let diffTextFg = NSColor(white: 0.82, alpha: 1)
  static let diffGutterFg = NSColor(white: 0.40, alpha: 1)

  // MARK: - Git status
  static let gitNew = NSColor(srgbRed: 0.45, green: 0.76, blue: 0.45, alpha: 1)
  static let gitModified = NSColor(srgbRed: 0.85, green: 0.75, blue: 0.40, alpha: 1)
  static let gitDeleted = NSColor(srgbRed: 0.85, green: 0.40, blue: 0.40, alpha: 1)
  static let gitRenamed = NSColor(srgbRed: 0.55, green: 0.70, blue: 0.90, alpha: 1)
  static let gitIgnored = NSColor(white: 0.43, alpha: 1)
  static let gitDefault = NSColor(white: 0.80, alpha: 1)

  // MARK: - File tree inline edit
  static let inlineEditBg = NSColor(white: 0.22, alpha: 1)
  static let inlineEditText = NSColor(white: 0.96, alpha: 1)
}
