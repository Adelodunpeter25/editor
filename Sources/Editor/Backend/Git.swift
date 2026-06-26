import Foundation

enum GitStatus: String {
  case none, new, modified, deleted, renamed, conflict, ignored
}

struct FileEntry {
  let path: String  // repo-relative, forward-slashed
  var status: GitStatus
  var isDir: Bool  // collapsed dir node (e.g. ignored node_modules)
}

enum Git {
  private static let git = "/usr/bin/git"

  private static func bytes(_ repo: String, _ args: [String]) -> Data {
    Shell.runData(git, ["-C", repo] + args)
  }

  private static func nulSplit(_ data: Data) -> [String] {
    data.split(separator: 0).compactMap { String(data: Data($0), encoding: .utf8) }.filter {
      !$0.isEmpty
    }
  }

  private static func category(_ xy: String) -> GitStatus {
    let c = Array(xy)
    let x = c.first ?? " "
    let y = c.count > 1 ? c[1] : " "
    if x == "?" || y == "?" { return .new }
    if x == "U" || y == "U" || (x == "D" && y == "D") || (x == "A" && y == "A") { return .conflict }
    if x == "R" || y == "R" || x == "C" || y == "C" { return .renamed }
    if x == "A" { return .new }
    if x == "D" || y == "D" { return .deleted }
    if x == "M" || y == "M" { return .modified }
    return .none
  }

  /// True if `repo` is inside a git work tree. Cached — a repo's git-ness doesn't change during a
  /// session, and this ran on every refresh before.
  private static var isRepoCache: [String: Bool] = [:]
  private static let isRepoLock = NSLock()
  static func isRepo(_ repo: String) -> Bool {
    isRepoLock.lock()
    if let cached = isRepoCache[repo] {
      isRepoLock.unlock()
      return cached
    }
    isRepoLock.unlock()
    let gitPath = (repo as NSString).appendingPathComponent(".git")
    let result = FileManager.default.fileExists(atPath: gitPath)
    isRepoLock.lock()
    isRepoCache[repo] = result
    isRepoLock.unlock()
    return result
  }

  static func repoFiles(_ repo: String, expandIgnored: Bool) -> [FileEntry] {
    isRepo(repo) ? gitFiles(repo, expandIgnored) : fsFiles(repo, expandIgnored)
  }

  /// Flat list of working-tree changes (modified / new / deleted / renamed), for the Changes view.
  static func changes(_ repo: String) -> [FileEntry] {
    guard isRepo(repo) else { return [] }
    var status: [String: GitStatus] = [:]
    let toks = nulSplit(bytes(repo, ["status", "--porcelain=v1", "-z", "--untracked-files=all"]))
    var i = 0
    while i < toks.count {
      let tok = toks[i]
      if tok.count >= 3 {
        let xy = String(tok.prefix(2))
        let path = String(tok.dropFirst(3))
        let cat = category(xy)
        if cat != .none { status[path] = cat }
        if xy.contains("R") || xy.contains("C") { i += 1 }
      }
      i += 1
    }
    return status.map { FileEntry(path: $0.key, status: $0.value, isDir: false) }
      .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
  }

  /// Working-tree changes split into staged (index) and unstaged (worktree), for the Changes view.
  static func statusGroups(_ repo: String) -> (staged: [FileEntry], unstaged: [FileEntry]) {
    guard isRepo(repo) else { return ([], []) }
    var staged: [FileEntry] = []
    var unstaged: [FileEntry] = []
    let toks = nulSplit(bytes(repo, ["status", "--porcelain=v1", "-z", "--untracked-files=all"]))
    var i = 0
    while i < toks.count {
      let tok = toks[i]
      if tok.count >= 3 {
        let chars = Array(tok)
        let x = chars[0]
        let y = chars[1]
        let path = String(tok.dropFirst(3))
        if x != " " && x != "?" {
          staged.append(FileEntry(path: path, status: statusFor(x), isDir: false))
        }
        if y != " " { unstaged.append(FileEntry(path: path, status: statusFor(y), isDir: false)) }
        if x == "R" || x == "C" || y == "R" || y == "C" { i += 1 }  // skip the rename's orig-path token
      }
      i += 1
    }
    let sort: ([FileEntry]) -> [FileEntry] = {
      $0.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }
    return (sort(staged), sort(unstaged))
  }

  private static func statusFor(_ c: Character) -> GitStatus {
    switch c {
    case "M": return .modified
    case "A": return .new
    case "D": return .deleted
    case "R", "C": return .renamed
    case "U": return .conflict
    case "?": return .new
    default: return .modified
    }
  }

  // MARK: Actions (return git's combined output; empty == typically success)

  @discardableResult private static func op(_ repo: String, _ args: [String]) -> String {
    Shell.run(git, ["-C", repo] + args)
  }

  static func stage(_ repo: String, _ path: String) { op(repo, ["add", "--", path]) }
  static func unstage(_ repo: String, _ path: String) {
    op(repo, ["reset", "-q", "HEAD", "--", path])
  }
  static func stageAll(_ repo: String) { op(repo, ["add", "-A"]) }
  static func unstageAll(_ repo: String) { op(repo, ["reset", "-q", "HEAD"]) }
  static func stash(_ repo: String) { op(repo, ["stash", "push", "-u"]) }
  static func unstash(_ repo: String) { op(repo, ["stash", "pop"]) }
  static func stashCount(_ repo: String) -> Int {
    let out = op(repo, ["stash", "list"])
    return out.isEmpty ? 0 : out.split(separator: "\n").count
  }

  /// Fully discard a file's changes (staged + unstaged). New files are removed from disk.
  static func discard(_ repo: String, _ path: String, _ status: GitStatus) {
    if status == .new {
      op(repo, ["reset", "-q", "--", path])  // unstage if it was staged (no-op otherwise)
      try? FileManager.default.removeItem(atPath: (repo as NSString).appendingPathComponent(path))
    } else {
      op(repo, ["checkout", "HEAD", "--", path])  // restore index + worktree to HEAD
    }
  }

  /// Nuke ALL working changes: reset tracked to HEAD and remove untracked files/dirs.
  static func discardAll(_ repo: String) {
    op(repo, ["reset", "--hard", "HEAD"])
    op(repo, ["clean", "-fd"])
  }

  /// Current branch name for the status bar; a short sha in parens when detached. nil outside a repo.
  static func branch(_ repo: String) -> String? {
    guard isRepo(repo) else { return nil }
    let name = Shell.run(git, ["-C", repo, "rev-parse", "--abbrev-ref", "HEAD"])
    guard !name.isEmpty else { return nil }
    if name == "HEAD" {  // detached — show the short commit instead
      let sha = Shell.run(git, ["-C", repo, "rev-parse", "--short", "HEAD"])
      return sha.isEmpty ? nil : "(\(sha))"
    }
    return name
  }

  /// Local branch names (sorted). The caller marks the current one via `branch(_:)`.
  static func localBranches(_ repo: String) -> [String] {
    guard isRepo(repo) else { return [] }
    return Shell.run(git, ["-C", repo, "for-each-ref", "--format=%(refname:short)", "refs/heads"])
      .split(separator: "\n").map(String.init).sorted()
  }

  /// Switch to an existing branch. nil on success, else the git error (e.g. uncommitted-changes block).
  static func checkout(_ repo: String, _ branch: String) -> String? {
    let r = Shell.runFull(git, ["-C", repo, "checkout", branch])
    return r.code == 0 ? nil : (r.err.isEmpty ? r.out : r.err)
  }

  /// Create + check out a new branch. nil on success, else the git error.
  static func createBranch(_ repo: String, _ name: String) -> String? {
    let r = Shell.runFull(git, ["-C", repo, "checkout", "-b", name])
    return r.code == 0 ? nil : (r.err.isEmpty ? r.out : r.err)
  }

  /// `git init` a freshly-created folder (for "New Project"). Returns nil on success, else an error message.
  @discardableResult
  static func initRepo(_ repo: String) -> String? {
    let r = Shell.runFull(git, ["-C", repo, "init"])
    isRepoLock.lock()
    isRepoCache[repo] = (r.code == 0)
    isRepoLock.unlock()  // refresh the isRepo cache
    return r.code == 0 ? nil : (r.err.isEmpty ? r.out : r.err)
  }

  /// Whether `branch` is fully merged into HEAD (an ancestor of the current commit). Lets the caller
  /// word the delete confirmation appropriately and pick `-d` vs `-D`.
  static func isMerged(_ repo: String, _ branch: String) -> Bool {
    Shell.runFull(git, ["-C", repo, "merge-base", "--is-ancestor", branch, "HEAD"]).code == 0
  }

  /// Delete a branch. `force` uses `-D` (deletes even if unmerged). Reports whether a safe `-d` was
  /// refused because the branch isn't fully merged, so the caller can confirm a force-delete.
  static func deleteBranch(_ repo: String, _ name: String, force: Bool) -> (
    ok: Bool, unmerged: Bool, error: String?
  ) {
    let r = Shell.runFull(git, ["-C", repo, "branch", force ? "-D" : "-d", name])
    if r.code == 0 { return (true, false, nil) }
    return (false, r.err.contains("not fully merged"), r.err.isEmpty ? r.out : r.err)
  }

  /// Commit staged changes. Returns git output (non-empty on error to surface).
  @discardableResult static func commit(_ repo: String, _ message: String) -> String {
    op(repo, ["commit", "-m", message])
  }

  /// Push the current branch; sets upstream automatically on first push.
  static func push(_ repo: String) {
    if op(repo, ["rev-parse", "--abbrev-ref", "@{u}"]).isEmpty {
      op(repo, ["push", "-u", "origin", "HEAD"])
    } else {
      op(repo, ["push"])
    }
  }

  /// Commit history entry.
  struct LogEntry {
    let hash: String  // short sha
    let fullHash: String  // full sha
    let message: String  // first line of commit message
    let author: String
    let date: String  // relative date (e.g. "2 hours ago")
  }

  /// Recent commit log. Uses `git log` with a compact separator format.
  static func log(_ repo: String, limit: Int = 100, skip: Int = 0) -> [LogEntry] {
    guard isRepo(repo) else { return [] }
    let format = "%h%x1f%H%x1f%s%x1f%an%x1f%ar"
    let output = Shell.run(
      git, ["-C", repo, "log", "--pretty=format:\(format)", "--skip=\(skip)", "-\(limit)"])
    guard !output.isEmpty else { return [] }
    let sep = "\u{1F}"
    let parsed: [LogEntry] = output.components(separatedBy: "\n").compactMap { line in
      let parts = line.components(separatedBy: sep)
      guard parts.count >= 5 else { return nil }
      return LogEntry(
        hash: parts[0], fullHash: parts[1], message: parts[2], author: parts[3], date: parts[4])
    }
    return parsed
  }

  /// Files changed in a specific commit.
  static func commitFiles(_ repo: String, hash: String) -> [String] {
    let output = Shell.run(
      git, ["-C", repo, "diff-tree", "--no-commit-id", "--name-only", "-r", hash])
    return output.components(separatedBy: "\n").filter { !$0.isEmpty }
  }

  /// Get the hash of the latest commit (HEAD) in the repo.
  static func lastCommitHash(_ repo: String) -> String {
    guard isRepo(repo) else { return "" }
    let output = Shell.run(git, ["-C", repo, "rev-parse", "HEAD"])
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func headText(forAbsolutePath path: String) -> String? {
    let dir = (path as NSString).deletingLastPathComponent
    let repo = Shell.run(git, ["-C", dir, "rev-parse", "--show-toplevel"])
    guard !repo.isEmpty else { return nil }
    let prefix = repo.hasSuffix("/") ? repo : repo + "/"
    let relativePath = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    let output = Shell.run(git, ["-C", repo, "show", "HEAD:\(relativePath)"])
    return output.isEmpty ? nil : output
  }

  static func workingTreeVersions(_ repo: String, _ path: String, liveNewText: String? = nil) -> (
    old: String, new: String
  ) {
    let old =
      String(data: Shell.runData(git, ["-C", repo, "show", "HEAD:\(path)"]), encoding: .utf8)
      ?? ""
    if let liveNewText { return (old, liveNewText) }
    let url = URL(fileURLWithPath: repo).appendingPathComponent(path)
    let new = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    return (old, new)
  }

  /// (oldText, newText) for a path. Either side may be "" (new file → empty old; deleted → empty new).
  static func versions(_ repo: String, _ path: String, commitHash: String? = nil) -> (
    old: String, new: String
  ) {
    if let commitHash {
      var old = ""
      var new = ""
      let group = DispatchGroup()

      group.enter()
      DispatchQueue.global().async {
        old =
          String(
            data: Shell.runData(git, ["-C", repo, "show", "\(commitHash)^:\(path)"]),
            encoding: .utf8) ?? ""
        group.leave()
      }

      group.enter()
      DispatchQueue.global().async {
        new =
          String(
            data: Shell.runData(git, ["-C", repo, "show", "\(commitHash):\(path)"]), encoding: .utf8
          )
          ?? ""
        group.leave()
      }

      group.wait()
      return (old, new)
    } else {
      let old =
        String(data: Shell.runData(git, ["-C", repo, "show", "HEAD:\(path)"]), encoding: .utf8)
        ?? ""
      let url = URL(fileURLWithPath: repo).appendingPathComponent(path)
      let new = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
      return (old, new)
    }
  }

  struct CommitSummary {
    let hash: String
    let authorName: String
    let authorEmail: String
    let date: String
    let message: String
    let files: [FileStat]
  }

  struct FileStat {
    let path: String
    let additions: Int
    let deletions: Int
  }

  static func commitSummary(_ repo: String, hash: String) -> CommitSummary? {
    let gitPath = Env.resolve("git")
    // Format: name\u{1}email\u{1}date\u{1}body
    let info = Shell.run(
      gitPath, ["-C", repo, "show", "--quiet", "--pretty=format:%an\u{1}%ae\u{1}%ad\u{1}%B", hash])
    let parts = info.components(separatedBy: "\u{1}")
    guard parts.count >= 4 else { return nil }

    let authorName = parts[0]
    let authorEmail = parts[1]
    let date = parts[2]
    let message = parts.dropFirst(3).joined(separator: "\u{1}")

    let numstat = Shell.run(gitPath, ["-C", repo, "show", "--numstat", "--format=", hash])
    var files: [FileStat] = []
    for line in numstat.components(separatedBy: "\n") {
      let lineParts = line.components(separatedBy: "\t")
      if lineParts.count >= 3 {
        let add = Int(lineParts[0]) ?? 0
        let del = Int(lineParts[1]) ?? 0
        let path = lineParts[2]
        if !path.isEmpty {
          files.append(FileStat(path: path, additions: add, deletions: del))
        }
      }
    }
    return CommitSummary(
      hash: hash, authorName: authorName, authorEmail: authorEmail, date: date, message: message,
      files: files)
  }

  private static func gitFiles(_ repo: String, _ expand: Bool) -> [FileEntry] {
    // Run status + ls-files in parallel for faster startup
    var statusMap: [String: GitStatus] = [:]
    var lsData = Data()
    var ignoredData = Data()

    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
      let toks = nulSplit(bytes(repo, ["status", "--porcelain=v1", "-z", "--untracked-files=all"]))
      var i = 0
      while i < toks.count {
        let tok = toks[i]
        if tok.count >= 3 {
          let xy = String(tok.prefix(2))
          let path = String(tok.dropFirst(3))
          let cat = category(xy)
          if cat != .none { statusMap[path] = cat }
          if xy.contains("R") || xy.contains("C") { i += 1 }
        }
        i += 1
      }
      group.leave()
    }
    group.enter()
    DispatchQueue.global().async {
      lsData = Shell.runData(
        git, ["-C", repo, "ls-files", "-z", "--cached", "--others", "--exclude-standard"])
      group.leave()
    }
    group.enter()
    DispatchQueue.global().async {
      let ignoredArgs =
        expand
        ? ["-C", repo, "ls-files", "-z", "--others", "--ignored", "--exclude-standard"]
        : [
          "-C", repo, "ls-files", "-z", "--others", "--ignored", "--exclude-standard",
          "--directory",
        ]
      ignoredData = Shell.runData(git, ignoredArgs)
      group.leave()
    }
    group.wait()

    var entries: [FileEntry] = []
    var seen = Set<String>()

    for path in nulSplit(lsData) {
      if statusMap[path] == .deleted { continue }
      if seen.insert(path).inserted {
        entries.append(FileEntry(path: path, status: statusMap[path] ?? .none, isDir: false))
      }
    }
    for raw in nulSplit(ignoredData) {
      let isDir = raw.hasSuffix("/")
      let path = isDir ? String(raw.dropLast()) : raw
      if seen.insert(path).inserted {
        entries.append(FileEntry(path: path, status: .ignored, isDir: isDir))
      }
    }
    return entries
  }

  private static func fsFiles(_ repo: String, _ expand: Bool) -> [FileEntry] {
    var out: [FileEntry] = []
    // Resolve symlinks (e.g. /tmp -> /private/tmp) so relative-path stripping works.
    let base = URL(fileURLWithPath: repo).resolvingSymlinksInPath()
    func walk(_ dir: URL) {
      guard
        let items = try? FileManager.default.contentsOfDirectory(
          at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
      else { return }
      for url in items {
        let name = url.lastPathComponent
        if name == ".git" { continue }
        let rel = String(url.path.dropFirst(base.path.count + 1))
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDir {
          if name == "node_modules" && !expand {
            out.append(FileEntry(path: rel, status: .none, isDir: true))
            continue
          }
          walk(url)
        } else {
          out.append(FileEntry(path: rel, status: .none, isDir: false))
        }
      }
    }
    walk(base)
    return out
  }
}
