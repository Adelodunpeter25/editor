import Foundation

/// Edited range storage to postpone validations.
///
/// This is similar to the IndexSet but preserving zero-width edited ranges.
public struct EditedRangeSet: Sendable {

  private(set) var ranges: [NSRange] = []

  public init(range: NSRange? = nil) {

    if let range {
      self.ranges = [range]
    }
  }

  /// A Boolean value indicating whether the collection is empty.
  public var isEmpty: Bool {

    self.ranges.isEmpty
  }

  /// The range that contains all ranges.
  public var range: NSRange? {

    self.ranges.union
  }

  /// The ranges as an `IndexSet`.
  public var indexSet: IndexSet {

    self.ranges.reduce(into: IndexSet()) { set, range in
      set.insert(integersIn: range.lowerBound..<range.upperBound)
    }
  }

  /// Clears all stored ranges.
  public mutating func clear() {

    self.ranges.removeAll()
  }

  /// Clear the current ranges and replaces with the given range.
  ///
  /// - Parameter editedRange: The new range.
  public mutating func update(editedRange: NSRange) {

    self.ranges = [editedRange]
  }

  /// Updates edit ranges by assuming the string was edited in an NSTextStorage and the storage returns the given `editedRange` and `changeInLength`.
  ///
  /// - Parameters:
  ///   - editedRange: The current remained range where edited.
  ///   - changeInLength: The difference between the current length of the edited range and its length before editing.
  public mutating func append(editedRange: NSRange, changeInLength: Int) {

    assert(editedRange.location != NSNotFound)

    let effectRange = NSRange(
      location: editedRange.location, length: editedRange.length - changeInLength)

    var added = false
    self.ranges = self.ranges.reduce(into: []) { ranges, range in
      if range.upperBound < editedRange.lowerBound {
        ranges.append(range)

      } else if effectRange.touches(range) {
        let union = range.union(effectRange)
        let modifiedRange = NSRange(location: union.location, length: union.length + changeInLength)

        if added, let last = ranges.last, last.touches(modifiedRange) {
          ranges[ranges.endIndex - 1].formUnion(modifiedRange)
        } else {
          ranges.append(modifiedRange)
          added = true
        }

      } else {
        ranges.append(range.shifted(by: changeInLength))
      }
    }

    if !added {
      let index =
        self.ranges.firstIndex { editedRange.location < $0.location } ?? self.ranges.endIndex

      self.ranges.insert(editedRange, at: index)
    }
  }
}
