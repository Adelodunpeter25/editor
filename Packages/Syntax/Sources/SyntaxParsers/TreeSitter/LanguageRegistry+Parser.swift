extension LanguageRegistry {

  /// Returns the parser and feature support for the given tree-sitter syntax.
  ///
  /// - Parameters:
  ///   - syntax: The tree-sitter syntax to look up in the registry.
  /// - Returns: A tuple of the parser and the supported features derived from available queries.
  /// - Throws: Any error that occurs while resolving the language layer.
  public func parser(syntax: TreeSitterSyntax) throws -> any HighlightParsing & OutlineParsing {

    let config = try self.configuration(for: syntax)

    return try TreeSitterClient(
      languageConfig: config, languageProvider: self.languageProvider, syntax: syntax)
  }
}
