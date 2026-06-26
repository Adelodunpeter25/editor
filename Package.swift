// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Editor",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
        .package(name: "EditorCore", path: "Packages/EditorCore"),
    ],
    targets: [
        .target(
            name: "Cfff",
            path: "Sources/Cfff",
            exclude: ["libfff_c.a"]
        ),
        .executableTarget(
            name: "Editor",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "LineEnding", package: "EditorCore"),
                .product(name: "TextFind", package: "EditorCore"),
                .product(name: "ValueRange", package: "EditorCore"),
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
    ],
    swiftLanguageVersions: [.v5]
)
