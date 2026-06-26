import Foundation
import SwiftTreeSitter
import SyntaxFormat

enum BashOutlineFormatter: TreeSitterOutlineFormatting {

  static func title(for match: QueryMatch, capture: OutlineCapture, source: NSString) -> (
    title: String, range: NSRange
  )? {

    switch capture.kind {
    case .function:
      return (
        title: source.substring(with: capture.range) + "()",
        range: Self.signatureRange(for: capture.range, source: source)
      )
    default:
      return Self.defaultTitle(capture: capture, source: source)
    }
  }
}

extension BashOutlineFormatter {

  /// Returns the Bash signature range, including `()` when present in source.
  ///
  /// - Parameters:
  ///   - nameRange: The captured function name range.
  ///   - source: The source text as `NSString`.
  /// - Returns: The signature range.
  fileprivate static func signatureRange(for nameRange: NSRange, source: NSString) -> NSRange {

    // -> `32` is a generous upper bound for whitespace before "()" in a Bash function definition.
    let searchEnd = min(source.length, nameRange.upperBound + 32)

    guard nameRange.upperBound < searchEnd else { return nameRange }

    let searchRange = NSRange(
      location: nameRange.upperBound, length: searchEnd - nameRange.upperBound)
    let matchRange = source.range(of: #"^\s*\(\)"#, options: .regularExpression, range: searchRange)

    guard matchRange.location != NSNotFound else { return nameRange }

    return NSRange(location: nameRange.location, length: nameRange.length + matchRange.length)
  }
}
