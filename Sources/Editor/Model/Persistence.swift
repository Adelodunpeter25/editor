import AppKit
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
  static let key = "editor.state"
  static let recentProjectsKey = "editor.recentProjects"
  static let recentProjectsLimit = 12

  static func load() -> PersistedState? {
    guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(PersistedState.self, from: data)
  }

  static func save(_ state: PersistedState) {
    if let data = try? JSONEncoder().encode(state) {
      UserDefaults.standard.set(data, forKey: key)
    }
  }

  static func recentProjects() -> [String] {
    let paths = UserDefaults.standard.stringArray(forKey: recentProjectsKey) ?? []
    return paths.filter { FileManager.default.fileExists(atPath: $0) }
  }

  static func noteRecentProject(_ path: String) {
    let resolved = (path as NSString).standardizingPath
    var paths = recentProjects().filter { $0 != resolved }
    paths.insert(resolved, at: 0)
    if paths.count > recentProjectsLimit { paths = Array(paths.prefix(recentProjectsLimit)) }
    UserDefaults.standard.set(paths, forKey: recentProjectsKey)
    // Register with macOS so the dock right-click "Open Recent" list works even when the app
    // is not running (same mechanism used by Xcode, VSCode, etc.).
    NSDocumentController.shared.noteNewRecentDocumentURL(URL(fileURLWithPath: resolved))
  }
}
