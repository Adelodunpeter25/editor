import AppKit

enum EditMode {
  case normal
  case insert
}

/// NSTextView subclass that intercepts Cmd+S to save and adds "Format Document" to the right-click menu.
/// Also implements a simplified vim mode: starts in normal mode (read-only), press 'i' to enter insert mode,
/// press Escape to return to normal mode. Prevents accidental edits while allowing navigation/selection.
final class CodeTextView: NSTextView {
  var onSave: (() -> Void)?
  var onFormat: (() -> Void)?
  var onModeChange: ((EditMode) -> Void)?
  
  var editMode: EditMode = .normal {
    didSet {
      updateCursor()
      onModeChange?(editMode)
    }
  }

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
      if event.charactersIgnoringModifiers?.lowercased() == "i" && 
         event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
        editMode = .insert
        return
      }
      
      // Escape does nothing in normal mode (already there)
      if event.keyCode == 53 { // Escape key
        return
      }
      
      // Allow navigation keys, selection, and standard editing shortcuts
      let isNavigation = (event.keyCode >= 123 && event.keyCode <= 126) || // Arrow keys
                         event.charactersIgnoringModifiers?.lowercased() == "h" ||
                         event.charactersIgnoringModifiers?.lowercased() == "j" ||
                         event.charactersIgnoringModifiers?.lowercased() == "k" ||
                         event.charactersIgnoringModifiers?.lowercased() == "l"
      
      let isSelection = event.modifierFlags.contains(.shift)
      let isStandardShortcut = event.modifierFlags.contains(.command) || 
                               event.modifierFlags.contains(.control)
      
      if isNavigation || isSelection || isStandardShortcut {
        super.keyDown(with: event)
        return
      }
      
      // Block all other character input in normal mode
      return
    }
    
    // In insert mode, handle Escape to return to normal mode
    if event.keyCode == 53 { // Escape key
      editMode = .normal
      return
    }
    
    // Normal typing in insert mode
    super.keyDown(with: event)
  }
  
  private func updateCursor() {
    if editMode == .normal {
      // Use green for block cursor in normal mode
      insertionPointColor = .systemGreen
    } else {
      // Use standard white for insert mode
      insertionPointColor = .white
    }
    // Force redraw of the insertion point
    setNeedsDisplay(visibleRect, avoidAdditionalLayout: false)
  }
  
  override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn: Bool) {
    if editMode == .normal && turnedOn {
      let blockColor = NSColor.systemGreen
      blockColor.setFill()
      
      var blockRect = rect.integral
      let cellWidth = max(2, ceil(font?.maximumAdvancement.width ?? 8))
      let cellHeight = max(blockRect.height, ceil(layoutManager?.defaultLineHeight(for: font ?? .systemFont(ofSize: 12)) ?? 14))
      blockRect.size.width = cellWidth + 2
      blockRect.size.height = cellHeight
      NSBezierPath(rect: blockRect).fill()
      return
    }
    
    super.drawInsertionPoint(in: rect, color: color, turnedOn: turnedOn)
  }
}
