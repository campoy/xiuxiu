import SwiftUI

/// "Nit" -- a cool ink ground with a warm accent, so the app reads as something you
/// write in at night rather than a utility. Light mode is warm paper, not white, which
/// keeps the same temperature rather than switching personality between appearances.
///
/// Deliberately plain constants, not an asset catalog colour set: two appearances of
/// five colours is less machinery than a catalog, and it stays greppable.
enum Nit {
    static func ground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x11141C) : Color(hex: 0xFAF6F0)
    }

    /// Cards and wells sitting on top of `ground`.
    static func raised(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 1, opacity: 0.035) : Color(hex: 0x2A2520).opacity(0.035)
    }

    static func line(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x2A3140) : Color(hex: 0x2A2520).opacity(0.12)
    }

    static func text(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF2EBE0) : Color(hex: 0x2A2520)
    }

    static func dim(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x9BA3B2) : Color(hex: 0x8A7F72)
    }

    /// The accent darkens in light mode: terracotta that reads well on ink is too pale on paper.
    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xD98E5F) : Color(hex: 0xC2764A)
    }

    /// Recording. A muted coral rather than system red, which would shout.
    static func live(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xE0685A) : Color(hex: 0xC8503F)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255
        )
    }
}

/// Metadata: small, tracked, upper case. Used for dates and status so they read as
/// labels rather than competing with the transcript.
struct MetaLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .tracking(1.4)
    }
}

extension View {
    func metaLabel() -> some View { modifier(MetaLabel()) }
}
