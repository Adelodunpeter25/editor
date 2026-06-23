// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Editor",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "Editor",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/Editor",
            // Grammar JSON for the native TextMate highlighter.
            // build.sh copies the generated Editor_Editor.bundle into Contents/Resources; the bundle
            // is resolved there at runtime (see GrammarBundle) to avoid Bundle.module's distributed-app crash.
            resources: [.copy("TextMate/Grammars")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
