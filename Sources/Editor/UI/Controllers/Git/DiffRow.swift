import AppKit

// MARK: - Line diff model and logic

enum DiffRow {
  case equal(old: Int, new: Int, text: String)
  case del(old: Int, text: String)
  case ins(new: Int, text: String)
  case change(old: Int, new: Int, oldText: String, newText: String)
}

/// Line-level diff using the standard library's Myers diff.
func computeDiff(old: String, new: String) -> [DiffRow] {
  let oldLines = old.isEmpty ? [] : old.components(separatedBy: "\n")
  let newLines = new.isEmpty ? [] : new.components(separatedBy: "\n")

  // Map each unique line to an integer ID to speed up the Myers diff by avoiding
  // expensive string hash and unicode-aware comparison operations in the hot loop.
  var lineToId = [String: Int]()
  var nextId = 0

  let oldIds = oldLines.map { line -> Int in
    if let id = lineToId[line] { return id }
    let id = nextId
    lineToId[line] = id
    nextId += 1
    return id
  }

  let newIds = newLines.map { line -> Int in
    if let id = lineToId[line] { return id }
    let id = nextId
    lineToId[line] = id
    nextId += 1
    return id
  }

  let diff = newIds.difference(from: oldIds)
  var removed = Set<Int>()
  var inserted = Set<Int>()
  for ch in diff {
    switch ch {
    case .remove(let o, _, _): removed.insert(o)
    case .insert(let o, _, _): inserted.insert(o)
    }
  }
  var rows: [DiffRow] = []
  var i = 0
  var j = 0
  while i < oldLines.count || j < newLines.count {
    let oRem = i < oldLines.count && removed.contains(i)
    let nIns = j < newLines.count && inserted.contains(j)
    if oRem && nIns {
      rows.append(.change(old: i + 1, new: j + 1, oldText: oldLines[i], newText: newLines[j]))
      i += 1
      j += 1
    } else if oRem {
      rows.append(.del(old: i + 1, text: oldLines[i]))
      i += 1
    } else if nIns {
      rows.append(.ins(new: j + 1, text: newLines[j]))
      j += 1
    } else if i < oldLines.count && j < newLines.count {
      rows.append(.equal(old: i + 1, new: j + 1, text: oldLines[i]))
      i += 1
      j += 1
    } else if i < oldLines.count {
      rows.append(.del(old: i + 1, text: oldLines[i]))
      i += 1
    } else {
      rows.append(.ins(new: j + 1, text: newLines[j]))
      j += 1
    }
  }
  return rows
}
