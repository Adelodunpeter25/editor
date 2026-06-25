import Foundation

/// Project-wide text search scoped to one repo. Shells out to `git grep` — every Editor session is a git
/// repo, so there's no extra dependency: it respects `.gitignore`, is fast, and (with `--untracked`)
/// covers tracked *and* new-but-not-ignored files, matching VS Code's default search scope. Cheap to call
/// off-main; the caller debounces and runs it on a background queue.
enum ProjectSearch {
  struct Options: Equatable {
    var matchCase = false
    var wholeWord = false
    var regex = false
  }

  struct Match {
    let line: Int
    let preview: String
  }
  struct FileHits {
    let file: String
    let matches: [Match]
  }

  struct Result {
    let files: [FileHits]
    /// `git grep` errored (e.g. an invalid regex) — distinct from simply finding nothing.
    let failed: Bool
    var matchCount: Int { files.reduce(0) { $0 + $1.matches.count } }
  }

  /// Run a search. Empty query → empty result (no subprocess). Caps total matches so a pathological
  /// query (a single char across a huge tree) stays light.
  static func run(
    _ query: String, in repo: String, fff: FffInstance?, options: Options, maxMatches: Int = 5000
  )
    -> Result
  {
    guard !query.isEmpty else { return Result(files: [], failed: false) }

    guard let fff = fff else {
      print("WARNING: FFF not available in ProjectSearch!")
      return Result(files: [], failed: true)
    }

    let mode: UInt8 = options.regex ? 1 : 0
    let matches = fff.liveGrep(query: query, mode: mode, pageSize: maxMatches)

    var grouped: [String: [Match]] = [:]
    var order: [String] = []
    for m in matches {
      let match = Match(line: m.lineNumber, preview: m.lineContent)
      if grouped[m.relativePath] == nil {
        grouped[m.relativePath] = []
        order.append(m.relativePath)
      }
      grouped[m.relativePath]?.append(match)
    }

    let files = order.map { file in
      FileHits(file: file, matches: grouped[file] ?? [])
    }
    return Result(files: files, failed: false)
  }
}
