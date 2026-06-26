import Foundation

extension Syntax.Kind {

  public var label: String {

    switch self {
    case .general: "General"
    case .code: "Code"
    }
  }
}

extension SyntaxType {

  public var label: String {

    switch self {
    case .keywords: "Keywords"
    case .commands: "Commands"
    case .types: "Types"
    case .attributes: "Attributes"
    case .variables: "Variables"
    case .values: "Values"
    case .numbers: "Numbers"
    case .strings: "Strings"
    case .characters: "Characters"
    case .comments: "Comments"
    }
  }
}

extension Syntax.Outline.Kind {

  public var label: String {

    switch self {
    case .container: "Container"
    case .value: "Value"
    case .function: "Function"
    case .title: "Title"
    case .heading(let level?):
      "Heading \(level)"
    case .heading(nil):
      "Heading"
    case .mark: "Mark"
    case .separator: "Separator"
    }
  }
}
