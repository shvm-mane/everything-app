// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

enum Theme {
    static let spaceGradient = LinearGradient(
        colors: [Color(white: 0.10),
                 Color(white: 0.04),
                 Color.black],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct NotchPresentationKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var notchPresentation: Bool {
        get { self[NotchPresentationKey.self] }
        set { self[NotchPresentationKey.self] = newValue }
    }
}

enum PanelSurface {
    static var popoverHostsFullSizeContent: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    static func baseFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.68) : Color.black.opacity(0.42)
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.38) : Color.white.opacity(0.075)
    }

    static func controlFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.055) : Color.white.opacity(0.085)
    }

    static func border(for scheme: ColorScheme) -> Color {
        let raised = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        return scheme == .light
            ? Color.black.opacity(raised ? 0.24 : 0.09)
            : Color.white.opacity(raised ? 0.28 : 0.11)
    }

    static func raisedFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.88) : Color.white.opacity(0.14)
    }

    static func raisedBorder(for scheme: ColorScheme) -> Color {
        let raised = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        return scheme == .light
            ? Color.black.opacity(raised ? 0.22 : 0.07)
            : Color.white.opacity(raised ? 0.32 : 0.16)
    }

    static func raisedShadow(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.14) : Color.black.opacity(0.38)
    }

    static func rimHighlight(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(colors: [Color.white.opacity(scheme == .light ? 0.95 : 0.30),
                                Color.white.opacity(scheme == .light ? 0.12 : 0.04)],
                       startPoint: .top,
                       endPoint: .bottom)
    }
}

func sectionTitle(_ text: String) -> some View {
    Text(text.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .kerning(0.5)
        .foregroundStyle(.secondary)
}

extension View {
    func panelCard(interactive: Bool = true, padded: Bool = true) -> some View {
        modifier(PanelCardModifier(interactive: interactive, padded: padded))
    }

    func panelGlassSurface() -> some View {
        background(PanelGlassSurface())
    }
}

private struct PanelCardModifier: ViewModifier {
    var interactive: Bool
    var padded = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.notchPresentation) private var notchPresentation

    func body(content: Content) -> some View {
        if notchPresentation {
            content.padding(padded ? 12 : 0).modifier(NotchControlSurface(cornerRadius: 18, interactive: interactive))
        } else {
        content
            .padding(padded ? 10 : 0)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(PanelSurface.cardFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7)
            )
        }
    }
}

private struct PanelGlassSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.notchPresentation) private var notchPresentation
    @Environment(\.notchGlassSurface) private var notchGlassSurface
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(DefaultsKey.liquidGlassEnabled) private var liquidGlassEnabled = false

    var body: some View {
        if notchPresentation {
            Rectangle().fill(notchGlassSurface ? Color.clear : .black)
        } else if PanelSurface.popoverHostsFullSizeContent {
            surface.ignoresSafeArea()
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var surface: some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *), liquidGlassEnabled, !reduceTransparency {
            Rectangle()
                .fill(Color.clear)
                .glassEffect(.regular, in: Rectangle())
                .overlay(
                    Rectangle()
                        .fill(PanelSurface.baseFill(for: colorScheme).opacity(colorScheme == .light ? 0.35 : 0.45))
                )
        } else {
            standardSurface
        }
#else
        standardSurface
#endif
    }

    @ViewBuilder
    private var standardSurface: some View {
        Rectangle()
            .fill(.regularMaterial)
            .overlay(Rectangle().fill(PanelSurface.baseFill(for: colorScheme)))
    }
}

func appDelegate() -> AppDelegate? {
    NSApp.delegate as? AppDelegate
}

struct BrandMark: View {
    var width: CGFloat
    var tint: Color = .white

    var body: some View {
        Image(systemName: "sum")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .fontWeight(.semibold)
            .foregroundStyle(tint)
            .frame(width: width * 0.62, height: width * 0.62)
            .frame(width: width, height: width)
    }
}

