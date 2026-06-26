public struct Pair<T> {

  public var begin: T
  public var end: T

  public var array: [T] { [begin, end] }

  public init(_ begin: T, _ end: T) {

    self.begin = begin
    self.end = end
  }
}

extension Pair: Equatable where T: Equatable {}
extension Pair: Hashable where T: Hashable {}
extension Pair: Sendable where T: Sendable {}

extension Pair: CustomDebugStringConvertible {

  public var debugDescription: String {

    "Pair(\(self.begin), \(self.end))"
  }
}
