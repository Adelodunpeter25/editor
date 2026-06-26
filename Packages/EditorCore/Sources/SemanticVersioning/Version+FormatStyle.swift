import Foundation

extension Version {

  public struct FormatStyle: Codable, Sendable {

    public enum Part: Codable, Sendable {

      case minor
      case patch
      case prerelease
    }

    var part: Part

    init(_ part: Part = .prerelease) {

      self.part = part
    }
  }
}

extension Version.FormatStyle: FormatStyle {

  /// Formats version number.
  public func format(_ value: Version) -> String {

    switch self.part {
    case .minor:
      "\(value.major).\(value.minor)"
    case .patch:
      "\(value.major).\(value.minor).\(value.patch)"
    case .prerelease:
      if let prerelease = value.prereleaseIdentifier {
        "\(value.major).\(value.minor).\(value.patch)-\(prerelease)"
      } else {
        "\(value.major).\(value.minor).\(value.patch)"
      }
    }
  }
}

extension Version {

  public struct ParseStrategy: Foundation.ParseStrategy, Sendable {

    public enum ParseError: Error {

      case invalidValue
    }

    /// Creates an instance of the `ParseOutput` type from `value`.
    ///
    /// - Parameter value: The string representation of `Version` instance.
    /// - Returns: A `Version` instance.
    public func parse(_ value: String) throws -> Version {

      guard let version = Version(value) else {
        throw ParseError.invalidValue
      }

      return version
    }
  }
}

extension Version {

  /// Converts `self` to its textual representation.
  ///
  /// - Returns: A string.
  public func formatted() -> String {

    Self.FormatStyle().format(self)
  }

  /// Converts `self` to another representation.
  ///
  /// - Parameter style: The format for formatting `self`.
  /// - Returns: A representation of `self` using the given `style`.
  public func formatted<F: Foundation.FormatStyle>(_ style: F) -> F.FormatOutput
  where F.FormatInput == Self {

    style.format(self)
  }
}

extension FormatStyle where Self == Version.FormatStyle {

  /// Format Version in String.
  public static var version: Version.FormatStyle { self.version() }

  /// Formats Version in String.
  ///
  /// - Parameters:
  ///   - part: The format style.
  /// - Returns: A Version.FormatStyle.
  public static func version(part: Version.FormatStyle.Part = .prerelease) -> Version.FormatStyle {

    Version.FormatStyle(part)
  }
}

extension Version: CustomStringConvertible {

  public var description: String {

    self.formatted()
  }
}
