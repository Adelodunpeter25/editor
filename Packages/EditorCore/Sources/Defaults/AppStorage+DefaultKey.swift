import SwiftUI

extension AppStorage {

  /// Creates a property that can read and write to a boolean user default.
  ///
  /// This initializer enables creating an AppStorage property from a DefaultKey with the registered default value.
  ///
  ///     @AppStorage(.foo) var foo: Bool
  ///
  /// - Parameters:
  ///   - key: The DefaultKey to read and write the value to in the user defaults store.
  ///   - store: The user defaults store to read and write to. A value of `nil` will use the user default store from the environment.
  public init(_ key: DefaultKey<Value>, store: UserDefaults? = nil) where Value == Bool {

    let defaultValue = (store ?? UserDefaults.standard)[initial: key]

    self.init(wrappedValue: defaultValue, key.rawValue, store: store)
  }

  /// Creates a property that can read and write to an integer user default.
  ///
  /// This initializer enables creating an AppStorage property from a DefaultKey with the registered default value.
  ///
  ///     @AppStorage(.foo) var foo: Int
  ///
  /// - Parameters:
  ///   - key: The DefaultKey to read and write the value to in the user defaults store.
  ///   - store: The user defaults store to read and write to. A value of `nil` will use the user default store from the environment.
  public init(_ key: DefaultKey<Value>, store: UserDefaults? = nil) where Value == Int {

    let defaultValue = (store ?? UserDefaults.standard)[initial: key]

    self.init(wrappedValue: defaultValue, key.rawValue, store: store)
  }

  public init(_ key: DefaultKey<Value>, store: UserDefaults? = nil) where Value == Double {

    let defaultValue = (store ?? UserDefaults.standard)[initial: key]

    self.init(wrappedValue: defaultValue, key.rawValue, store: store)
  }

  public init(_ key: DefaultKey<Value>, store: UserDefaults? = nil) where Value == Double? {

    self.init(key.rawValue, store: store)
  }

  public init(_ key: DefaultKey<Value>, store: UserDefaults? = nil) where Value == String {

    let defaultValue = (store ?? UserDefaults.standard)[initial: key]

    self.init(wrappedValue: defaultValue, key.rawValue, store: store)
  }

  public init(_ key: DefaultKey<Value>, store: UserDefaults? = nil) where Value == String? {

    self.init(key.rawValue, store: store)
  }

  public init(_ key: DefaultKey<Value>, store: UserDefaults? = nil)
  where Value: RawRepresentable, Value.RawValue == Int {

    let defaultValue = (store ?? UserDefaults.standard)[initial: key]

    self.init(wrappedValue: defaultValue, key.rawValue, store: store)
  }

  public init(_ key: RawRepresentableDefaultKey<Value>, store: UserDefaults? = nil)
  where Value: RawRepresentable, Value: DefaultInitializable, Value.RawValue == String {

    let defaultValue = (store ?? UserDefaults.standard)[initial: key] ?? .defaultValue

    self.init(wrappedValue: defaultValue, key.rawValue, store: store)
  }

  public init(_ key: DefaultKey<Value>, store: UserDefaults? = nil) where Value == Data? {

    self.init(key.rawValue, store: store)
  }
}
