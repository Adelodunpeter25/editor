import Foundation

extension NSRegularExpression {

  /// Returns an array of all the matches of the regular expression in the string.
  ///
  /// - Parameters:
  ///   - string: The string to search.
  ///   - options: The matching options to use.
  ///   - range: The range of the string to search.
  /// - Throws: `CancellationError`
  /// - Returns: An array of all the matches.
  public final func cancellableMatches(
    in string: String, options: MatchingOptions = [], range: NSRange
  ) throws -> [NSTextCheckingResult] {

    var matches: [NSTextCheckingResult] = []
    self.enumerateMatches(in: string, options: options, range: range) { match, _, stopPointer in
      if Task.isCancelled {
        stopPointer.pointee = ObjCBool(true)
        return
      }

      if let match {
        matches.append(match)
      }
    }

    try Task.checkCancellation()

    return matches
  }

  /// Returns an array of all the ranges matched by the regular expression in the string.
  ///
  /// - Parameters:
  ///   - string: The string to search.
  ///   - options: The matching options to use.
  ///   - range: The range of the string to search.
  /// - Throws: `CancellationError`
  /// - Returns: An array of all the matched ranges.
  public final func cancellableMatchRanges(
    in string: String, options: MatchingOptions = [], range: NSRange
  ) throws -> [NSRange] {

    var ranges: [NSRange] = []
    self.enumerateMatches(in: string, options: options, range: range) { match, _, stopPointer in
      if Task.isCancelled {
        stopPointer.pointee = ObjCBool(true)
        return
      }

      if let match {
        ranges.append(match.range)
      }
    }

    try Task.checkCancellation()

    return ranges
  }
}
