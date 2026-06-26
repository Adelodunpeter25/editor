import Foundation

public struct NumberingFormat: Sendable {

  private var format: @Sendable (String) -> String
  private var numberedFormat: @Sendable (String, Int) -> String

  public init(
    _ format: @escaping @Sendable (_ base: String) -> String,
    numbered numberedFormat: @escaping @Sendable (_ base: String, _ count: Int) -> String
  ) {

    self.format = format
    self.numberedFormat = numberedFormat
  }
}

extension URL {

  /// Creates an URL with a unique filename at the same directory by appending a unique number.
  ///
  /// - Parameters:
  ///   - format: The naming format.
  /// - Returns: A unique file URL, or `self` if it is already unique.
  public func appendingUniqueNumber(format: NumberingFormat? = nil) -> URL {

    let format = format ?? NumberingFormat({ $0 }, numbered: { "\($0) \($1)" })
    let filename = self.lastPathComponent
    let (baseName, count) = format.components(filename.deletingPathExtension)
    let baseURL = self.deletingLastPathComponent()
    let pathExtension = filename.pathExtension

    return (count...).lazy
      .map { format.filename(baseName, count: $0) }
      .map { baseURL.appending(component: $0) }
      .map { url in
        if let pathExtension {
          url.appendingPathExtension(pathExtension)
        } else {
          url
        }
      }
      .first { !$0.isReachable }!
  }
}

extension NumberingFormat {

  /// Creates the filename.
  ///
  /// - Parameters:
  ///   - base: The base name.
  ///   - count: The number to append.
  /// - Returns: A filename.
  func filename(_ base: String, count: Int) -> String {

    (count < 2) ? self.format(base) : self.numberedFormat(base, count)
  }

  /// Parses the given name into the base part of the name and the suffix number.
  ///
  /// - Parameter name: The name.
  /// - Returns: The base part of the name and the suffix number.
  func components(_ name: String) -> (base: String, count: Int) {

    if let match = try? self.multiRegex.wholeMatch(in: name), let count = Int(match.count) {
      let base = String(match.base)
      return if self.filename(base, count: count) == name {
        (base, count)
      } else {
        (name, 1)
      }
    } else if let match = try? self.singleRegex.wholeMatch(in: name) {
      return (String(match.base), 1)
    } else {
      return (name, 1)
    }
  }

  /// The regular expression for parsing a numbered name.
  private var multiRegex: Regex<(Substring, base: Substring, count: Substring)> {

    let pattern = NSRegularExpression.escapedPattern(for: self.numberedFormat("%@", 0))
      .replacing("%@", with: "(?<base>.+)")
      .replacing("0", with: "(?<count>[0-9]+)")

    return try! Regex(pattern)
  }

  /// The regular expression for parsing name.
  private var singleRegex: Regex<(Substring, base: Substring)> {

    let pattern = NSRegularExpression.escapedPattern(for: self.format("%@"))
      .replacing("%@", with: "(?<base>.+)")

    return try! Regex(pattern)
  }
}
