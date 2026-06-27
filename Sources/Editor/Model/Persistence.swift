import AppKit
import Defaults
import Foundation

// JSON snapshot persisted to UserDefaults("editor.state"). Tab/session ids are random UUIDs that
// regenerate on restore, so active selections are persisted by *index*, not id.

struct PersistedTab: Codable {
  var kind: String
  var title: String
  var path: String?
  var pinned: Bool?
}

struct PersistedSession: Codable {
  var url: String
  var tabs: [PersistedTab]
  var activeTabIndex: Int?
}

struct PersistedState: Codable {
  var sessions: [PersistedSession]
  var activeSessionIndex: Int?
}

enum Persistence {
  static let recentProjectsLimit = 12

  static func load() -> PersistedState? {
    guard let data = UserDefaults.standard[AppDefaults.persistedState] else { return nil }
    return try? JSONDecoder().decode(PersistedState.self, from: data)
  }

  static func save(_ state: PersistedState) {
    if let data = try? JSONEncoder().encode(state) {
      UserDefaults.standard[AppDefaults.persistedState] = data
    }
  }

  static func recentProjects() -> [String] {
    let paths = UserDefaults.standard[AppDefaults.recentProjects]
    let filtered = paths.filter { FileManager.default.fileExists(atPath: $0) }
    if filtered.count != paths.count {
      UserDefaults.standard[AppDefaults.recentProjects] = filtered
    }
    return filtered
  }

  static func noteRecentProject(_ path: String) {
    let resolved = (path as NSString).standardizingPath
    var paths = recentProjects().filter { $0 != resolved }
    paths.insert(resolved, at: 0)
    if paths.count > recentProjectsLimit { paths = Array(paths.prefix(recentProjectsLimit)) }
    UserDefaults.standard[AppDefaults.recentProjects] = paths
    // Register with macOS LaunchServices so the dock "Open Recent" list is populated
    // even when the app is not running. Must be called on the main thread.
    let url = URL(fileURLWithPath: resolved)
    if Thread.isMainThread {
      NSDocumentController.shared.noteNewRecentDocumentURL(url)
    } else {
      DispatchQueue.main.async { NSDocumentController.shared.noteNewRecentDocumentURL(url) }
    }
  }
}
