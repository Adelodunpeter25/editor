/// A range representation that allows negative values.
///
/// When a negative value is set, it generally counts the elements from the end of the sequence.
public struct FuzzyRange: Equatable, Sendable {

  public var location: Int
  public var length: Int = 0

  public init(location: Int, length: Int) {

    self.location = location
    self.length = length
  }
}
