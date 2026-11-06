// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

final class NotchQuickAccessMotion: ObservableObject {
    @Published private(set) var progress: CGFloat = 0
    @Published private(set) var interactive = false
    @Published private(set) var configuration = NotchQuickAccessConfiguration(side: .left, actions: [.settings])
    @Published private(set) var placements: [NotchQuickAccessPlacement] = []
    private var bodyFrame = CGRect.zero
    private var visible = false
    private var generation = 0

    func configure(_ configuration: NotchQuickAccessConfiguration, body: CGRect, headerTop: CGFloat, animated: Bool) {
        let values = NotchQuickAccessLayout.placements(configuration, body: body, headerTop: headerTop)
        guard self.configuration != configuration || placements != values else { return }
        let spring = NotchMotion.sideSpring(from: bodyFrame.size, to: body.size)
        let widens = body.width >= bodyFrame.width
        let duration = spring.duration * (widens ? 0.75 : 1.2)
        let animation: Animation? = animated && visible
            ? .spring(duration: duration, bounce: widens ? spring.bounce : 0) : nil
        bodyFrame = body
        withAnimation(animation) {
            self.configuration = configuration
            placements = values
        }
    }

    var hoverRects: [CGRect] { placements.map(NotchQuickAccessLayout.hoverRect) }

    func setVisible(_ visible: Bool, animated: Bool, delay: TimeInterval = 0) {
        guard self.visible != visible else { return }
        self.visible = visible
        generation += 1
        let token = generation
        interactive = false
        let animation: Animation? = animated
            ? (visible ? .spring(duration: 0.3, bounce: 0.18).delay(delay) : .easeOut(duration: NotchQuickAccessLayout.withdrawalDuration))
            : nil
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            progress = visible ? 1 : 0
        } completion: { [weak self] in
            guard let self, self.generation == token else { return }
            self.interactive = visible
        }
    }

    func contains(_ point: CGPoint) -> Bool {
        interactive && placements.contains { NotchQuickAccessLayout.contains(point, placement: $0) }
    }
}

struct NotchQuickAccessView: View {
    @ObservedObject var service: NotchService
    @ObservedObject var motion: NotchQuickAccessMotion
    let backdrop: NotchBackdropPresentation
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var microphone = MicMuteService.shared
    @ObservedObject private var recorder = ScreenRecorderService.shared
    @AppStorage(DefaultsKey.notchLiquidGlassEnabled) private var glass = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var followsGlass: Bool {
#if compiler(>=6.2)
        if #available(macOS 26, *) { return glass && !reduceTransparency && contrast != .increased }
#endif
        return false
    }

    var body: some View {
        let drops = NotchQuickAccessDrops(placements: motion.placements, progress: motion.progress)
        let buttons = ZStack(alignment: .topLeading) {
            ForEach(motion.placements) { placement in
                bubble(placement.button, height: placement.height)
                    .scaleEffect(0.4 + 0.6 * motion.progress)
                    .opacity(Double(motion.progress))
                    .position(placement.center(progress: motion.progress))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        Group {
            if followsGlass {
                buttons.modifier(NotchQuickAccessGlassSurface(presentation: backdrop, drops: drops,
                                                              clipsToIsland: motion.progress < 1))
            } else {
                buttons.background { drops }
            }
        }
        .environment(\.colorScheme, .dark)
        .environment(\.notchPresentation, true)
        .foregroundStyle(.white)
        .tint(.white)
        .allowsHitTesting(motion.interactive)
        .accessibilityHidden(!motion.interactive)
    }

    private func bubble(_ button: NotchQuickButton, height: CGFloat) -> some View {
        let action = button.action ?? .settings
        let selected: Bool = {
            if action == .pin { return service.pinned }
            if action == .control(.keepAwake) { return awake.isActive }
            if action == .control(.microphone) { return microphone.isMuted }
            if action == .control(.recording) { return recorder.isRecording }
            if case .module(let module) = action {
                return !service.showingSections && !service.showingAppPanel && service.selected == module
            }
            return false
        }()
        var actionTitle = action.title(l10n)
        var symbol = action.symbol
        switch action {
        case .pin:
            actionTitle = service.pinned ? FeatureStrings.notch(l10n.language).unpin : FeatureStrings.notch(l10n.language).pin
            if service.pinned { symbol = "pin.fill" }
        case .control(.microphone):
            actionTitle = microphone.isMuted ? l10n.s.micUnmuteName : l10n.s.micMuteName
            if microphone.isMuted { symbol = "mic.slash.fill" }
        case .control(.keepAwake) where awake.isActive: symbol = "cup.and.saucer.fill"
        case .control(.recording) where recorder.isRecording: symbol = "stop.circle.fill"
        default: break
        }
        let title = button.label.isEmpty ? actionTitle : button.label
        return Button {
            service.activateQuickAction(action)
        } label: {
            Group {
                if case .module(.agents) = action {
                    ClaudeMark()
                        .fill(selected ? ClaudeMark.tint : Color.white)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(selected ? Color(nsColor: .systemBlue) : .white.opacity(0.85))
                }
            }
            .frame(width: NotchQuickAccessLayout.width, height: height)
            .background(followsGlass ? Color.black.opacity(0.02) : Color.black, in: Capsule())
            .overlay {
                Capsule().strokeBorder(.white.opacity(selected || contrast == .increased ? 0.5 : 0.14), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.2), value: selected)
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: NotchQuickAccessLayout.width / 2))
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("notch.quickAccess.\(button.id.uuidString)")
    }
}

private struct NotchQuickAccessDrops: View {
    let placements: [NotchQuickAccessPlacement]
    let progress: CGFloat

    var body: some View {
        ZStack {
            ForEach(placements) { placement in
                NotchQuickAccessDrop(progress: progress, index: placement.index, edge: placement.edge,
                                     top: placement.top, height: placement.height, side: placement.side)
                    .fill(.black)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct NotchQuickAccessGlassSurface: ViewModifier {
    @ObservedObject var presentation: NotchBackdropPresentation
    let drops: NotchQuickAccessDrops
    var clipsToIsland = true
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let island = presentation.usesGlass ? presentation.contour : Path()
        content
            .background {
                if presentation.usesGlass {
                    GeometryReader { proxy in
                        LinearGradient(stops: NotchSurfaceBackground.shade(openness: presentation.openness, contrast: contrast),
                                       startPoint: .top,
                                       endPoint: UnitPoint(x: 0.5, y: (island.isEmpty ? 0 : island.boundingRect.maxY)
                                                            / max(1, proxy.size.height)))
                            .mask { drops }
                    }
                } else {
                    drops
                }
            }
            .clipShape(NotchQuickAccessOutside(island: clipsToIsland ? island : Path()), style: FillStyle(eoFill: true))
    }
}

private struct NotchQuickAccessOutside: Shape {
    let island: Path

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        guard !island.isEmpty else { return path }
        path.addPath(island, transform: CGAffineTransform(translationX: rect.midX - island.boundingRect.midX, y: 0))
        return path
    }
}

struct NotchQuickAccessDrop: Shape {
    var progress: CGFloat
    let index: Int
    var edge: CGFloat
    var top: CGFloat
    var height: CGFloat
    let side: NotchQuickAccessSide
    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get { AnimatablePair(progress, AnimatablePair(edge, AnimatablePair(top, height))) }
        set {
            progress = newValue.first; edge = newValue.second.first
            top = newValue.second.second.first; height = newValue.second.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let phase = min(1.1, max(0, progress))
        guard phase > 0.001 else { return Path() }
        let anchor = side == .bottom ? rect.height - edge : side == .left ? edge : rect.width - edge
        let center = NotchQuickAccessLayout.center(index: index, progress: phase, edge: anchor, top: top, side: .left)
        let scale = 0.4 + 0.6 * phase
        let radius = NotchQuickAccessLayout.width / 2 * scale
        let halfHeight = height / 2 * scale
        var path = Path(roundedRect: CGRect(x: center.x - radius, y: center.y - halfHeight,
                                            width: radius * 2, height: halfHeight * 2),
                        cornerRadius: radius, style: .continuous)
        let neck = halfHeight * 0.8 * max(0, 1 - phase / 0.84)
        if neck > 0, center.x + radius < anchor {
            path.move(to: CGPoint(x: anchor + 2, y: center.y + neck))
            path.addCurve(to: CGPoint(x: center.x + radius * 0.55, y: center.y + neck * 0.75),
                          control1: CGPoint(x: anchor - 7, y: center.y + neck),
                          control2: CGPoint(x: center.x + radius, y: center.y + neck * 0.15))
            path.addLine(to: CGPoint(x: center.x + radius * 0.55, y: center.y - neck * 0.75))
            path.addCurve(to: CGPoint(x: anchor + 2, y: center.y - neck),
                          control1: CGPoint(x: center.x + radius, y: center.y - neck * 0.15),
                          control2: CGPoint(x: anchor - 7, y: center.y - neck))
            path.closeSubpath()
        }
        if side == .bottom { return path.applying(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: rect.height)) }
        if side == .right { return path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.width, ty: 0)) }
        return path
    }
}

extension NotchQuickAction {
    var symbol: String {
        switch self {
        case .settings: return "gearshape"
        case .pin: return "pin"
        case .module(let module): return module.symbol
        case .control(let item): return item.symbol
        }
    }

    func title(_ l10n: L10n) -> String {
        switch self {
        case .settings: return l10n.s.menuSettings
        case .pin: return FeatureStrings.notch(l10n.language).pin
        case .module(let module): return module.title(l10n.language)
        case .control(let item): return item.title(l10n)
        }
    }
}
