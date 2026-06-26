import Combine
import Foundation
import Defaults

/// App settings, backed by `UserDefaults`. `@Published` so view controllers can `sink` and react;
/// each `didSet` persists. Not a SwiftUI type — Combine is independent of SwiftUI.
final class Settings: ObservableObject {
  /// How the quick-access terminal (⌃`) appears.
  enum QuickTermMode: String, CaseIterable {
    case floating, centered, bottom
    var label: String {
      switch self {
      case .floating: return "Floating window"
      case .centered: return "Centered overlay"
      case .bottom: return "Bottom panel"
      }
    }
  }

  private let d = UserDefaults.standard

  @Published var expandIgnored: Bool { didSet { d[Keys.expandIgnored] = expandIgnored } }
  @Published var restoreOnLaunch: Bool { didSet { d[Keys.restore] = restoreOnLaunch } }
  @Published var fontSize: Double { didSet { d[Keys.fontSize] = fontSize } }
  @Published var showResourceMonitor: Bool {
    didSet { d[Keys.resourceMonitor] = showResourceMonitor }
  }
  /// How the quick-access terminal (⌃`) opens: floating window / centered overlay / bottom panel.
  @Published var quickTermMode: QuickTermMode {
    didSet { d[Keys.quickTermMode] = quickTermMode }
  }
  /// Formatter ids the user has turned off (empty = all enabled).
  @Published var disabledFormatters: Set<String> {
    didSet { d[Keys.disabledFormatters] = Array(disabledFormatters) }
  }
  @Published var formatOnSave: Bool { didSet { d[Keys.formatOnSave] = formatOnSave } }
  /// Find-bar toggles, remembered across files + launches (like VS Code).
  @Published var findMatchCase: Bool { didSet { d[Keys.findMatchCase] = findMatchCase } }
  @Published var findWholeWord: Bool { didSet { d[Keys.findWholeWord] = findWholeWord } }
  @Published var findRegex: Bool { didSet { d[Keys.findRegex] = findRegex } }

  init() {
    d.register(defaults: [
      Keys.expandIgnored.rawValue: false,
      Keys.restore.rawValue: true,
      Keys.fontSize.rawValue: 13.0,
      Keys.resourceMonitor.rawValue: false,
      Keys.formatOnSave.rawValue: false,
      Keys.quickTermMode.rawValue: QuickTermMode.floating.rawValue,
    ])
    // didSet does not fire for these initial assignments inside init.
    expandIgnored = d[Keys.expandIgnored]
    restoreOnLaunch = d[Keys.restore]
    fontSize = d[Keys.fontSize]
    showResourceMonitor = d[Keys.resourceMonitor]
    quickTermMode = d[Keys.quickTermMode] ?? .floating
    disabledFormatters = Set(d[Keys.disabledFormatters])
    formatOnSave = d[Keys.formatOnSave]
    findMatchCase = d[Keys.findMatchCase]
    findWholeWord = d[Keys.findWholeWord]
    findRegex = d[Keys.findRegex]
  }

  /// Shared font size for terminal + editor, clamped to a readable range.
  func bumpFont(_ delta: Double) { fontSize = min(24, max(9, fontSize + delta)) }

  func formatterEnabled(_ id: String) -> Bool { !disabledFormatters.contains(id) }
  func setFormatter(_ id: String, enabled: Bool) {
    if enabled { disabledFormatters.remove(id) } else { disabledFormatters.insert(id) }
  }

  private enum Keys {
    static let expandIgnored = DefaultKey<Bool>("expandIgnored")
    static let restore = DefaultKey<Bool>("restoreOnLaunch")
    static let fontSize = DefaultKey<Double>("fontSize")
    static let resourceMonitor = DefaultKey<Bool>("showResourceMonitor")
    static let quickTermMode = RawRepresentableDefaultKey<QuickTermMode>("quickTermMode")
    static let disabledFormatters = DefaultKey<[String]>("disabledFormatters")
    static let formatOnSave = DefaultKey<Bool>("formatOnSave")
    static let findMatchCase = DefaultKey<Bool>("findMatchCase")
    static let findWholeWord = DefaultKey<Bool>("findWholeWord")
    static let findRegex = DefaultKey<Bool>("findRegex")
  }
}
