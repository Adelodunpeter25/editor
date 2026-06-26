extension Unicode.UTF32.CodeUnit {

  /// Returns Unicode name.
  ///
  /// Implemented at UTF32.CodeUnit level in order to cover single surrogate characters
  /// that are not allowed by Unicode.Scalar.
  public var unicodeName: String? {

    if let name = Unicode.Scalar(self)?.name {
      return name
    }

    if let codeUnit = UTF16.CodeUnit(exactly: self) {
      if UTF16.isLeadSurrogate(codeUnit) {
        return "<lead surrogate-\(codeUnit.codePoint)>"
      }
      if UTF16.isTrailSurrogate(codeUnit) {
        return "<trail surrogate-\(codeUnit.codePoint)>"
      }
    }

    return nil
  }
}
