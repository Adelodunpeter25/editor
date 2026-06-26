import ArgumentParser
import Foundation
import SyntaxFormat

@main
struct Command: ParsableCommand {

  static let configuration = CommandConfiguration(
    abstract:
      "A command-line tool for CotEditor to build SyntaxMap.json from CotEditor Syntax files."
  )

  @Argument(help: "A path to the Syntaxes directory.", transform: { URL(filePath: $0) })
  var input: URL

  @Argument(help: "The path to the result JSON file.", transform: { URL(filePath: $0) })
  var output: URL

  func run() throws {

    let urls = try FileManager.default.contentsOfDirectory(
      at: self.input, includingPropertiesForKeys: nil
    )
    .filter { $0.pathExtension == "cotsyntax" }
    let syntaxMap = try Syntax.FileMap.load(at: urls)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    let data = try encoder.encode(syntaxMap)
    try data.write(to: self.output)
  }
}
