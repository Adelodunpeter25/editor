extension Character {

  /// The representative character to display in the user interface.
  public var pictureCharacter: Character? {

    self.unicodeScalars.count == 1  // ignore CRLF
      ? self.unicodeScalars.first?.pictureRepresentation.map(Character.init)
      : nil
  }

  /// Whether the character consists with multiple Unicode scalars.
  public var isComplex: Bool {

    self.unicodeScalars.count > 1 && !self.isVariant
  }

  /// Whether the character is a single variant character.
  public var isVariant: Bool {

    (self.unicodeScalars.count == 2 && self.unicodeScalars.last?.variantDescription != nil)
  }
}
