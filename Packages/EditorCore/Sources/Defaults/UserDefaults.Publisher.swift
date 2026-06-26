import Combine
import Foundation

extension UserDefaults {

  /// Publishes values when the value identified by a default key changes.
  ///
  /// - Parameters:
  ///   - key: The default key of the default value to publish.
  ///   - initial: If `true`, the first output will be send immediately, before the observer registration method even returns.
  /// - Returns: A publisher that emits elements each time the defaults’ value changes.
  public func publisher<Value>(for key: DefaultKey<Value>, initial: Bool = false) -> Publisher<
    Value
  > {

    Publisher(userDefaults: self, key: key, initial: initial)
  }

  public struct Publisher<Value: Equatable>: Combine.Publisher {

    public typealias Output = Value
    public typealias Failure = Never

    // MARK: Internal Properties

    let userDefaults: UserDefaults
    let key: DefaultKey<Value>
    let initial: Bool

    // MARK: Publisher Methods

    public func receive(subscriber: some Combine.Subscriber<Output, Failure>) {

      let subscription = Subscription(
        subscriber: subscriber, userDefaults: self.userDefaults, key: self.key)

      subscriber.receive(subscription: subscription)
      subscription.register(initial: self.initial)  // register after assigning to subscriber to pass the initial emission
    }
  }
}

extension UserDefaults.Publisher {

  fileprivate final class Subscription<S: Subscriber>: NSObject, Combine.Subscription
  where S.Input == Value {

    // MARK: Private Properties

    private var subscriber: S?
    private var userDefaults: UserDefaults?
    private let key: DefaultKey<Value>
    private var demand: Subscribers.Demand = .none
    private var lastValue: Value?

    // MARK: Lifecycle

    init(subscriber: S, userDefaults: UserDefaults, key: DefaultKey<Value>) {

      self.subscriber = subscriber
      self.userDefaults = userDefaults
      self.key = key
    }

    deinit {
      self.cancel()
    }

    // MARK: Subscription Methods

    func request(_ demand: Subscribers.Demand) {

      self.demand += demand
    }

    func cancel() {

      self.userDefaults?.removeObserver(self, forKeyPath: self.key.rawValue)
      self.userDefaults = nil
      self.subscriber = nil
    }

    // MARK: KVO

    func register(initial: Bool) {

      self.userDefaults?.addObserver(
        self, forKeyPath: self.key.rawValue, options: initial ? [.new, .initial] : [.new],
        context: nil)
    }

    override func observeValue(
      forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
      context: UnsafeMutableRawPointer?
    ) {

      guard
        let change,
        keyPath == self.key.rawValue,
        object as? NSObject == self.userDefaults
      else {
        return super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
      }

      guard
        self.demand > 0,
        let subscriber = self.subscriber
      else { return }

      let newValue: Value
      do {
        newValue = try self.key.newValue(from: change[.newKey])
      } catch {
        return assertionFailure(
          "UserDefaults.Publisher.Subscription could not obtain value for '.\(self.key)' key as \(Value.self)."
        )
      }

      guard newValue != self.lastValue else { return }  // workaround for the issue that KVO can be invoked multiple times with UserDefaults

      self.lastValue = newValue
      self.demand -= 1
      self.demand += subscriber.receive(newValue)
    }
  }
}
