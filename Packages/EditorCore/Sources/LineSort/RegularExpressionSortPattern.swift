import Foundation
import StringUtils

public struct RegularExpressionSortPattern: SortPattern, Equatable, Sendable {

  public var searchPattern: String
  public var ignoresCase: Bool
  public var usesCaptureGroup: Bool
  public var group: Int

  public var numberOfCaptureGroups: Int { (try? self.regex)?.numberOfCaptureGroups ?? 0 }

  public init(
    searchPattern: String = "", ignoresCase: Bool = true, usesCaptureGroup: Bool = false,
    group: Int = 1
  ) {

    self.searchPattern = searchPattern
    self.ignoresCase = ignoresCase
    self.usesCaptureGroup = usesCaptureGroup
    self.group = group
  }

  // MARK: Sort Pattern Methods

  public func sortKey(for line: String) -> String? {

    guard let range = self.range(for: line) else { return nil }

    return String(line[range])
  }

  public func range(for line: String) -> Range<String.Index>? {

    guard
      let regex = try? self.regex,
      let match = regex.firstMatch(in: line, range: line.nsRange)
    else { return nil }

    if self.usesCaptureGroup {
      guard (0..<match.numberOfRanges).contains(self.group) else { return nil }
      return Range(match.range(at: self.group), in: line)
    } else {
      return Range(match.range, in: line)
    }
  }

  /// Tests the regular expression pattern is valid.
  public func validate() throws {

    if self.searchPattern.isEmpty {
      throw SortPatternError.emptyPattern
    }

    let regex: NSRegularExpression
    do {
      regex = try self.regex
    } catch {
      throw SortPatternError.invalidRegularExpressionPattern
    }

    guard !self.usesCaptureGroup || (0...regex.numberOfCaptureGroups).contains(self.group) else {
      throw SortPatternError.invalidRegularExpressionPattern
    }
  }

  // MARK: Private Methods

  private var regex: NSRegularExpression {

    get throws {
      try NSRegularExpression(
        pattern: self.searchPattern, options: self.ignoresCase ? [.caseInsensitive] : [])
    }
  }
}
