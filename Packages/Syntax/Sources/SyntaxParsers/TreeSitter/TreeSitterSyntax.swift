import SyntaxFormat
import TreeSitterBash
import TreeSitterC
import TreeSitterCPP
import TreeSitterCSS
import TreeSitterCSharp
import TreeSitterDart
import TreeSitterDockerfile
import TreeSitterGo
import TreeSitterHTML
import TreeSitterJava
import TreeSitterJavaScript
import TreeSitterJSON
import TreeSitterKotlin
import TreeSitterLatex
import TreeSitterLua
import TreeSitterMake
import TreeSitterMarkdown
import TreeSitterPHP
import TreeSitterPython
import TreeSitterRuby
import TreeSitterRust
import TreeSitterScala
import TreeSitterSql
import TreeSitterSwift
import TreeSitterTypeScript
import TreeSitterXML
import TreeSitterYAML

public enum TreeSitterSyntax: String, CaseIterable, Sendable {

  case bash = "Bash"
  case c = "C"
  case cpp = "C++"
  case cSharp = "C#"
  case css = "CSS"
  case dart = "Dart"
  case dockerfile = "Dockerfile"
  case go = "Go"
  case html = "HTML"
  case java = "Java"
  case javaScript = "JavaScript"
  case json = "JSON"
  case kotlin = "Kotlin"
  case latex = "LaTeX"
  case lua = "Lua"
  case makefile = "Makefile"
  case markdown = "Markdown"
  case php = "PHP"
  case python = "Python"
  case ruby = "Ruby"
  case rust = "Rust"
  case scala = "Scala"
  case sql = "SQL"
  case swift = "Swift"
  case typeScript = "TypeScript"
  case xml = "XML"
  case yaml = "YAML"

  var name: String { self.rawValue }

  /// Lowercase aliases that map common language identifiers (file extensions, fence names) to this
  /// syntax. This is the single source of truth for language-key → TreeSitterSyntax resolution.
  public var languageKeys: [String] {
    switch self {
    case .bash: ["bash", "shell", "sh", "zsh"]
    case .c: ["c", "h"]
    case .cpp: ["cpp", "c++", "hpp", "hh", "hxx", "cxx", "cc"]
    case .cSharp: ["csharp", "c#", "cs"]
    case .css: ["css"]
    case .dart: ["dart"]
    case .dockerfile: ["dockerfile", "containerfile"]
    case .go: ["go"]
    case .html: ["html", "htm", "xhtml"]
    case .java: ["java"]
    case .javaScript: ["javascript", "js", "jsx", "mjs", "cjs"]
    case .json: ["json", "jsonc"]
    case .kotlin: ["kotlin", "kt"]
    case .latex: ["latex", "tex"]
    case .lua: ["lua"]
    case .makefile: ["makefile", "mk"]
    case .markdown: ["markdown", "md"]
    case .php: ["php"]
    case .python: ["python", "py", "pyw", "pyi"]
    case .ruby: ["ruby", "rb", "rake", "gemspec"]
    case .rust: ["rust", "rs"]
    case .scala: ["scala"]
    case .sql: ["sql"]
    case .swift: ["swift"]
    case .typeScript: ["typescript", "ts", "tsx", "mts", "cts"]
    case .xml: ["xml", "svg", "plist", "xsd", "rss"]
    case .yaml: ["yaml", "yml"]
    }
  }

  /// Resolve a language key (file extension, fence name, or display name) to a `TreeSitterSyntax`.
  /// Case-insensitive. Returns `nil` if the key doesn't match any supported language.
  public init?(languageKey key: String) {
    let lowered = key.lowercased()
    for syntax in TreeSitterSyntax.allCases {
      if syntax.languageKeys.contains(lowered) || syntax.rawValue.lowercased() == lowered {
        self = syntax
        return
      }
    }
    return nil
  }

  /// Supported features.
  public var features: ParserFeatures {

    switch self {
    case .markdown: [.outline]
    default: [.highlight, .outline]
    }
  }

  /// The provider/injection name.
  var providerName: String {

    switch self {
    case .cSharp: "c_sharp"
    case .makefile: "make"
    default: self.rawValue.lowercased()
    }
  }

  /// The tree-sitter language pointer.
  var language: OpaquePointer {

    switch self {
    case .bash: tree_sitter_bash()
    case .c: tree_sitter_c()
    case .cpp: tree_sitter_cpp()
    case .cSharp: tree_sitter_c_sharp()
    case .css: tree_sitter_css()
    case .dart: tree_sitter_dart()
    case .dockerfile: tree_sitter_dockerfile()
    case .go: tree_sitter_go()
    case .html: tree_sitter_html()
    case .java: tree_sitter_java()
    case .javaScript: tree_sitter_javascript()
    case .json: tree_sitter_json()
    case .kotlin: tree_sitter_kotlin()
    case .latex: tree_sitter_latex()
    case .lua: tree_sitter_lua()
    case .makefile: tree_sitter_make()
    case .markdown: tree_sitter_markdown()
    case .php: tree_sitter_php()
    case .python: tree_sitter_python()
    case .ruby: tree_sitter_ruby()
    case .rust: tree_sitter_rust()
    case .scala: tree_sitter_scala()
    case .sql: tree_sitter_sql()
    case .swift: tree_sitter_swift()
    case .typeScript: tree_sitter_typescript()
    case .xml: tree_sitter_xml()
    case .yaml: tree_sitter_yaml()
    }
  }
}
