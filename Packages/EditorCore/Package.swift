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
        
        .library(name: "ValueRange", targets: ["ValueRange"]),
        
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
        
        .target(name: "Defaults"),
        
        .target(name: "DocumentFile", dependencies: ["FileEncoding", "URLUtils"]),
        
        .target(name: "FileEncoding", dependencies: ["ValueRange"]),
        
        .target(name: "FolderFind", dependencies: ["DocumentFile", "FileEncoding", "LineEnding", "StringUtils", "TextFind"]),
        
        .target(name: "Invisible"),
        
        .target(name: "LineEnding", dependencies: ["StringUtils", "ValueRange"]),
        
        .target(name: "LineSort", dependencies: ["StringUtils"]),
        
        .target(name: "SemanticVersioning"),
        
        .target(name: "StringUtils"),
        
        .target(name: "TextClipping"),
        
        .target(name: "TextEditing", dependencies: ["StringUtils"]),
        
        .target(name: "TextFind", dependencies: ["StringUtils", "ValueRange"]),
        
        .target(name: "URLUtils"),
        
        .target(name: "ValueRange"),
    ]
)
