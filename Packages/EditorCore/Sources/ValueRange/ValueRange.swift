import struct Foundation.NSRange

public struct ValueRange<Value> {

  public var value: Value
  public var range: NSRange

  public var lowerBound: Int { self.range.lowerBound }
  public var upperBound: Int { self.range.upperBound }

  public init(value: Value, range: NSRange) {

    self.value = value
    self.range = range
  }

  /// Returns a copy by shifting the range location toward the given offset.
  ///
  /// - Parameter offset: The offset to shift.
  /// - Returns: A new ValueRange.
  public func shifted(by offset: Int) -> Self {

    Self(value: self.value, range: self.range.shifted(by: offset))
  }

  /// Shifts the range location toward the given offset.
  ///
  /// - Parameter offset: The offset to shift.
  public mutating func shift(by offset: Int) {

    self.range.location += offset
  }
}

extension ValueRange: Equatable where Value: Equatable {}
extension ValueRange: Hashable where Value: Hashable {}
extension ValueRange: Sendable where Value: Sendable {}

// MARK: - Private

extension NSRange {

  /// Returns a copied NSRange but whose location is shifted toward the given `offset`.
  ///
  /// - Parameter offset: The offset to shift.
  /// - Returns: A new NSRange.
  fileprivate func shifted(by offset: Int) -> NSRange {

    NSRange(location: self.location + offset, length: self.length)
  }
}
