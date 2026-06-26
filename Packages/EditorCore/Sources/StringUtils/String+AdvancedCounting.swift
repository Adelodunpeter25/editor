import Foundation

public struct CharacterCountOptions: Sendable {

  public enum CharacterUnit: String, Sendable, CaseIterable {

    case graphemeCluster
    case unicodeScalar
    case utf16
    case byte
  }

  public var unit: CharacterUnit
  public var normalizationForm: UnicodeNormalizationForm?
  public var ignoresNewlines: Bool
  public var ignoresWhitespaces: Bool
  public var treatsConsecutiveWhitespaceAsSingle: Bool
  public var encoding: String.Encoding

  public init(
    unit: CharacterUnit = .graphemeCluster, normalizationForm: UnicodeNormalizationForm? = nil,
    ignoresNewlines: Bool = false, ignoresWhitespaces: Bool = false,
    treatsConsecutiveWhitespaceAsSingle: Bool = false, encoding: String.Encoding = .utf8
  ) {

    self.unit = unit
    self.normalizationForm = normalizationForm
    self.ignoresNewlines = ignoresNewlines
    self.ignoresWhitespaces = ignoresWhitespaces
    self.treatsConsecutiveWhitespaceAsSingle = treatsConsecutiveWhitespaceAsSingle
    self.encoding = encoding
  }
}

extension String {

  /// Counts string in the way described in the `option`.
  ///
  /// - Parameter options: The way to count.
  /// - Returns: Counted number, or nil if failed.
  public func count(options: CharacterCountOptions) -> Int? {

    guard !self.isEmpty else { return 0 }

    var string = self

    if options.ignoresNewlines {
      let regex = try! Regex("\\R")
      string = string.replacing(regex, with: "")
    }
    if options.ignoresWhitespaces {
      let regex = try! Regex("[\\t\\p{Zs}]")
      string = string.replacing(regex, with: "")
    }
    if options.treatsConsecutiveWhitespaceAsSingle,
      !options.ignoresNewlines || !options.ignoresWhitespaces
    {
      // \s = [\t\n\f\r\p{Z}]
      let regex = try! Regex("\\s{2,}")
      string = string.replacing(regex, with: " ")
    }

    if let normalizationForm = options.normalizationForm {
      string = string.normalizing(in: normalizationForm)
    }

    switch options.unit {
    case .graphemeCluster:
      return string.count
    case .unicodeScalar:
      return string.unicodeScalars.count
    case .utf16:
      return string.utf16.count
    case .byte:
      guard string.canBeConverted(to: options.encoding) else { return nil }
      return string.lengthOfBytes(using: options.encoding)
    }
  }
}
