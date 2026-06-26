import Foundation

public final class FolderFindProgress: Sendable {

  private final class Storage {

    var metrics: FolderFind.Metrics

    init(metrics: FolderFind.Metrics) {

      self.metrics = metrics
    }
  }

  // MARK: Private Properties

  private let lock = NSLock()
  private let storage: Storage

  // MARK: Lifecycle

  /// Initializes folder find progress.
  ///
  /// - Parameter findString: The string to search for.
  public init(findString: String) {

    self.storage = Storage(metrics: FolderFind.Metrics(findString: findString))
  }

  // MARK: Public Methods

  /// The current progress snapshot.
  public var snapshot: FolderFind.Metrics {

    self.lock.lock()
    defer { self.lock.unlock() }
    return self.storage.metrics
  }

  // MARK: Internal Methods

  /// Updates the current progress snapshot.
  ///
  /// - Parameter snapshot: The new progress snapshot.
  func update(snapshot: FolderFind.Metrics) {

    self.lock.lock()
    self.storage.metrics = snapshot
    self.lock.unlock()
  }
}

extension FolderFindProgress: Equatable {

  public static func == (lhs: FolderFindProgress, rhs: FolderFindProgress) -> Bool {

    lhs === rhs
  }
}
