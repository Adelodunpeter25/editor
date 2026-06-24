import AppKit

// MARK: - Tree model

final class TreeNode {
  let id: String  // repo-relative path
  let name: String
  var status: GitStatus
  let isDir: Bool  // collapsed dir (e.g. ignored) with no children
  var children: [TreeNode]?
  init(id: String, name: String, status: GitStatus, isDir: Bool, children: [TreeNode]?) {
    self.id = id
    self.name = name
    self.status = status
    self.isDir = isDir
    self.children = children
  }
  var isFolder: Bool { children != nil }
}

private let priority: [GitStatus] = [.conflict, .deleted, .modified, .renamed, .new]

func buildTree(_ entries: [FileEntry]) -> [TreeNode] {
  let root = TreeNode(id: "", name: "", status: .none, isDir: false, children: [])
  var dirs: [String: TreeNode] = ["": root]

  for e in entries {
    let parts = e.path.split(separator: "/").map(String.init)
    var parent = root
    var prefix = ""
    for (i, name) in parts.enumerated() {
      let cur = prefix.isEmpty ? name : "\(prefix)/\(name)"
      if i == parts.count - 1 {
        let leaf = TreeNode(id: cur, name: name, status: e.status, isDir: e.isDir, children: nil)
        parent.children?.append(leaf)
      } else {
        if let d = dirs[cur] {
          parent = d
        } else {
          let d = TreeNode(id: cur, name: name, status: .none, isDir: false, children: [])
          dirs[cur] = d
          parent.children?.append(d)
          parent = d
        }
        prefix = cur
      }
    }
  }

  func agg(_ node: TreeNode) -> GitStatus {
    guard node.isFolder else {
      return (node.status == .ignored || node.status == .none) ? .none : node.status
    }
    var best: GitStatus = .none
    for ch in node.children ?? [] {
      let s = agg(ch)
      if s != .none, best == .none || priority.firstIndex(of: s)! < priority.firstIndex(of: best)! {
        best = s
      }
    }
    node.status = best
    return best
  }
  func sort(_ node: TreeNode) {
    node.children?.sort { a, b in
      let da = a.isFolder || a.isDir
      let db = b.isFolder || b.isDir
      return da != db ? da : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
    node.children?.forEach(sort)
  }
  root.children?.forEach { _ = agg($0) }
  sort(root)
  return root.children ?? []
}

func nsStatusColor(_ s: GitStatus) -> NSColor {
  switch s {
  case .none: return Theme.gitDefault
  case .new, .renamed: return NSColor(red: 0.45, green: 0.79, blue: 0.57, alpha: 1)
  case .modified: return NSColor(red: 0.89, green: 0.75, blue: 0.55, alpha: 1)
  case .deleted: return NSColor(red: 0.78, green: 0.31, blue: 0.22, alpha: 1)
  case .conflict: return NSColor(red: 0.89, green: 0.40, blue: 0.42, alpha: 1)
  case .ignored: return Theme.gitIgnored
  }
}
