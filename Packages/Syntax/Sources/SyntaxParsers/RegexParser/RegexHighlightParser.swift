import Foundation
import SyntaxFormat

actor RegexHighlightParser: HighlightParsing {

  // MARK: Internal Properties

  nonisolated let highlightBuffer = 2_000

  // MARK: Private Properties

  private let extractors: [SyntaxType: [any HighlightExtractable]]
  private let nestables: [NestableToken: SyntaxType]

  // MARK: Lifecycle

  init(extractors: [SyntaxType: [any HighlightExtractable]], nestables: [NestableToken: SyntaxType])
  {

    self.extractors = extractors
    self.nestables = nestables
  }

  // MARK: HighlightParsing Methods

  /// Parses and returns syntax highlighting for a substring of the given source string.
  ///
  /// - Parameters:
  ///   - string: The full source text to analyze.
  ///   - range: The requested range to update.
  /// - Returns: The highlights and the range that should be updated, or `nil` if nothing needs updating.
  /// - Throws: `CancellationError`.
  func parseHighlights(in string: String, range: NSRange) async throws -> (
    highlights: [Highlight], updateRange: NSRange
  )? {

    try await withThrowingTaskGroup(of: [SyntaxType: [NSRange]].self) {
      [extractors, nestables] group in
      group.addTask { try nestables.parseHighlights(in: string, range: range) }

      for (type, extractors) in extractors {
        for extractor in extractors {
          group.addTask { [type: try extractor.ranges(in: string, range: range)] }
        }
      }

      let dictionary: [SyntaxType: [NSRange]] = try await group.reduce(
        into: [SyntaxType: [NSRange]]()
      ) { dictionary, partial in
        for (type, ranges) in partial {
          dictionary[type, default: []].append(contentsOf: ranges)
        }
      }
      let highlights = try Highlight.highlights(dictionary: dictionary)

      return (highlights, range)
    }
  }
}
