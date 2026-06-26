public enum LineEnding: Character, Sendable, CaseIterable {

  case lf = "\n"
  case cr = "\r"
  case crlf = "\r\n"
  case nel = "\u{0085}"
  case lineSeparator = "\u{2028}"
  case paragraphSeparator = "\u{2029}"

  /// The string representation of the line ending.
  public var string: String {

    String(self.rawValue)
  }

  /// The length in Unicode scalars.
  public var length: Int {

    self.rawValue.unicodeScalars.count
  }

  /// The index in the `enum`.
  public var index: Int {

    Self.allCases.firstIndex(of: self)!
  }

  /// Whether the line ending is a basic one.
  public var isBasic: Bool {

    switch self {
    case .lf, .cr, .crlf: true
    case .nel, .lineSeparator, .paragraphSeparator: false
    }
  }

  /// The short label to display.
  public var label: String {

    switch self {
    case .lf: "LF"
    case .cr: "CR"
    case .crlf: "CRLF"
    case .nel: "NEL"
    case .lineSeparator: "LS"
    case .paragraphSeparator: "PS"
    }
  }

  /// The localized name to display.
  public var localizedName: String {

    self.label
  }

  /// Detect the line ending type from a string.
  ///
  /// - Parameter string: The string to detect line endings from.
  /// - Returns: The detected line ending type, or nil if no line endings found.
  public static func detect(in string: String) -> LineEnding? {

    let ranges = string.lineEndingRanges()
    return ranges.first?.value
  }
}
