import Foundation

public struct FilteredItem<Value: Identifiable & Sendable>: Identifiable, Sendable {

  public enum State: Sendable {

    case noFilter
    case filtered([Range<String.Index>])
  }

  public var value: Value
  public var state: State
  public var string: String

  public var id: Value.ID { self.value.id }
}

extension FilteredItem {

  /// Attributed string of which matched parts are styled as `.inlinePresentationIntent = .stronglyEmphasized`.
  public var attributedString: AttributedString {

    let attributedString = AttributedString(self.string)

    switch self.state {
    case .noFilter:
      return attributedString

    case .filtered(let ranges):
      return
        ranges
        .compactMap { Range($0, in: attributedString) }
        .reduce(into: attributedString) { attributedString, range in
          attributedString[range].inlinePresentationIntent = .stronglyEmphasized
        }
    }
  }
}

extension Identifiable where Self: Sendable {

  /// Filters with given string.
  ///
  /// - Parameters:
  ///   - filter: The search string.
  ///   - keyPath: The key path to value to filter.
  /// - Returns: A FilteredItem when matched or not filtered, otherwise `nil`.
  public func filter(_ filter: String, keyPath: KeyPath<Self, String>) -> FilteredItem<Self>? {

    if filter.isEmpty {
      FilteredItem(value: self, state: .noFilter, string: self[keyPath: keyPath])
    } else if let ranges = self[keyPath: keyPath].abbreviatedMatchedRanges(with: filter) {
      FilteredItem(value: self, state: .filtered(ranges), string: self[keyPath: keyPath])
    } else {
      nil
    }
  }
}

extension String {

  public struct AbbreviatedMatchResult: Equatable, Sendable {

    public var ranges: [Range<String.Index>]
    public var remaining: String
    public var score: Int
  }

  /// Searches ranges of the characters contains in the `searchString` in the `searchString` order.
  ///
  /// - Parameter searchString: The string to search.
  /// - Returns: The matched character ranges and score, or `nil` if not matched.
  public func abbreviatedMatch(with searchString: String) -> AbbreviatedMatchResult? {

    guard let ranges = self.abbreviatedMatchedRanges(with: searchString, incomplete: true) else {
      return nil
    }

    let remaining = String(searchString.suffix(searchString.count - ranges.count))

    // just simply calculate the length...
    let score = self.distance(from: ranges.first!.lowerBound, to: ranges.last!.upperBound)

    return AbbreviatedMatchResult(ranges: ranges, remaining: remaining, score: score)
  }

  /// Searches ranges of the characters contains in the `searchString` in the `searchString` order.
  ///
  /// - Parameters:
  ///   - searchString: The string to search.
  ///   - incomplete: If `true`, returns the ranges up to the part found, even if not found completely.
  /// - Returns: The matched character ranges, or `nil` if not matched.
  public func abbreviatedMatchedRanges(with searchString: String, incomplete: Bool = false)
    -> [Range<String.Index>]?
  {

    guard !searchString.isEmpty, !self.isEmpty else { return nil }

    var ranges: [Range<String.Index>] = []
    for character in searchString {
      let index = ranges.last?.upperBound ?? self.startIndex

      guard
        let range = self.range(
          of: String(character), options: .caseInsensitive, range: index..<self.endIndex)
      else {
        if incomplete { break } else { return nil }
      }

      ranges.append(range)
    }

    return ranges.isEmpty ? nil : ranges
  }
}

extension String {

  /// Returns word-instance ranges that match the word at the given range.
  ///
  /// - Note: Single-letter words are not treated as a match target.
  ///
  /// - Parameter range: The word range in the receiver's UTF-16 based `NSRange`.
  /// - Returns: The ranges of word instances in the receiver, or an empty array if the range is not a word.
  /// - Throws: A cancellation error if the underlying match operation is cancelled.
  public func instanceRangesOfWord(at range: NSRange) throws -> [NSRange] {

    guard
      (try! NSRegularExpression(pattern: #"\A\b\w.*\w\b\z"#))
        .firstMatch(in: self, options: [.withTransparentBounds], range: range) != nil
    else { return [] }

    let substring = (self as NSString).substring(with: range)
    let pattern = "\\b" + NSRegularExpression.escapedPattern(for: substring) + "\\b"
    let regex = try! NSRegularExpression(pattern: pattern)

    return try regex.cancellableMatchRanges(in: self, range: self.range)
  }
}
