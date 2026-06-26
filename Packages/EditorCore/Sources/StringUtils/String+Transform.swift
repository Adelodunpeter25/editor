extension StringProtocol {

  /// Transforms half-width roman characters to full-width forms, or vice versa.
  ///
  /// - Parameter reverse: `True` to transform from full-width to half-width.
  /// - Returns: A transformed string.
  public func fullwidthRoman(reverse: Bool = false) -> String {

    self.unicodeScalars
      .map { $0.convertedToFullwidthRoman(reverse: reverse) ?? $0 }
      .reduce(into: "") { $0.unicodeScalars.append($1) }
  }
}

extension String {

  /// Straightens all curly quotes.
  public var straighteningQuotes: String {

    let leftQuotes = try! Regex("[‘’‚‛]")
    let rightQuotes = try! Regex("[“”„‟]")
    return self.replacing(leftQuotes, with: "'")  // U+2018..201B
      .replacing(rightQuotes, with: "\"")  // U+201C..201F
  }
}

// MARK: - Private Extensions

extension Unicode.Scalar {

  private static let fullwidthRomanRange: ClosedRange<UTF32.CodeUnit> = 0xFF01...0xFF5E
  private static let widthShifter: UTF32.CodeUnit = 0xFEE0

  /// Converts this scalar between half-width and full-width roman forms when applicable.
  ///
  /// - Parameters:
  ///   - reverse: Pass `true` to convert from full-width to half-width.
  /// - Returns: The converted scalar if the conversion was applied, otherwise `nil`.
  fileprivate func convertedToFullwidthRoman(reverse: Bool = false) -> Self? {

    let fullwidthValue = reverse ? self.value : self.value + Self.widthShifter

    guard Self.fullwidthRomanRange.contains(fullwidthValue) else { return nil }

    let newScalar =
      reverse
      ? self.value - Self.widthShifter
      : self.value + Self.widthShifter

    return Self(newScalar)
  }
}
