import Foundation
import StringUtils

// MARK: - Fuzzy scoring (thin wrappers around StringUtils.abbreviatedMatch)

enum Fuzzy {
  /// Subsequence match of `query` in `candidate` (case-insensitive). Returns nil if not all query
  /// chars appear in order; otherwise a score where higher = better (shorter match span ranks higher).
  static func score(_ query: String, _ candidate: String) -> Int? {
    guard let result = candidate.abbreviatedMatch(with: query) else { return nil }
    return -result.score
  }

  /// The character indices `query` matches in `candidate`, in order. Empty if not a full subsequence.
  static func matches(_ query: String, _ candidate: String) -> [Int] {
    guard let ranges = candidate.abbreviatedMatchedRanges(with: query) else { return [] }
    return ranges.map { range in
      candidate.distance(from: candidate.startIndex, to: range.lowerBound)
    }
  }
}
