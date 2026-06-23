import AppKit
import Combine
import UserNotifications

/// Settings window: native checkboxes / stepper bound to `Settings` (UserDefaults). ESC closes it.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settings: Settings
    private var fontLabel: NSTextField!
    private var stepper: NSStepper!
    private var quickTermSeg: NSSegmentedControl!
    
    private var escMonitor: Any?

    // Tabs.
    private var segmented: NSSegmentedControl!
    private var generalPane: NSView!
    private var formattersPane: NSView!
    private var generalStack: NSStackView!
    private var formattersStack: NSStackView!
    // Per-formatter row controls, keyed by spec index, for live status refresh.
    private var fmtStatus: [NSTextField] = []
    private var fmtInstall: [NSButton] = []
    private var fmtEnable: [NSButton] = []

    init(settings: Settings) {
        self.settings = settings
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        super.init(window: window)
        window.delegate = self
        window.contentView = buildContent()
        window.center()

        // ESC closes the settings window (a local monitor catches it even when a field is focused).
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true, event.keyCode == 53 else { return event }
            self.close()
            return nil
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit { if let escMonitor { NSEvent.removeMonitor(escMonitor) } }

    /// Root: a General | Formatters tab switcher over two panes; the window resizes to fit the active one.
    private func buildContent() -> NSView {
        segmented = PointerSegmentedControl(labels: ["General", "Formatters"], trackingMode: .selectOne,
                                            target: self, action: #selector(tabChanged))
        segmented.selectedSegment = 0
        segmented.translatesAutoresizingMaskIntoConstraints = false

        generalPane = buildGeneralPane()
        formattersPane = buildFormattersPane()
        generalPane.translatesAutoresizingMaskIntoConstraints = false
        formattersPane.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
        root.addSubview(segmented)
        root.addSubview(generalPane)
        root.addSubview(formattersPane)
        NSLayoutConstraint.activate([
            segmented.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            segmented.centerXAnchor.constraint(equalTo: root.centerXAnchor),
        ])
        for pane in [generalPane!, formattersPane!] {
            NSLayoutConstraint.activate([
                pane.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 8),
                pane.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                pane.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                pane.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            ])
        }
        selectTab(0)
        return root
    }

    private func buildGeneralPane() -> NSView {
        let expand = checkbox("Show contents of gitignored folders", \.expandIgnored)
        let restore = checkbox("Restore sessions & tabs on launch", \.restoreOnLaunch)
        let monitor = checkbox("Show resource usage (memory / CPU) in the title bar", \.showResourceMonitor)

        stepper = NSStepper()
        stepper.minValue = 9; stepper.maxValue = 24; stepper.increment = 1
        stepper.integerValue = Int(settings.fontSize)
        stepper.target = self; stepper.action = #selector(fontChanged)
        fontLabel = NSTextField(labelWithString: "Font size: \(Int(settings.fontSize)) pt")
        fontLabel.font = .systemFont(ofSize: 13)
        let fontRow = NSStackView(views: [fontLabel, stepper])
        fontRow.orientation = .horizontal; fontRow.spacing = 8

        // Quick-terminal (⌃`) display mode.
        quickTermSeg = PointerSegmentedControl(labels: ["Floating", "Centered", "Bottom"],
                                               trackingMode: .selectOne,
                                               target: self, action: #selector(quickTermModeChanged))
        quickTermSeg.selectedSegment = Settings.QuickTermMode.allCases.firstIndex(of: settings.quickTermMode) ?? 0
        let quickTermLabel = NSTextField(labelWithString: "Quick terminal (⌃`) opens as")
        quickTermLabel.font = .systemFont(ofSize: 13)
        let quickTermRow = NSStackView(views: [quickTermLabel, quickTermSeg])
        quickTermRow.orientation = .horizontal; quickTermRow.spacing = 8

        let stack = NSStackView(views: [expand, restore, monitor, fontRow, quickTermRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        generalStack = stack

        let host = NSView()
        host.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: host.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor, constant: -24),
        ])
        return host
    }

    // MARK: - Formatters tab

    private func buildFormattersPane() -> NSView {
        let intro = NSTextField(wrappingLabelWithString:
            "Editor formats the active file with the matching tool installed on your machine (⇧⌥F). " +
            "Turn one off to skip it, or install a missing one.")
        intro.font = .systemFont(ofSize: 11)
        intro.textColor = NSColor(white: 0.6, alpha: 1)
        intro.preferredMaxLayoutWidth = 440

        let onSave = checkbox("Format on save (⌘S)", \.formatOnSave)
        let rows: [NSView] = Formatter.specs.enumerated().map { idx, spec in formatterRow(spec, index: idx) }
        let stack = NSStackView(views: [intro, onSave] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        formattersStack = stack

        let host = NSView()
        host.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: host.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -24),
        ])
        refreshFormatterStatus()
        return host
    }

    /// One formatter row: name + extensions on the left; status + (enable toggle | Install) on the right.
    private func formatterRow(_ spec: FormatterSpec, index: Int) -> NSView {
        let name = NSTextField(labelWithString: spec.name)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        let extsText = spec.exts.prefix(6).joined(separator: ", ") + (spec.exts.count > 6 ? ", …" : "")
        let exts = NSTextField(labelWithString: extsText)
        exts.font = .systemFont(ofSize: 10)
        exts.textColor = NSColor(white: 0.55, alpha: 1)
        let left = NSStackView(views: [name, exts])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 1

        let status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 11)
        fmtStatus.append(status)

        let enable = PointerButton(checkboxWithTitle: "On", target: self, action: #selector(formatterEnableToggled(_:)))
        enable.tag = index
        fmtEnable.append(enable)

        let install = PointerButton()
        install.bezelStyle = .rounded
        install.controlSize = .small
        install.title = "Install in Terminal"
        install.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
        install.imagePosition = .imageLeading
        install.toolTip = "Opens a Terminal tab and runs:\n\(spec.installCommand)"
        install.tag = index
        install.target = self
        install.action = #selector(formatterInstall(_:))
        fmtInstall.append(install)

        let right = NSStackView(views: [status, enable, install])
        right.orientation = .horizontal
        right.spacing = 8
        right.alignment = .centerY

        let row = NSStackView(views: [left, NSView(), right])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 432).isActive = true
        return row
    }

    /// Re-detect each formatter's install status (fast `which`-style checks) and reflect it in the rows.
    private func refreshFormatterStatus() {
        for (i, spec) in Formatter.specs.enumerated() {
            guard i < fmtStatus.count else { continue }
            let installed = Formatter.isInstalled(spec)
            fmtStatus[i].stringValue = installed ? "Installed" : "Not installed"
            fmtStatus[i].textColor = installed ? NSColor(red: 0.45, green: 0.79, blue: 0.57, alpha: 1)
                                               : NSColor(white: 0.55, alpha: 1)
            fmtInstall[i].isHidden = installed
            fmtEnable[i].isHidden = !installed
            fmtEnable[i].state = settings.formatterEnabled(spec.id) ? .on : .off
        }
    }

    @objc private func formatterInstall(_ sender: NSButton) {
        FormatterInstall.run?(Formatter.specs[sender.tag].installCommand)
    }
    @objc private func formatterEnableToggled(_ sender: NSButton) {
        settings.setFormatter(Formatter.specs[sender.tag].id, enabled: sender.state == .on)
    }

    @objc private func tabChanged() { selectTab(segmented.selectedSegment) }

    /// Show a tab and size the window to fit it.
    private func selectTab(_ index: Int) {
        segmented.selectedSegment = index
        generalPane.isHidden = index != 0
        formattersPane.isHidden = index != 1
        let stack: NSStackView = index == 0 ? generalStack : formattersStack
        stack.layoutSubtreeIfNeeded()
        let height = stack.fittingSize.height + 92    // segmented + paddings around the pane
        window?.setContentSize(NSSize(width: 520, height: height))
    }

    /// Open Settings to the Formatters tab (used by the "Manage Formatters…" prompt link).
    func showFormatters() { selectTab(1); refreshFormatterStatus() }
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        
        refreshFormatterStatus()
    }

    /// Re-check when the window regains focus — e.g. the user installed a formatter / toggled the OS
    /// permission in System Settings and clicked back, with this window still open.
    func windowDidBecomeKey(_ notification: Notification) {
        
        refreshFormatterStatus()
    }

    private func checkbox(_ title: String, _ keyPath: ReferenceWritableKeyPath<Settings, Bool>) -> NSButton {
        let b = PointerButton(checkboxWithTitle: title, target: self, action: #selector(toggle(_:)))
        b.state = settings[keyPath: keyPath] ? .on : .off
        keyPaths[ObjectIdentifier(b)] = keyPath
        return b
    }
    private var keyPaths: [ObjectIdentifier: ReferenceWritableKeyPath<Settings, Bool>] = [:]

    @objc private func toggle(_ sender: NSButton) {
        guard let kp = keyPaths[ObjectIdentifier(sender)] else { return }
        settings[keyPath: kp] = sender.state == .on
    }
    @objc private func fontChanged() {
        settings.fontSize = Double(stepper.integerValue)
        fontLabel.stringValue = "Font size: \(stepper.integerValue) pt"
    }
    @objc private func quickTermModeChanged() {
        let modes = Settings.QuickTermMode.allCases
        if modes.indices.contains(quickTermSeg.selectedSegment) {
            settings.quickTermMode = modes[quickTermSeg.selectedSegment]
        }
    }
}
