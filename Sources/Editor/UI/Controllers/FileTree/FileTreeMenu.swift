import AppKit

// MARK: - Context menu (right-click)

extension FileTreeViewController {

    /// Rebuild the menu for the right-clicked row (`clickedRow`); empty space → root create actions.
    /// Also select the row so it uses our subtle highlight instead of the system rounded one.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let row = outline.clickedRow
        if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        menuTargetNode = (row >= 0) ? outline.item(atRow: row) as? TreeNode : nil
        menu.items = contextItems(for: menuTargetNode)
    }

    /// Pure builder (also drives the dev-harness menu assertion).
    func contextItems(for node: TreeNode?) -> [NSMenuItem] {
        func item(_ title: String, _ sel: Selector) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: ""); i.target = self; return i
        }
        guard let node else {
            return [item("New File", #selector(ctxNewFile)), item("New Folder", #selector(ctxNewFolder))]
        }
        let copy = [item("Copy Path", #selector(ctxCopyPath)), item("Copy Relative Path", #selector(ctxCopyRelative))]
        let edit = [item("Rename", #selector(ctxRename)), item("Delete", #selector(ctxDelete))]
        if node.isFolder {
            return [item("New File", #selector(ctxNewFile)), item("New Folder", #selector(ctxNewFolder)),
                    .separator()] + edit + [.separator()] + copy
        }
        return edit + [.separator()] + copy + [.separator(),
                item("New File", #selector(ctxNewFile)), item("New Folder", #selector(ctxNewFolder))]
    }

    /// Folder a context-menu create should target: the clicked folder, the clicked file's folder, else root.
    private func contextParent() -> TreeNode? {
        guard let target = menuTargetNode, let node = findNode(target.id, in: roots) else { return nil }
        if node.isFolder { return node }
        let parentId = (node.id as NSString).deletingLastPathComponent
        return parentId.isEmpty ? nil : findNode(parentId, in: roots)
    }

    @objc private func ctxNewFile()   { beginCreate(.newFile, parent: contextParent()) }
    @objc private func ctxNewFolder() { beginCreate(.newFolder, parent: contextParent()) }
    @objc private func ctxRename()    { if let n = menuTargetNode { beginRename(n) } }
    @objc private func ctxDelete()    { if let n = menuTargetNode { confirmDelete(n) } }
    @objc private func ctxCopyPath()  { if let n = menuTargetNode { Clipboard.copy((store.repo as NSString).appendingPathComponent(n.id)) } }
    @objc private func ctxCopyRelative() { if let n = menuTargetNode { Clipboard.copy(n.id) } }
}
