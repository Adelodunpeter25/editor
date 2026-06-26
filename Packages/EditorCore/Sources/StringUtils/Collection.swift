// MARK: Unique

extension Sequence where Element: Hashable {

  /// An array consists of unique elements of receiver by keeping ordering.
  public var uniqued: [Element] {

    var seen = Set<Element>()

    return self.filter { seen.insert($0).inserted }
  }
}

extension Array where Element: Hashable {

  /// Removes duplicated elements by keeping ordering.
  public mutating func unique() {

    self = self.uniqued
  }
}

// MARK: Count

public enum QuantityComparisonResult: Sendable {

  case less, equal, greater
}

extension Sequence {

  /// Performance efficient way to compare the number of elements with the given number.
  ///
  /// - Note: This method takes advantage especially when counting elements is heavy (such as String count) and the number to compare is small.
  ///
  /// - Parameter number: The number of elements to test.
  /// - Returns: The result whether the number of the elements in the receiver is less than, equal, or more than the given number.
  public func compareCount(with number: Int) -> QuantityComparisonResult {

    assert(number >= 0, "The count number to compare should be a natural number.")
    assert(number < 5, "This method should be used only for a small number comparison.")

    guard number >= 0 else { return .greater }

    var count = 0
    for _ in self {
      count += 1
      if count > number { return .greater }
    }

    return (count == number) ? .equal : .less
  }
}
