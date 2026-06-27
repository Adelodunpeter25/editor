import Foundation

/// Watches one file's parent directory and fires when that file changes on disk.
/// Used by the editor and diff viewer to refresh clean buffers from external writes.
final class FileChangeWatcher {
  private let targetPath: String
  private let directory: String
  private let onChange: () -> Void
  private var stream: FSEventStreamRef?
  private var debounce: DispatchWorkItem?
  private let queue = DispatchQueue(label: "com.editor.filewatch", qos: .utility)

  init(path: String, onChange: @escaping () -> Void) {
    self.targetPath = (path as NSString).standardizingPath
    self.directory = ((path as NSString).deletingLastPathComponent as NSString).standardizingPath
    self.onChange = onChange
  }

  func start() {
    guard stream == nil else { return }
    var ctx = FSEventStreamContext(
      version: 0,
      info: Unmanaged.passUnretained(self).toOpaque(),
      retain: nil, release: nil, copyDescription: nil)
    let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
      guard let info else { return }
      let watcher = Unmanaged<FileChangeWatcher>.fromOpaque(info).takeUnretainedValue()
      let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
      watcher.fired(paths: paths)
    }
    let flags = FSEventStreamCreateFlags(
      kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        | kFSEventStreamCreateFlagUseCFTypes
    )
    guard
      let s = FSEventStreamCreate(
        kCFAllocatorDefault, callback, &ctx,
        [directory] as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        0.2, flags)
    else { return }
    FSEventStreamSetDispatchQueue(s, queue)
    FSEventStreamStart(s)
    stream = s
  }

  func stop() {
    queue.async { [weak self] in
      self?.debounce?.cancel()
      self?.debounce = nil
    }
    guard let s = stream else { return }
    FSEventStreamStop(s)
    FSEventStreamInvalidate(s)
    FSEventStreamRelease(s)
    stream = nil
  }

  private func fired(paths: [String]) {
    guard !paths.isEmpty else { return }
    let changed = paths.contains { $0 == targetPath || $0.hasPrefix(targetPath + "/") }
    guard changed else { return }

    queue.async { [weak self] in
      guard let self else { return }
      self.debounce?.cancel()
      let work = DispatchWorkItem { [weak self] in
        DispatchQueue.main.async { self?.onChange() }
      }
      self.debounce = work
      self.queue.asyncAfter(deadline: .now() + 0.1, execute: work)
    }
  }

  deinit { stop() }
}
