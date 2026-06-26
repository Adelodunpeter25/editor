public class DefaultKeys: RawRepresentable, @unchecked Sendable {

  public final let rawValue: String

  public required init(rawValue: String) {

    self.rawValue = rawValue
  }

  public init(_ key: String) {

    self.rawValue = key
  }
}

extension DefaultKeys: Hashable {

  public final func hash(into hasher: inout Hasher) {

    hasher.combine(self.rawValue)
  }
}

extension DefaultKeys: CustomStringConvertible {

  public final var description: String {

    self.rawValue
  }
}

enum DefaultKeyError: Error, Sendable {

  case invalidValue
}

public class DefaultKey<Value>: DefaultKeys, @unchecked Sendable {

  func newValue(from value: Any?) throws -> Value {

    // -> The second Optional cast is important for in case if `Value` is already an optional type.
    guard let newValue = value as? Value ?? Optional<Any>.none as? Value else {
      throw DefaultKeyError.invalidValue
    }

    return newValue
  }
}

// Specialize RawRepresentable types to use them for UserDefaults observation using UserDefaults.Publisher.
// Otherwise, the type inference for RawRepresentable doesn't work unfortunately.
public final class RawRepresentableDefaultKey<Value>: DefaultKey<Value>, @unchecked Sendable
where Value: RawRepresentable {

  override func newValue(from value: Any?) throws -> Value {

    if let newValue = (value as? Value.RawValue).flatMap(Value.init) {
      return newValue
    }

    // fall back for broken external values, matching the integer subscript behavior
    if Value.RawValue.self == Int.self,
      let rawValue = 0 as? Value.RawValue,
      let newValue = Value(rawValue: rawValue)
    {
      return newValue
    }

    throw DefaultKeyError.invalidValue
  }
}
