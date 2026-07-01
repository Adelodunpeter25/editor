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
  /// `run` result). Returns the number of files modified. Uses `TextFind` from EditorCore for
  /// proper full-word, case-sensitivity, and regex capture-group handling.
  static func replaceAll(
    _ query: String, with replacement: String, in repo: String,
    options: Options, files: [FileHits]
  ) -> Int {
    guard !query.isEmpty, !files.isEmpty else { return 0 }

    let mode = options.textFindMode

    var changedCount = 0
    for hit in files {
      let absPath = (repo as NSString).appendingPathComponent(hit.file)
      guard let content = try? String(contentsOfFile: absPath, encoding: .utf8) else { continue }
      guard let finder = try? TextFind(
        for: content, findString: query, mode: mode, inSelection: false,
        selectedRanges: [content.range])
      else { continue }

      let (items, _) = finder.replaceAll(with: replacement) { _, _, _ in }
      guard !items.isEmpty else { continue }

      // Apply the replacement items to build the new content.
      let mutable = NSMutableAttributedString(string: content)
      for item in items.reversed() {
        mutable.replaceCharacters(in: item.range, with: item.value)
      }
      let newContent = mutable.string
      try? newContent.write(toFile: absPath, atomically: true, encoding: .utf8)
      changedCount += 1
    }
    return changedCount
  }
}

extension ProjectSearch.Options {
  var textFindMode: TextFind.Mode {
    if regex {
      let regexOpts: NSRegularExpression.Options = matchCase ? [] : [.caseInsensitive]
      return .regularExpression(options: regexOpts, unescapesReplacement: true)
    } else {
      let compareOpts: String.CompareOptions = matchCase ? [] : [.caseInsensitive]
      return .textual(options: compareOpts, fullWord: wholeWord)
    }
  }
}
