import Foundation

public struct FileAttributes: Equatable, Sendable {

  public var creationDate: Date?
  public var modificationDate: Date?
  public var size: Int64
  public var permissions: FilePermissions
  public var owner: String?
  public var tags: [FinderTag] = []

  public init(
    creationDate: Date? = nil, modificationDate: Date? = nil, size: Int64,
    permissions: FilePermissions, owner: String? = nil, tags: [FinderTag]
  ) {

    self.creationDate = creationDate
    self.modificationDate = modificationDate
    self.size = size
    self.permissions = permissions
    self.owner = owner
    self.tags = tags
  }
}

extension FileAttributes {

  public init(dictionary: [FileAttributeKey: Any]) {

    self.creationDate = dictionary[.creationDate] as? Date
    self.modificationDate = dictionary[.modificationDate] as? Date
    self.size = dictionary[.size] as? Int64 ?? 0
    self.permissions = FilePermissions(mask: dictionary[.posixPermissions] as? Int16 ?? 0)
    self.owner = dictionary[.ownerAccountName] as? String
    self.tags =
      (dictionary[.extendedAttributes] as? [String: Data])?[ExtendedFileAttributeName.userTags]
      .flatMap(FinderTag.tags(data:)) ?? []
  }
}
