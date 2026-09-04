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

      // h/j/k/l move the caret instead of inserting: passing them to super would run them
      // through `interpretKeyEvents`, which has no binding for a bare "h" and inserts it as
      // text (same for Shift+letter via the old shift passthrough). With Shift held they
      // extend the selection, matching arrow-key behaviour.
      if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
        let key = event.charactersIgnoringModifiers?.lowercased(),
        key.count == 1, "hjkl".contains(key)
      {
        let selecting = event.modifierFlags.contains(.shift)
        switch key {
        case "h": selecting ? moveLeftAndModifySelection(self) : moveLeft(self)
        case "l": selecting ? moveRightAndModifySelection(self) : moveRight(self)
        case "j": selecting ? moveDownAndModifySelection(self) : moveDown(self)
        case "k": selecting ? moveUpAndModifySelection(self) : moveUp(self)
        default: break
        }
        return
      }

      // Allow non-text navigation keys (arrows, Home/End, Page Up/Down — Shift variants
      // extend the selection natively) and standard shortcuts (Cmd/Ctrl combos).
      let keyCode = event.keyCode
      let isNavigationKey =
        (keyCode >= 123 && keyCode <= 126)  // Arrow keys
        || keyCode == 115 || keyCode == 119  // Home / End
        || keyCode == 116 || keyCode == 121  // Page Up / Page Down

      let isStandardShortcut =
        event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)

      if isNavigationKey || isStandardShortcut {
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

  // MARK: - Normal-mode write protection (defense in depth behind keyDown)

  // Normal mode is documented read-only, but several edit paths bypass keyDown: IME/dictation
  // and drag-and-drop funnel through `insertText`, while Cmd+V arrives as the `paste:` action.
  // Blocking them here keeps normal mode from editing. Programmatic edits (highlighting via
  // `addAttributes`, format-on-save / find-replace via `replaceCharacters`) don't use these
  // paths, so they keep working regardless of mode. `delete` degrades to a no-op in normal
  // mode because STTextView implements it via `insertText`.
  override func insertText(_ string: Any, replacementRange: NSRange) {
    guard editMode == .insert else { return }
    super.insertText(string, replacementRange: replacementRange)
  }

  override func insertText(_ insertString: Any) {
    guard editMode == .insert else { return }
    super.insertText(insertString)
  }

  override func paste(_ sender: Any?) {
    guard editMode == .insert else { return }
    super.paste(sender)
  }

  override func pasteAsPlainText(_ sender: Any?) {
    guard editMode == .insert else { return }
    super.pasteAsPlainText(sender)
  }

  override func pasteAsRichText(_ sender: Any?) {
    guard editMode == .insert else { return }
    super.pasteAsRichText(sender)
  }

  override func cut(_ sender: Any?) {
    guard editMode == .insert else { return }
    super.cut(sender)
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
