import Foundation
import StringUtils
import SwiftTreeSitter
import SyntaxFormat

enum LuaOutlineFormatter: TreeSitterOutlineFormatting {

  static func title(for match: QueryMatch, capture: OutlineCapture, source: NSString) -> (
    title: String, range: NSRange
  )? {

    switch capture.kind {
    case .function:
      return (
        title: Self.functionTitle(
          for: match, title: source.substring(with: capture.range), source: source),
        range: Self.signatureRange(for: match, nameRange: capture.range)
      )
    default:
      return Self.defaultTitle(capture: capture, source: source)
    }
  }
}

extension LuaOutlineFormatter {

  /// Builds the displayed Lua function title from a query match.
  ///
  /// - Parameters:
  ///   - match: The resolved query match.
  ///   - title: The raw title capture text.
  ///   - source: The source text as `NSString`.
  /// - Returns: The displayed Lua function title.
  fileprivate static func functionTitle(for match: QueryMatch, title: String, source: NSString)
    -> String
  {

    let parameters =
      Self.parametersRange(for: match)
      .map(source.substring(with:))
      .map(Self.normalizedClause)
      ?? "()"

    return title + parameters
  }

  /// Returns the signature range spanning the Lua function name through its parameter list.
  ///
  /// - Parameters:
  ///   - match: The resolved query match.
  ///   - nameRange: The captured function name range.
  /// - Returns: The signature range.
  fileprivate static func signatureRange(for match: QueryMatch, nameRange: NSRange) -> NSRange {

    nameRange.union(with: [Self.parametersRange(for: match)])
  }

  /// Returns a whitespace-normalized Lua parameter clause.
  ///
  /// - Parameter clause: The raw parameter clause text.
  /// - Returns: The clause with normalized spacing.
  private static func normalizedClause(_ clause: String) -> String {

    clause
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "\\(\\s+", with: "(", options: .regularExpression)
      .replacingOccurrences(of: "\\s+\\)", with: ")", options: .regularExpression)
      .replacingOccurrences(of: "\\s*,\\s*", with: ", ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
