import Foundation
import ValueRange

protocol LazyLineEndingCaching: AnyObject, LineRangeCalculating {

  /// The source string to parse line endings.
  var string: String { get }

  /// Line Endings sorted by location.
  var lineEndings: [ValueRange<LineEnding>] { get set }

  /// The first character index not yet parsed.
  var firstUnparsedIndex: Int { get set }
}

extension LazyLineEndingCaching {

  /// The UTF16-based length of the content string (implementation of `LineRangeCalculating`).
  public var length: Int {

    self.string.utf16.count
  }

  /// Calculates and caches `lineEndings` up to the line that contains the given character index, if not already done.
  ///
  /// - Parameters:
  ///   - characterIndex: The character index where needs the line number.
  ///   - needsNextEnd: Whether needs the next line ending to ensure the line range for the given `characterIndex`.
  func ensureLineEndings(upTo characterIndex: Int, needsNextEnd: Bool = false) {

    assert(characterIndex <= self.string.utf16.count)

    guard characterIndex >= self.firstUnparsedIndex else { return }

    guard self.length > 0 else { return }

    let parseRange = NSRange(self.firstUnparsedIndex..<characterIndex)
    var parsedRange = NSRange(location: NSNotFound, length: 0)
    var lineEndings = self.string.lineEndingRanges(in: parseRange, effectiveRange: &parsedRange)

    if needsNextEnd {
      let parsedUpper: Int
      if let next = self.string.nextLineEnding(at: parsedRange.upperBound) {
        lineEndings.append(next)
        parsedUpper = next.upperBound
      } else {
        parsedUpper = self.length
      }
      parsedRange = NSRange(parsedRange.lowerBound..<parsedUpper)
    }

    self.lineEndings.replace(items: lineEndings, in: parsedRange)
    self.firstUnparsedIndex = parsedRange.upperBound
  }
}
