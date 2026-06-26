import Foundation

public struct TextClipping: Equatable, Sendable, Decodable {

  public static let pathExtension = "textClipping"

  public var string: String

  enum CodingKeys: String, CodingKey {

    case string = "public.utf8-plain-text"
  }

  public init(contentsOf url: URL) throws {

    let data = try Data(contentsOf: url)
    let plist = try PropertyListDecoder().decode([String: TextClipping].self, from: data)

    guard let textClipping = plist["UTI-Data"] else {
      throw CocoaError.error(.coderReadCorrupt, url: url)
    }

    self = textClipping
  }
}
