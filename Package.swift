// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Editor",
    // STTextView (TextKit 2 editor component) requires macOS 14+.
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ed", targets: ["ed"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
        // Source editor component (TextKit 2). GPLv3 — see LICENSE-STTextView.md re: the
        // commercial-license option if this app is ever distributed closed-source.
        .package(url: "https://github.com/krzyzanowskim/STTextView", from: "2.3.0"),
        .package(name: "EditorCore", path: "Packages/EditorCore"),
        .package(name: "Syntax", path: "Packages/Syntax"),
    ],
    targets: [
        .target(
            name: "Cfff",
            path: "Sources/Cfff",
            exclude: ["libfff_c.dylib"]
        ),
        .executableTarget(
            name: "Editor",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "STTextView", package: "STTextView"),
                .product(name: "LineEnding", package: "EditorCore"),
                .product(name: "TextFind", package: "EditorCore"),
                .product(name: "ValueRange", package: "EditorCore"),
                .product(name: "StringUtils", package: "EditorCore"),
                .product(name: "TextEditing", package: "EditorCore"),
                .product(name: "URLUtils", package: "EditorCore"),
                .product(name: "Defaults", package: "EditorCore"),
                .product(name: "SyntaxParsers", package: "Syntax"),
                .product(name: "SyntaxFormat", package: "Syntax"),
                "Cfff",
            ],
            path: "Sources/Editor",
            // Grammar JSON for the native TextMate highlighter.
            // build.sh copies the generated Editor_Editor.bundle into Contents/Resources; the bundle
            // is resolved there at runtime (see GrammarBundle) to avoid Bundle.module's distributed-app crash.
            resources: [.copy("TextMate/Grammars")],
            linkerSettings: [
                .linkedLibrary("fff_c"),
                .linkedLibrary("z"),
                .linkedLibrary("iconv"),
                .unsafeFlags(["-L", "Sources/Cfff"])
            ]
        ),
        .executableTarget(
            name: "ed",
            path: "Sources/ed"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
