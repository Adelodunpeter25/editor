import Foundation

enum DiffRow {
  case equal(old: Int, new: Int, text: String)
  case del(old: Int, text: String)
  case ins(new: Int, text: String)
  case change(old: Int, new: Int, oldText: String, newText: String)
}

struct GitGutterChangeSet {
  var addedLines: Set<Int> = []
  var modifiedLines: Set<Int> = []
  var deletedLines: Set<Int> = []
}

enum GitDiff {
  static func rows(old: String, new: String) -> [DiffRow] {
    let oldLines = logicalLines(old)
    let newLines = logicalLines(new)

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
    for change in diff {
      switch change {
      case .remove(let offset, _, _): removed.insert(offset)
      case .insert(let offset, _, _): inserted.insert(offset)
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

  static func gutterChanges(head: String?, current: String) -> GitGutterChangeSet {
    let currentLineCount = logicalLines(current).count
    guard let head else {
      return GitGutterChangeSet(
        addedLines: currentLineCount > 0 ? Set(1...currentLineCount) : [],
        modifiedLines: [],
        deletedLines: []
      )
    }

    let rows = rows(old: head, new: current)
    var changes = GitGutterChangeSet()
    for row in rows {
      switch row {
      case .ins(let new, _):
        changes.addedLines.insert(new)
      case .change(_, let new, _, _):
        changes.modifiedLines.insert(new)
      case .del:
        break
      case .equal:
        break
      }
    }

    var pendingDelete = false
    var pendingDeleteTarget = 1
    for row in rows {
      switch row {
      case .del(let old, _):
        pendingDelete = true
        pendingDeleteTarget = max(1, min(old, max(1, currentLineCount)))
      case .equal(_, let new, _):
        if pendingDelete {
          changes.deletedLines.insert(new)
          pendingDelete = false
        }
      case .ins(let new, _), .change(_, let new, _, _):
        if pendingDelete {
          changes.deletedLines.insert(new)
          pendingDelete = false
        }
      }
    }
    if pendingDelete { changes.deletedLines.insert(pendingDeleteTarget) }
    return changes
  }

  private static func logicalLines(_ text: String) -> [String] {
    guard !text.isEmpty else { return [] }
    var lines = text.components(separatedBy: "\n")
    if text.hasSuffix("\n"), lines.last == "" { lines.removeLast() }
    return lines
  }
}
