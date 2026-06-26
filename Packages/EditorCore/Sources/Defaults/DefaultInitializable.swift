public protocol DefaultInitializable: RawRepresentable, Sendable {

  static var defaultValue: Self { get }
}

extension DefaultInitializable {

  /// Non-optional initializer by setting the defaultValue if failed.
  ///
  /// - Parameter rawValue: The optional raw value.
  public init(_ rawValue: RawValue?) {

    self = Self(rawValue: rawValue ?? Self.defaultValue.rawValue) ?? Self.defaultValue
  }
}
