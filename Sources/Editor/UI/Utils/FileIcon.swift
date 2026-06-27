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

  /// Returns a pre-tinted SF Symbol image for the given filename (the color is baked in, so it
  /// renders correctly inside NSOutlineView cells where contentTintColor is unreliable).
  static func tintedIcon(forFilename filename: String, color: NSColor, size: CGFloat = 11)
    -> NSImage?
  {
    guard let img = icon(forFilename: filename, size: size) else { return nil }
    return tint(img, with: color)
  }

  /// Folder icon (expanded or collapsed), pre-tinted with the folder color.
  static func tintedFolderIcon(expanded: Bool, size: CGFloat = 12) -> NSImage? {
    guard let img = folderIcon(expanded: expanded, size: size) else { return nil }
    return tint(img, with: folderColor())
  }

  /// Bake a color into a template SF Symbol image (sourceAtop compositing).
  private static func tint(_ image: NSImage, with color: NSColor) -> NSImage {
    let size = image.size
    let result = NSImage(size: size)
    result.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: size))
    color.withAlphaComponent(1).set()
    NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
    result.unlockFocus()
    return result
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

  // MARK: - Colors

  /// Returns a per-file-type color for the given filename, suitable for tinting SF Symbol icons.
  static func color(forFilename filename: String) -> NSColor {
    let lower = filename.lowercased()
    if specialFileColors[lower] != nil { return specialFileColors[lower]! }
    let ext = (lower as NSString).pathExtension
    return extensionColors[ext] ?? defaultColor
  }

  /// Folder icon color (macOS-style blue).
  static func folderColor() -> NSColor {
    NSColor(srgbRed: 0.32, green: 0.55, blue: 0.92, alpha: 1)
  }

  private static let defaultColor: NSColor = NSColor(white: 0.62, alpha: 1)

  private static let specialFileColors: [String: NSColor] = [
    "dockerfile": NSColor(srgbRed: 0.24, green: 0.47, blue: 0.74, alpha: 1),
    "containerfile": NSColor(srgbRed: 0.24, green: 0.47, blue: 0.74, alpha: 1),
    "makefile": NSColor(srgbRed: 0.66, green: 0.45, blue: 0.20, alpha: 1),
    "gnumakefile": NSColor(srgbRed: 0.66, green: 0.45, blue: 0.20, alpha: 1),
    ".gitignore": NSColor(white: 0.55, alpha: 1),
    ".gitattributes": NSColor(white: 0.55, alpha: 1),
    "license": NSColor(srgbRed: 0.55, green: 0.55, blue: 0.55, alpha: 1),
    "readme.md": NSColor(srgbRed: 0.40, green: 0.51, blue: 0.84, alpha: 1),
  ]

  private static let extensionColors: [String: NSColor] = [
    // Code
    "swift": NSColor(srgbRed: 0.98, green: 0.45, blue: 0.27, alpha: 1),
    "js": NSColor(srgbRed: 0.93, green: 0.79, blue: 0.27, alpha: 1),
    "mjs": NSColor(srgbRed: 0.93, green: 0.79, blue: 0.27, alpha: 1),
    "cjs": NSColor(srgbRed: 0.93, green: 0.79, blue: 0.27, alpha: 1),
    "jsx": NSColor(srgbRed: 0.40, green: 0.58, blue: 0.90, alpha: 1),
    "ts": NSColor(srgbRed: 0.33, green: 0.56, blue: 0.86, alpha: 1),
    "tsx": NSColor(srgbRed: 0.40, green: 0.58, blue: 0.90, alpha: 1),
    "mts": NSColor(srgbRed: 0.33, green: 0.56, blue: 0.86, alpha: 1),
    "py": NSColor(srgbRed: 0.35, green: 0.58, blue: 0.82, alpha: 1),
    "pyw": NSColor(srgbRed: 0.35, green: 0.58, blue: 0.82, alpha: 1),
    "go": NSColor(srgbRed: 0.20, green: 0.72, blue: 0.86, alpha: 1),
    "rs": NSColor(srgbRed: 0.78, green: 0.42, blue: 0.32, alpha: 1),
    "c": NSColor(srgbRed: 0.39, green: 0.58, blue: 0.86, alpha: 1),
    "h": NSColor(srgbRed: 0.39, green: 0.58, blue: 0.86, alpha: 1),
    "cpp": NSColor(srgbRed: 0.39, green: 0.58, blue: 0.86, alpha: 1),
    "cc": NSColor(srgbRed: 0.39, green: 0.58, blue: 0.86, alpha: 1),
    "cxx": NSColor(srgbRed: 0.39, green: 0.58, blue: 0.86, alpha: 1),
    "hpp": NSColor(srgbRed: 0.39, green: 0.58, blue: 0.86, alpha: 1),
    "java": NSColor(srgbRed: 0.78, green: 0.32, blue: 0.28, alpha: 1),
    "kt": NSColor(srgbRed: 0.62, green: 0.35, blue: 0.78, alpha: 1),
    "rb": NSColor(srgbRed: 0.83, green: 0.22, blue: 0.28, alpha: 1),
    "php": NSColor(srgbRed: 0.60, green: 0.40, blue: 0.78, alpha: 1),
    "lua": NSColor(srgbRed: 0.20, green: 0.45, blue: 0.78, alpha: 1),
    "pl": NSColor(srgbRed: 0.20, green: 0.50, blue: 0.45, alpha: 1),
    "r": NSColor(srgbRed: 0.40, green: 0.58, blue: 0.72, alpha: 1),
    // Web
    "html": NSColor(srgbRed: 0.85, green: 0.45, blue: 0.28, alpha: 1),
    "htm": NSColor(srgbRed: 0.85, green: 0.45, blue: 0.28, alpha: 1),
    "css": NSColor(srgbRed: 0.27, green: 0.55, blue: 0.82, alpha: 1),
    "scss": NSColor(srgbRed: 0.78, green: 0.33, blue: 0.50, alpha: 1),
    "less": NSColor(srgbRed: 0.27, green: 0.55, blue: 0.82, alpha: 1),
    "svg": NSColor(srgbRed: 0.85, green: 0.55, blue: 0.25, alpha: 1),
    // Data / Config
    "json": NSColor(srgbRed: 0.85, green: 0.66, blue: 0.30, alpha: 1),
    "jsonc": NSColor(srgbRed: 0.85, green: 0.66, blue: 0.30, alpha: 1),
    "yaml": NSColor(srgbRed: 0.85, green: 0.66, blue: 0.30, alpha: 1),
    "yml": NSColor(srgbRed: 0.85, green: 0.66, blue: 0.30, alpha: 1),
    "toml": NSColor(srgbRed: 0.85, green: 0.66, blue: 0.30, alpha: 1),
    "xml": NSColor(srgbRed: 0.40, green: 0.62, blue: 0.42, alpha: 1),
    "plist": NSColor(srgbRed: 0.40, green: 0.62, blue: 0.42, alpha: 1),
    "sql": NSColor(srgbRed: 0.33, green: 0.55, blue: 0.72, alpha: 1),
    // Shell / Config
    "sh": NSColor(srgbRed: 0.30, green: 0.72, blue: 0.40, alpha: 1),
    "bash": NSColor(srgbRed: 0.30, green: 0.72, blue: 0.40, alpha: 1),
    "zsh": NSColor(srgbRed: 0.30, green: 0.72, blue: 0.40, alpha: 1),
    "fish": NSColor(srgbRed: 0.30, green: 0.72, blue: 0.40, alpha: 1),
    "mk": NSColor(srgbRed: 0.66, green: 0.45, blue: 0.20, alpha: 1),
    "cmake": NSColor(srgbRed: 0.66, green: 0.45, blue: 0.20, alpha: 1),
    "ini": NSColor(srgbRed: 0.66, green: 0.45, blue: 0.20, alpha: 1),
    "cfg": NSColor(srgbRed: 0.66, green: 0.45, blue: 0.20, alpha: 1),
    "conf": NSColor(srgbRed: 0.66, green: 0.45, blue: 0.20, alpha: 1),
    "env": NSColor(srgbRed: 0.66, green: 0.45, blue: 0.20, alpha: 1),
    // Documents
    "md": NSColor(srgbRed: 0.40, green: 0.51, blue: 0.84, alpha: 1),
    "markdown": NSColor(srgbRed: 0.40, green: 0.51, blue: 0.84, alpha: 1),
    "txt": NSColor(white: 0.62, alpha: 1),
    "log": NSColor(white: 0.55, alpha: 1),
    "pdf": NSColor(srgbRed: 0.78, green: 0.22, blue: 0.22, alpha: 1),
    // Images
    "png": NSColor(srgbRed: 0.30, green: 0.72, blue: 0.56, alpha: 1),
    "jpg": NSColor(srgbRed: 0.30, green: 0.72, blue: 0.56, alpha: 1),
    "jpeg": NSColor(srgbRed: 0.30, green: 0.72, blue: 0.56, alpha: 1),
    "gif": NSColor(srgbRed: 0.30, green: 0.72, blue: 0.56, alpha: 1),
    "webp": NSColor(srgbRed: 0.30, green: 0.72, blue: 0.56, alpha: 1),
    "ico": NSColor(srgbRed: 0.30, green: 0.72, blue: 0.56, alpha: 1),
    "icns": NSColor(srgbRed: 0.30, green: 0.72, blue: 0.56, alpha: 1),
    "bmp": NSColor(srgbRed: 0.30, green: 0.72, blue: 0.56, alpha: 1),
    // Archives
    "zip": NSColor(srgbRed: 0.72, green: 0.55, blue: 0.35, alpha: 1),
    "tar": NSColor(srgbRed: 0.72, green: 0.55, blue: 0.35, alpha: 1),
    "gz": NSColor(srgbRed: 0.72, green: 0.55, blue: 0.35, alpha: 1),
    "rar": NSColor(srgbRed: 0.72, green: 0.55, blue: 0.35, alpha: 1),
    "7z": NSColor(srgbRed: 0.72, green: 0.55, blue: 0.35, alpha: 1),
    // Fonts
    "ttf": NSColor(srgbRed: 0.45, green: 0.50, blue: 0.60, alpha: 1),
    "otf": NSColor(srgbRed: 0.45, green: 0.50, blue: 0.60, alpha: 1),
    "woff": NSColor(srgbRed: 0.45, green: 0.50, blue: 0.60, alpha: 1),
    "woff2": NSColor(srgbRed: 0.45, green: 0.50, blue: 0.60, alpha: 1),
  ]

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
