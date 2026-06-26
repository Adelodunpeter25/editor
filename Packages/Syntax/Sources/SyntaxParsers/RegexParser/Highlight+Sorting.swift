import Foundation
import StringUtils
import SyntaxFormat
import ValueRange

extension ValueRange<SyntaxType> {

  /// Converts a syntax highlight dictionary to sorted Highlights.
  ///
  /// - Note: This sanitization significantly reduces the performance time of attribute application.
  ///
  /// - Parameter dictionary: The syntax highlight dictionary.
  /// - Returns: An array of sorted Highlight structs.
  /// - Throws: CancellationError.
  static func highlights(dictionary: [SyntaxType: [NSRange]]) throws -> [ValueRange<SyntaxType>] {

    var occupied = IndexSet()

    return try SyntaxType.allCases.reversed()
      .reduce(into: [SyntaxType: IndexSet]()) { result, type in
        guard let ranges = dictionary[type] else { return }

        try Task.checkCancellation()

        var indexes = IndexSet(integersIn: ranges)
        indexes.subtract(occupied)

        result[type] = indexes
        occupied.formUnion(indexes)
      }
      .mapValues { $0.rangeView.map(NSRange.init) }
      .flatMap { type, ranges in ranges.map { ValueRange(value: type, range: $0) } }
      .sorted(using: KeyPathComparator(\.range.location))
  }
}
