import Foundation

extension URL {

  /// Gets extended attribute.
  ///
  /// - Parameter name: The key name of the attribute to get.
  /// - Returns: Data.
  public func extendedAttribute(for name: String) throws -> Data {

    try self.withUnsafeFileSystemRepresentation { fileSystemPath -> Data in
      // check buffer size
      let length = getxattr(fileSystemPath, name, nil, 0, 0, XATTR_NOFOLLOW)

      guard length >= 0 else { throw POSIXError(err: errno) }

      // get xattr data
      var data = Data(count: length)
      let size = data.withUnsafeMutableBytes {
        getxattr(fileSystemPath, name, $0.baseAddress, length, 0, XATTR_NOFOLLOW)
      }

      guard size >= 0 else { throw POSIXError(err: errno) }

      return data
    }
  }

  /// Sets extended attribute.
  ///
  /// - Parameters:
  ///   - data: The data to set.
  ///   - name: The attribute key name to set.
  public func setExtendedAttribute(data: Data?, for name: String) throws {

    // remove if nil is passed
    guard let data else {
      return try self.removeExtendedAttribute(for: name)
    }

    try self.withUnsafeFileSystemRepresentation { fileSystemPath in
      let size = data.withUnsafeBytes {
        setxattr(fileSystemPath, name, $0.baseAddress, data.count, 0, XATTR_NOFOLLOW)
      }

      guard size >= 0 else { throw POSIXError(err: errno) }
    }
  }

  /// Removes extended attribute.
  ///
  /// - Parameter name: The attribute key name to remove.
  private func removeExtendedAttribute(for name: String) throws {

    try self.withUnsafeFileSystemRepresentation { fileSystemPath in
      let size = removexattr(fileSystemPath, name, XATTR_NOFOLLOW)

      guard size >= 0 else { throw POSIXError(err: errno) }
    }
  }
}

extension POSIXError {

  fileprivate init(err: Int32) {

    self.init(Code(rawValue: err)!)
  }
}
