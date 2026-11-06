// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct RadialMenuView: View {
    @ObservedObject private var service = RadialMenuService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(DefaultsKey.liquidGlassEnabled) private var liquidGlassEnabled = false

    @State private var wedgeAngle = 0.0
    @State private var wedgeSlice = Double.pi / 3
    @State private var wedgeShown = false

    private static let sweepDuration = 0.12

    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    private var items: [RadialMenuItem] { service.stack.last ?? [] }
    private var animates: Bool { !reduceMotion }
    private var profileColor: Color { Color(red: 0.93, green: 0.92, blue: 0.9) }

    var body: some View {
        ZStack {
            backplate
            wedge
            ring.id(service.stack.count)
            hub
        }
        .frame(width: RadialMenuLayout.panelSize, height: RadialMenuLayout.panelSize)
        .contentShape(Rectangle())
        .onTapGesture { service.activatePointer() }
        .scaleEffect(service.visible || !animates ? 1 : 0.9)
        .animation(animates
                   ? (service.visible
                      ? .spring(response: 0.19, dampingFraction: 0.86)
                      : .easeIn(duration: 0.09))
                   : nil,
                   value: service.visible)
        .onChange(of: service.highlightedIndex) { _, _ in syncWedge() }
        .environment(\.colorScheme, .dark)
        .onChange(of: items.count) { _, _ in syncWedge() }
        .accessibilityLabel(text.pageTitle)
    }

    private var wedge: some View {
        RadialWedgeShape(centerAngle: wedgeAngle,
                         sliceAngle: wedgeSlice,
                         innerRadius: RadialMenuLayout.deadZoneRadius,
                         outerRadius: RadialMenuLayout.wheelDiameter / 2 - 4)
            .fill(RadialGradient(colors: [profileColor.opacity(colorScheme == .light ? 0.05 : 0.08),
                                          profileColor.opacity(colorScheme == .light ? 0.20 : 0.30)],
                                 center: .center,
                                 startRadius: RadialMenuLayout.deadZoneRadius,
                                 endRadius: RadialMenuLayout.wheelDiameter / 2))
            .opacity(wedgeShown ? 1 : 0)
    }

    private func syncWedge() {
        let count = items.count
        guard count > 0, let index = service.highlightedIndex, items.indices.contains(index) else {
            guard wedgeShown else { return }
            withAnimation(animates ? .easeOut(duration: 0.084) : nil) { wedgeShown = false }
            return
        }
        let slice = 2 * Double.pi / Double(count)
        var angle = slice * Double(index)
        guard wedgeShown else {
            var placement = Transaction()
            placement.disablesAnimations = true
            withTransaction(placement) {
                wedgeAngle = angle
                wedgeSlice = slice
            }
            withAnimation(animates ? .easeOut(duration: 0.084) : nil) { wedgeShown = true }
            return
        }
        angle = wedgeAngle + (angle - wedgeAngle).remainder(dividingBy: 2 * Double.pi)
        withAnimation(animates ? .spring(response: 0.14, dampingFraction: 0.86) : nil) {
            wedgeAngle = angle
            wedgeSlice = slice
        }
    }

    private var backplate: some View {
        discMaterial
            .overlay(Circle().strokeBorder(PanelSurface.rimHighlight(for: colorScheme), lineWidth: 1.2))
            .overlay(Circle().strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.8))
            .overlay(sliceGuides)
            .frame(width: RadialMenuLayout.wheelDiameter, height: RadialMenuLayout.wheelDiameter)
            .shadow(color: .black.opacity(colorScheme == .light ? 0.22 : 0.55), radius: 24, y: 8)
    }

    @ViewBuilder
    private var discMaterial: some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *), liquidGlassEnabled, !reduceTransparency {
            Circle()
                .fill(Color.clear)
                .glassEffect(.regular, in: Circle())
                .overlay(Circle().fill(Color.black.opacity(0.86)))
        } else {
            Circle()
                .fill(Color.black.opacity(0.92))
        }
#else
        Circle()
            .fill(.regularMaterial)
            .overlay(Circle().fill(PanelSurface.baseFill(for: colorScheme)))
#endif
    }

    private var sliceGuides: some View {
        let count = items.count
        return ZStack {
            if count > 1 {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(Color.primary.opacity(colorScheme == .light ? 0.07 : 0.09))
                        .frame(width: 1, height: RadialMenuLayout.wheelDiameter / 2
                               - RadialMenuLayout.deadZoneRadius - 14)
                        .offset(y: -(RadialMenuLayout.deadZoneRadius
                                     + (RadialMenuLayout.wheelDiameter / 2
                                        - RadialMenuLayout.deadZoneRadius - 14) / 2 + 7))
                        .rotationEffect(.radians(2 * Double.pi * (Double(index) + 0.5) / Double(count)))
                }
            }
        }
    }

    private var ring: some View {
        let count = items.count
        return ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            RadialChipView(item: item,
                           name: item.displayName(text, nowPlayingState: service.nowPlayingState),
                           nowPlayingState: service.nowPlayingState,
                           highlighted: service.highlightedIndex == index,
                           animates: animates,
                           profileColor: profileColor,
                           direction: RadialMenuGeometry.unitPosition(index: index, itemCount: count),
                           openDelay: Self.openDelay(index: index, count: count),
                           open: service.visible)
                .accessibilityLabel(item.displayName(text, nowPlayingState: service.nowPlayingState))
        }
    }

    private static func openDelay(index: Int, count: Int) -> Double {
        guard count > 1 else { return 0 }
        return sweepDuration * Double(index) / Double(count - 1)
    }

    private var hub: some View {
        ZStack {
            Circle()
                .fill(Color.primary.opacity(colorScheme == .light ? 0.045 : 0.075))
                .frame(width: RadialMenuLayout.hubDiameter, height: RadialMenuLayout.hubDiameter)
            hubFace
                .id(hubFaceKey)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
        .frame(width: RadialMenuLayout.hubDiameter, height: RadialMenuLayout.hubDiameter)
        .animation(animates ? .easeOut(duration: 0.1) : nil, value: hubFaceKey)
    }

    private var hubFaceKey: String {
        if let index = service.highlightedIndex, items.indices.contains(index) {
            return "item.\(items[index].id)"
        }
        if let parent = service.trail.last { return "back.\(parent)" }
        return "brand"
    }

    @ViewBuilder
    private var hubFace: some View {
        if let index = service.highlightedIndex, items.indices.contains(index) {
            Text(items[index].displayName(text, nowPlayingState: service.nowPlayingState))
                .font(.system(size: 8, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
                .frame(width: RadialMenuLayout.hubDiameter - 14)
        } else if let parent = service.trail.last {
            VStack(spacing: 3) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(parent.isEmpty ? text.kindSubmenu : parent)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .accessibilityLabel(text.backButton)
        } else {
            BrandMark(width: 34, tint: Color.primary)
        }
    }
}

private struct RadialChipView: View {
    let item: RadialMenuItem
    let name: String
    let nowPlayingState: RadialNowPlayingState
    let highlighted: Bool
    let animates: Bool
    let profileColor: Color
    let direction: (dx: CGFloat, dyUp: CGFloat)
    let openDelay: Double
    let open: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var settled = false

    var body: some View {
        ZStack {
            Circle()
                .fill(highlighted ? AnyShapeStyle(profileColor)
                                  : AnyShapeStyle(PanelSurface.raisedFill(for: colorScheme)))
                .overlay(Circle().strokeBorder(highlighted
                                               ? Color.clear
                                               : PanelSurface.raisedBorder(for: colorScheme),
                                               lineWidth: 0.8))
                .shadow(color: highlighted ? profileColor.opacity(0.45)
                                           : PanelSurface.raisedShadow(for: colorScheme),
                        radius: highlighted ? 13 : 5,
                        y: highlighted ? 4 : 2)
            icon
        }
        .frame(width: RadialMenuLayout.chipSize, height: RadialMenuLayout.chipSize)
        .scaleEffect(highlighted && animates ? 1.06 : 1)
        .animation(animates ? .spring(response: 0.17, dampingFraction: 0.72) : nil, value: highlighted)
        .scaleEffect(settled || !animates ? 1 : 0.35)
        .opacity(settled || !animates ? 1 : 0)
        .offset(x: direction.dx * reach, y: -direction.dyUp * reach)
        .onAppear { if open { bloom() } else { settled = false } }
        .onChange(of: open) { _, isOpen in
            if isOpen { bloom() } else { fold() }
        }
    }

    private var reach: CGFloat {
        settled || !animates ? RadialMenuLayout.ringRadius : RadialMenuLayout.deadZoneRadius * 0.2
    }

    private func bloom() {
        guard animates else {
            settled = true
            return
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75).delay(openDelay)) {
            settled = true
        }
    }

    private func fold() {
        guard animates else {
            settled = false
            return
        }
        withAnimation(.easeIn(duration: 0.07).delay(openDelay * 0.25)) {
            settled = false
        }
    }

    @ViewBuilder
    private var icon: some View {
        if item.mediaKey == .nowPlaying {
            if case let .playing(snapshot) = nowPlayingState,
               let icon = RadialNowPlayingApplication.icon(for: snapshot) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 27, height: 27)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(highlighted ? AnyShapeStyle(.black) : AnyShapeStyle(.white))
            }
        } else if item.symbolName.isEmpty, let customImage = RadialMenuIconStore.customIcon(for: item) {
            Image(nsImage: customImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 27, height: 27)
        } else if item.usesFileIcon {
            Image(nsImage: RadialMenuIconStore.fileIcon(for: item.payload))
                .resizable()
                .interpolation(.high)
                .frame(width: 27, height: 27)
        } else {
            Image(systemName: item.effectiveSymbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(highlighted ? AnyShapeStyle(.black) : AnyShapeStyle(.white))
        }
    }
}

struct RadialWedgeShape: Shape {
    var centerAngle: Double
    var sliceAngle: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(centerAngle, sliceAngle) }
        set {
            centerAngle = newValue.first
            sliceAngle = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = Angle(radians: centerAngle - sliceAngle / 2 - .pi / 2)
        let end = Angle(radians: centerAngle + sliceAngle / 2 - .pi / 2)
        var path = Path()
        path.addArc(center: center, radius: innerRadius, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: outerRadius, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

enum RadialMenuIconStore {
    private static var icons: [String: NSImage] = [:]
    private static var names: [String: String] = [:]
    private static var customIcons: [UUID: NSImage] = [:]

    static func fileIcon(for payload: String) -> NSImage {
        if let cached = icons[payload] { return cached }
        let path = (payload as NSString).expandingTildeInPath
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 34, height: 34)
        icons[payload] = icon
        return icon
    }

    static func customIcon(for item: RadialMenuItem) -> NSImage? {
        guard let data = item.customIconData else { return nil }
        if let cached = customIcons[item.id] { return cached }
        guard let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: 34, height: 34)
        customIcons[item.id] = image
        return image
    }

    static func fileName(for payload: String) -> String {
        if let cached = names[payload] { return cached }
        let path = (payload as NSString).expandingTildeInPath
        let name = FileManager.default.displayName(atPath: path)
        names[payload] = name
        return name
    }

    static func invalidate(_ payload: String) {
        icons.removeValue(forKey: payload)
        names.removeValue(forKey: payload)
    }

    static func invalidate(item: RadialMenuItem) {
        icons.removeValue(forKey: item.payload)
        names.removeValue(forKey: item.payload)
        customIcons.removeValue(forKey: item.id)
    }
}

extension RadialMenuItem {
    func displayName(_ text: RadialMenuFeatureStrings,
                     nowPlayingState: RadialNowPlayingState? = nil) -> String {
        if !name.isEmpty { return name }
        switch kind {
        case .app, .file:
            return RadialMenuIconStore.fileName(for: payload)
        case .url:
            let normalized = RadialMenuSupport.normalizedURL(payload) ?? payload
            return URL(string: normalized)?.host ?? payload
        case .shortcut:
            return GlobalShortcut(storageValue: payload)?.displayString ?? text.kindShortcut
        case .tool:
            guard let tool else { return text.kindTool }
            return tool.title
        case .quickToggle:
            return quickToggle?.radialTitle ?? FeatureStrings.quickToggles(L10n.shared.language).pageTitle
        case .windowLayout:
            guard let windowLayoutAction else {
                return FeatureStrings.windowLayout(L10n.shared.language).title
            }
            return windowLayoutAction.title(FeatureStrings.windowLayout(L10n.shared.language))
        case .media:
            switch mediaKey {
            case .playPause: return text.mediaPlayPause
            case .previousTrack: return text.mediaPrevious
            case .nextTrack: return text.mediaNext
            case .nowPlaying:
                switch nowPlayingState {
                case let .some(.playing(snapshot)): return snapshot.radialLabel ?? text.mediaNowPlaying
                case .some(.nothingPlaying): return text.mediaNothingPlaying
                case .some(.loading), .none: return text.mediaNowPlaying
                }
            case nil: return text.kindMedia
            }
        case .submenu:
            return text.kindSubmenu
        }
    }

    var usesFileIcon: Bool {
        (kind == .app || kind == .file) && symbolName.isEmpty
    }
}

extension RadialMenuQuickToggle {
    var radialTitle: String {
        let strings = FeatureStrings.quickToggles(L10n.shared.language)
        let toggles = QuickTogglesService.shared
        switch self {
        case .darkMode:
            return toggles.systemAppearanceIsDark == true ? strings.darkModeToLight : strings.darkModeToDark
        case .emptyTrash: return strings.emptyTrashTitle
        case .quitAllApps: return strings.quitAllTitle
        case .ejectDisks: return strings.ejectTitle
        case .hiddenFiles: return toggles.hiddenFilesShown ? strings.hiddenFilesHide : strings.hiddenFilesShow
        case .desktopIcons: return toggles.desktopIconsShown ? strings.desktopIconsHide : strings.desktopIconsShow
        case .lockScreen: return strings.lockScreenTitle
        case .displayOff: return strings.displayOffTitle
        case .screenSaver: return strings.screenSaverTitle
        }
    }
}
