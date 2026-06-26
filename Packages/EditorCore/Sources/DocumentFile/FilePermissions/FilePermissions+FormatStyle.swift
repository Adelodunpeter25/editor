import Foundation

extension FilePermissions {

  public struct FormatStyle: Codable, Sendable {

    public enum Style: Codable, Sendable {

      /// Octal presentation like `644`.
      case octal

      /// Symbolic presentation like `-rw-r--r--`.
      case symbolic

      /// Both octal and symbolic presentations like `644 (-rw-r--r--)`.
      case full
    }

    var style: Style

    init(_ style: Style = .full) {

      self.style = style
    }
  }
}

extension FilePermissions.FormatStyle: FormatStyle {

  /// Formats permission number to human readable permission expression.
  public func format(_ value: FilePermissions) -> String {

    switch self.style {
    case .octal:
      value.octal
    case .symbolic:
      "-\(value.symbolic)"
    case .full:
      "\(value.octal) (-\(value.symbolic))"
    }
  }
}

extension FilePermissions {

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

extension FormatStyle where Self == FilePermissions.FormatStyle {

  /// Format POSIX permission mask in String.
  public static var filePermissions: FilePermissions.FormatStyle { self.filePermissions() }

  /// Formats POSIX permission mask in String.
  ///
  /// - Parameters:
  ///   - style: The format style.
  /// - Returns: A FilePermissions.FormatStyle.
  public static func filePermissions(_ style: FilePermissions.FormatStyle.Style = .full)
    -> FilePermissions.FormatStyle
  {

    FilePermissions.FormatStyle(style)
  }
}
