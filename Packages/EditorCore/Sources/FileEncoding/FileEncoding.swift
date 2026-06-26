import Foundation

public struct FileEncoding: Equatable, Hashable, Sendable {

  public static let utf8 = FileEncoding(encoding: .utf8)

  public var encoding: String.Encoding
  public var withUTF8BOM: Bool = false

  public init(encoding: String.Encoding, withUTF8BOM: Bool = false) {

    assert(encoding == .utf8 || !withUTF8BOM)

    self.encoding = encoding
    self.withUTF8BOM = withUTF8BOM
  }

  /// Human-readable encoding name by taking UTF-8 BOM into consideration.
  ///
  /// The `withUTF8BOM` flag is just ignored when `encoding` is other than UTF-8.
  public var localizedName: String {

    assert(self.encoding == .utf8 || !self.withUTF8BOM)

    let localizedName = String.localizedName(of: self.encoding)

    return (self.encoding == .utf8 && self.withUTF8BOM)
      ? "\(localizedName) with BOM"
      : localizedName
  }
}
