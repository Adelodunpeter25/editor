import AppKit

/// Root layout: a horizontal split with the sidebar (files) on the left and the workspace (center)
/// on the right. A *plain* NSSplitView (not NSSplitViewController) so the divider drags reliably.
final class WorkspaceViewController: NSViewController, NSSplitViewDelegate {
  private let model: AppModel
  private let centerVC: CenterViewController
  private let sidebarVC: SidebarViewController
  private var didSizeOnce = false

  init(model: AppModel) {
    self.model = model
    self.centerVC = CenterViewController(model: model)
    self.sidebarVC = SidebarViewController(model: model)
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func loadView() {
    let split = NSSplitView()
    split.isVertical = true
    split.dividerStyle = .thin
    split.autosaveName = "EditorMainSplit"
    split.delegate = self
    addChild(sidebarVC)
    addChild(centerVC)
    split.addArrangedSubview(sidebarVC.view)
    split.addArrangedSubview(centerVC.view)
    split.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
    split.setHoldingPriority(.defaultLow, forSubviewAt: 1)
    self.view = split
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    guard let split = view as? NSSplitView, split.bounds.width > 100,
      split.arrangedSubviews.count > 1
    else { return }
    let total = split.bounds.width
    let sidebarW = split.arrangedSubviews[0].frame.width
    if !didSizeOnce {
      didSizeOnce = true
      if sidebarW < 120 || sidebarW > total - 200 {
        split.setPosition(320, ofDividerAt: 0)
      }
    } else if sidebarW < 120 {
      split.setPosition(320, ofDividerAt: 0)
    }
  }

  func splitView(
    _ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat,
    ofSubviewAt dividerIndex: Int
  ) -> CGFloat { 220 }
  func splitView(
    _ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat,
    ofSubviewAt dividerIndex: Int
  ) -> CGFloat { splitView.bounds.width - 360 }
  func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
    view !== sidebarVC.view
  }
}
