public struct EntireLineSortPattern: SortPattern, Equatable, Sendable {

  public init() {}

  // MARK: Sort Pattern Methods

  public func sortKey(for line: String) -> String? {

    line
  }

  public func range(for line: String) -> Range<String.Index>? {

    line.startIndex..<line.endIndex
  }

  public func validate() throws {}
}
