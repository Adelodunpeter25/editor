import AppKit
import Defaults

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
    if !didSizeOnce {
      didSizeOnce = true
      let saved = UserDefaults.standard[AppDefaults.sidebarWidth]
      let width = saved >= 120 ? CGFloat(saved) : 320
      split.setPosition(width, ofDividerAt: 0)
    } else {
      let sidebarW = split.arrangedSubviews[0].frame.width
      if sidebarW < 120 {
        split.setPosition(320, ofDividerAt: 0)
      }
    }
  }

  func splitViewDidResizeSubviews(_ notification: Notification) {
    guard let split = view as? NSSplitView, split.arrangedSubviews.count > 0 else { return }
    let width = split.arrangedSubviews[0].frame.width
    if width >= 120 {
      UserDefaults.standard[AppDefaults.sidebarWidth] = Double(width)
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
