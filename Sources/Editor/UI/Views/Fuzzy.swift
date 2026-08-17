import Foundation

// MARK: - Fuzzy scoring and highlighting

enum Fuzzy {
  /// Subsequence match of `query` in `candidate` (case-insensitive).
  /// Returns nil if not all query characters appear in order; otherwise a score where higher = better.
  static func score(_ query: String, _ candidate: String) -> Int? {
    let q = query.trimmingCharacters(in: .whitespaces)
    if q.isEmpty { return 0 }
    if candidate.isEmpty { return nil }

    // Fast exact match
    if candidate.caseInsensitiveCompare(q) == .orderedSame {
      return 100_000
    }

    let qChars = Array(q.lowercased())
    let cChars = Array(candidate.lowercased())
    let origChars = Array(candidate)

    guard let matchIndices = findMatchIndices(qChars: qChars, cChars: cChars) else {
      return nil
    }

    var score = 1000

    // Exact prefix match bonus
    if candidate.lowercased().hasPrefix(q.lowercased()) {
      score += 20_000
    } else if let range = candidate.range(of: q, options: .caseInsensitive) {
      // Contiguous substring match bonus
      let dist = candidate.distance(from: candidate.startIndex, to: range.lowerBound)
      score += 10_000 - (dist * 10)
    }

    // Evaluate matching character bonuses
    var prevIndex = -2
    for (i, idx) in matchIndices.enumerated() {
      // Consecutive match bonus
      if idx == prevIndex + 1 {
        score += 80
      }

      // Word boundary bonuses (start of string, after separator, or camelCase uppercase)
      if isWordBoundary(at: idx, chars: origChars) {
        score += 120
      }

      // Exact case match bonus
      if i < q.count && origChars[idx] == Array(q)[i] {
        score += 20
      }

      prevIndex = idx
    }

    // Penalize match span (compact matches rank higher)
    if let first = matchIndices.first, let last = matchIndices.last {
      let span = last - first + 1
      score -= (span - qChars.count) * 10
      score -= first * 5
    }

    // Penalize long candidate string length slightly
    score -= candidate.count

    return score
  }

  /// The character indices `query` matches in `candidate`, in order. Empty if not a full subsequence.
  static func matches(_ query: String, _ candidate: String) -> [Int] {
    let q = query.trimmingCharacters(in: .whitespaces)
    if q.isEmpty || candidate.isEmpty { return [] }

    // If query is a contiguous substring, prioritize the contiguous match for cleaner UI highlight
    if let range = candidate.range(of: q, options: .caseInsensitive) {
      let start = candidate.distance(from: candidate.startIndex, to: range.lowerBound)
      let len = candidate.distance(from: range.lowerBound, to: range.upperBound)
      return Array(start..<(start + len))
    }

    let qChars = Array(q.lowercased())
    let cChars = Array(candidate.lowercased())

    return findMatchIndices(qChars: qChars, cChars: cChars) ?? []
  }

  private static func findMatchIndices(qChars: [Character], cChars: [Character]) -> [Int]? {
    var result: [Int] = []
    result.reserveCapacity(qChars.count)

    var cIdx = 0
    for qChar in qChars {
      var found = false
      while cIdx < cChars.count {
        if cChars[cIdx] == qChar {
          result.append(cIdx)
          cIdx += 1
          found = true
          break
        }
        cIdx += 1
      }
      if !found { return nil }
    }
    return result
  }

  private static func isWordBoundary(at index: Int, chars: [Character]) -> Bool {
    if index == 0 { return true }
    let prev = chars[index - 1]
    let curr = chars[index]
    if prev == " " || prev == "_" || prev == "-" || prev == "." || prev == "/" || prev == ":" {
      return true
    }
    if prev.isLowercase && curr.isUppercase {
      return true
    }
    return false
  }
}
