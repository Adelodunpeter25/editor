import Foundation
import SyntaxFormat

enum MarkdownOutlineFormatter: TreeSitterOutlineFormatting {

  /// Formats a Markdown outline title by stripping ATX prefixes and setext underlines.
  ///
  /// - Parameters:
  ///   - title: The raw title text.
  ///   - kind: The outline item kind.
  /// - Returns: The formatted title, or `nil` to exclude the item.
  static func formatTitle(_ title: String, kind: Syntax.Outline.Kind) -> String? {

    guard case .heading = kind else { return title }

    // Setext headings include the underline on following lines.
    let firstLine =
      title.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
      .first.map(String.init) ?? title

    let normalized =
      firstLine
      .replacingOccurrences(of: "^#{1,6}[ \\t]*", with: "", options: .regularExpression)  // ATX prefix
      .replacingOccurrences(of: "[ \\t]*#+[ \\t]*$", with: "", options: .regularExpression)  // optional ATX closing
      .trimmingCharacters(in: .whitespacesAndNewlines)

    return normalized.isEmpty ? nil : normalized
  }
}
