import Foundation

/// What a tab shows.
enum TabKind: String, Codable { case terminal, file, diff, search }

/// A single tab in a session. Value type — sessions hold `[Tab]` and mutate by index, so changes
/// flow through `Session`'s `@Published var tabs` for free.
struct Tab: Identifiable, Equatable {
    var id: String
    var kind: TabKind
    var title: String
    var path: String?             // absolute file path (for .file / .diff)
    var dirty: Bool               // unsaved edits (for .file)
    var shown: Bool               // lazy-spawn gate: process isn't started until first viewed
    var exited: Bool              // transient: the terminal process ended (→ "Session ended" bar); not persisted

    init(id: String = UUID().uuidString,
         kind: TabKind,
         title: String,
         path: String? = nil,
         dirty: Bool = false,
         shown: Bool = false,
         exited: Bool = false) {
        self.id = id
        self.kind = kind
        self.title = title
        self.path = path
        self.dirty = dirty
        self.shown = shown
        self.exited = exited
    }
}
