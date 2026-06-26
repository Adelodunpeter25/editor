import Defaults
import Foundation

/// App-level UserDefaults keys that live outside the `Settings` class — UI state like the sidebar
/// width, the diff split toggle, the sidebar mode, and the persisted session/recent-projects data.
/// Centralized here so every access goes through a type-safe `DefaultKey` (no stringly-typed keys).
enum AppDefaults {
  // UI state
  static let sidebarWidth = DefaultKey<Double>("editor.sidebarWidth")
  static let sidebarMode = DefaultKey<Int>("rightMode")
  static let diffSplit = DefaultKey<Bool>("diffSplit")

  // Per-repo empty-dirs set (key is dynamic — append the repo path).
  static func emptyDirsKey(forRepo repo: String) -> String { "editor.emptyDirs:" + repo }

  // Persisted session snapshot (Data) + recent projects list.
  static let persistedState = DefaultKey<Data?>("editor.state")
  static let recentProjects = DefaultKey<[String]>("editor.recentProjects")
}
