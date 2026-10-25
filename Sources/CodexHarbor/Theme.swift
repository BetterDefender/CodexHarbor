import AppKit
import SwiftUI

enum AppTheme: String, CaseIterable {
    case system
    case light
    case dark

    static let preferenceKey = "interfaceTheme"

    static func saved(in defaults: UserDefaults = .standard) -> AppTheme {
        AppTheme(rawValue: defaults.string(forKey: preferenceKey) ?? "") ?? .system
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum Palette {
    static let background = adaptive(light: NSColor(srgbRed: 0.96, green: 0.96, blue: 0.94, alpha: 1),
                                     dark: NSColor(srgbRed: 0.055, green: 0.063, blue: 0.071, alpha: 1))
    static let panel = adaptive(light: .white,
                                dark: NSColor(srgbRed: 0.085, green: 0.094, blue: 0.102, alpha: 1))
    static let raised = adaptive(light: NSColor(srgbRed: 0.90, green: 0.91, blue: 0.885, alpha: 1),
                                 dark: NSColor(srgbRed: 0.12, green: 0.13, blue: 0.14, alpha: 1))
    static let ink = adaptive(light: NSColor(srgbRed: 0.10, green: 0.11, blue: 0.095, alpha: 1),
                              dark: NSColor(srgbRed: 0.94, green: 0.95, blue: 0.91, alpha: 1))
    static let muted = adaptive(light: NSColor(srgbRed: 0.39, green: 0.42, blue: 0.39, alpha: 1),
                                dark: NSColor(srgbRed: 0.62, green: 0.65, blue: 0.64, alpha: 1))
    static let acid = adaptive(light: NSColor(srgbRed: 0.34, green: 0.47, blue: 0.0, alpha: 1),
                               dark: NSColor(srgbRed: 0.81, green: 0.98, blue: 0.36, alpha: 1))
    static let line = adaptive(light: NSColor.black.withAlphaComponent(0.10),
                               dark: NSColor.white.withAlphaComponent(0.10))
    static let hover = adaptive(light: NSColor.black.withAlphaComponent(0.04),
                                dark: NSColor.white.withAlphaComponent(0.05))

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

extension Font {
    /// Keeps the original hierarchy while using standard macOS sizes. Body and control text
    /// get a lighter reduction than display headlines.
    static func app(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: (size * (size < 24 ? 0.86 : 0.8)).rounded(), weight: weight, design: design)
    }
}

struct ActionStyle: ButtonStyle {
    var prominent = false
    var compact = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.app(compact ? 14 : 16, weight: .semibold))
            .padding(.horizontal, compact ? 12 : 18).padding(.vertical, compact ? 7 : 12)
            .foregroundStyle(prominent ? Palette.background : Palette.ink)
            .background(prominent ? Palette.acid : Palette.raised, in: RoundedRectangle(cornerRadius: compact ? 7 : 9))
            .overlay(RoundedRectangle(cornerRadius: compact ? 7 : 9).stroke(prominent ? .clear : Palette.line))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: compact ? 7 : 9))
    }
}
