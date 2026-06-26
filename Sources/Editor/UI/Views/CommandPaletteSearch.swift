import Foundation

// MARK: - Search types

/// A file result row for the palette.
struct PaletteFileRow {
  let rel: String
  let status: GitStatus
}

/// A command entry for the `>` command mode.
struct PaletteCommand {
  let title: String
  let keepsOpen: Bool
  let run: () -> Void
}

/// The active palette mode.
enum PaletteMode {
  case file
  case line
  case command
}

/// The result of a palette search.
struct PaletteSearchResult {
  var mode: PaletteMode = .file
  var fileHits: [PaletteFileRow] = []
  var commandHits: [PaletteCommand] = []
  var commandQuery: String = ""  // for match highlighting
  var lineJump: Int? = nil
  var isGlob: Bool = false  // glob results don't get fuzzy highlight
}

// MARK: - PaletteSearchEngine

/// Handles all filtering logic for the command palette: fuzzy file search, glob patterns,
/// command mode (`>`), and line-jump mode (`:`).
/// Separated from the controller so the controller stays a thin UI shell.
final class PaletteSearchEngine {
  private let model: AppModel

  /// Full repo file listing (lazy, fetched on present).
  private(set) var allFiles: [PaletteFileRow] = []
  /// Currently-open file tabs (shown for empty query).
  private(set) var openFiles: [PaletteFileRow] = []

  init(model: AppModel) {
    self.model = model
  }

  /// Build the open-tabs quick-switch list from the active session.
  func refreshOpenFiles() {
    guard let session = model.activeSession else {
      openFiles = []
      return
    }
    openFiles = session.tabs
      .filter { $0.kind == .file }
      .compactMap { $0.path }
      .map { PaletteFileRow(rel: Self.relative($0, to: session.url), status: .none) }
  }

  /// Fetch the full repo file listing off-main. Calls `completion` on main when done.
  func loadRepoFiles(completion: @escaping () -> Void) {
    guard let repo = model.activeSession?.url else {
      allFiles = []
      completion()
      return
    }
    DispatchQueue.global().async { [weak self] in
      let rows = Git.repoFiles(repo, expandIgnored: false)
        .filter { !$0.isDir }
        .map { PaletteFileRow(rel: $0.path, status: $0.status) }
      DispatchQueue.main.async {
        self?.allFiles = rows
        completion()
      }
    }
  }

  /// Run the search for a given query string and return the result.
  func search(query: String) -> PaletteSearchResult {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    var result = PaletteSearchResult()

    if trimmed.hasPrefix(">") {
      result.mode = .command
      result.commandQuery = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
      let cmds = buildCommands()
      if result.commandQuery.isEmpty {
        result.commandHits = cmds
      } else {
        result.commandHits =
          cmds.compactMap { c in Fuzzy.score(result.commandQuery, c.title).map { (c, $0) } }
          .sorted { $0.1 > $1.1 }.map { $0.0 }
      }
    } else if trimmed.hasPrefix(":") {
      result.mode = .line
      let digits = trimmed.dropFirst().filter(\.isNumber)
      result.lineJump = digits.isEmpty ? nil : Int(digits)
    } else if trimmed.isEmpty {
      result.mode = .file
      result.fileHits = openFiles
    } else if isGlob(trimmed) {
      result.mode = .file
      result.isGlob = true
      result.fileHits = filterByGlob(trimmed)
    } else {
      result.mode = .file
      result.fileHits = filterByFuzzy(trimmed)
    }

    return result
  }

  // MARK: - Glob

  /// Whether the query looks like a glob pattern (contains `*` or `?`).
  static func isGlob(_ query: String) -> Bool {
    query.contains("*") || query.contains("?")
  }

  private func isGlob(_ query: String) -> Bool { Self.isGlob(query) }

  /// Convert a glob pattern to a case-insensitive regex and filter the file list.
  /// `*` matches any characters (including `/`), `?` matches any single character.
  private func filterByGlob(_ pattern: String) -> [PaletteFileRow] {
    let regex = Self.globToRegex(pattern)
    return allFiles.filter { row in
      regex.firstMatch(in: row.rel, range: NSRange(location: 0, length: row.rel.utf16.count)) != nil
    }
  }

  /// Convert a glob pattern to a case-insensitive `NSRegularExpression`.
  /// - `*` → `.*` (match anything)
  /// - `?` → `.` (match one char)
  /// - Other regex metacharacters are escaped.
  static func globToRegex(_ glob: String) -> NSRegularExpression {
    var pattern = ""
    for ch in glob {
      switch ch {
      case "*": pattern += ".*"
      case "?": pattern += "."
      default:
        if "\\^$.|+(){}[]".contains(ch) {
          pattern += "\\\(ch)"
        } else {
          pattern += String(ch)
        }
      }
    }
    // Anchor to the full path so `*.swift` matches the whole relative path.
    pattern = "^" + pattern + "$"
    return try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
  }

  // MARK: - Fuzzy

  private func filterByFuzzy(_ query: String) -> [PaletteFileRow] {
    guard let fff = model.activeSession?.fff else {
      return []
    }
    let results = fff.search(query: query, maxResults: 50)
    return results.map { PaletteFileRow(rel: $0.relativePath, status: .none) }
  }

  // MARK: - Commands

  /// Build the command list for `>` mode. Built fresh each search so availability tracks current state.
  func buildCommands() -> [PaletteCommand] {
    var c: [PaletteCommand] = []
    if let s = model.activeSession {
      c.append(
        PaletteCommand(title: "New Terminal", keepsOpen: false) {
          s.addTab(Tab(kind: .terminal, title: "Terminal"))
        })
    }
    if ActiveEditor.current != nil {
      c.append(
        PaletteCommand(title: "Format Document", keepsOpen: false) {
          ActiveEditor.current?.formatDocument()
        })
    }
    if model.activeSession != nil {
      c.append(
        PaletteCommand(title: "Find in Files…", keepsOpen: false) { SidebarSearchHook.reveal?() })
    }
    c.append(
      PaletteCommand(title: "Go to File…", keepsOpen: true) { [weak self] in
        self?.onEnterFileMode?()
      })
    c.append(
      PaletteCommand(title: "Settings…", keepsOpen: false) { [weak self] in
        self?.model.showSettings = true
      })
    if let s = model.activeSession, let t = s.activeTab {
      c.append(
        PaletteCommand(title: "Close Tab", keepsOpen: false) {
          if UnsavedGuard.confirmClose(t) { s.closeTab(t.id) }
        })
    }
    return c
  }

  /// Set by the controller so the "Go to File…" command can switch the palette back to file mode.
  var onEnterFileMode: (() -> Void)?

  // MARK: - Helpers

  /// Convert an absolute path to a repo-relative path (basename if outside the repo).
  static func relative(_ abs: String, to repo: String) -> String {
    let prefix = repo.hasSuffix("/") ? repo : repo + "/"
    return abs.hasPrefix(prefix)
      ? String(abs.dropFirst(prefix.count)) : (abs as NSString).lastPathComponent
  }
}
