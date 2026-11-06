import AppKit

enum WispTheme: String, CaseIterable {
    case dark
    case light
}

enum ThemePreference: String, CaseIterable {
    case light
    case dark
    case system

    var next: ThemePreference {
        switch self {
        case .light: return .dark
        case .dark: return .system
        case .system: return .light
        }
    }

    @MainActor func resolve() -> WispTheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system:
            let match = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? .dark : .light
        }
    }
}

extension NSAttributedString.Key {
    static let wispCodeBlock = NSAttributedString.Key("wispCodeBlock")
}

struct WispPalette {
    let text: NSColor
    let cursor: NSColor
    let selection: NSColor
    let divider: NSColor
    let syntax: NSColor
    let findHighlight: NSColor

    static func codeBackground(for theme: WispTheme, transparency: Transparency) -> NSColor {
        switch (theme, transparency) {
        case (.dark, .off):     return NSColor(white: 1.0, alpha: 0.08)
        case (.dark, .subtle):  return NSColor(white: 1.0, alpha: 0.10)
        case (.dark, .strong):  return NSColor(white: 1.0, alpha: 0.14)
        case (.light, .off):    return NSColor(white: 0.0, alpha: 0.055)
        case (.light, .subtle): return NSColor(white: 0.0, alpha: 0.07)
        case (.light, .strong): return NSColor(white: 0.0, alpha: 0.10)
        }
    }

    static func `for`(_ theme: WispTheme) -> WispPalette {
        switch theme {
        case .dark:
            let text = NSColor(red: 0.95, green: 0.93, blue: 0.89, alpha: 1.0)
            return WispPalette(
                text: text,
                cursor: NSColor(red: 0.98, green: 0.97, blue: 0.93, alpha: 1.0),
                selection: NSColor.controlAccentColor.withAlphaComponent(0.32),
                divider: text.withAlphaComponent(0.35),
                syntax: text.withAlphaComponent(0.38),
                findHighlight: NSColor(red: 0.98, green: 0.78, blue: 0.28, alpha: 0.42)
            )
        case .light:
            let text = NSColor(white: 0.10, alpha: 1.0)
            return WispPalette(
                text: text,
                cursor: NSColor(white: 0.0, alpha: 1.0),
                selection: NSColor.controlAccentColor.withAlphaComponent(0.22),
                divider: text.withAlphaComponent(0.30),
                syntax: text.withAlphaComponent(0.36),
                findHighlight: NSColor(red: 1.0, green: 0.82, blue: 0.18, alpha: 0.55)
            )
        }
    }
}

enum Transparency: String, CaseIterable {
    case off
    case subtle
    case strong

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .subtle: return "Subtle"
        case .strong: return "Strong"
        }
    }

    func tintAlpha(for theme: WispTheme) -> CGFloat {
        switch (theme, self) {
        case (_, .off):           return 1.0
        case (.dark, .subtle):    return 0.50
        case (.dark, .strong):    return 0.22
        case (.light, .subtle):   return 0.72
        case (.light, .strong):   return 0.40
        }
    }

    func tintColor(for theme: WispTheme) -> NSColor {
        switch theme {
        case .dark:
            return self == .off
                ? NSColor(white: 0.10, alpha: 1.0)
                : NSColor(white: 0.0, alpha: tintAlpha(for: theme))
        case .light:
            return NSColor(white: 1.0, alpha: tintAlpha(for: theme))
        }
    }
}

struct Chrome {
    let material: NSVisualEffectView.Material
    let tintColor: NSColor
    let appearance: NSAppearance.Name
    let usesVisualEffect: Bool

    static func `for`(_ theme: WispTheme, transparency: Transparency) -> Chrome {
        Chrome(
            material: .fullScreenUI,
            tintColor: transparency.tintColor(for: theme),
            appearance: theme == .dark ? .darkAqua : .aqua,
            usesVisualEffect: transparency != .off
        )
    }
}
