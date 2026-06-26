import Foundation

extension FuzzyRange {

  /// Gets a formatted string from a format style.
  ///
  /// - Parameter style: The fuzzy range format style.
  /// - Returns: A formatted string.
  public func formatted(_ style: FormatStyle = .init()) -> FormatStyle.FormatOutput {

    style.format(self)
  }
}

extension FormatStyle where Self == FuzzyRange.FormatStyle {

  public static var fuzzyRange: FuzzyRange.FormatStyle {

    FuzzyRange.FormatStyle()
  }
}

extension FuzzyRange {

  public struct FormatStyle: ParseableFormatStyle, Sendable {

    public var parseStrategy: ParseStrategy {

      ParseStrategy()
    }

    public func format(_ value: FuzzyRange) -> String {

      (0...1).contains(value.length)
        ? String(value.location)
        : String(value.location) + ":" + String(value.length)
    }

    public init() {}
  }
}

extension FuzzyRange {

  public struct ParseStrategy: Foundation.ParseStrategy, Sendable {

    public enum ParseError: Error {

      case invalidValue
    }

    /// Creates an instance of the `ParseOutput` type from `value`.
    ///
    /// - Parameter value: The string representation of `FuzzyRange` instance.
    /// - Returns: A `FuzzyRange` instance.
    public func parse(_ value: String) throws -> FuzzyRange {

      let components = value.split(separator: ":", omittingEmptySubsequences: false)

      guard
        (1...2).contains(components.count),
        let location = Int(components[0]),
        let length = (components.count > 1) ? Int(components[1]) : 0
      else { throw ParseError.invalidValue }

      return FuzzyRange(location: location, length: length)
    }
  }
}
