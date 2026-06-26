public typealias SymbolPair = Pair<Character>

extension Pair where T == Character {

  public static let braces: [SymbolPair] = [
    SymbolPair("(", ")"),
    SymbolPair("{", "}"),
    SymbolPair("[", "]"),
  ]
  public static let quotes: [SymbolPair] = [
    SymbolPair("\"", "\""),
    SymbolPair("'", "'"),
    SymbolPair("`", "`"),
  ]
  public static let ltgt = SymbolPair("<", ">")

  public enum PairIndex: Equatable, Sendable {

    case begin(String.Index)
    case end(String.Index)
  }
}

extension Pair.PairIndex {

  /// The representing string index.
  public var index: String.Index {

    switch self {
    case .begin(let index), .end(let index): index
    }
  }
}

extension String {

  /// Finds the range enclosed by one of given symbol pairs.
  ///
  /// - Parameters:
  ///   - range: The character range on which to base the search.
  ///   - candidates: The pairs of symbols to search.
  ///   - escapeCharacter: The escape character, or `nil` for no escape.
  /// - Returns: The range of the enclosing symbol pair, or `nil` if not found.
  public func rangeOfEnclosingSymbolPair(
    at range: Range<Index>, candidates: [SymbolPair], escapeCharacter: Character? = nil
  ) -> Range<Index>? {

    SymbolPairScanner(
      string: self, candidates: candidates, baseRange: range, escapeCharacter: escapeCharacter
    )
    .scan()
  }

  /// Finds the range enclosed by the symbol pair, one of which locates at the given index.
  ///
  /// - Parameters:
  ///   - index: The character index of the symbol character to find the mate.
  ///   - candidates: Symbol pairs to find.
  ///   - pairToIgnore: The symbol pair in which symbol characters should be ignored.
  ///   - escapeCharacter: The escape character, or `nil` for no escape.
  /// - Returns: The range enclosed by the symbol pair, or `nil` if not found.
  public func rangeOfSymbolPair(
    at index: Index, candidates: [SymbolPair], ignoring pairToIgnore: SymbolPair? = nil,
    escapeCharacter: Character? = nil
  ) -> ClosedRange<Index>? {

    guard
      let pairIndex = self.indexOfSymbolPair(
        at: index, candidates: candidates, ignoring: pairToIgnore, escapeCharacter: escapeCharacter)
    else { return nil }

    return switch pairIndex {
    case .begin(let beginIndex): beginIndex...index
    case .end(let endIndex): index...endIndex
    }
  }

  /// Finds the mate of a symbol pair.
  ///
  /// - Parameters:
  ///   - index: The character index of the symbol character to find the mate.
  ///   - candidates: Symbol pairs to find.
  ///   - range: The range of characters to find in.
  ///   - pairToIgnore: The symbol pair in which symbol characters should be ignored.
  ///   - escapeCharacter: The escape character, or `nil` for no escape.
  /// - Returns: The character index of the matched pair.
  public func indexOfSymbolPair(
    at index: Index, candidates: [SymbolPair], in range: Range<Index>? = nil,
    ignoring pairToIgnore: SymbolPair? = nil, escapeCharacter: Character? = nil
  ) -> SymbolPair.PairIndex? {

    let character = self[index]

    guard let pair = candidates.first(where: { $0.begin == character || $0.end == character })
    else { return nil }

    // check if this position is escaped (non-double-delimiter style)
    if let escapeCharacter, escapeCharacter != pair.end {
      guard !self.isEscaped(at: index, by: escapeCharacter) else { return nil }
    }

    if pair.begin == pair.end {
      let beginIndex = self.indexOfSymbolPair(
        endIndex: index, pair: pair, until: range?.lowerBound, ignoring: pairToIgnore,
        escapeCharacter: escapeCharacter)
      let endIndex = self.indexOfSymbolPair(
        beginIndex: index, pair: pair, until: range?.upperBound, ignoring: pairToIgnore,
        escapeCharacter: escapeCharacter)

      return switch (beginIndex, endIndex) {
      case (let beginIndex?, nil): .begin(beginIndex)
      case (nil, let endIndex?): .end(endIndex)
      default: nil
      }
    }

    switch character {
    case pair.begin:
      guard
        let endIndex = self.indexOfSymbolPair(
          beginIndex: index, pair: pair, until: range?.upperBound, ignoring: pairToIgnore,
          escapeCharacter: escapeCharacter)
      else { return nil }
      return .end(endIndex)

    case pair.end:
      guard
        let beginIndex = self.indexOfSymbolPair(
          endIndex: index, pair: pair, until: range?.lowerBound, ignoring: pairToIgnore,
          escapeCharacter: escapeCharacter)
      else { return nil }
      // verify this end is the actual matching end by forward-searching from the found begin
      if let escapeCharacter, escapeCharacter == pair.end {
        let foundEnd = self.indexOfSymbolPair(
          beginIndex: beginIndex, pair: pair, until: range?.upperBound, ignoring: pairToIgnore,
          escapeCharacter: escapeCharacter)
        guard foundEnd == index else { return nil }
      }
      return .begin(beginIndex)

    default: preconditionFailure()
    }
  }

  /// Finds character index of matched opening symbol before a given index.
  ///
  /// This method ignores escaped characters.
  ///
  /// - Parameters:
  ///   - endIndex: The character index of the closing symbol of the pair to find.
  ///   - pair: The symbol pair to find.
  ///   - beginIndex: The lower boundary of the find range.
  ///   - pairToIgnore: The symbol pair in which symbol characters should be ignored.
  ///   - escapeCharacter: The escape character, or `nil` for no escape.
  /// - Returns: The character index of the matched opening symbol, or `nil` if not found.
  public func indexOfSymbolPair(
    endIndex: Index, pair: SymbolPair, until beginIndex: Index? = nil,
    ignoring pairToIgnore: SymbolPair? = nil, escapeCharacter: Character? = nil
  ) -> Index? {

    assert(endIndex <= self.endIndex)

    let beginIndex = beginIndex ?? self.startIndex

    guard beginIndex < endIndex else { return nil }

    var index = endIndex
    var nestDepth = 0

    // double-delimiter style: escape character is the same as end delimiter
    if let escapeCharacter, escapeCharacter == pair.end {
      while index > beginIndex {
        index = self.index(before: index)

        if self[index] == pair.end {
          if index > beginIndex {
            let previousIndex = self.index(before: index)
            if self[previousIndex] == pair.end {
              index = previousIndex
              continue
            }
          }
          if pair.begin == pair.end {
            return index  // same-pair: first non-doubled is the match
          }
          nestDepth += 1
        } else if self[index] == pair.begin {
          if nestDepth == 0 { return index }
          nestDepth -= 1
        }
      }

      return nil
    }

    var ignoredNestDepth = 0
    while index > beginIndex {
      index = self.index(before: index)

      switch self[index] {
      case pair.begin where ignoredNestDepth == 0:
        if let escapeCharacter, self.isEscaped(at: index, by: escapeCharacter) { continue }
        if nestDepth == 0 { return index }  // found
        nestDepth -= 1

      case pair.end where ignoredNestDepth == 0:
        if let escapeCharacter, self.isEscaped(at: index, by: escapeCharacter) { continue }
        nestDepth += 1

      case pairToIgnore?.begin:
        if let escapeCharacter, self.isEscaped(at: index, by: escapeCharacter) { continue }
        ignoredNestDepth -= 1

      case pairToIgnore?.end:
        if let escapeCharacter, self.isEscaped(at: index, by: escapeCharacter) { continue }
        ignoredNestDepth += 1

      default: break
      }
    }

    return nil
  }

  /// Finds character index of matched closing symbol after a given index.
  ///
  /// This method ignores escaped characters.
  ///
  /// - Parameters:
  ///   - beginIndex: The character index of the opening symbol of the pair to find.
  ///   - pair: The symbol pair to find.
  ///   - endIndex: The upper boundary of the find range.
  ///   - pairToIgnore: The symbol pair in which symbol characters should be ignored.
  ///   - escapeCharacter: The escape character, or `nil` for no escape.
  /// - Returns: The character index of the matched closing symbol, or `nil` if not found.
  public func indexOfSymbolPair(
    beginIndex: Index, pair: SymbolPair, until endIndex: Index? = nil,
    ignoring pairToIgnore: SymbolPair? = nil, escapeCharacter: Character? = nil
  ) -> Index? {

    assert(beginIndex >= self.startIndex)

    // avoid (endIndex == self.startIndex)
    guard !self.isEmpty, endIndex.map({ $0 > self.startIndex }) != false else { return nil }

    let endIndex = self.index(before: endIndex ?? self.endIndex)

    guard beginIndex < endIndex else { return nil }

    // double-delimiter style: escape character is the same as end delimiter
    if let escapeCharacter, escapeCharacter == pair.end {
      var index = beginIndex

      while index < endIndex {
        index = self.index(after: index)

        guard self[index] == pair.end else { continue }

        if index < endIndex {
          let nextIndex = self.index(after: index)
          if self[nextIndex] == pair.end {
            index = nextIndex
            continue
          }
        }

        return index
      }

      return nil
    }

    var index = beginIndex
    var nestDepth = 0
    var ignoredNestDepth = 0

    while index < endIndex {
      index = self.index(after: index)

      switch self[index] {
      case pair.end where ignoredNestDepth == 0:
        if let escapeCharacter, self.isEscaped(at: index, by: escapeCharacter) { continue }
        if nestDepth == 0 { return index }  // found
        nestDepth -= 1

      case pair.begin where ignoredNestDepth == 0:
        if let escapeCharacter, self.isEscaped(at: index, by: escapeCharacter) { continue }
        nestDepth += 1

      case pairToIgnore?.end:
        if let escapeCharacter, self.isEscaped(at: index, by: escapeCharacter) { continue }
        ignoredNestDepth -= 1

      case pairToIgnore?.begin:
        if let escapeCharacter, self.isEscaped(at: index, by: escapeCharacter) { continue }
        ignoredNestDepth += 1

      default: break
      }
    }

    return nil
  }
}

// MARK: -

private final class SymbolPairScanner {

  let string: String
  let candidates: [SymbolPair]

  private var scanningRange: Range<String.Index>
  private var scanningPair: SymbolPair?
  private let escapeCharacter: Character?
  private var finished: Bool = false
  private var found: Bool = false

  init(
    string: String, candidates: [SymbolPair], baseRange: Range<String.Index>,
    escapeCharacter: Character?
  ) {

    assert(candidates.allSatisfy({ $0.begin != $0.end }))

    self.string = string
    self.candidates = candidates
    self.scanningRange = baseRange
    self.escapeCharacter = escapeCharacter
  }

  // MARK: Public Methods

  /// Finds the nearest range enclosed by one of the candidate symbol pairs.
  ///
  /// - Returns: The range of characters.
  func scan() -> Range<String.Index>? {

    while !self.finished {
      self.scanForward()

      guard !self.finished else { return nil }

      self.scanBackward()
    }

    return self.found ? self.scanningRange : nil
  }

  // MARK: Private Methods

  /// Scans the next symbol from the current scanning range.
  private func scanForward() {

    var index = self.scanningRange.upperBound
    var nestDepths: [SymbolPair: Int] = [:]
    var isEscaped =
      if let escapeCharacter {
        self.string.isEscaped(at: index, by: escapeCharacter)
      } else {
        false
      }

    for character in self.string[index...] {
      index = self.string.index(after: index)

      if isEscaped {
        isEscaped = false
        continue
      }

      if let pair = self.candidates.first(where: { $0.begin == character }) {
        nestDepths[pair, default: 0] += 1

      } else if let pair = self.candidates.first(where: { $0.end == character }) {
        if nestDepths[pair, default: 0] > 0 {
          nestDepths[pair, default: 0] -= 1
        } else {
          self.scanningRange = self.scanningRange.lowerBound..<index
          self.scanningPair = pair
          return
        }
      }

      isEscaped = (character == self.escapeCharacter)
    }

    self.finished = true
  }

  /// Scans the previous symbol from the current scanning range.
  private func scanBackward() {

    var index = self.scanningRange.lowerBound
    var nestDepths: [SymbolPair: Int] = [:]
    let candidates = self.scanningPair.map { [$0] } ?? self.candidates

    for character in self.string[..<index].reversed() {
      index = self.string.index(before: index)

      if let pair = candidates.first(where: { $0.begin == character }) {
        if let escapeCharacter, self.string.isEscaped(at: index, by: escapeCharacter) { continue }

        if nestDepths[pair, default: 0] > 0 {
          nestDepths[pair, default: 0] -= 1
        } else {
          self.finished = true
          self.found = true
          self.scanningRange = index..<self.scanningRange.upperBound
          return
        }

      } else if let pair = candidates.first(where: { $0.end == character }) {
        if let escapeCharacter, self.string.isEscaped(at: index, by: escapeCharacter) { continue }

        nestDepths[pair, default: 0] += 1
      }
    }

    self.finished = true
  }
}
