//
//  LanguageRegistry.swift
//  Syntax
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-01-23.
//
//  ---------------------------------------------------------------------------
//
//  © 2026 1024jp
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

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

  private let directoryURL: URL
  private let lock = NSLock()
  private var cachedConfiguration: [TreeSitterSyntax: LanguageConfiguration] = [:]

  // MARK: Lifecycle

  init() {

    self.directoryURL = Bundle.module.url(forResource: "Queries", withExtension: nil)!
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
