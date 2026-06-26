import Foundation
import SyntaxFormat

enum CSSOutlineFormatter: TreeSitterOutlineFormatting {

  /// Formats a CSS outline title by keeping only the at-rule header.
  static func formatTitle(_ title: String, kind: Syntax.Outline.Kind) -> String? {

    let header =
      if let index = title.firstIndex(of: "{") ?? title.firstIndex(of: ";") {
        title[..<index]
      } else {
        title[...]
      }

    let normalized = header.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    return normalized.isEmpty ? nil : normalized
  }
}
