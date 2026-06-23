import AppKit

// MARK: - Tab context menu (right-click)

extension TabChipView {
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        func item(_ title: String, _ sel: Selector) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: ""); i.target = self; return i
        }
        menu.addItem(item(pinned ? "Unpin Tab" : "Pin Tab", #selector(pinTapped)))
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(closeTapped)))
        menu.addItem(item("Close Others", #selector(closeOthersTapped)))
        menu.addItem(item("Close All", #selector(closeAllTapped)))
        if copyPaths != nil {
            menu.addItem(.separator())
            menu.addItem(item("Copy Path", #selector(copyAbsolute)))
            menu.addItem(item("Copy Relative Path", #selector(copyRelative)))
        }
        return menu
    }

    @objc func pinTapped() { onPin() }
    @objc func closeOthersTapped() { onCloseOthers() }
    @objc func closeAllTapped() { onCloseAll() }
    @objc func copyAbsolute() { if let p = copyPaths?.absolute { Clipboard.copy(p) } }
    @objc func copyRelative() { if let p = copyPaths?.relative { Clipboard.copy(p) } }
}
