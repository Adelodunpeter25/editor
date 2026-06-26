import Foundation

extension StringProtocol {

  /// The number of words in the whole string.
  public var numberOfWords: Int {

    var count = 0
    self.enumerateSubstrings(
      in: self.startIndex..<self.endIndex, options: [.byWords, .localized, .substringNotRequired]
    ) { _, _, _, _ in
      count += 1
    }

    return count
  }

  /// The number of lines in the whole string excluding the last blank line.
  public var numberOfLines: Int {

    self.numberOfLines()
  }

  /// Calculates the line number at the given character index (1-based).
  ///
  /// - Parameter index: The character index.
  /// - Returns: The line number.
  public func lineNumber(at index: Index) -> Int {

    guard !self.isEmpty, index > self.startIndex else { return 1 }

    return self.numberOfLines(in: self.startIndex..<index, includesLastBreak: true)
  }

  /// Counts the number of lines in the given range.
  ///
  /// - Parameters:
  ///   - range: The character range to count lines, or when `nil`, the entire range.
  ///   - includesLastBreak: The flag to count the new line character at the end.
  /// - Returns: The number of lines.
  public func numberOfLines(in range: Range<String.Index>? = nil, includesLastBreak: Bool = false)
    -> Int
  {

    let range = range ?? self.startIndex..<self.endIndex

    if self.isEmpty || range.isEmpty { return 0 }

    var count = 0
    self.enumerateSubstrings(in: range, options: [.byLines, .substringNotRequired]) { _, _, _, _ in
      count += 1
    }

    if includesLastBreak, self[range].last?.isNewline == true {
      count += 1
    }

    return count
  }

  /// Counts the number of lines in the given ranges.
  ///
  /// - Parameters:
  ///   - ranges: The character ranges to count lines.
  ///   - includesLastBreak: The flag to count the new line character at the end.
  /// - Returns: The number of lines.
  public func numberOfLines(in ranges: [Range<String.Index>], includesLastBreak: Bool = false)
    -> Int
  {

    assert(!ranges.isEmpty)

    if self.isEmpty || ranges.isEmpty { return 0 }

    // use simple count for efficiency
    if ranges.count == 1 {
      return self.numberOfLines(in: ranges[0], includesLastBreak: includesLastBreak)
    }

    // evaluate line ranges to avoid double-count lines holding multiple ranges
    var lineRanges: Set<Range<String.Index>> = []
    for range in ranges {
      let lineRange = self.lineRange(for: range)
      self.enumerateSubstrings(in: lineRange, options: [.byLines, .substringNotRequired]) {
        _, substringRange, _, _ in
        lineRanges.insert(substringRange)
      }

      if includesLastBreak, self[range].last?.isNewline == true {
        lineRanges.insert(self.lineRange(at: range.upperBound))
      }
    }

    return lineRanges.count
  }

  /// Calculates the number of characters from the beginning of the line where the given character index locates (0-based).
  ///
  /// - Parameter index: The character index.
  /// - Returns: The column number.
  public func columnNumber(at index: Index) -> Int {

    self.distance(from: self.lineStartIndex(at: index), to: index)
  }
}

// MARK: NSRange based

extension String {

  /// Calculates the line number at the given character index (1-based).
  ///
  /// - Parameter location: The UTF16-based character index.
  /// - Returns: The line number.
  public func lineNumber(at location: Int) -> Int {

    guard !self.isEmpty, location > 0 else { return 1 }

    return self.numberOfLines(in: NSRange(location: 0, length: location), includesLastBreak: true)
  }

  /// Counts the number of lines in the given range.
  ///
  /// - Parameters:
  ///   - range: The character range to count lines, or when `nil`, the entire range.
  ///   - includesLastBreak: The flag to count the new line character at the end.
  /// - Returns: The number of lines.
  public func numberOfLines(in range: NSRange? = nil, includesLastBreak: Bool = false) -> Int {

    let range = range ?? self.nsRange

    if self.isEmpty || range.isEmpty { return 0 }

    let string = self as NSString
    var count = 0
    string.enumerateSubstrings(in: range, options: [.byLines, .substringNotRequired]) {
      _, _, _, _ in
      count += 1
    }

    if includesLastBreak,
      string.character(at: range.upperBound - 1).isNewline,
      !string.isInsideCRLF(at: range.upperBound)
    {
      count += 1
    }

    return count
  }
}
