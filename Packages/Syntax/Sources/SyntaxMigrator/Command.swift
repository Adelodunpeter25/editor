import ArgumentParser
import Foundation
import SyntaxFormat

@main
struct Command: ParsableCommand {

  static let configuration = CommandConfiguration(
    abstract:
      "A command-line tool to migrate CotEditor's legacy syntax definitions in YAML to the CotEditor Syntax format used since CotEditor 7."
  )

  @Argument(
    help: "A path to a legacy syntax file or a directory containing legacy syntax files.",
    transform: { URL(filePath: $0) })
  var path: URL

  @Option(
    name: .customLong("out"), help: "The path to the output directory.",
    transform: { URL(filePath: $0) })
  var destinationURL: URL?

  @Flag(help: "whether to keep the original.")
  var keep: Bool = false

  func run() throws {

    if try self.path.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
      try Syntax.migrateFormat(in: self.path, to: self.destinationURL, deletingOriginal: !self.keep)
    } else {
      try Syntax.migrate(fileURL: self.path, to: self.destinationURL, deletingOriginal: !self.keep)
    }
  }
}
