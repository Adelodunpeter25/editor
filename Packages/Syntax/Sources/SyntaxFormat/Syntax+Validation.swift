import Foundation

extension Syntax {

  public struct Error: Swift.Error, Equatable {

    public enum Code: Equatable, Sendable {

      case duplicated
      case regularExpression
      case blockComment
      case nestableBlockComment
      case invalidEscapeCharacter
    }

    public enum Scope: Equatable, Sendable {

      case highlight(SyntaxType)
      case outline
      case blockComment
      case stringDelimiter
      case characterDelimiter
    }

    public var code: Code
    public var scope: Scope
    public var value: String

    public init(_ code: Code, scope: Scope, value: String) {

      self.code = code
      self.scope = scope
      self.value = value
    }
  }

  // MARK: Public Methods

  /// Checks syntax and returns `Error`s.
  ///
  /// - Returns: The validation errors.
  public func validate() -> [Error] {

    var errors: [Error] = []

    for type in SyntaxType.allCases {
      guard
        let highlights = self.highlights[type]?
          .sorted(using: [KeyPathComparator(\.begin), KeyPathComparator(\.end)])  // sort for duplication check
      else { continue }

      // allow appearing the same highlights in different kinds
      var lastHighlight: Syntax.Highlight?

      for highlight in highlights {
        defer {
          lastHighlight = highlight
        }

        guard highlight != lastHighlight else {
          errors.append(Error(.duplicated, scope: .highlight(type), value: highlight.begin))
          continue
        }

        if highlight.isRegularExpression {
          do {
            _ = try NSRegularExpression(pattern: highlight.begin)
          } catch {
            errors.append(
              Error(.regularExpression, scope: .highlight(type), value: highlight.begin))
          }

          if let end = highlight.end {
            do {
              _ = try NSRegularExpression(pattern: end)
            } catch {
              errors.append(Error(.regularExpression, scope: .highlight(type), value: end))
            }
          }
        }
      }
    }

    for outline in self.outlines {
      do {
        _ = try NSRegularExpression(pattern: outline.pattern)
      } catch {
        errors.append(Error(.regularExpression, scope: .outline, value: outline.pattern))
      }
    }

    // validate block comment delimiter pairs
    errors += self.commentDelimiters.blocks.compactMap { delimiter in
      switch (delimiter.begin.isEmpty, delimiter.end.isEmpty) {
      case (true, false):
        Error(.blockComment, scope: .blockComment, value: delimiter.end)
      case (false, true):
        Error(.blockComment, scope: .blockComment, value: delimiter.begin)
      case (false, false) where delimiter.isNestable && delimiter.begin == delimiter.end:
        Error(.nestableBlockComment, scope: .blockComment, value: delimiter.begin)
      default:
        nil
      }
    }

    // validate escape characters are single UTF-16 code unit
    errors += self.stringDelimiters
      .compactMap(\.escapeCharacter)
      .filter { $0.utf16.count != 1 }
      .map { Error(.invalidEscapeCharacter, scope: .stringDelimiter, value: String($0)) }
    errors += self.characterDelimiters
      .compactMap(\.escapeCharacter)
      .filter { $0.utf16.count != 1 }
      .map { Error(.invalidEscapeCharacter, scope: .characterDelimiter, value: String($0)) }

    return errors
  }
}
