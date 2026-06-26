import struct Foundation.NSRange

public struct EditingContext: Equatable, Sendable {

  public var strings: [String]
  public var ranges: [NSRange]
  public var selectedRanges: [NSRange]?

  /// Creates abstracted context how to edit strings in a text editor.
  ///
  /// - Parameters:
  ///   - strings: The strings to replace with.
  ///   - ranges: The ranges where replace with `strings`.
  ///   - selectedRanges: The new selected ranges after applying the replacements, or `nil` to let the editor set them.
  public init(strings: [String], ranges: [NSRange], selectedRanges: [NSRange]? = nil) {

    assert(strings.count == ranges.count)

    self.strings = strings
    self.ranges = ranges
    self.selectedRanges = selectedRanges
  }
}
