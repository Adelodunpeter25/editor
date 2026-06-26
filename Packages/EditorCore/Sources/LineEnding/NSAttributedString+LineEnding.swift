import Foundation

extension NSMutableAttributedString {

  /// Replaces all line endings in the receiver with given line endings.
  ///
  /// - Parameters:
  ///     - lineEnding: The line ending type with which to replace the target.
  public final func replaceLineEndings(with lineEnding: LineEnding) {

    // -> Intentionally avoid replacing characters in the mutableString directly,
    //    because it posts a quantity of small edited notifications,
    //    which costs high. (2023-11, macOS 14)
    self.replaceCharacters(
      in: NSRange(..<self.length), with: self.string.replacingLineEndings(with: lineEnding))
  }
}
