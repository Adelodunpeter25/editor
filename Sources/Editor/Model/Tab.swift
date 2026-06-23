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
    var pinned: Bool              // pinned tabs stick to the left and survive "close others"
    var shown: Bool               // lazy-spawn gate: process isn't started until first viewed
    var exited: Bool              // transient: the terminal process ended (→ "Session ended" bar); not persisted
    var createdAt: Date           // when the tab was opened (used for auto-replacement logic)

    init(id: String = UUID().uuidString,
         kind: TabKind,
         title: String,
         path: String? = nil,
         dirty: Bool = false,
         pinned: Bool = false,
         shown: Bool = false,
         exited: Bool = false,
         createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.title = title
        self.path = path
        self.dirty = dirty
        self.pinned = pinned
        self.shown = shown
        self.exited = exited
        self.createdAt = createdAt
    }
}
