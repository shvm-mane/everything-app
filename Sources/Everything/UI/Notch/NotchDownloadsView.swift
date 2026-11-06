// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct NotchDownloadStrip: View {
    @ObservedObject var service: NotchService
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var downloads = NotchDownloadService.shared
    @ObservedObject private var l10n = L10n.shared

    private var geometry: NotchGeometry { displayGeometry ?? service.compactActivityGeometry }
    private var iconSize: CGFloat {
        min(17, geometry.compactActivityContentHeight - NotchLayout.compactEdgeGap * 2)
    }
    private var iconInset: CGFloat {
        geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2)
    }

    var body: some View {
        let item = downloads.items.first { $0.active && !$0.completed }
        Button { service.openActivity(.downloads) } label: {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    if geometry.compactActivityWingWidth >= 40 {
                        Image(systemName: "arrow.down.circle.fill").font(.system(size: iconSize))
                        if NotchDownloadSupport.showsCompactName(in: geometry) {
                            Text(item?.name ?? FeatureStrings.notchFiles(l10n.language).downloadsTitle)
                                .font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                .padding(.leading, geometry.compactActivityWingWidth >= 40 ? iconInset : 0)
                .padding(.trailing, 4)
                .frame(width: geometry.compactActivityWingWidth, alignment: .leading).clipped()
                Color.clear.frame(width: geometry.compactActivityCameraGap)
                HStack(spacing: 6) {
                    if NotchDownloadSupport.showsCompactName(in: geometry), let fraction = item?.fraction {
                        NotchMeter(value: fraction, height: 4).padding(.leading, 4)
                    } else {
                        Spacer(minLength: 0)
                    }
                    if geometry.compactActivityWingWidth >= 36 {
                        if let fraction = item?.fraction {
                            Text(fraction, format: NotchDownloadSupport.percentFormat(l10n.language))
                                .font(.system(size: NotchDownloadSupport.percentSize, weight: .medium))
                                .monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(NotchDownloadSupport.percentMinimumScale)
                                .layoutPriority(1)
                        } else {
                            ProgressView().controlSize(.mini)
                        }
                    }
                }
                .padding(.trailing, geometry.compactActivityWingWidth >= 36
                                    ? NotchDownloadSupport.percentInset(in: geometry) : 0)
                .frame(width: geometry.compactActivityWingWidth, alignment: .trailing).clipped()
            }
            .frame(height: geometry.compactActivityContentHeight)
            .padding(.horizontal, geometry.compactActivityHorizontalPadding)
            .padding(.top, geometry.compactActivityTopPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item?.name ?? FeatureStrings.notchFiles(l10n.language).downloadsTitle)
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }
}
