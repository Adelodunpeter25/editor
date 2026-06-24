import Foundation

enum GitIgnoreUtil {
    /// List of common build/cache directories that should be skipped in scans.
    static let ignoredDirectories: Set<String> = [
        ".git",
        ".build",
        ".swiftpm",
        "node_modules",
        ".next",
        "Pods",
        "DerivedData"
    ]

    /// Returns true if a path is considered a build artifact, temporary file, or metadata
    /// that should be ignored for file system watching and status updates.
    static func isIgnoredPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        
        // Ignore build, dependency, and cache directories
        if lower.contains("/.build/") || lower.hasSuffix("/.build")
            || lower.contains("/.swiftpm/")
            || lower.contains("/node_modules/") || lower.hasSuffix("/node_modules")
            || lower.contains("/.next/") || lower.hasSuffix("/.next")
            || lower.contains("/pods/") || lower.hasSuffix("/pods")
            || lower.contains("/deriveddata/") || lower.hasSuffix("/deriveddata") {
            return true
        }
        
        // Ignore OS metadata and temporary git state logs
        if lower.hasSuffix(".ds_store")
            || lower.contains("/.git/logs/")
            || lower.contains("/.git/commit_editmsg") {
            return true
        }
        
        return false
    }
}
