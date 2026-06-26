import Foundation
import Observation

public final class FindProgress: Sendable {

  public enum State: Equatable, Sendable {

    case ready
    case processing
    case finished
    case cancelled

    /// Whether the progress is terminated.
    public var isTerminated: Bool {

      switch self {
      case .ready, .processing: false
      case .finished, .cancelled: true
      }
    }
  }

  private final class Storage: @unchecked Sendable {

    var state: State = .ready
    var count: Int = 0
    var completedUnit: Int = 0
  }

  // MARK: Private Properties

  private let lock = NSLock()
  private let storage = Storage()
  private let scope: Range<Int>

  // MARK: Lifecycle

  /// Instantiates a progress.
  ///
  /// - Parameter scope: The range of progress unit to work with.
  public init(scope: Range<Int>) {

    self.scope = scope
  }

  // MARK: Public Methods

  /// The current progress state.
  public var state: State {

    self.lock.lock()
    defer { self.lock.unlock() }
    return self.storage.state
  }

  /// The number of items completed.
  public var count: Int {

    self.lock.lock()
    defer { self.lock.unlock() }
    return self.storage.count
  }

  /// The fraction of task completed in between 0...1.0.
  public var fractionCompleted: Double {

    self.lock.lock()
    defer { self.lock.unlock() }
    if self.storage.state == .finished || self.scope.isEmpty {
      return 1
    } else {
      return Double(self.storage.completedUnit) / Double(self.scope.count)
    }
  }

  /// Changes the state to `.cancelled`.
  public func cancel() {

    self.lock.lock()
    self.storage.state = .cancelled
    self.lock.unlock()
  }

  /// Changes the state to `.finished`.
  public func finish() {

    self.lock.lock()
    self.storage.state = .finished
    self.lock.unlock()
  }

  /// Increments count.
  ///
  /// - Parameter count: The amount to increment.
  public func incrementCount(by count: Int = 1) {

    self.lock.lock()
    self.storage.count += count
    self.lock.unlock()
  }

  /// Updates the `completedUnit` to a new value.
  ///
  /// - Parameter unit: The new completed unit.
  public func updateCompletedUnit(to unit: Int) {

    self.lock.lock()
    self.storage.completedUnit = unit
    self.lock.unlock()
  }

  // MARK: Internal Methods

  /// Increments the `completedUnit` by one.
  func incrementCompletedUnit() {

    self.lock.lock()
    self.storage.completedUnit += 1
    self.lock.unlock()
  }
}
