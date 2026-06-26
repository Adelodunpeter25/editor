public enum Invisible: Sendable, CaseIterable {

  case newLine
  case tab
  case space
  case noBreakSpace
  case fullwidthSpace
  case otherWhitespace  // Unicode Category Zs (excl. U+1680)
  case otherControl  // Unicode Category Cc and some of Cf

  public init?(codeUnit: UTF16.CodeUnit) {

    // > NSGlyphGenerator generates NSControlGlyph for all characters
    // > in the Unicode General Category C* and U200B (ZERO WIDTH SPACE).
    //   cf. https://developer.apple.com/documentation/appkit/nscontrolglyph

    switch codeUnit {
    case 0x000A,  // LINE FEED (Cc) a.k.a. \n
      0x000D,  // CARRIAGE RETURN (Cc) a.k.a. \r
      0x0085,  // NEW LINE (Cc)
      0x2028,  // LINE SEPARATOR (Zl)
      0x2029:  // PARAGRAPH SEPARATOR (Zp)
      self = .newLine
    case 0x0009:  // HORIZONTAL TABULATION (Cc) a.k.a. \t
      self = .tab
    case 0x0020:  // SPACE (Zs)
      self = .space
    case 0x00A0,  // NO-BREAK SPACE (Zs)
      0x2007,  // FIGURE SPACE (Zs)
      0x202F:  // NARROW NO-BREAK SPACE (Zs)
      self = .noBreakSpace
    case 0x3000:  // IDEOGRAPHIC SPACE (Zs) a.k.a. Japanese full-width space
      self = .fullwidthSpace
    case 0x2000...0x200A,  // (Zs) various width spaces, such as THREE-PER-EM SPACE
      0x205F:  // MEDIUM MATHEMATICAL SPACE (Zs)
      self = .otherWhitespace
    case 0x0000...0x001F, 0x007F...0x009F,  // C0 and C1 (Cc)
      0x200B,  // ZERO WIDTH SPACE (Cf)
      0x200C,  // ZERO WIDTH NON-JOINER (Cf)
      0x2060,  // WORD JOINER (Cf)
      0xFEFF,  // ZERO WIDTH NO-BREAK SPACE a.k.a. BOM (Cf)
      0x061C, 0x200E...0x200F, 0x202A...0x202E, 0x2066...0x206F,  // bidi controls (Cf)
      0x2061...0x2065,  // invisible operators (Cf)
      0xFFF9...0xFFFB:  // interlinear annotations, controls for ruby (Cf)
      self = .otherControl
    default:
      return nil
    }
  }
}

extension Invisible {

  /// The character representation to print in text.
  public var symbol: Character {

    switch self {
    case .newLine: "↩"
    case .tab: "→"
    case .space: "·"
    case .noBreakSpace: "·̂"
    case .fullwidthSpace: "□"
    case .otherWhitespace: "⹀"
    case .otherControl: "�"
    }
  }
}
