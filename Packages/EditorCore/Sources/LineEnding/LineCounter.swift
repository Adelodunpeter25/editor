import ValueRange

/// Counts line endings lazily.
public final class LineCounter: LazyLineEndingCaching {

  let string: String
  public internal(set) var lineEndings: [ValueRange<LineEnding>] = []
  var firstUnparsedIndex = 0

  public init(string: String) {

    self.string = string
  }
}
