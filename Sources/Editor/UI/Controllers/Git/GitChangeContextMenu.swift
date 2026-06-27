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
    menu.addItem(item("View Diff", symbol: "arrow.left.arrow.right", action: onOpenDiff))

    if file.status != .deleted {
      menu.addItem(item("Open in Editor", symbol: "square.and.pencil", action: onOpenFile))
    }

    menu.addItem(.separator())

    // ── Stage / Unstage ───────────────────────────────────────────────────────
    if staged {
      menu.addItem(item("Unstage", symbol: "minus", action: onStageToggle))
    } else {
      menu.addItem(item("Stage", symbol: "plus", action: onStageToggle))
    }

    menu.addItem(.separator())

    // ── Destructive ───────────────────────────────────────────────────────────
    let discard = item("Discard Changes…", symbol: "arrow.uturn.backward", action: onDiscard)
    discard.attributedTitle = NSAttributedString(
      string: "Discard Changes…",
      attributes: [.foregroundColor: NSColor.systemRed])
    menu.addItem(discard)

    // ── File path (disabled, cosmetic) ────────────────────────────────────────
    menu.addItem(.separator())
    let info = NSMenuItem(title: file.path, action: nil, keyEquivalent: "")
    info.isEnabled = false
    info.attributedTitle = NSAttributedString(
      string: file.path,
      attributes: [
        .foregroundColor: NSColor(white: 0.45, alpha: 1),
        .font: NSFont.systemFont(ofSize: 11),
      ])
    menu.addItem(info)
  }

  // MARK: - Private helpers

  private static func item(
    _ title: String,
    symbol: String,
    action: @escaping () -> Void
  ) -> NSMenuItem {
    let item = ClosureMenuItem(title: title, action: action)
    item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
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
