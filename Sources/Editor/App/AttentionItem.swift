import AppKit
import Combine

/// Menu-bar status indicator (stubbed — Claude status removed).
final class AttentionItem: NSObject {
  static weak var current: AttentionItem?

  private let model: AppModel
  var onJump: ((_ sessionID: String, _ tabID: String?) -> Void)?

  private var statusItem: NSStatusItem?

  init(model: AppModel) {
    self.model = model
    super.init()
    AttentionItem.current = self
  }

  func start() {
    // No-op: status indicator removed (no ClaudeState).
  }

  func debugState() -> [String: Any] {
    return ["installed": statusItem != nil]
  }
}
