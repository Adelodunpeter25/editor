extension String {

  /// The remainder of the string after the last dot removed.
  public var deletingPathExtension: String {

    let regex = try! Regex("^(.+)\\.[^ .]+$")
    return self.replacing(
      regex,
      with: { match in
        String(match.output[1].substring ?? "")
      })
  }

  /// The file extension part of the receiver by assuming the string is a filename.
  public var pathExtension: String? {

    let regex = try! Regex("\\.([^ .]+)$")
    guard let match = self.firstMatch(of: regex) else { return nil }

    return String(match.output[1].substring ?? "")
  }

  /// Creates a unique name from the given names by adding the smallest unique number if needed.
  ///
  /// - Parameters:
  ///   - names: The names already taken.
  /// - Returns: A unique name.
  public func appendingUniqueNumber(in names: [String]) -> String {

    let (base, count) = self.numberingComponents
    let usedNames = Set(names)

    return (count...).lazy
      .map { ($0 < 2) ? base : "\(base) \($0)" }
      .first { !usedNames.contains($0) }!
  }
}

extension String {

  /// Splits the receiver into parts of filename for unique numbering..
  var numberingComponents: (base: String, count: Int) {

    assert(!self.isEmpty)

    let regex = try! Regex("(?<base>.+?)(?: (?<number>[0-9]+))?")
    let match = self.wholeMatch(of: regex)!
    let base = String(match["base"]?.substring ?? "")
    let count = match["number"]?.substring.flatMap { Int($0) } ?? 1

    return (base, count)
  }
}
