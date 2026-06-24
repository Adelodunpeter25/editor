import Foundation

enum LanguageUtil {
  private static let extToLanguage: [String: String] = [
    "swift": "swift",
    "py": "python",
    "pyw": "python",
    "pyi": "python",
    "js": "javascript",
    "mjs": "javascript",
    "cjs": "javascript",
    "jsx": "javascript",
    "ts": "typescript",
    "mts": "typescript",
    "cts": "typescript",
    "tsx": "tsx",
    "json": "json",
    "jsonc": "json",
    "go": "go",
    "rs": "rust",
    "c": "c",
    "h": "c",
    "cpp": "cpp",
    "cc": "cpp",
    "cxx": "cpp",
    "c++": "cpp",
    "hpp": "cpp",
    "hh": "cpp",
    "hxx": "cpp",
    "m": "objc",
    "mm": "objc",
    "java": "java",
    "rb": "ruby",
    "rake": "ruby",
    "gemspec": "ruby",
    "php": "php",
    "html": "html",
    "htm": "html",
    "xhtml": "html",
    "css": "css",
    "scss": "scss",
    "less": "less",
    "sh": "shell",
    "bash": "shell",
    "zsh": "shell",
    "ksh": "shell",
    "yml": "yaml",
    "yaml": "yaml",
    "md": "markdown",
    "markdown": "markdown",
    "sql": "sql",
    "xml": "xml",
    "svg": "xml",
    "plist": "xml",
    "xsd": "xml",
    "ini": "ini",
    "cfg": "ini",
    "conf": "ini",
    "toml": "ini",
    "bat": "bat",
    "cmd": "bat",
    "ps1": "powershell",
    "psm1": "powershell",
    "psd1": "powershell",
    "mk": "makefile",
    "pl": "perl",
    "pm": "perl",
    "lua": "lua",
  ]

  private static let fenceAliases: [String: String] = [
    "py": "python",
    "js": "javascript",
    "jsx": "javascript",
    "ts": "typescript",
    "tsx": "tsx",
    "rb": "ruby",
    "rs": "rust",
    "sh": "shell",
    "bash": "shell",
    "zsh": "shell",
    "shell": "shell",
    "yml": "yaml",
    "c++": "cpp",
    "h": "c",
    "hpp": "cpp",
    "objective-c": "objc",
    "m": "objc",
    "ps1": "powershell",
    "md": "markdown",
    "htm": "html",
    "dockerfile": "dockerfile",
  ]

  private static let langDisplayNames: [String: String] = [
    "javascript": "JavaScript",
    "typescript": "TypeScript",
    "tsx": "TypeScript JSX",
    "objc": "Objective-C",
    "cpp": "C++",
    "json": "JSON",
    "html": "HTML",
    "css": "CSS",
    "scss": "SCSS",
    "less": "Less",
    "yaml": "YAML",
    "toml": "TOML",
    "ini": "INI",
    "php": "PHP",
    "sql": "SQL",
    "xml": "XML",
    "objcpp": "Objective-C++",
  ]

  /// Map a file path to a bundled grammar key. Filename is checked first (Dockerfile, Makefile),
  /// then the extension.
  static func language(forPath path: String) -> String? {
    let name = (path as NSString).lastPathComponent.lowercased()
    switch name {
    case "dockerfile", "containerfile": return "dockerfile"
    case "makefile", "gnumakefile": return "makefile"
    case ".gitignore", ".gitattributes", ".gitconfig": return "ini"
    default: break
    }
    return extToLanguage[(path as NSString).pathExtension.lowercased()]
  }

  /// Resolve alias/fence name to target grammar key.
  static func resolveAlias(_ fence: String) -> String {
    let f = fence.lowercased()
    return fenceAliases[f] ?? f
  }

  /// Get the user-friendly display name for a language identifier.
  static func displayName(forKey key: String) -> String {
    if let name = langDisplayNames[key] { return name }
    return key.prefix(1).uppercased() + key.dropFirst()
  }
}
