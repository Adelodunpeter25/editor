import Foundation
import TextFind

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

  /// Replace all occurrences of `query` with `replacement` across the given files (from a prior
  /// `run` result). Returns the number of files modified. Uses the same options (matchCase/wholeWord/
  /// regex) as `run`. For non-regex mode the query is treated as a literal string. For regex mode,
  /// `$1`/`$2` capture groups are supported.
  static func replaceAll(
    _ query: String, with replacement: String, in repo: String,
    options: Options, files: [FileHits]
  ) -> Int {
    guard !query.isEmpty, !files.isEmpty else { return 0 }

    // Build the regex for replacement.
    var pattern = options.regex ? query : NSRegularExpression.escapedPattern(for: query)
    if options.wholeWord { pattern = "\\b" + pattern + "\\b" }
    let regexOpts: NSRegularExpression.Options = options.matchCase ? [] : [.caseInsensitive]
    guard let regex = try? NSRegularExpression(pattern: pattern, options: regexOpts) else { return 0 }

    var changedCount = 0
    for hit in files {
      let absPath = (repo as NSString).appendingPathComponent(hit.file)
      guard let content = try? String(contentsOfFile: absPath, encoding: .utf8) else { continue }
      let mutable = NSMutableString(string: content)
      let range = NSRange(location: 0, length: mutable.length)
      let replaced = regex.replaceMatches(
        in: mutable, range: range, withTemplate: replacement)
      if replaced > 0 {
        let newContent = mutable as String
        try? newContent.write(toFile: absPath, atomically: true, encoding: .utf8)
        changedCount += 1
      }
    }
    return changedCount
  }
}
