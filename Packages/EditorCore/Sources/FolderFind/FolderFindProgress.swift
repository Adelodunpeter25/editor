//
//  FolderFindProgress.swift
//  FolderFind
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-05-29.
//
//  ---------------------------------------------------------------------------
//
//  © 2026 1024jp
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

public final class FolderFindProgress: Sendable {

  // MARK: Private Properties

  private let lock = NSLock()
  private var storage: FolderFind.Metrics

  // MARK: Lifecycle

  /// Initializes folder find progress.
  ///
  /// - Parameter findString: The string to search for.
  public init(findString: String) {

    self.storage = FolderFind.Metrics(findString: findString)
  }

  // MARK: Public Methods

  /// The current progress snapshot.
  public var snapshot: FolderFind.Metrics {

    self.lock.lock()
    defer { self.lock.unlock() }
    return self.storage
  }

  // MARK: Internal Methods

  /// Updates the current progress snapshot.
  ///
  /// - Parameter snapshot: The new progress snapshot.
  func update(snapshot: FolderFind.Metrics) {

    self.lock.lock()
    self.storage = snapshot
    self.lock.unlock()
  }
}

extension FolderFindProgress: Equatable {

  public static func == (lhs: FolderFindProgress, rhs: FolderFindProgress) -> Bool {

    lhs === rhs
  }
}
