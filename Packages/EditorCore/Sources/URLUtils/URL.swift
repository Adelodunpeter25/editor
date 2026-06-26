import Foundation

extension URL {

  /// Simply checks the reachability of the URL by ignoring errors.
  public var isReachable: Bool {

    (try? self.checkResourceIsReachable()) == true
  }

  /// Returns whether the URL points to a directory.
  ///
  /// - Note: This property uses cached resource if available.
  /// - Throws: An error if the resource values cannot be read.
  public var isDirectory: Bool {

    get throws {
      try self.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
    }
  }

  /// Returns the path string relative to the given URL.
  ///
  /// - Note: The `baseURL` is assumed its `directoryHint` is properly set.
  ///
  /// - Parameter baseURL: The URL the relative path based on.
  /// - Returns: A path string.
  public func path(relativeTo baseURL: URL) -> String {

    assert(self.isFileURL)
    assert(baseURL.isFileURL)

    let isDirectory = (try? baseURL.isDirectory) ?? baseURL.hasDirectoryPath

    if baseURL == self, !isDirectory {
      return self.lastPathComponent
    }

    let filename = self.lastPathComponent
    let pathComponents = self.pathComponents.dropLast()
    let basePathComponents = baseURL.pathComponents.dropLast(isDirectory ? 0 : 1)

    let sameCount = zip(basePathComponents, pathComponents).prefix(while: { $0.0 == $0.1 }).count
    let parentCount = basePathComponents.count - sameCount
    let parentComponents = [String](repeating: "..", count: parentCount)
    let diffComponents = pathComponents[sameCount...]
    let components = parentComponents + diffComponents + [filename]

    return components.joined(separator: "/")
  }

  /// Checks whether the receiver is an ancestor of the given URL.
  ///
  /// - Parameter url: The descendant candidate URL.
  /// - Returns: `true` if the receiver is an ancestor of the given URL.
  public func isAncestor(of url: URL) -> Bool {

    let ancestorComponents = self.standardizedFileURL.resolvingSymlinksInPath().pathComponents
    let childComponents = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents

    guard ancestorComponents.count < childComponents.count else { return false }

    return zip(ancestorComponents, childComponents).allSatisfy(==)
  }

  /// Returns the URL of the first unique directory among the given URLs.
  ///
  /// - Parameter urls: The file URLs to find.
  /// - Returns: A directory URL.
  public func firstUniqueDirectoryURL(in urls: [URL]) -> URL? {

    let duplicatedURLs =
      urls
      .filter { $0 != self }
      .filter { $0.lastPathComponent == self.lastPathComponent }

    guard !duplicatedURLs.isEmpty else { return nil }

    let components =
      duplicatedURLs
      .map { Array($0.pathComponents.reversed()) }

    let offset = self.pathComponents
      .reversed()
      .enumerated()
      .dropFirst()  // last path component is already checked
      .first { index, component in
        !components
          .filter { $0.indices.contains(index) }
          .map { $0[index] }
          .contains(component)
      }?
      .offset

    guard let offset else { return nil }

    return (0..<offset).reduce(into: self) { url, _ in url.deleteLastPathComponent() }
  }
}

// MARK: User Domain

extension FileManager {

  /// Creates intermediate directories to the given URL if not available.
  ///
  /// - Parameter fileURL: The file URL.
  /// - Throws: An error if the directory cannot be created.
  public final func createIntermediateDirectories(to fileURL: URL) throws {

    try self.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
  }
}

// MARK: Sandboxing

extension URL {

  private static let homeDirectory: String = {
    if let home = getpwuid(getuid())?.pointee.pw_dir {
      return FileManager.default.string(
        withFileSystemRepresentation: home, length: Int(strlen(home)))
    } else {
      return NSHomeDirectory()
    }
  }()

  /// A path string that replaces the user's home directory with a tilde (~) character.
  public var pathAbbreviatingWithTilde: String {

    let path = self.path(percentEncoded: false)

    guard path == Self.homeDirectory || path.hasPrefix(Self.homeDirectory + "/") else {
      return path
    }

    return path.replacingOccurrences(of: Self.homeDirectory, with: "~", options: .anchored)
  }
}
