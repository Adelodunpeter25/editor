import Foundation
import SwiftTreeSitter

extension Query.Definition {

  static let outline = Self.custom("outline")
}

public final class LanguageRegistry {

  enum RegistryError: Error {

    case noQueriesDirectory
    case emptyQueries
  }

  // MARK: Public Properties

  public static let shared: LanguageRegistry = .init()

  // MARK: Private Properties

  /// Resolves the SwiftPM resource bundle (`Syntax_SyntaxParsers.bundle`) holding the `Queries` directory.
  ///
  /// `Bundle.module`'s generated accessor only checks the `.app` *root*
  /// (`Bundle.main.bundleURL` → `Editor.app/Syntax_...bundle`) and the baked
  /// build-machine path (`.../.build/...`), so a distributed `.app` (which must keep
  /// resources in `Contents/Resources/`) would `fatalError`. We check the real
  /// resource locations first and **never** call `Bundle.module` unless we know it
  /// would succeed — otherwise a missing bundle would still crash during static init.
  private static let resourceBundle: Bundle? = {
    // 1) Distributed .app: Contents/Resources/Syntax_SyntaxParsers.bundle (build.sh)
    if let res = Bundle.main.resourceURL {
      let url = res.appendingPathComponent("Syntax_SyntaxParsers.bundle")
      if let b = Bundle(url: url) { return b }
    }
    // 2) Generated accessor's mainPath: Editor.app/Syntax_...bundle (build.sh also copies there for SwiftTerm compat)
    let bundleURL = Bundle.main.bundleURL
    let url2 = bundleURL.appendingPathComponent("Syntax_SyntaxParsers.bundle")
    if let b = Bundle(url: url2) { return b }
    // 3) `swift run` / CLI: executable's directory is `.build/.../debug`
    if let execDir = Bundle.main.executableURL?.deletingLastPathComponent() {
      let url3 = execDir.appendingPathComponent("Syntax_SyntaxParsers.bundle")
      if let b = Bundle(url: url3) { return b }
      // Also check one level up for `swift build` layouts
      let url4 = execDir.deletingLastPathComponent().appendingPathComponent("debug/Syntax_SyntaxParsers.bundle")
      if let b = Bundle(url: url4) { return b }
    }
    // 4) Fallback via Bundle(for:) – works for tests / frameworks
    if let path = Bundle(for: LanguageRegistry.self).path(forResource: "Syntax_SyntaxParsers", ofType: "bundle"),
       let b = Bundle(path: path)
    {
      return b
    }
    // Intentionally do NOT call `Bundle.module` here – it would `fatalError` if the bundle
    // is absent (stripped install). Returning nil lets `init()` degrade gracefully.
    return nil
  }()

  private let directoryURL: URL
  private let lock = NSLock()
  private var cachedConfiguration: [TreeSitterSyntax: LanguageConfiguration] = [:]

  // MARK: Lifecycle

  init() {
    if let bundle = Self.resourceBundle,
       let url = bundle.url(forResource: "Queries", withExtension: nil)
    {
      self.directoryURL = url
      return
    }
    // Final fallback for `swift run` where the bundle is still at the baked
    // build path and none of the heuristics above matched: try Bundle.module
    // only if we can prove it would succeed (file exists at mainPath), otherwise
    // avoid calling it – it would `fatalError`.
    let mainPath = Bundle.main.bundleURL.appendingPathComponent("Syntax_SyntaxParsers.bundle").path
    if FileManager.default.fileExists(atPath: mainPath),
       let url = Bundle.module.url(forResource: "Queries", withExtension: nil)
    {
      self.directoryURL = url
      return
    }
    // Avoid crashing during static init (`LanguageRegistry.shared`) if the bundle
    // is missing (e.g. stripped install). Subsequent `configuration(for:)` calls
    // will throw `noQueriesDirectory` and highlighting gracefully degrades.
    self.directoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("missing-queries-\(UUID().uuidString)")
  }

  // MARK: Internal Methods

  /// Returns a provider mapping from a language provider/injection name to its `LanguageConfiguration`.
  ///
  /// - Parameters:
  ///   - name: The provider or injection name (e.g., "javascript", "markdown_inline").
  /// - Returns: A cached or newly created `LanguageConfiguration` if the language is supported, otherwise `nil`.
  func languageProvider(name: String) -> LanguageConfiguration? {

    guard let syntax = TreeSitterSyntax(providerName: name) else { return nil }

    return try? self.configuration(for: syntax)
  }

  /// Returns (and caches) a `LanguageConfiguration` for the given syntax.
  ///
  /// - Parameters:
  ///   - syntax: The target syntax.
  /// - Returns: A language configuration.
  func configuration(for syntax: TreeSitterSyntax) throws -> LanguageConfiguration {

    self.lock.lock()
    if let cache = self.cachedConfiguration[syntax] {
      self.lock.unlock()
      return cache
    }
    self.lock.unlock()

    let queriesURL = self.queriesURL(for: syntax)

    guard (try? queriesURL.checkResourceIsReachable()) == true else {
      throw RegistryError.noQueriesDirectory
    }

    let queries = syntax.loadQueries(at: queriesURL)

    guard !queries.isEmpty else { throw RegistryError.emptyQueries }

    let config = LanguageConfiguration(syntax.language, name: syntax.name, queries: queries)
    self.lock.lock()
    self.cachedConfiguration[syntax] = config
    self.lock.unlock()

    return config
  }

  /// Returns the file URL to the queries directory for the given syntax.
  ///
  /// - Parameters:
  ///   - syntax: The target syntax.
  /// - Returns: A file URL.
  func queriesURL(for syntax: TreeSitterSyntax) -> URL {

    self.directoryURL.appending(component: syntax.name)
  }
}

// MARK: -

extension TreeSitterSyntax {

  /// Resolves from provider/injection name.
  ///
  /// - Parameter providerName: The provider name.
  fileprivate init?(providerName: String) {

    let lowercased = providerName.lowercased()

    guard
      let syntax = Self.allCases.first(where: { $0.providerName == lowercased })
    else { return nil }

    self = syntax
  }

  /// Loads query files from the given directory.
  ///
  /// - Parameters:
  ///   - queriesURL: The queries directory URL.
  /// - Returns: The loaded queries keyed by their definition.
  fileprivate func loadQueries(at queriesURL: URL) -> [Query.Definition: Query] {

    let definitions: [Query.Definition] = [
      .injections,
      .highlights,
      .outline,
    ]

    var queries: [Query.Definition: Query] = [:]
    for definition in definitions {
      let queryURL = queriesURL.appending(path: definition.filename)

      guard (try? queryURL.resourceValues(forKeys: [.isReadableKey]))?.isReadable == true else {
        continue
      }

      let language = Language(self.language)
      do {
        queries[definition] = try Query(language: language, url: queryURL)
      } catch {
        assertionFailure(
          "failed open \(self.name)'s \(queryURL.lastPathComponent): \(error.localizedDescription)")
      }
    }

    return queries
  }
}
