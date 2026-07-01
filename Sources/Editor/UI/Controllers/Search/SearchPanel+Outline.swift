import AppKit
import TextFind

// MARK: - NSOutlineView data source & delegate

extension SearchViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    if item == nil { return nodes.count }
    return (item as? FileNode)?.matches.count ?? 0
  }

  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    if item == nil { return nodes[index] }
    return (item as! FileNode).matches[index]
  }

  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    item is FileNode
  }

  func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
    item is FileNode ? 26 : 22
  }

  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    if let f = item as? FileNode {
      let id = NSUserInterfaceItemIdentifier("fileCell")
      let cell: SearchFileCell = {
        if let existing = outlineView.makeView(withIdentifier: id, owner: self) as? SearchFileCell {
          return existing
        }
        let c = SearchFileCell()
        c.identifier = id
        return c
      }()
      cell.configure(file: f.file, count: f.matches.count, expanded: outlineView.isItemExpanded(f))
      return cell
    }
    guard let m = item as? MatchNode else { return nil }
    let id = NSUserInterfaceItemIdentifier("matchCell")
    let cell: SearchMatchCell = {
      if let existing = outlineView.makeView(withIdentifier: id, owner: self) as? SearchMatchCell {
        return existing
      }
      let c = SearchMatchCell()
      c.identifier = id
      return c
    }()
    cell.configure(line: m.line, preview: m.preview, query: field.stringValue, mode: options.textFindMode)
    return cell
  }

  func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
    SearchRowView()
  }
}
