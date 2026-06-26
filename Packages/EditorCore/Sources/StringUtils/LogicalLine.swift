import Foundation

package struct LogicalLine: Equatable, Sendable {

  /// The line contents excluding line-ending characters.
  package var contents: String

  /// The line-ending characters immediately following the contents, or `nil` if absent.
  package var lineEnding: String?

  /// Creates a logical line.
  ///
  /// - Parameters:
  ///   - contents: The line contents excluding line-ending characters.
  ///   - lineEnding: The line-ending characters immediately following the contents, or `nil` if absent.
  package init(contents: String, lineEnding: String?) {

    self.contents = contents
    self.lineEnding = lineEnding
  }
}

extension String {

  /// Splits the range into logical lines preserving existing line endings.
  ///
  /// - Parameter range: The range to split.
  /// - Returns: Logical lines with their trailing line endings.
  package func logicalLines(in range: NSRange) -> [LogicalLine] {

    let string = self as NSString
    let ranges = self.lineContentsRanges(for: range)

    return ranges.enumerated().map { index, lineRange in
      let upperBound =
        ranges.indices.contains(index + 1)
        ? ranges[index + 1].lowerBound
        : range.upperBound
      let lineEndingRange = NSRange(lineRange.upperBound..<upperBound)
      let lineEnding = lineEndingRange.isEmpty ? nil : string.substring(with: lineEndingRange)

      return LogicalLine(contents: string.substring(with: lineRange), lineEnding: lineEnding)
    }
  }
}

extension Collection where Element == LogicalLine {

  /// Joins lines preserving line endings.
  ///
  /// - Parameters:
  ///   - baseLineEnding: The line ending to add when a line without one moves before a line-ending slot.
  ///   - includingTrailingLineEnding: Whether to include a line ending after the final line.
  /// - Returns: A joined string.
  package func joined(baseLineEnding: String, includingTrailingLineEnding: Bool = false) -> String {

    self.enumerated()
      .map { offset, line in
        let isLast = (offset == self.count - 1)
        let lineEnding =
          (isLast && !includingTrailingLineEnding) ? "" : (line.lineEnding ?? baseLineEnding)

        return line.contents + lineEnding
      }
      .joined()
  }
}
