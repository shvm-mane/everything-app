// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(minWidth: 20, minHeight: 22)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            )
    }
}

struct ShortcutCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                KeyCap(label: key)
            }
        }
    }
}

struct HUDBackdrop: View {
    enum Contrast {
        case standard
        case high
    }

    var cornerRadius: CGFloat = 0
    var contrast: Contrast = .standard
    var opacity: Double = 1

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(DefaultsKey.liquidGlassEnabled) private var liquidGlassEnabled = false

    private var materialOpacity: Double {
        reduceTransparency ? 1 : min(max(opacity, 0), 1)
    }

    static func plateOpacity(dark: Bool) -> Double { dark ? 0.55 : 0.5 }

    private var plateOpacity: Double {
        guard contrast == .high, !reduceTransparency else { return 0 }
        return Self.plateOpacity(dark: colorScheme == .dark)
    }

    static func drawsLiquidGlass(enabled: Bool, reduceTransparency: Bool) -> Bool {
#if compiler(>=6.2)
        if #available(macOS 26.0, *) { return enabled && !reduceTransparency }
#endif
        return false
    }

    var body: some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *),
           Self.drawsLiquidGlass(enabled: liquidGlassEnabled, reduceTransparency: reduceTransparency) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(colorScheme == .dark ? Color.black : Color.white)
                        .opacity(plateOpacity)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 0.8)
                )
        } else {
            classicBackdrop
        }
#else
        classicBackdrop
#endif
    }

    @ViewBuilder
    private var classicBackdrop: some View {
        HUDBackdropMaterial(cornerRadius: cornerRadius, opacity: materialOpacity)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color.black : Color.white)
                    .opacity(plateOpacity)
            )
    }
}

private struct HUDBackdropMaterial: NSViewRepresentable {
    var cornerRadius: CGFloat = 0
    var opacity: Double = 1

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSVisualEffectView) {
        view.alphaValue = CGFloat(opacity)
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}

struct DisclosureHeaderRow<Label: View>: View {
    @ObservedObject private var l10n = L10n.shared

    private let isExpanded: Binding<Bool>
    private let label: () -> Label

    init(isExpanded: Binding<Bool>, @ViewBuilder label: @escaping () -> Label) {
        self.isExpanded = isExpanded
        self.label = label
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                label()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded.wrappedValue
            ? l10n.s.disclosureExpanded : l10n.s.disclosureCollapsed)
    }
}

extension View {
    func disclosureIndent() -> some View {
        padding(.leading, 25)
    }
}
