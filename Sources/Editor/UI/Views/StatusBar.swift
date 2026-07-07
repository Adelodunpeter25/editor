import AppKit
import Combine
import LineEnding

/// Editor → status bar nudge: the active editor calls this when its caret/selection moves, so the bar
/// refreshes Ln/Col without polling.
enum EditorStatus { static var onChange: (() -> Void)? }

/// Resource monitor → status bar: `AppDelegate`'s `ResourceMonitor` pushes mem/CPU here (only while the
/// "Show resource monitor" setting is on, which is what starts the monitor).
enum ResourceStatus { static var onUpdate: ((_ memMB: Double, _ cpu: Double) -> Void)? }

/// VS Code-style bottom status bar for the *center* pane. Left: the active session's git branch. Right
/// (editor tabs only): `Ln X, Col Y` · indentation · line-ending · language · mode. Context-aware — the editor
/// items hide for terminal / Claude / diff / image tabs, and the whole bar hides when no repo is open.
/// Clickable: **branch** (switch / create / delete), **Ln/Col** (Go to Line), **indentation**,
/// **line-ending** (LF/CRLF), and **language**.
/// 
/// This view is purely for rendering - all business logic is delegated to StatusBarController.
final class StatusBarView: NSView {
  private let controller: StatusBarController
  private var cancellables = Set<AnyCancellable>()

  private let branchButton = StatusBarView.flatButton()
  private let resourceLabel = NSTextField(labelWithString: "")  // mem · CPU (when enabled in settings)
  private let lnColButton = StatusBarView.flatButton()
  private let indentButton = StatusBarView.flatButton()
  private let eolButton = StatusBarView.flatButton()
  private let langButton = StatusBarView.flatButton()
  private let modeButton = StatusBarView.flatButton()  // NORMAL/INSERT indicator
  private let shortcutsButton = StatusBarView.flatButton()  // always-visible, far right
  private lazy var editorItems: [NSView] = [lnColButton, indentButton, eolButton, langButton, modeButton]

  init(controller: StatusBarController) {
    self.controller = controller
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor(white: 0.14, alpha: 1).cgColor
    buildUI()
    setupBindings()
    render()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  /// A bit smaller than the editor body (status bars read as secondary), tracking the shared size.
  private var statusFontSize: CGFloat { max(9, CGFloat(controller.model.settings.fontSize) - 2) }

  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: ceil(statusFontSize) + 11)
  }

  private func setupBindings() {
    // Branch changes
    controller.onBranchChange = { [weak self] in
      self?.render()
      self?.updateBranchIcon()
    }
    
    // Editor status changes
    controller.onEditorStatusChange = { [weak self] in
      self?.render()
    }
    
    // Resource monitor updates
    controller.onResourceUpdate = { [weak self] _, _ in
      self?.render()
    }
    
    // Font size changes
    controller.model.settings.$fontSize.receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.invalidateIntrinsicContentSize()
        self?.updateBranchIcon()
        self?.updateShortcutsIcon()
        self?.render()
      }
      .store(in: &cancellables)
  }

  private func render() {
    isHidden = controller.isHidden

    let branch = controller.branchName
    setTitle(branchButton, branch ?? "")
    branchButton.isHidden = branch == nil

    let showRes = controller.showResourceMonitor
    resourceLabel.isHidden = !showRes
    if showRes {
      resourceLabel.font = .systemFont(ofSize: statusFontSize)
      resourceLabel.textColor = StatusBarView.fg
      resourceLabel.stringValue = controller.resourceText
    }

    if let info = controller.editorInfo {
      setTitle(lnColButton, info.lineColumn)
      setTitle(indentButton, info.indentStyle)
      setTitle(eolButton, info.lineEnding)
      setTitle(langButton, info.language)
      setTitle(modeButton, info.editMode)
      editorItems.forEach { $0.isHidden = false }
    } else {
      editorItems.forEach { $0.isHidden = true }
    }
  }

  // MARK: - Actions

  @objc private func branchClicked() {
    guard let menu = controller.handleBranchClick() else { return }
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: branchButton)
  }

  @objc private func goToLineClicked() {
    controller.handleGoToLineClick()
  }

  @objc private func indentClicked() {
    guard let menu = controller.handleIndentClick() else { return }
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: indentButton)
  }

  @objc private func eolClicked() {
    guard let menu = controller.handleEolClick() else { return }
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: eolButton)
  }

  @objc private func langClicked() {
    guard let menu = controller.handleLangClick() else { return }
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: langButton)
  }

  @objc private func shortcutsClicked() {
    controller.handleShortcutsClick()
  }

  // MARK: - Build

  private func buildUI() {
    let border = NSView()
    border.wantsLayer = true
    border.layer?.backgroundColor = NSColor(white: 0.25, alpha: 1).cgColor
    border.translatesAutoresizingMaskIntoConstraints = false
    addSubview(border)

    updateBranchIcon()
    branchButton.imagePosition = .imageLeading
    branchButton.contentTintColor = StatusBarView.fg
    branchButton.target = self
    branchButton.action = #selector(branchClicked)
    branchButton.toolTip = "Switch / create / delete branch"
    setContentHuggingPriority(.defaultHigh, for: .vertical)

    for (b, sel, tip) in [
      (lnColButton, #selector(goToLineClicked), "Go to Line… (⌘P then :)"),
      (indentButton, #selector(indentClicked), "Select indentation"),
      (eolButton, #selector(eolClicked), "Select line ending"),
      (langButton, #selector(langClicked), "Select language mode"),
    ] {
      b.target = self
      b.action = sel
      b.toolTip = tip
    }
    
    modeButton.isEnabled = false
    modeButton.toolTip = "Current edit mode (press 'i' to insert, Esc to normal)"

    updateShortcutsIcon()
    shortcutsButton.contentTintColor = StatusBarView.fg
    shortcutsButton.target = self
    shortcutsButton.action = #selector(shortcutsClicked)
    shortcutsButton.toolTip = "Keyboard shortcuts"

    let left = NSStackView(views: [branchButton, resourceLabel])
    left.spacing = 12
    left.alignment = .centerY
    let right = NSStackView(views: editorItems + [shortcutsButton])
    right.spacing = 14
    right.alignment = .centerY
    
    for s in [left, right] {
      s.translatesAutoresizingMaskIntoConstraints = false
      addSubview(s)
    }

    NSLayoutConstraint.activate([
      border.topAnchor.constraint(equalTo: topAnchor),
      border.leadingAnchor.constraint(equalTo: leadingAnchor),
      border.trailingAnchor.constraint(equalTo: trailingAnchor),
      border.heightAnchor.constraint(equalToConstant: 1),
      left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      left.centerYAnchor.constraint(equalTo: centerYAnchor),
      right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      right.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  private static let fg = NSColor(white: 0.62, alpha: 1)

  private static func flatButton() -> PointerButton {
    let b = PointerButton()
    b.isBordered = false
    b.bezelStyle = .inline
    b.setButtonType(.momentaryChange)
    b.setContentHuggingPriority(.required, for: .horizontal)
    return b
  }

  private func setTitle(_ b: NSButton, _ s: String) {
    b.attributedTitle = NSAttributedString(
      string: s,
      attributes: [
        .foregroundColor: StatusBarView.fg, .font: NSFont.systemFont(ofSize: statusFontSize),
      ])
  }

  private func updateBranchIcon() {
    let cfg = NSImage.SymbolConfiguration(pointSize: statusFontSize, weight: .regular)
    branchButton.image = NSImage(
      systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Branch")?
      .withSymbolConfiguration(cfg)
  }

  private func updateShortcutsIcon() {
    let cfg = NSImage.SymbolConfiguration(pointSize: statusFontSize + 1, weight: .regular)
    shortcutsButton.image = NSImage(
      systemSymbolName: "keyboard", accessibilityDescription: "Keyboard shortcuts")?
      .withSymbolConfiguration(cfg)
  }
}