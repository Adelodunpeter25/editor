import Foundation
import SyntaxFormat
import ValueRange

public typealias Highlight = ValueRange<SyntaxType>

public protocol IncrementalParsing: Actor {

  /// Updates the entire content and resets the parser state.
  ///
  /// Call this when the whole document changes or the parser falls out of sync.
  ///
  /// - Parameters:
  ///   - content: The new content.
  func update(content: String)

  /// Notifies the parser about a text edit so it can update its incremental parse state.
  ///
  /// Call this from `NSTextStorage.didProcessEditing` when `.editedCharacters` is in the edit mask.
  ///
  /// - Parameters:
  ///   - editedRange: The range that contains changes in the post-edit string.
  ///   - delta: The change in length of the edited range.
  ///   - insertedText: The substring currently contained in `editedRange` in the post-edit string.
  func noteEdit(editedRange: NSRange, delta: Int, insertedText: String) throws
}

public protocol HighlightParsing: Actor {

  nonisolated var highlightBuffer: Int { get }

  /// Parses and returns syntax highlighting for a substring of the given source string.
  ///
  /// - Parameters:
  ///   - string: The full source text to analyze.
  ///   - range: The requested range to update.
  /// - Returns: The highlights and the range that should be updated, or `nil` if nothing needs updating.
  /// - Throws: `CancellationError`.
  func parseHighlights(in string: String, range: NSRange) async throws -> (
    highlights: [Highlight], updateRange: NSRange
  )?
}

public protocol OutlineParsing: Actor {

  /// Parses and returns outline items from the given source string using all configured outline extractors.
  ///
  /// - Parameters:
  ///   - string: The full source text to analyze.
  /// - Returns: An array of `OutlineItem`.
  /// - Throws: `CancellationError`.
  func parseOutline(in string: String) async throws -> [OutlineItem]
}
