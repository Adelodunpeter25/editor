public enum SyntaxType: String, CaseIterable, Sendable {

  case keywords
  case commands
  case types
  case attributes
  case variables
  case values
  case numbers
  case strings
  case characters
  case comments
}

extension SyntaxType: Codable, CodingKeyRepresentable {}
