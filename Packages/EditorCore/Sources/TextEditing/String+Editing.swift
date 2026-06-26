import Foundation
import StringUtils

extension String {

  /// Surrounds the text in the given ranges with the provided strings.
  ///
  /// - Parameters:
  ///   - selectedRanges: The selected ranges to surround.
  ///   - begin: The string to insert before each selected range.
  ///   - end: The string to insert after each selected range.
  /// - Returns: An `EditingContext`, or `nil` if no ranges were provided.
  public func surround(in selectedRanges: [NSRange], begin: String, end: String) -> EditingContext?
  {

    guard !selectedRanges.isEmpty else { return nil }

    let replacementStrings = selectedRanges.map {
      begin + (self as NSString).substring(with: $0) + end
    }
    let newSelectedRanges = selectedRanges.enumerated().map { offset, range in
      range.shifted(by: (offset + 1) * begin.length + offset * end.length)
    }

    return EditingContext(
      strings: replacementStrings, ranges: selectedRanges, selectedRanges: newSelectedRanges)
  }

  /// Transforms the text in the given ranges.
  ///
  /// - Parameters:
  ///   - selectedRanges: The selected ranges to transform.
  ///   - transform: The transformation to apply to each selected substring.
  /// - Returns: An `EditingContext`, or `nil` if no non-empty ranges were provided.
  public func transformSelections(
    in selectedRanges: [NSRange], with transform: (_ substring: String) -> String
  ) -> EditingContext? {

    var strings: [String] = []
    var ranges: [NSRange] = []
    var newSelectedRanges: [NSRange] = []
    var deltaLocation = 0

    for range in selectedRanges where !range.isEmpty {
      let substring = (self as NSString).substring(with: range)
      let string = transform(substring)
      let newRange = NSRange(location: range.location - deltaLocation, length: string.length)

      strings.append(string)
      ranges.append(range)
      newSelectedRanges.append(newRange)

      deltaLocation += range.length - newRange.length
    }

    guard !strings.isEmpty else { return nil }

    return EditingContext(strings: strings, ranges: ranges, selectedRanges: newSelectedRanges)
  }
}
