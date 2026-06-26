import AppKit

/// Owns the `TabBarView` and wires all tab interactions (select, close, pin, reorder, new terminal,
/// file drop) to the active session on the model. Extracted from `CenterViewController` so the center
/// controller doesn't carry tab-action wiring, and `TabBarView` stays a pure view.
final class TabBarController {
  let view = TabBarView()
  private let model: AppModel

  init(model: AppModel) {
    self.model = model
    wireActions()
  }

  /// Update the tab bar from the active session. Called by `CenterViewController` on each render.
  func render() {
    guard let session = model.activeSession else {
      view.isHidden = true
      return
    }
    view.isHidden = false
    view.render(session: session, activeTabID: session.activeTabID)
  }

  // MARK: - Wiring

  private func wireActions() {
    view.onSelect = { [weak self] id in self?.model.activeSession?.activate(id) }

    view.onClose = { [weak self] id in
      guard let session = self?.model.activeSession,
        let tab = session.tabs.first(where: { $0.id == id })
      else { return }
      if UnsavedGuard.confirmClose(tab) { session.closeTab(id) }
    }

    view.onPin = { [weak self] id in self?.model.activeSession?.togglePin(id) }

    view.onCloseOthers = { [weak self] id in self?.model.activeSession?.closeOthers(id) }

    view.onCloseAll = { [weak self] in self?.model.activeSession?.closeAll() }

    view.onNewTerminal = { [weak self] in
      self?.model.activeSession?.addTab(Tab(kind: .terminal, title: "Terminal"))
    }

    view.onReorder = { [weak self] dragged, beforeID in
      guard let session = self?.model.activeSession else { return }
      if let beforeID {
        session.moveTab(dragged, before: beforeID)
      } else {
        session.moveTabToEnd(dragged)
      }
    }

    // File dragged from the sidebar and dropped onto the tab bar: ALWAYS open as a new tab.
    // We bypass session.openFile() (which can silently replace a fresh tab) because a drag
    // is an explicit intent — the user wants a new tab for that file.
    // If the file is already open we just focus it; otherwise we add a fresh tab.
    view.onOpenFilePath = { [weak self] absolutePath in
      guard let session = self?.model.activeSession else { return }
      if let existing = session.tabs.first(where: { $0.kind == .file && $0.path == absolutePath }) {
        session.activate(existing.id)
      } else {
        let title = (absolutePath as NSString).lastPathComponent
        session.addTab(Tab(kind: .file, title: title, path: absolutePath))
      }
    }
  }
}
