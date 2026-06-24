import AppKit

/// Centralized file icon resolution. Maps file extensions and well-known filenames to SF Symbols.
/// Used by the file tree and tab bar to show consistent icons.
enum FileIcon {

  /// Returns an SF Symbol image for the given filename, at the specified point size.
  static func icon(forFilename filename: String, size: CGFloat = 11) -> NSImage? {
    let symbol = symbolName(forFilename: filename)
    return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: size, weight: .regular))
  }

  /// Returns the SF Symbol name for a given filename (checks well-known names first, then extension).
  static func symbolName(forFilename filename: String) -> String {
    let lower = filename.lowercased()

    // Well-known filenames
    if let special = specialFiles[lower] { return special }

    // Extension-based
    let ext = (lower as NSString).pathExtension
    return extensionMap[ext] ?? "doc"
  }

  /// Folder icon (expanded or collapsed).
  static func folderIcon(expanded: Bool, size: CGFloat = 12) -> NSImage? {
    let name = expanded ? "folder.fill" : "folder"
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: size, weight: .regular))
  }

  // MARK: - Mappings

  private static let specialFiles: [String: String] = [
    "dockerfile": "shippingbox",
    "containerfile": "shippingbox",
    "makefile": "gearshape",
    "gnumakefile": "gearshape",
    ".gitignore": "eye.slash",
    ".gitattributes": "eye.slash",
    "license": "doc.text",
    "readme.md": "doc.richtext",
  ]

  private static let extensionMap: [String: String] = [
    // Code
    "swift": "swift",
    "js": "doc.text",
    "mjs": "doc.text",
    "cjs": "doc.text",
    "jsx": "doc.text",
    "ts": "doc.text",
    "tsx": "doc.text",
    "mts": "doc.text",
    "py": "doc.text",
    "pyw": "doc.text",
    "go": "doc.text",
    "rs": "doc.text",
    "c": "doc.text",
    "h": "doc.text",
    "cpp": "doc.text",
    "cc": "doc.text",
    "cxx": "doc.text",
    "hpp": "doc.text",
    "java": "doc.text",
    "kt": "doc.text",
    "rb": "doc.text",
    "php": "doc.text",
    "lua": "doc.text",
    "pl": "doc.text",
    "r": "doc.text",
    // Web
    "html": "globe",
    "htm": "globe",
    "css": "paintbrush",
    "scss": "paintbrush",
    "less": "paintbrush",
    "svg": "square.on.circle",
    // Data / Config
    "json": "curlybraces",
    "jsonc": "curlybraces",
    "yaml": "curlybraces",
    "yml": "curlybraces",
    "toml": "curlybraces",
    "xml": "chevron.left.forwardslash.chevron.right",
    "plist": "chevron.left.forwardslash.chevron.right",
    "sql": "cylinder",
    // Shell / Config
    "sh": "terminal",
    "bash": "terminal",
    "zsh": "terminal",
    "fish": "terminal",
    "mk": "gearshape",
    "cmake": "gearshape",
    "ini": "gearshape",
    "cfg": "gearshape",
    "conf": "gearshape",
    "env": "gearshape",
    // Documents
    "md": "doc.richtext",
    "markdown": "doc.richtext",
    "txt": "doc.plaintext",
    "log": "doc.plaintext",
    "pdf": "doc.fill",
    // Images
    "png": "photo",
    "jpg": "photo",
    "jpeg": "photo",
    "gif": "photo",
    "webp": "photo",
    "ico": "photo",
    "icns": "photo",
    "bmp": "photo",
    // Archives
    "zip": "doc.zipper",
    "tar": "doc.zipper",
    "gz": "doc.zipper",
    "rar": "doc.zipper",
    "7z": "doc.zipper",
    // Fonts
    "ttf": "textformat",
    "otf": "textformat",
    "woff": "textformat",
    "woff2": "textformat",
  ]
}
