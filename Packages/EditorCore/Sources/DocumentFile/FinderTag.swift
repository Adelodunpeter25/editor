import Foundation

public struct FinderTag: Equatable, Sendable {

  public enum Color: Int, CaseIterable, Sendable {

    case none
    case gray
    case green
    case purple
    case blue
    case yellow
    case red
    case orange

    /// The color list ordered like in the Finder (2025-02, macOS 15).
    public static let allCases: [Self] = [
      .none, .red, .orange, .yellow, .green, .blue, .purple, .gray,
    ]
  }

  public var name: String
  public var color: Color = .none

  public init(name: String, color: Color = .none) {

    self.name = name
    self.color = color
  }
}

extension FinderTag {

  /// Parses tags from the extended attribute data.
  ///
  /// - Parameter data: The bplist data.
  /// - Returns: `FinderTag`s.
  public static func tags(data: Data) -> [Self] {

    // -> The data is encoded as bplist.
    guard let strings = try? PropertyListDecoder().decode([String].self, from: data) else {
      return []
    }

    return strings.compactMap(Self.init(string:))
  }

  /// Instantiates a Finder tag from the string stored in the extended attributes.
  ///
  /// - Parameter string: The string stored in the extended attributes.
  private init?(string: String) {

    let components = string.split(separator: "\n")

    guard let name = components.first else { return nil }

    self.name = String(name)

    if components.count > 1,
      let number = Int(components[1]),
      let color = Color(rawValue: number)
    {
      self.color = color
    }
  }
}
