extension UTF32.CodeUnit {

  /// The standard hexadecimal representation of the code unit.
  var codePoint: String {

    String(self, radix: 16, uppercase: true)
      .leftPadding(toLength: 4, withPad: "0")
  }
}

extension UTF16.CodeUnit {

  /// The standard hexadecimal representation of the code unit.
  var codePoint: String {

    String(self, radix: 16, uppercase: true)
      .leftPadding(toLength: 4, withPad: "0")
  }
}

extension String {

  /// Returns a new string padded on the left to at least the specified length.
  ///
  /// - Parameters:
  ///   - length: The minimum length of the resulting string.
  ///   - character: The character to use for left padding.
  /// - Returns: The left-padded string, or the original string if no padding is needed.
  fileprivate func leftPadding(toLength length: Int, withPad character: Character) -> String {

    if self.count < length {
      String(repeating: character, count: length - self.count) + self
    } else {
      self
    }
  }
}
