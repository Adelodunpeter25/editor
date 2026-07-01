import AppKit

/// Builds the right-click context menu for a changed file row in the git Changes panel.
/// All the actions mirror the hover buttons on `ChangeRowView` so keyboard-first and
/// mouse users get identical functionality.
///
/// Usage:
/// ```swift
/// tableView.menu = GitChangeContextMenu.menu(
///     for: fileEntry, staged: true,
///     onOpenDiff: { … }, onOpenFile: { … },
///     onStageToggle: { … }, onDiscard: { … })
/// ```
enum GitChangeContextMenu {

  /// Populates `menu` with items for a single changed file.
  /// Items are added directly — no copy needed.
  ///
  /// - Parameters:
  ///   - menu: The menu to populate (cleared by the caller before this is called).
  ///   - file: The git-changed file entry.
  ///   - staged: Whether the file is in the staged section.
  ///   - onOpenDiff: Open the file's diff tab.
  ///   - onOpenFile: Open the file in the editor.
  ///   - onStageToggle: Stage the file (if unstaged) or unstage it (if staged).
  ///   - onDiscard: Discard this file's changes (with confirmation handled by the caller).
  static func populate(
    _ menu: NSMenu,
    for file: FileEntry,
    staged: Bool,
    onOpenDiff: @escaping () -> Void,
    onOpenFile: @escaping () -> Void,
    onStageToggle: @escaping () -> Void,
    onDiscard: @escaping () -> Void
  ) {
    // ── Primary actions ───────────────────────────────────────────────────────
    menu.addItem(item("View Diff", action: onOpenDiff))

    if file.status != .deleted {
      menu.addItem(item("Open in Editor", action: onOpenFile))
    }

    menu.addItem(.separator())

    // ── Stage / Unstage ───────────────────────────────────────────────────────
    if staged {
      menu.addItem(item("Unstage", action: onStageToggle))
    } else {
      menu.addItem(item("Stage", action: onStageToggle))
    }

    menu.addItem(.separator())

    // ── Destructive ───────────────────────────────────────────────────────────
    let discard = item("Discard Changes…", action: onDiscard)
    discard.attributedTitle = NSAttributedString(
      string: "Discard Changes…",
      attributes: [.foregroundColor: NSColor.systemRed])
    menu.addItem(discard)
  }

  // MARK: - Private helpers

  private static func item(
    _ title: String,
    action: @escaping () -> Void
  ) -> NSMenuItem {
    let item = ClosureMenuItem(title: title, action: action)
    item.isEnabled = true
    return item
  }
}

// MARK: - ClosureMenuItem

/// An `NSMenuItem` that fires a Swift closure instead of a target/action pair.
final class ClosureMenuItem: NSMenuItem {
  private let handler: () -> Void

  init(title: String, action: @escaping () -> Void) {
    self.handler = action
    super.init(title: title, action: #selector(fire), keyEquivalent: "")
    self.target = self
  }

  @available(*, unavailable)
  required init(coder: NSCoder) { fatalError() }

  @objc private func fire() { handler() }
}
