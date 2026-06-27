import Foundation

enum EdLauncher {
  private static let bundleIDs = [
    "com.adelodunpeter.editor",
    "com.adelodunpeter.editor.dev",
  ]

  private static let appNames = [
    "Editor",
    "Editor Dev",
  ]

  static func main() {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count <= 1 else {
      fputs("usage: ed [path]\n", stderr)
      exit(2)
    }

    let rawPath = args.first ?? "."
    let target = resolvePath(rawPath)
    let fm = FileManager.default
    guard fm.fileExists(atPath: target) else {
      fputs("ed: no such file or directory: \(rawPath)\n", stderr)
      exit(1)
    }

    if launchEditor(for: target) {
      exit(0)
    }

    fputs("ed: could not find an installed Editor app\n", stderr)
    exit(1)
  }

  private static func resolvePath(_ path: String) -> String {
    let fm = FileManager.default
    if path == "." { return fm.currentDirectoryPath }
    let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
    return URL(fileURLWithPath: path, relativeTo: cwd).standardizedFileURL.path
  }

  private static func launchEditor(for path: String) -> Bool {
    for bundleID in bundleIDs where open(arguments: ["-b", bundleID, path]) {
      return true
    }
    for appName in appNames where open(arguments: ["-a", appName, path]) {
      return true
    }
    return false
  }

  @discardableResult
  private static func open(arguments: [String]) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    p.arguments = arguments
    do {
      try p.run()
      p.waitUntilExit()
      return p.terminationStatus == 0
    } catch {
      return false
    }
  }
}

EdLauncher.main()
