// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct NotchWatchThumbnail: View {
    let image: CGImage
    let height: CGFloat

    var body: some View {
        Image(decorative: image, scale: 2)
            .resizable().interpolation(.medium).aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .frame(width: NotchWatchSupport.thumbnailWidth, height: height)
            .accessibilityHidden(true)
    }
}

struct NotchWatchEye: View {
    let size: CGFloat
    var hidden = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(PerformanceMode.key) private var performanceModeMotion = false
    private var reduceMotion: Bool { systemReduceMotion || performanceModeMotion }

    var body: some View {
        NotchWatchEyeBridge(size: size, hidden: hidden, animates: !hidden && !reduceMotion)
            .frame(width: size + 2, height: size + 2)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

private struct NotchWatchEyeBridge: NSViewRepresentable {
    let size: CGFloat
    let hidden: Bool
    let animates: Bool

    func makeNSView(context: Context) -> NotchAgentAnimationView { NotchAgentAnimationView() }
    func updateNSView(_ view: NotchAgentAnimationView, context: Context) {
        let image = NSImage(systemSymbolName: hidden ? "eye.slash" : "eye", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium))
        view.configureGlyph(image: image, size: size, tint: NotchWatchStrip.eyeTint, animates: animates)
    }
    static func dismantleNSView(_ view: NotchAgentAnimationView, coordinator: ()) { view.stop() }
}

struct NotchWatchStrip: View {
    static let tint = Color.purple
    static let eyeTint = NSColor.systemPurple.withAlphaComponent(0.75)

    @ObservedObject var service: NotchService
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var watch = NotchWatchService.shared
    @ObservedObject private var l10n = L10n.shared

    private var geometry: NotchGeometry { displayGeometry ?? service.compactActivityGeometry }
    private var iconSize: CGFloat {
        NotchTimerSupport.stripAgentMarkSize(height: geometry.compactActivityContentHeight, working: 1)
    }
    private var textSize: CGFloat { NotchTimerSupport.stripTextSize(height: geometry.compactActivityContentHeight) }
    private var iconInset: CGFloat { geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2) }
    private var textInset: CGFloat { geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0) }

    var body: some View {
        Button { service.openActivity(.watch) } label: {
            HStack(spacing: 0) {
                NotchWatchEye(size: iconSize, hidden: watch.state == .hidden)
                    .padding(.leading, iconInset)
                    .frame(width: geometry.compactActivityWingWidth, alignment: .leading)
                    .opacity(geometry.compactActivityWingWidth >= 28 ? 1 : 0)
                Color.clear.frame(width: geometry.compactActivityCameraGap)
                reading
                    .padding(.trailing, textInset)
                    .frame(width: geometry.compactActivityWingWidth, alignment: .trailing)
                    .clipped()
            }
            .frame(height: geometry.compactActivityContentHeight)
            .padding(.horizontal, geometry.compactActivityHorizontalPadding)
            .padding(.top, geometry.compactActivityTopPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(FeatureStrings.notchWatch(l10n.language).title)
        .accessibilityValue(watch.headline)
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }

    @ViewBuilder private var reading: some View {
        if geometry.compactActivityWingWidth < 36 {
            EmptyView()
        } else if watch.showsThumbnail, let preview = watch.preview {
            NotchWatchThumbnail(image: preview, height: max(8, geometry.compactActivityContentHeight - 6))
        } else if watch.headline.isEmpty {
            if watch.state != .hidden { ProgressView().controlSize(.mini) }
        } else {
            Text(watch.headline)
                .font(.system(size: textSize, weight: .medium)).monospacedDigit()
                .foregroundStyle(Self.tint)
                .lineLimit(1).minimumScaleFactor(0.7).truncationMode(.tail)
        }
    }
}
