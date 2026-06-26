public struct ParserFeatures: OptionSet, Sendable {

  public var rawValue: Int

  public static let highlight = Self(rawValue: 1 << 0)
  public static let outline = Self(rawValue: 1 << 1)

  public static let all: Self = [.highlight, .outline]

  public init(rawValue: Int) {

    self.rawValue = rawValue
  }
}
