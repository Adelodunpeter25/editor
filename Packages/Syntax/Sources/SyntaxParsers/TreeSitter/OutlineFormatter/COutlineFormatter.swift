import Foundation
import SwiftTreeSitter
import SyntaxFormat

enum COutlineFormatter: TreeSitterOutlineFormatting {

  static func title(for match: QueryMatch, capture: OutlineCapture, source: NSString) -> (
    title: String, range: NSRange
  )? {

    switch capture.kind {
    case .function:
      guard
        let node = match.outlineNode,
        let resolved = Self.resolvedSignature(for: node, source: source)
      else { return Self.defaultTitle(capture: capture, source: source) }

      return resolved
    default:
      return Self.defaultTitle(capture: capture, source: source)
    }
  }
}

extension COutlineFormatter {

  /// Resolves the display title and signature range for a C function declarator in a single tree traversal.
  ///
  /// - Parameters:
  ///   - declarator: The captured top-level declarator node.
  ///   - source: The source text as `NSString`.
  /// - Returns: The display title and signature range, or `nil` if the node is not a function declarator.
  fileprivate static func resolvedSignature(for declarator: Node, source: NSString) -> (
    title: String, range: NSRange
  )? {

    guard
      let functionDeclarator = Self.functionDeclarator(in: declarator),
      let name = Self.functionName(in: functionDeclarator),
      let parameters = functionDeclarator.child(byFieldName: "parameters")
    else { return nil }

    let parameterList = source.substring(with: parameters.range)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    let title = source.substring(with: name.range) + parameterList
    let range = name.range.union(parameters.range)

    return (title, range)
  }

  /// Returns the innermost function declarator for a C declarator tree.
  ///
  /// - Parameter declarator: The declarator node to inspect.
  /// - Returns: The function declarator, or `nil` if none exists.
  private static func functionDeclarator(in declarator: Node) -> Node? {

    if declarator.nodeType == "function_declarator" {
      return declarator
    }
    if let child = declarator.child(byFieldName: "declarator") {
      return Self.functionDeclarator(in: child)
    }

    return nil
  }

  /// Returns the identifier node representing the C function name.
  ///
  /// - Parameter declarator: The function declarator to inspect.
  /// - Returns: The function name node, or `nil` if it cannot be resolved.
  private static func functionName(in declarator: Node) -> Node? {

    guard let child = declarator.child(byFieldName: "declarator") else { return nil }

    return Self.identifier(in: child)
  }

  /// Returns the identifier node contained in a nested C declarator tree.
  ///
  /// - Parameter declarator: The declarator node to inspect.
  /// - Returns: The identifier node, or `nil` if it cannot be resolved.
  private static func identifier(in declarator: Node) -> Node? {

    if declarator.nodeType == "identifier" {
      return declarator
    }
    if let child = declarator.child(byFieldName: "declarator") {
      return Self.identifier(in: child)
    }

    for index in 0..<declarator.namedChildCount {
      if let child = declarator.namedChild(at: index), let identifier = Self.identifier(in: child) {
        return identifier
      }
    }

    return nil
  }
}
