extension Unicode.Scalar {

  /// The code point string in format like `U+000F`.
  public var codePoint: String {

    "U+\(self.value.codePoint)"
  }

  /// The code point pair in UTF-16 surrogate pair.
  public var surrogateCodePoints: (lead: String, trail: String)? {

    guard self.isSurrogatePair else { return nil }

    return (
      lead: "U+\(UTF16.leadSurrogate(self).codePoint)",
      trail: "U+\(UTF16.trailSurrogate(self).codePoint)"
    )
  }

  /// The Unicode name.
  public var name: String? {

    self.properties.nameAlias
      ?? self.properties.name
      ?? self.controlCharacterName  // get control character name from special table
  }

  /// The Unicode block name defined in the Unicode.
  public var blockName: String? {

    self.value.blockName
  }

  /// The localized Unicode block name.
  public var localizedBlockName: String? {

    guard let blockName else { return nil }

    return localizeBlockName(blockName) ?? blockName
  }
}

extension Unicode.Scalar {

  /// Boolean value indicating whether character becomes a surrogate pair in UTF-16.
  var isSurrogatePair: Bool {

    (UTF16.width(self) == 2)
  }
}
