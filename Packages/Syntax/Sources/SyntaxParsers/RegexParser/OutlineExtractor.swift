import Foundation
import StringUtils
import SyntaxFormat

struct OutlineExtractor: Sendable {

  var regex: NSRegularExpression
  var template: String
  var kind: Syntax.Outline.Kind?

  init(definition: Syntax.Outline) throws {

    // compile to regex object
    var options: NSRegularExpression.Options = .anchorsMatchLines
    if definition.ignoreCase {
      options.formUnion(.caseInsensitive)
    }
    self.regex = try NSRegularExpression(pattern: definition.pattern, options: options)

    self.template = definition.template
    self.kind = definition.kind
  }

  /// Extracts outline items in the given string.
  ///
  /// - Parameters:
  ///   - string: The string to parse.
  ///   - parseRange: The range of the string to parse.
  /// - Throws: `CancellationError`
  /// - Returns: An array of `OutlineItem`.
  func items(in string: String, range parseRange: NSRange) throws -> [OutlineItem] {

    try self.regex.cancellableMatches(
      in: string, options: [.withTransparentBounds, .withoutAnchoringBounds], range: parseRange
    ).lazy
      .compactMap { result in
        // separator
        if self.kind == .separator {
          return OutlineItem.separator(range: result.range)
        }

        // standard outline
        let title =
          (self.template.isEmpty
          ? (string as NSString).substring(with: result.range)
          : self.regex.replacementString(
            for: result, in: string, offset: 0, template: self.template))
          .replacingOccurrences(of: "(\\S)\\s+", with: "$1 ", options: .regularExpression)

        let indentRegex = try! Regex("(?<indent>\\s*)(?<title>.+)$")
        guard
          let match = title.firstMatch(of: indentRegex),
          let titleMatch: Substring = match["title"]?.substring,
          !titleMatch.isEmpty
        else { return nil }

        let kind: Syntax.Outline.Kind? =
          switch self.kind {
          case .heading(_?): .heading(nil)
          default: self.kind
          }
        let indentMatch: Substring = match["indent"]?.substring ?? Substring()
        let indent: OutlineItem.Indent =
          switch self.kind {
          case .title: .level(0)
          case .heading(let level?): .level(level)
          default: .string(String(indentMatch))
          }

        return OutlineItem(
          title: String(titleMatch), range: result.range, kind: kind, indent: indent)
      }
  }
}
