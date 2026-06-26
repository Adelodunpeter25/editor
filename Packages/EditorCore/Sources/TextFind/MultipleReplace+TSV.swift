extension MultipleReplace {

  public struct TSVParseOptions: OptionSet, Sendable {

    public var rawValue: Int

    public static let failsOnInvalidValue = Self(rawValue: 1 << 0)

    public init(rawValue: Int) {

      self.rawValue = rawValue
    }
  }

  /// Creates a `MultipleReplace` from a tab-separated values (TSV) string.
  ///
  /// - Parameters:
  ///   - tabSeparatedText: The TSV-formatted source string.
  ///   - options: Parsing options.
  /// - Throws: `TSVParseError.invalidFormat` if an invalid line is encountered and `.failsOnInvalidValue` is specified.
  public init(tabSeparatedText: String, options: TSVParseOptions = []) throws {

    let lineBreakRegex = try! Regex("\\R")
    let replacements = try tabSeparatedText.split(separator: lineBreakRegex)
      .filter { !$0.isEmpty }
      .compactMap {
        do {
          return try Replacement(line: $0)
        } catch {
          if options.contains(.failsOnInvalidValue) {
            throw error
          } else {
            return nil
          }
        }
      }

    self.init(replacements: replacements)
  }
}

extension MultipleReplace.Replacement {

  enum TSVParseError: Error {

    case invalidFormat
  }

  /// Creates a `Replacement` from a single TSV line.
  ///
  /// - Parameter line: A single line of TSV input.
  /// - Throws: `TSVParseError.invalidFormat`.
  init(line: any StringProtocol) throws {

    let items = line.split(separator: "\t", omittingEmptySubsequences: false)

    guard
      items.count >= 2,
      !items[0].isEmpty
    else { throw TSVParseError.invalidFormat }

    self.init(findString: String(items[0]), replacementString: String(items[1]))
  }
}
