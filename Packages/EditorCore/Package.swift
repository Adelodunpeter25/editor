// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "EditorCore",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "EditorCore", targets: [
            "CharacterInfo",
            "Defaults",
            "DocumentFile",
            "FileEncoding",
            "FolderFind",
            "Invisible",
            "LineEnding",
            "LineSort",
            "SemanticVersioning",
            "StringUtils",
            "TextClipping",
            "TextEditing",
            "TextFind",
            "URLUtils",
            "ValueRange",
        ]),
        
        .library(name: "CharacterInfo", targets: ["CharacterInfo"]),
        .library(name: "Defaults", targets: ["Defaults"]),
        .library(name: "DocumentFile", targets: ["DocumentFile"]),
        .library(name: "FileEncoding", targets: ["FileEncoding"]),
        .library(name: "FolderFind", targets: ["FolderFind"]),
        .library(name: "Invisible", targets: ["Invisible"]),
        .library(name: "LineEnding", targets: ["LineEnding"]),
        .library(name: "LineSort", targets: ["LineSort"]),
        .library(name: "SemanticVersioning", targets: ["SemanticVersioning"]),
        .library(name: "StringUtils", targets: ["StringUtils"]),
        .library(name: "TextClipping", targets: ["TextClipping"]),
        .library(name: "TextEditing", targets: ["TextEditing"]),
        .library(name: "TextFind", targets: ["TextFind"]),
        .library(name: "URLUtils", targets: ["URLUtils"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(name: "CharacterInfo"),
        .testTarget(name: "CharacterInfoTests", dependencies: ["CharacterInfo"]),
        
        .target(name: "Defaults"),
        .testTarget(name: "DefaultsTests", dependencies: ["Defaults"]),
        
        .target(name: "DocumentFile", dependencies: ["FileEncoding", "URLUtils"]),
        .testTarget(name: "DocumentFileTests", dependencies: ["DocumentFile"]),
        
        .target(name: "FileEncoding", dependencies: ["ValueRange"]),
        .testTarget(name: "FileEncodingTests", dependencies: ["FileEncoding"]),
        
        .target(name: "FolderFind", dependencies: ["DocumentFile", "FileEncoding", "LineEnding", "StringUtils", "TextFind"]),
        .testTarget(name: "FolderFindTests", dependencies: ["FolderFind"]),
        
        .target(name: "Invisible"),
        
        .target(name: "LineEnding", dependencies: ["StringUtils", "ValueRange"]),
        .testTarget(name: "LineEndingTests", dependencies: ["LineEnding", "StringUtils"]),
        
        .target(name: "LineSort", dependencies: ["StringUtils"]),
        .testTarget(name: "LineSortTests", dependencies: ["LineSort"]),
        
        .target(name: "SemanticVersioning"),
        .testTarget(name: "SemanticVersioningTests", dependencies: ["SemanticVersioning"]),
        
        .target(name: "StringUtils"),
        .testTarget(name: "StringUtilsTests", dependencies: ["StringUtils"]),
        
        .target(name: "TextClipping"),
        .testTarget(name: "TextClippingTests", dependencies: ["TextClipping"]),
        
        .target(name: "TextEditing", dependencies: ["StringUtils"]),
        .testTarget(name: "TextEditingTests", dependencies: ["TextEditing"]),
        
        .target(name: "TextFind", dependencies: ["StringUtils", "ValueRange"]),
        .testTarget(name: "TextFindTests", dependencies: ["TextFind"]),
        
        .target(name: "URLUtils"),
        .testTarget(name: "URLUtilsTests", dependencies: ["URLUtils"]),
        
        .target(name: "ValueRange"),
        .testTarget(name: "ValueRangeTests", dependencies: ["ValueRange"]),
    ]
)
