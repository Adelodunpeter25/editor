import Foundation

/// Watches a repo directory tree with FSEvents and fires `onChange` (coalesced + debounced) only
/// when files actually change — replacing the constant 1.5s git polling. When nothing changes, it
/// does nothing, so idle CPU is ~0 even with the app in the foreground.
final class RepoWatcher {
    private let path: String
    private let onChange: () -> Void
    private var stream: FSEventStreamRef?
    private var debounce: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.editor.watcher", qos: .utility)

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    func start() {
        guard stream == nil else { return }
        var ctx = FSEventStreamContext(version: 0,
                                       info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<RepoWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            watcher.fired(paths: paths)
        }
        // 0.4s latency lets FSEvents coalesce bursts (saves, builds) into one callback. FileEvents
        // flag = per-file granularity; covers .git/ changes (staging/commits) too.
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagUseCFTypes
        )
        guard let s = FSEventStreamCreate(kCFAllocatorDefault, callback, &ctx,
                                          [path] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                          0.4, flags) else { return }
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
        FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s)
        stream = nil
    }

    private func fired(paths: [String]) {
        // If all changed paths are inside ignored directories, skip polling.
        if !paths.isEmpty {
            let allIgnored = paths.allSatisfy { GitIgnoreUtil.isIgnoredPath($0) }
            if allIgnored { return }
        }

        queue.async { [weak self] in
            guard let self else { return }
            self.debounce?.cancel()
            let work = DispatchWorkItem { [weak self] in
                DispatchQueue.main.async {
                    self?.onChange()
                }
            }
            self.debounce = work
            self.queue.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
    }

    deinit { stop() }
}
