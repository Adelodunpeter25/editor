import Foundation

extension AttributedString {

  /// Truncates the head with an ellipsis until the specified `index` if the length before `index` exceeds `offset`.
  ///
  /// - Parameters:
  ///   - index: The character index at which truncation should start.
  ///   - offset: The maximum number of characters to leave to the left of `index`.
  /// - Returns: The truncated attributed string.
  public func truncatedHead(until index: Index, offset: Int) -> AttributedString {

    var string = self
    string.truncateHead(until: index, offset: offset)

    return string
  }

  /// Truncates the head with an ellipsis until the specified `index` if the length before `index` exceeds `offset`.
  ///
  /// - Parameters:
  ///   - index: The character index at which truncation should start.
  ///   - offset: The maximum number of characters to leave to the left of `index`.
  public mutating func truncateHead(until index: Index, offset: Int) {

    precondition(offset >= 0)

    let length = self.characters.distance(from: self.startIndex, to: index)

    guard length > offset else { return }

    let truncationIndex = self.characters.index(index, offsetBy: -offset)

    self.removeSubrange(..<truncationIndex)
    self.insert(AttributedString("…"), at: self.startIndex)
  }
}

extension String {

  /// Truncates the head with an ellipsis until the specified `index` if the length before `index` exceeds `offset`.
  ///
  /// - Parameters:
  ///   - index: The character index at which truncation should start.
  ///   - offset: The maximum number of characters to leave to the left of `index`.
  /// - Returns: The truncated string.
  public func truncatedHead(until index: Index, offset: Int) -> String {

    var string = self
    string.truncateHead(until: index, offset: offset)

    return string
  }

  /// Truncates the head with an ellipsis until the specified `index` if the length before `index` exceeds `offset`.
  ///
  /// - Parameters:
  ///   - index: The character index at which truncation should start.
  ///   - offset: The maximum number of characters to leave to the left of `index`.
  public mutating func truncateHead(until index: Index, offset: Int) {

    precondition(offset >= 0)

    let length = self.distance(from: self.startIndex, to: index)

    guard length > offset else { return }

    let truncationIndex = self.index(index, offsetBy: -offset)

    self.removeSubrange(..<truncationIndex)
    self.insert("…", at: self.startIndex)
  }
}
