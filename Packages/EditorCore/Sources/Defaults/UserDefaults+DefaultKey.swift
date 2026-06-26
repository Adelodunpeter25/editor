import Foundation

extension UserDefaults {

  /// Restores default value to the factory default.
  ///
  /// - Parameter key: The default key to restore.
  public func restore<T>(key: DefaultKey<T>) {

    self.removeObject(forKey: key.rawValue)
  }

  /// Returns the initial value for key registered on `register(defaults:)`.
  ///
  /// - Parameter key: The default key.
  /// - Returns: The initial value.
  public subscript<T>(initial key: DefaultKey<T>) -> T {

    self.volatileDomain(forName: UserDefaults.registrationDomain)[key.rawValue] as! T
  }

  /// Returns the initial value for key registered on `register(defaults:)`.
  ///
  /// - Parameter key: The default key.
  /// - Returns: The initial value.
  public subscript<T>(initial key: DefaultKey<T>) -> T where T: RawRepresentable, T.RawValue == Int
  {

    let rawValue =
      self.volatileDomain(forName: UserDefaults.registrationDomain)[key.rawValue] as? T.RawValue
      ?? 0

    return T(rawValue: rawValue) ?? T(rawValue: 0)!
  }

  /// Returns the initial value for key registered on `register(defaults:)`.
  ///
  /// - Parameter key: The default key.
  /// - Returns: The initial value.
  public subscript<T>(initial key: DefaultKey<T>) -> T?
  where T: RawRepresentable, T.RawValue == String {

    let rawValue =
      self.volatileDomain(forName: UserDefaults.registrationDomain)[key.rawValue] as? T.RawValue
      ?? ""

    return T(rawValue: rawValue)
  }

  public subscript(key: DefaultKey<Bool>) -> Bool {

    get { self.bool(forKey: key.rawValue) }
    set { self.set(newValue, forKey: key.rawValue) }
  }

  public subscript(key: DefaultKey<Int>) -> Int {

    get { self.integer(forKey: key.rawValue) }
    set { self.set(newValue, forKey: key.rawValue) }
  }

  public subscript(key: DefaultKey<Double>) -> Double {

    get { self.double(forKey: key.rawValue) }
    set { self.set(newValue, forKey: key.rawValue) }
  }

  public subscript(key: DefaultKey<Double?>) -> Double? {

    get { self.double(forKey: key.rawValue) }
    set { self.set(newValue, forKey: key.rawValue) }
  }

  public subscript(key: DefaultKey<Data?>) -> Data? {

    get { self.data(forKey: key.rawValue) }
    set { self.set(newValue, forKey: key.rawValue) }
  }

  public subscript(key: DefaultKey<String>) -> String {

    get { self.string(forKey: key.rawValue)! }
    set { self.set(newValue, forKey: key.rawValue) }
  }

  public subscript(key: DefaultKey<String?>) -> String? {

    get { self.string(forKey: key.rawValue) }
    set { self.set(newValue, forKey: key.rawValue) }
  }

  public subscript(key: DefaultKey<[String]>) -> [String] {

    get { self.stringArray(forKey: key.rawValue) ?? [] }
    set { self.set(newValue, forKey: key.rawValue) }
  }

  public subscript(key: DefaultKey<[String: AnyHashable]>) -> [String: AnyHashable] {

    get { self.dictionary(forKey: key.rawValue) as? [String: AnyHashable] ?? [:] }
    set { self.set(newValue, forKey: key.rawValue) }
  }

  public subscript<T>(key: DefaultKey<[T]>) -> [T] {

    get { self.array(forKey: key.rawValue) as? [T] ?? [] }
    set { self.set(newValue, forKey: key.rawValue) }
  }

  public subscript<T>(key: DefaultKey<T>) -> T where T: RawRepresentable, T.RawValue == Int {

    get { T(rawValue: self.integer(forKey: key.rawValue)) ?? T(rawValue: 0)! }
    set { self.set(newValue.rawValue, forKey: key.rawValue) }
  }

  public subscript<T>(key: DefaultKey<T>) -> T? where T: RawRepresentable, T.RawValue == String {

    get { T(rawValue: self.string(forKey: key.rawValue) ?? "") }
    set { self.set(newValue?.rawValue, forKey: key.rawValue) }
  }
}
