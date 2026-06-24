import AppKit

// MARK: - Inline create / rename / delete

extension FileTreeViewController {

  func beginNewFile() { beginCreate(.newFile, parent: targetFolder()) }
  func beginNewFolder() { beginCreate(.newFolder, parent: targetFolder()) }

  /// Dev-harness hook: run the inline create end-to-end (begin → name → commit) without a keyboard.
  func debugCreate(name: String, folder: Bool) {
    beginCreate(folder ? .newFolder : .newFile, parent: targetFolder())
    finishEditing(name: name)
  }

  /// Dev-harness hooks for the context-menu mutations.
  func debugRename(rel: String, to newName: String) {
    guard let node = findNode(rel, in: roots) else { return }
    beginRename(node)
    finishEditing(name: newName)
  }
  func debugDelete(rel: String) {
    guard let node = findNode(rel, in: roots) else { return }
    let abs = (store.repo as NSString).appendingPathComponent(node.id)
    try? FileManager.default.trashItem(at: URL(fileURLWithPath: abs), resultingItemURL: nil)
    expandedPaths.remove(node.id)
    if pendingEmptyDirs.remove(node.id) != nil { persistEmptyDirs() }
    onDelete(node.id)
    store.refreshNow()
  }

  /// Dev-harness hook: expand every folder.
  func debugExpandAll() {
    restoring = true
    outline.expandItem(nil, expandChildren: true)
    restoring = false
    for row in 0..<outline.numberOfRows {
      if let n = outline.item(atRow: row) as? TreeNode, n.isFolder { expandedPaths.insert(n.id) }
    }
  }

  /// Insert an empty draft row in the given folder (nil = root) and start inline editing it.
  func beginCreate(_ kind: EditKind, parent: TreeNode?) {
    guard editingNode == nil else { return }
    draftParentId = parent?.id ?? ""
    let draft = TreeNode(id: Self.draftId, name: "", status: .new, isDir: false, children: nil)
    if let parent { parent.children?.insert(draft, at: 0) } else { roots.insert(draft, at: 0) }
    editKind = kind
    editingNode = draft
    editCancelled = false

    if let parent, !outline.isItemExpanded(parent) {
      restoring = true
      outline.expandItem(parent)
      restoring = false
      expandedPaths.insert(parent.id)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
        guard let self, self.editingNode === draft else { return }
        self.beginFieldEditing(for: draft)
      }
    } else {
      outline.insertItems(at: IndexSet(integer: 0), inParent: parent, withAnimation: [])
      beginFieldEditing(for: draft)
    }
  }

  /// Inline-rename an existing row.
  func beginRename(_ node: TreeNode) {
    guard editingNode == nil, !node.id.isEmpty, let live = findNode(node.id, in: roots) else {
      return
    }
    editKind = .rename
    editingNode = live
    renameOriginalId = live.id
    editCancelled = false
    outline.reloadItem(live)
    beginFieldEditing(for: live)
  }

  func confirmDelete(_ node: TreeNode) {
    guard !node.id.isEmpty, let window = outline.window else { return }
    let alert = NSAlert()
    alert.messageText = "Delete \"\(node.name)\"?"
    alert.informativeText = "It will be moved to the Trash."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Move to Trash")
    alert.addButton(withTitle: "Cancel")
    alert.beginSheetModal(for: window) { [weak self] response in
      guard response == .alertFirstButtonReturn, let self else { return }
      let abs = (self.store.repo as NSString).appendingPathComponent(node.id)
      try? FileManager.default.trashItem(at: URL(fileURLWithPath: abs), resultingItemURL: nil)
      self.expandedPaths.remove(node.id)
      if self.pendingEmptyDirs.remove(node.id) != nil { self.persistEmptyDirs() }
      self.onDelete(node.id)
      self.store.refreshNow()
    }
  }

  // MARK: - Field editing

  func beginFieldEditing(for node: TreeNode) {
    let row = outline.row(forItem: node)
    guard row >= 0 else {
      let wasDraft = editingNode?.id == Self.draftId
      editingNode = nil
      editKind = nil
      editCancelled = false
      if wasDraft { removeNode(node) }
      reloadAfterEdit()
      return
    }
    outline.scrollRowToVisible(row)
    outline.editColumn(0, row: row, with: nil, select: true)
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
    -> Bool
  {
    if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
      editCancelled = true
      outline.window?.makeFirstResponder(outline)
      return true
    }
    return false
  }

  func controlTextDidEndEditing(_ note: Notification) {
    guard isEditing, let field = note.object as? NSTextField else { return }
    finishEditing(name: field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  func finishEditing(name: String) {
    guard let kind = editKind, let node = editingNode else { return }
    let cancelled = editCancelled
    editingNode = nil
    editKind = nil
    editCancelled = false
    defer { reloadAfterEdit() }

    switch kind {
    case .rename:
      guard !cancelled, isValidName(name), name != node.name else { return }
      renameCommit(to: name)
    case .newFile, .newFolder:
      removeNode(node)
      guard !cancelled, isValidName(name) else { return }
      createCommit(kind, name: name)
    }
  }

  // MARK: - Commit operations

  private func createCommit(_ kind: EditKind, name: String) {
    let rel = draftParentId.isEmpty ? name : draftParentId + "/" + name
    let abs = (store.repo as NSString).appendingPathComponent(rel)
    let fm = FileManager.default
    var isDir: ObjCBool = false
    let exists = fm.fileExists(atPath: abs, isDirectory: &isDir)

    if kind == .newFolder {
      if exists {
        guard isDir.boolValue else {
          warn("A file named \"\(name)\" already exists.")
          return
        }
        pendingEmptyDirs.insert(rel)
        persistEmptyDirs()
        store.refreshNow()
        reveal(rel)
        return
      }
      try? fm.createDirectory(atPath: abs, withIntermediateDirectories: true)
      pendingEmptyDirs.insert(rel)
      persistEmptyDirs()
    } else {
      guard !exists else {
        warn("\"\(name)\" already exists.")
        return
      }
      try? fm.createDirectory(
        atPath: (abs as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
      fm.createFile(atPath: abs, contents: nil)
    }
    store.refreshNow()
    if kind == .newFile { onOpen(rel) }
  }

  private func renameCommit(to name: String) {
    let parentId = (renameOriginalId as NSString).deletingLastPathComponent
    let destRel = parentId.isEmpty ? name : parentId + "/" + name
    guard destRel != renameOriginalId else { return }
    let fm = FileManager.default
    let src = (store.repo as NSString).appendingPathComponent(renameOriginalId)
    let dst = (store.repo as NSString).appendingPathComponent(destRel)
    guard fm.fileExists(atPath: src) else {
      store.refreshNow()
      return
    }
    guard !fm.fileExists(atPath: dst) else {
      warn("\"\(name)\" already exists.")
      return
    }
    do {
      try fm.createDirectory(
        atPath: (dst as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
      try fm.moveItem(atPath: src, toPath: dst)
    } catch {
      warn("Couldn't rename: \(error.localizedDescription)")
      return
    }
    remapPaths(from: renameOriginalId, to: destRel)
    onRename(renameOriginalId, destRel)
    store.refreshNow()
  }

  private func remapPaths(from old: String, to new: String) {
    func remap(_ s: String) -> String {
      if s == old { return new }
      if s.hasPrefix(old + "/") { return new + s.dropFirst(old.count) }
      return s
    }
    expandedPaths = Set(expandedPaths.map(remap))
    if !pendingEmptyDirs.isEmpty {
      pendingEmptyDirs = Set(pendingEmptyDirs.map(remap))
      persistEmptyDirs()
    }
  }

  // MARK: - Validation

  func isValidName(_ name: String) -> Bool {
    let parts = name.split(separator: "/", omittingEmptySubsequences: false)
    return !parts.isEmpty && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
  }

  private func targetFolder() -> TreeNode? {
    let row = outline.selectedRow
    guard row >= 0, let node = outline.item(atRow: row) as? TreeNode, node.isFolder else {
      return nil
    }
    return node
  }
}
