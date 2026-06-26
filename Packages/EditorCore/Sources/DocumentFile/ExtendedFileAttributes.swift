import FileEncoding
import Foundation

extension FileAttributeKey {

  public static let extendedAttributes = FileAttributeKey("NSFileExtendedAttributes")
}

public enum ExtendedFileAttributeName {

  public static let encoding = "com.apple.TextEncoding"
  public static let userTags = "com.apple.metadata:_kMDItemUserTags"
  public static let verticalText = "com.coteditor.VerticalText"
  public static let allowLineEndingInconsistency = "com.coteditor.AllowLineEndingInconsistency"
}

public struct ExtendedFileAttributes: Equatable, Sendable {

  public var encoding: String.Encoding?
  public var isVerticalText: Bool = false
  public var allowsInconsistentLineEndings: Bool = false

  public init(dictionary: [FileAttributeKey: Any]) {

    let extendedAttributes = dictionary[.extendedAttributes] as? [String: Data]
    self.encoding = extendedAttributes?[ExtendedFileAttributeName.encoding]?.decodingXattrEncoding
    self.isVerticalText = (extendedAttributes?[ExtendedFileAttributeName.verticalText] != nil)
    self.allowsInconsistentLineEndings =
      (extendedAttributes?[ExtendedFileAttributeName.allowLineEndingInconsistency] != nil)
  }
}
