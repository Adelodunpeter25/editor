import AppKit

/// Centralized font resolution. Prefers JetBrains Mono Nerd Font (mono variant),
/// falls back to the system monospaced font if not installed.
enum AppFont {
    static func mono(size: Double) -> NSFont {
        NSFont(name: "JetBrainsMonoNFM-Regular", size: size)
            ?? NSFont(name: "JetBrainsMonoNerdFontMono-Regular", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func monoBold(size: Double) -> NSFont {
        NSFont(name: "JetBrainsMonoNFM-Bold", size: size)
            ?? NSFont(name: "JetBrainsMonoNerdFontMono-Bold", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .bold)
    }

    static func monoMedium(size: Double) -> NSFont {
        NSFont(name: "JetBrainsMonoNFM-Medium", size: size)
            ?? NSFont(name: "JetBrainsMonoNerdFontMono-Medium", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .medium)
    }
}
