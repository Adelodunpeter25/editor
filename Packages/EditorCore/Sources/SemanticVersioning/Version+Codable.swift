extension Version: Codable {

  public init(from decoder: any Decoder) throws {

    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)

    guard let version = Version(string) else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Unsupported version expression")
    }

    self = version
  }

  public func encode(to encoder: any Encoder) throws {

    var container = encoder.singleValueContainer()

    try container.encode(self.formatted())
  }
}
