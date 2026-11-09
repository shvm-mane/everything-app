// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchCompactMusicSnapshot {
    let playback: NotchPlayback
    let artwork: NSImage?
    let tint: NotchArtworkTint?
    let geometry: NotchGeometry
    var namedWing: CGFloat? = nil
    var namesSong = false
}

struct NotchMusicStrip: View {
    @ObservedObject var service: NotchService
    var snapshot: NotchCompactMusicSnapshot? = nil
    var displayGeometry: NotchGeometry? = nil
    var interactive = false
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(PerformanceMode.key) private var performanceModeMotion = false
    private var reduceMotion: Bool { systemReduceMotion || performanceModeMotion }

    private typealias Layout = NotchMusicStripLayout
    private var geometry: NotchGeometry { snapshot?.geometry ?? displayGeometry ?? service.compactActivityGeometry }
    private var shown: NotchCompactMusicSnapshot? {
        snapshot ?? service.heldMusic ?? (interactive ? service.musicStripStandIn(for: music.playback) : nil)
    }
    private var playback: NotchPlayback? { shown?.playback ?? music.playback }
    private var artwork: NSImage? { shown == nil ? music.artwork : shown?.artwork }
    private var tint: NotchArtworkTint? { shown == nil ? music.artworkTint : shown?.tint }
    private var live: Bool { interactive && snapshot == nil }
    private var innerInset: CGFloat { Layout.innerInset(geometry) }

    private var artworkSide: CGFloat { Layout.coverSide(geometry) }
    private var artworkRadius: CGFloat { min(artworkSide / 2, geometry.compactMusicArtworkRadius) }
    private var artworkInset: CGFloat { Layout.coverInset(geometry) }
    private var barsInset: CGFloat {
        max(0, min(geometry.compactMusicBarsInset,
                   geometry.compactActivityWingWidth - NotchLayout.compactMusicBarsWidth - innerInset))
    }

    private var title: String { playback?.track.title ?? FeatureStrings.radialMenu(l10n.language).mediaNowPlaying }
    private var artist: String? {
        guard let artist = playback?.track.artist?.trimmingCharacters(in: .whitespaces), !artist.isEmpty else { return nil }
        return artist
    }
    private var fillsCameraGap: Bool { Layout.fillsCameraGap(geometry) }
    private var showsArtist: Bool { Layout.showsArtist(geometry) }
    private var namedWing: CGFloat? { live ? service.namedMusicWings?.leading : snapshot?.namedWing }
    private var showsControl: Bool { live && service.musicStripShowsControl }
    private var playing: Bool { (live ? service.musicStripRequest : nil) ?? playback?.isPlaying == true }

    var body: some View {
        let wing = geometry.compactActivityWingWidth
        let named = namedWing
        Button { live ? service.activateMusicStrip() : service.openActivity(.music) } label: {
            HStack(spacing: 0) {
                HStack(spacing: Layout.spacing) {
                    if named != nil { namedLabel }
                    if wing > 0 {
                        NotchMusicCover(artwork: artwork, side: artworkSide, radius: artworkRadius,
                                        source: playback?.track)
                    }
                }
                .padding(.leading, named == nil ? artworkInset : Layout.endInset)
                .padding(.trailing, named == nil ? innerInset : wing - artworkInset - artworkSide)
                .frame(width: named ?? wing, height: geometry.compactActivityContentHeight,
                       alignment: named == nil ? .leading : .trailing)
                .clipped()
                .contentShape(Rectangle())
                .onHover { if live { service.hoverMusicStrip(.cover, entered: $0) } }
                Group {
                    if fillsCameraGap { trackLabel } else { Color.clear }
                }
                .frame(width: geometry.compactActivityCameraGap, height: geometry.compactActivityContentHeight)
                .clipped()
                HStack {
                    if wing > 0 { bars }
                }
                .padding(.leading, innerInset)
                .padding(.trailing, barsInset + 4)
                .frame(width: wing, height: geometry.compactActivityContentHeight, alignment: .trailing)
                .contentShape(Rectangle())
                .onHover { if live { service.hoverMusicStrip(.bars, entered: $0) } }
            }
            .frame(height: geometry.compactActivityContentHeight)
            .modifier(NotchMusicSwipeFeedback(enabled: snapshot == nil))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel([title, playback?.track.artist].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
        .accessibilityAction(named: Text(FeatureStrings.radialMenu(l10n.language).mediaPlayPause)) {
            if !service.toggleMusicStripSong() { service.openActivity(.music) }
        }
        .help(title)
        .frame(width: (named ?? wing) * 2 + geometry.compactActivityCameraGap, alignment: .leading)
    }

    private var bars: some View {
        ZStack {
            NotchLiveEqualizerBars(isPlaying: playing && !showsControl,
                                   bars: NotchLayout.compactMusicBarCount,
                                   barWidth: NotchLayout.compactMusicBarWidth,
                                   height: geometry.compactMusicBarHeight,
                                   tint: tint?.color ?? .white)
                .opacity(showsControl ? 0 : 1)
            if showsControl {
                NotchMusicStripButton(playing: playing, tint: tint?.color ?? .white,
                                      height: geometry.compactMusicBarHeight)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: showsControl)
    }

    private var namedLabel: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(title)
                .font(Font(Layout.titleFont as CTFont))
                .lineLimit(1)
                .truncationMode(.tail)
            if showsArtist, let artist {
                Text(artist)
                    .font(Font(Layout.artistFont as CTFont))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityHidden(true)
    }

    private var trackLabel: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if showsArtist, let artist {
                Text(artist)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, geometry.compactMusicLabelInset)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

struct NotchMusicStripButton: View {
    let playing: Bool
    let tint: Color
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(PerformanceMode.key) private var performanceModeMotion = false
    private var reduceMotion: Bool { systemReduceMotion || performanceModeMotion }

    var body: some View {
        let symbol = playing ? "pause.fill" : "play.fill"
        let size = min(13, max(8, height - 3))
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
            .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: playing)
            .alignmentGuide(VerticalAlignment.center) {
                $0[VerticalAlignment.center] + NotchCapsuleLayout.symbolDrop(symbol, size: size, weight: .semibold)
            }
            .frame(width: NotchLayout.compactMusicBarsWidth, height: height)
            .accessibilityHidden(true)
    }
}

struct NotchMusicSwipeFeedback: ViewModifier {
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(PerformanceMode.key) private var performanceModeMotion = false
    private var reduceMotion: Bool { systemReduceMotion || performanceModeMotion }
    @State private var trigger = 0
    @State private var direction: CGFloat = -1

    func body(content: Content) -> some View {
        let displacement = reduceMotion ? 0 : direction
        return content
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { view, travel in
                view.offset(x: displacement * travel)
            } keyframes: { _ in
                CubicKeyframe(8, duration: 0.09)
                SpringKeyframe(0, duration: 0.25, spring: .smooth)
            }
            .onReceive(NotchMusicService.shared.gestureSkips) { forward in
                guard enabled, !reduceMotion else { return }
                direction = forward ? -1 : 1
                trigger &+= 1
            }
    }
}

struct NotchMusicCover: View {
    let artwork: NSImage?
    let side: CGFloat
    let radius: CGFloat
    var source: RadialNowPlayingSnapshot? = nil

    var body: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork).resizable().scaledToFill()
            } else if let icon = source.flatMap(RadialNowPlayingApplication.icon(for:)) {
                Color.black.overlay {
                    Image(nsImage: icon).resizable().interpolation(.high).scaledToFit().padding(side * 0.08)
                }
            } else {
                Color.black.overlay { Image(systemName: "music.note").foregroundStyle(.secondary) }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .circular))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .circular)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        }
    }
}
