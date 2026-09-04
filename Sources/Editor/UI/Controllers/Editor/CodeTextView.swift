import AppKit
import STTextView
import LineEnding

enum EditMode {
  case normal
  case insert
}

/// STTextView (TextKit 2) subclass that intercepts Cmd+S to save and adds "Format Document" to the
/// right-click menu. Also implements a simplified vim mode: starts in normal mode (read-only), press
/// 'i' to enter insert mode, press Escape to return to normal mode. Prevents accidental edits while
/// allowing navigation/selection.
///
/// MIGRATION NOTE (STTextView): line numbers and the separator are now drawn natively by
/// `gutterView` (see `showsLineNumbers` set up in EditorViewController.loadView). Git added/modified/
/// deleted markers are drawn by a small overlay view docked inside the gutter — see
/// CodeTextView+Gutter.swift — because STTextView's gutter marker API is oriented around per-line
/// annotations rather than a raw draw hook the way the old TextKit 1 `draw(_:)` override was.
final class CodeTextView: STTextView {
  var onSave: (() -> Void)?
  var onFormat: (() -> Void)?
  var onModeChange: ((EditMode) -> Void)?

  var editMode: EditMode = .normal {
    didSet {
      updateCursorAppearance()
      onModeChange?(editMode)
    }
  }

  var gitAddedLines: Set<Int> = [] { didSet { gutterOverlay?.needsDisplay = true } }
  var gitModifiedLines: Set<Int> = [] { didSet { gutterOverlay?.needsDisplay = true } }
  var gitDeletedLines: Set<Int> = [] { didSet { gutterOverlay?.needsDisplay = true } }

  /// Installed once the gutter view exists (after the text view is added to a scroll view).
  private(set) var gutterOverlay: GitGutterOverlayView?

  // MARK: - Gutter overlay lifecycle

  /// Called by EditorViewController right after `showsLineNumbers` is enabled and the text view is
  /// in its scroll view, so `gutterView` is non-nil.
  func installGitGutterOverlay() {
    guard gutterOverlay == nil, let gutter = gutterView else { return }
    let overlay = GitGutterOverlayView(textView: self)
    overlay.translatesAutoresizingMaskIntoConstraints = false
    gutter.addSubview(overlay)
    NSLayoutConstraint.activate([
      overlay.leadingAnchor.constraint(equalTo: gutter.leadingAnchor),
      overlay.topAnchor.constraint(equalTo: gutter.topAnchor),
      overlay.widthAnchor.constraint(equalToConstant: 5),
      overlay.bottomAnchor.constraint(equalTo: gutter.bottomAnchor),
    ])
    gutterOverlay = overlay
  }

  // MARK: - Menu

  override func menu(for event: NSEvent) -> NSMenu? {
    let menu = super.menu(for: event) ?? NSMenu()
    let item = NSMenuItem(
      title: "Format Document", action: #selector(formatFromMenu), keyEquivalent: "")
    item.target = self
    menu.insertItem(item, at: 0)
    menu.insertItem(.separator(), at: 1)
    return menu
  }
  @objc private func formatFromMenu() { onFormat?() }

  // MARK: - Key Handling

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.modifierFlags.contains(.command),
      event.charactersIgnoringModifiers?.lowercased() == "s"
    {
      onSave?()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  override func keyDown(with event: NSEvent) {
    // Handle mode switching
    if editMode == .normal {
      // 'i' enters insert mode
      if event.charactersIgnoringModifiers?.lowercased() == "i"
        && event.modifierFlags.intersection([.command, .control, .option]).isEmpty
      {
        editMode = .insert
        return
      }

      // Escape does nothing in normal mode (already there)
      if event.keyCode == 53 {  // Escape key
        return
      }

      // Allow navigation keys, selection, and standard editing shortcuts
      let isNavigation =
        (event.keyCode >= 123 && event.keyCode <= 126)  // Arrow keys
        || event.charactersIgnoringModifiers?.lowercased() == "h"
        || event.charactersIgnoringModifiers?.lowercased() == "j"
        || event.charactersIgnoringModifiers?.lowercased() == "k"
        || event.charactersIgnoringModifiers?.lowercased() == "l"

      let isSelection = event.modifierFlags.contains(.shift)
      let isStandardShortcut =
        event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)

      if isNavigation || isSelection || isStandardShortcut {
        super.keyDown(with: event)
        return
      }

      // Block all other character input in normal mode
      return
    }

    // In insert mode, handle Escape to return to normal mode
    if event.keyCode == 53 {  // Escape key
      editMode = .normal
      return
    }

    // Normal typing in insert mode
    super.keyDown(with: event)
  }

  // MARK: - Cursor Appearance

  /// MIGRATION NOTE (STTextView): the old TextKit 1 editor drew a translucent block caret in normal
  /// mode via `NSTextView.drawInsertionPoint`, which STTextView does not expose (insertion point
  /// rendering is owned by its internal `STInsertionPointView`). As a first-pass approximation we only
  /// tint the (thin) insertion point; a true block cursor would need a custom `STPlugin` or an
  /// overlay view positioned at the caret — left as a follow-up once the basic integration is verified.
  private func updateCursorAppearance() {
    insertionPointColor = editMode == .normal ? .white.withAlphaComponent(0.5) : .white
  }
}
