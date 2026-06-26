import Foundation
import StringUtils

actor RegexOutlineParser: OutlineParsing {

  // MARK: Private Properties

  private let extractors: [OutlineExtractor]
  private let policy: OutlinePolicy
  private var identityResolver: OutlineItem.IdentityResolver = .init()

  // MARK: Lifecycle

  init(extractors: [OutlineExtractor], policy: OutlinePolicy = .init()) {

    self.extractors = extractors
    self.policy = policy
  }

  // MARK: OutlineParsing Methods

  /// Parses and returns outline items from the given source string using all configured outline extractors.
  ///
  /// - Parameters:
  ///   - string: The full source text to analyze.
  /// - Returns: An array of `OutlineItem`.
  /// - Throws: `CancellationError`.
  func parseOutline(in string: String) async throws -> [OutlineItem] {

    let normalizedItems = try await withThrowingTaskGroup(of: [OutlineItem].self) {
      [extractors, policy] group in
      for extractor in extractors {
        group.addTask { try extractor.items(in: string, range: string.range) }
      }

      let items = try await group.reduce(into: [OutlineItem]()) { $0 += $1 }
        .sorted(using: [
          KeyPathComparator(\.range.location),
          KeyPathComparator(\.range.length),
        ])

      return policy.normalize(items)
    }

    return self.identityResolver.resolve(normalizedItems)
      .removingDuplicateIDs
  }
}
