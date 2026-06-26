import AppKit
import SyntaxFormat
import SyntaxParsers
import ValueRange

/// Maps a file path or language key to a tree-sitter parser and converts the parser's `Highlight`
/// array into color spans for the editor.
///
/// The Syntax package exposes `LanguageRegistry.shared.parser(syntax:)` which returns an actor
/// conforming to `HighlightParsing & OutlineParsing`. Because the parser is an actor, all calls
/// are async; the highlighter keeps a single long-lived parser per language and feeds it the full
/// document text on each request (incremental edits are supported via `noteEdit` but the editor
/// currently re-tokenizes the whole document, matching the TextMate path).
final class TreeSitterHighlighter {
  private let parser: any HighlightParsing & OutlineParsing
  private let syntax: TreeSitterSyntax

  private init(parser: any HighlightParsing & OutlineParsing, syntax: TreeSitterSyntax) {
    self.parser = parser
    self.syntax = syntax
  }

  // MARK: Loading & caching

  private static var cache: [String: TreeSitterHighlighter] = [:]
  private static let cacheLock = NSLock()

  /// Highlighter for a file, by extension / well-known filename. `nil` → no tree-sitter grammar.
  static func forPath(_ path: String) -> TreeSitterHighlighter? {
    guard let language = LanguageUtil.language(forPath: path) else { return nil }
    return load(language: language)
  }

  /// Highlighter for a fenced-code-block language tag. `nil` → no tree-sitter grammar.
  static func forLanguage(_ fence: String) -> TreeSitterHighlighter? {
    return load(language: LanguageUtil.resolveAlias(fence))
  }

  /// All tree-sitter-supported language keys, sorted (for the status-bar picker).
  /// Uses the primary (first) language key for each syntax.
  static var availableLanguages: [String] {
    TreeSitterSyntax.allCases.compactMap { $0.languageKeys.first }.sorted()
  }

  private static func load(language: String) -> TreeSitterHighlighter? {
    cacheLock.lock()
    if let hit = cache[language] {
      cacheLock.unlock()
      return hit
    }
    cacheLock.unlock()

    // Resolve the language key to a TreeSitterSyntax via the Syntax package's built-in mapping.
    guard let syntax = TreeSitterSyntax(languageKey: language) else { return nil }

    do {
      let parser = try LanguageRegistry.shared.parser(syntax: syntax)
      let hl = TreeSitterHighlighter(parser: parser, syntax: syntax)
      cacheLock.lock()
      cache[language] = hl
      cacheLock.unlock()
      return hl
    } catch {
      return nil
    }
  }

  // MARK: Tokenizing

  /// Color spans for `text`, computed asynchronously via the tree-sitter parser.
  /// Returns spans on the main actor so the caller can apply them directly.
  func spans(for text: String) async -> [(NSRange, NSColor)] {
    let ns = text as NSString
    let fullRange = NSRange(location: 0, length: ns.length)
    guard fullRange.length > 0 else { return [] }

    do {
      guard let result = try await parser.parseHighlights(in: text, range: fullRange) else {
        return []
      }
      return result.highlights.compactMap { highlight in
        guard let color = TreeSitterTheme.color(for: highlight.value) else { return nil }
        return (highlight.range, color)
      }
    } catch {
      return []
    }
  }

  /// The language key for this highlighter (used by the status bar).
  var languageKey: String { syntax.rawValue }
}
