// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchMusicView: View {
    let size: CGSize
    let extrasHeight: CGFloat
    @ObservedObject private var service = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var shuffle = NotchShuffleService.shared
    @AppStorage(DefaultsKey.notchLyricsEnabled) private var lyricsEnabled = true
    @AppStorage(DefaultsKey.notchQueueEnabled) private var queueEnabled = true
    @AppStorage(DefaultsKey.notchMusicShowVolume) private var showVolume = false
    @State private var extra: MusicExtra?
    private enum MusicExtra { case lyrics, queue }
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(PerformanceMode.key) private var performanceModeMotion = false
    private var reduceMotion: Bool { systemReduceMotion || performanceModeMotion }
    @Environment(\.notchSettingsPreview) private var preview
    @Environment(\.notchBand) private var band
    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    private var accent: Color { service.artworkTint?.color ?? .white }
    private var showsLyrics: Bool { lyricsEnabled && AppFeature.notchLyrics.isAvailable }
    private var showsQueue: Bool { queueEnabled && AppFeature.notchQueue.isAvailable }
    private var showsVolume: Bool { showVolume && AppFeature.mixer.isAvailable }
    private var openExtra: MusicExtra? {
        guard service.playback != nil else { return nil }
        switch extra {
        case .lyrics: return showsLyrics ? .lyrics : nil
        case .queue: return showsQueue ? .queue : nil
        case nil: return nil
        }
    }
    private var bandHeight: CGFloat { band.besideCamera ? band.height : 0 }

    var body: some View {
        let geometry = NotchService.shared.geometry
        let split = NotchLayout.musicSplit(
            height: size.height, extras: extrasHeight,
            resting: NotchLayout.musicPlayerHeight(band: bandHeight, playing: service.playback != nil, showVolume: showsVolume),
            keepsPlayer: !preview && geometry.layout != .custom, extraOpen: openExtra != nil)
        let reserve = split.showsPlayer ? 0
            : band.besideCamera ? bandHeight + NotchLayout.spacing : 28 + NotchLayout.rowSpacing
        VStack(spacing: NotchLayout.rowSpacing) {
            if split.showsPlayer {
                if let playback = service.playback {
                    player(playback)
                } else if !service.awaitingPlayback {
                    idle
                } else {
                    Color.clear.frame(height: split.player)
                }
            } else if band.besideCamera {
                Color.clear.frame(height: reserve - NotchLayout.rowSpacing)
                    .overlay(alignment: .topLeading) { sectionsButton.frame(height: band.height) }
            } else {
                HStack(spacing: 6) { Spacer(minLength: 0); extraButtons; sectionsButton }.frame(height: 28)
            }
            if let openExtra, let playback = service.playback {
                Group {
                    switch openExtra {
                    case .lyrics: NotchLyricsView(playback: playback)
                    case .queue: NotchQueueView(playback: playback)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(height: max(0, min(split.extra, size.height - reserve)), alignment: .top)
                .clipped()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .notchBand(trailing: {
            if band.besideCamera, service.playback != nil { extraButtons }
        })
        .onAppear {
            guard !preview else { return }
            syncExtras()
            service.refreshAutomation()
            shuffle.refresh(for: service.playback)
        }
        .onChange(of: extra) { syncExtras() }
        .onChange(of: service.playback.map(NotchMusicIdentity.init)) {
            syncExtras()
            if !preview { shuffle.refresh(for: service.playback) }
        }
        .onChange(of: service.automationAvailability?.access) { old, new in
            if !preview, old != nil, new != nil { shuffle.refresh(for: service.playback) }
        }
        .onChange(of: features.revision) { syncExtras() }
        .onChange(of: lyricsEnabled) { syncExtras() }
        .onChange(of: queueEnabled) { syncExtras() }
        .onDisappear {
            guard !preview else { return }
            NotchService.shared.setMusicDetailsVisible(false)
            NotchService.shared.setPageLayer(.music, close: nil)
            NotchLyricsService.shared.hide()
            service.setQueueVisible(false)
            shuffle.stop()
        }
    }

    private func syncExtras() {
        guard !preview else { return }
        NotchService.shared.setMusicDetailsVisible(openExtra != nil)
        NotchService.shared.setPageLayer(.music, close: openExtra == nil ? nil : { extra = nil })
        NotchLyricsService.shared.update(playback: service.playback, visible: extra == .lyrics)
        service.setQueueVisible(extra == .queue)
    }

    private func head<Artwork: View, Titles: View, Accessory: View, Corner: View>(
        corner showsCorner: Bool = false,
        @ViewBuilder artwork: () -> Artwork, @ViewBuilder titles: () -> Titles,
        @ViewBuilder accessory: () -> Accessory, @ViewBuilder corner: () -> Corner = { EmptyView() }) -> some View {
        HStack(alignment: .bottom, spacing: 14) {
            artwork()
            titles()
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: NotchLayout.musicTitleHeight)
            VStack(alignment: .trailing, spacing: 0) {
                if showsCorner {
                    HStack(spacing: 6) { corner() }.frame(height: 28)
                }
                HStack(spacing: 8) { accessory() }.frame(maxHeight: .infinity)
            }
            .frame(height: NotchLayout.musicArtworkSize)
        }
        .frame(height: NotchLayout.musicHeadHeight(band: bandHeight), alignment: .bottom)
    }

    private var idle: some View {
        let player = preview ? nil : NotchPreferredPlayer.current()
        let opens = player != nil
        let openTitle = player.map { NotchPreferredPlayer.openTitle(for: $0) } ?? ""
        return VStack(spacing: 0) {
            head(corner: !band.besideCamera && band.pageSectionsButton) {
                Button { NotchPreferredPlayer.open() } label: {
                    NotchArtwork(image: nil, size: NotchLayout.musicArtworkSize)
                }
                .buttonStyle(NotchButtonStyle(cornerRadius: NotchLayout.musicArtworkSize * 0.19))
                .disabled(!opens)
                .help(openTitle)
                .accessibilityLabel(opens ? openTitle : text.mediaNothingPlaying)
            } titles: {
                VStack(alignment: .leading, spacing: 2) {
                    if !service.sources.isEmpty || !service.sourceIsAutomatic {
                        sourcePicker(nil)
                    } else {
                        Text(text.mediaNothingPlaying).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    }
                    if opens {
                        Text(openTitle).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } accessory: {
                EmptyView()
            } corner: {
                sectionsButton
            }
            Group {
                if opens {
                    transportRow(leading: { EmptyView() }) { slot in
                        NotchMusicIdleTransport(openTitle: openTitle, slot: slot)
                    }
                } else {
                    Text(FeatureStrings.notch(l10n.language).musicHint)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: NotchLayout.musicTransportHeight)
            .padding(.top, NotchLayout.musicHeadSpacing)
            volumeRow
            Color.clear.frame(height: NotchLayout.musicBottomRoom)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var volumeRow: some View {
        if showsVolume {
            NotchAudioControls()
                .padding(.top, NotchLayout.rowSpacing)
        }
    }

    @ViewBuilder private var extraButtons: some View {
        if showsLyrics {
            extraButton(.lyrics, title: FeatureStrings.notchMusicExtras(l10n.language).lyrics, symbol: "quote.bubble")
        }
        if showsQueue {
            extraButton(.queue, title: FeatureStrings.notchMusicExtras(l10n.language).queue, symbol: "list.bullet")
        }
    }

    @ViewBuilder private var sectionsButton: some View {
        EmptyView()
    }

    private func extraButton(_ target: MusicExtra, title: String, symbol: String) -> some View {
        NotchIconButton(symbol: symbol, title: title, selected: extra == target) {
            extra = extra == target ? nil : target
        }
    }

    private var shuffleButton: some View {
        let strings = FeatureStrings.notchMusicExtras(l10n.language)
        let consent = shuffle.availability?.access == .consent
        return NotchMusicSideButton(symbol: "shuffle", title: strings.shuffle, hint: consent ? strings.allowPlayback : nil,
                                    active: shuffle.enabled == true, tint: accent) { shuffle.toggle() }
            .disabled(shuffle.requestingAccess || !shuffle.allowed)
    }

    private func transportRow<Leading: View, Middle: View>(
        @ViewBuilder leading: () -> Leading, @ViewBuilder middle: (CGFloat) -> Middle) -> some View {
        let slot = size.width / 5
        return HStack(spacing: 0) {
            Color.clear.frame(width: slot).overlay { leading() }
            middle(slot).frame(width: slot * 3)
            Color.clear.frame(width: slot).overlay {
                if AppFeature.mixer.isAvailable { NotchMusicOutputButton() }
            }
        }
        .frame(height: NotchLayout.musicTransportHeight)
    }

    private func player(_ playback: NotchPlayback) -> some View {
        VStack(spacing: 0) {
            head(corner: !band.besideCamera && (showsLyrics || showsQueue || band.pageSectionsButton)) {
                Button { RadialNowPlayingApplication.open(playback.track) } label: {
                    ZStack {
                        NotchArtwork(image: service.artwork, size: NotchLayout.musicArtworkSize, source: playback.track)
                            .id(service.artwork.map { ObjectIdentifier($0) })
                            .transition(.opacity)
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: service.artwork.map { ObjectIdentifier($0) })
                        .scaleEffect(playback.isPlaying || reduceMotion ? 1 : 0.94)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: playback.isPlaying)
                }
                .buttonStyle(NotchButtonStyle(cornerRadius: NotchLayout.musicArtworkSize * 0.19))
                .help(text.mediaNowPlaying)
                .accessibilityLabel(text.mediaNowPlaying)
            } titles: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(playback.track.title ?? text.mediaNowPlaying)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: playback.track.title)
                        .help(playback.track.title ?? text.mediaNowPlaying)
                    Text(service.commandFailed ? FeatureStrings.notchMusicExtras(l10n.language).playbackFailed
                         : playback.track.artist ?? playback.track.album ?? text.mediaNowPlaying)
                        .font(.system(size: 13))
                        .foregroundStyle(service.commandFailed ? .orange : .secondary)
                        .lineLimit(1)
                }
            } accessory: {
                if service.sources.count > 1 || !service.sourceIsAutomatic {
                    sourceMenu(playback)
                }
                NotchLiveEqualizerBars(isPlaying: playback.isPlaying, bars: 4, barWidth: 2.5, height: 15,
                                       tint: .white.opacity(0.5))
                if band.besideCamera { sectionsButton }
            } corner: {
                extraButtons
                sectionsButton
            }
            NotchMusicTimeline(playback: playback, service: service, tint: accent, timesBeside: true)
                .padding(.top, NotchLayout.musicHeadSpacing)
            transportRow {
                if !preview && shuffle.isOffered { shuffleButton }
            } middle: { slot in
                NotchMusicTransport(playback: playback, slot: slot)
            }
            .padding(.top, NotchLayout.rowSpacing)
            volumeRow
            Color.clear.frame(height: NotchLayout.musicBottomRoom)
        }
        .modifier(NotchMusicSwipeFeedback())
    }

    private func sourceMenu(_ playback: NotchPlayback) -> some View {
        let extras = FeatureStrings.notchMusicExtras(l10n.language)
        let current = service.sources.first { $0.pid == playback.track.appPID }
        let app = playback.track.appPID.map { NotchPlayerApps.app(pid: $0, bundle: playback.track.appBundleIdentifier) }
        let name = current?.displayName ?? app?.name ?? playback.track.appBundleIdentifier ?? extras.playbackSource
        let icon = app?.icon
        var items = [NotchMenuItem(title: extras.automaticSource, checked: service.sourceIsAutomatic) { service.selectSource(nil) },
                     .separator]
        items += service.sources.map { source in
            let title = source.displayName ?? NotchPlayerApps.app(pid: source.pid, bundle: source.bundleIdentifier).name
                ?? source.bundleIdentifier
            return NotchMenuItem(title: title, checked: source.pid == service.selectedSourcePID) { service.selectSource(source.selection) }
        }
        return NotchMenuButton(title: extras.playbackSource, items: items, cornerRadius: 6) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "app").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 18, height: 18)
            .padding(3)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .help("\(extras.playbackSource): \(name)")
        .accessibilityValue([service.sourceIsAutomatic ? extras.automaticSource : nil, name].compactMap { $0 }.joined(separator: ", "))
    }

    private func sourcePicker(_ playback: NotchPlayback?) -> some View {
        let extras = FeatureStrings.notchMusicExtras(l10n.language)
        let pid = playback?.track.appPID
        let name = service.sources.first(where: { $0.pid == pid })?.displayName
            ?? pid.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
            ?? playback?.track.appBundleIdentifier ?? extras.playbackSource
        return Menu {
            Button { service.selectSource(nil) } label: {
                if service.sourceIsAutomatic { Label(extras.automaticSource, systemImage: "checkmark") }
                else { Text(extras.automaticSource) }
            }
            Divider()
            ForEach(service.sources, id: \.pid) { source in
                let title = source.displayName ?? NSRunningApplication(processIdentifier: source.pid)?.localizedName ?? source.bundleIdentifier
                Button { service.selectSource(source.selection) } label: {
                    if source.pid == service.selectedSourcePID {
                        Label(title, systemImage: "checkmark")
                    } else { Text(title) }
                }
            }
        } label: {
            Text(name).lineLimit(1).truncationMode(.tail)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: 110)
        .fixedSize()
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .accessibilityLabel(extras.playbackSource)
        .accessibilityValue([service.sourceIsAutomatic ? extras.automaticSource : nil,
                             playback == nil ? nil : name].compactMap { $0 }.joined(separator: ", "))
        .help(extras.playbackSource)
    }
}

private struct NotchMusicSideButton: View {
    let symbol: String
    let title: String
    var hint: String?
    let active: Bool
    let tint: Color
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(PerformanceMode.key) private var performanceModeMotion = false
    private var reduceMotion: Bool { systemReduceMotion || performanceModeMotion }
    private let height: CGFloat = 44
    private let plate: CGFloat = 32

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(active ? tint : .white.opacity(isEnabled ? 0.55 : 0.3))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: plate, height: plate)
                .background(.white.opacity(active ? 0.12 : 0), in: Circle())
                .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: active)
                .frame(width: height, height: height)
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: height / 2))
        .help(hint ?? title)
        .accessibilityLabel(title)
        .accessibilityHint(hint ?? "")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private enum NotchPlayerApps {
    private static var known: [Int32: (bundle: String?, name: String?, icon: NSImage?)] = [:]

    static func app(pid: Int32, bundle: String?) -> (name: String?, icon: NSImage?) {
        if let entry = known[pid], bundle == nil || entry.bundle == bundle { return (entry.name, entry.icon) }
        let running = NSRunningApplication(processIdentifier: pid)
        if known.count >= 16 { known.removeAll() }
        known[pid] = (running?.bundleIdentifier ?? bundle, running?.localizedName, running?.icon)
        return (running?.localizedName, running?.icon)
    }
}

private struct NotchMusicOutputButton: View {
    @ObservedObject private var notch = NotchService.shared
    @ObservedObject private var mixer = AppVolumeMixer.shared
    @ObservedObject private var l10n = L10n.shared

    private var deviceName: String {
        mixer.outputDevices.first(where: { $0.uid == mixer.currentOutputDeviceUID })?.name ?? l10n.s.mixerSystemOutputTitle
    }

    private var symbol: String {
        guard let device = mixer.outputDevices.first(where: { $0.uid == mixer.currentOutputDeviceUID }) else { return "airplay.audio" }
        if device.isHeadphones { return NotchAccessorySupport.symbol(for: .audio, name: device.name) }
        switch device.priorityTier {
        case .builtIn: return PowerSampler.hasInternalBattery ? "laptopcomputer" : "desktopcomputer"
        case .hardware: return "hifispeaker"
        case .virtual: return "airplay.audio"
        }
    }

    var body: some View {
        NotchMenuButton(title: l10n.s.mixerSystemOutputTitle, items: items, cornerRadius: 22) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .help(mixer.outputSwitchError ?? deviceName)
        .accessibilityValue(deviceName)
    }

    private var items: [NotchMenuItem] { NotchAudioControls.outputItems(mixer: mixer, notch: notch, l10n: l10n) }
}

struct NotchMusicIdleTransport: View {
    var compact = false
    let openTitle: String
    var slot: CGFloat? = nil
    @ObservedObject private var l10n = L10n.shared
    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    private var height: CGFloat { compact ? 36 : 44 }

    var body: some View {
        HStack(spacing: slot == nil ? (compact ? 12 : 18) : 0) {
            button("backward.fill", title: text.mediaPrevious, size: compact ? 16 : 19).frame(width: slot)
            button("play.fill", title: text.mediaPlayPause, size: compact ? 22 : slot == nil ? 26 : 28).frame(width: slot)
            button("forward.fill", title: text.mediaNext, size: compact ? 16 : 19).frame(width: slot)
        }
        .frame(height: height)
    }

    private func button(_ symbol: String, title: String, size: CGFloat) -> some View {
        Button { NotchPreferredPlayer.open() } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: height, height: height)
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: height / 2))
        .accessibilityLabel(title)
        .accessibilityHint(openTitle)
        .help(openTitle)
    }
}

private struct NotchMusicTransport: View {
    let playback: NotchPlayback
    var compact = false
    var slot: CGFloat? = nil
    @ObservedObject private var service = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(PerformanceMode.key) private var performanceModeMotion = false
    private var reduceMotion: Bool { systemReduceMotion || performanceModeMotion }
    @Environment(\.notchSettingsPreview) private var preview
    @State private var requestedPlaying: Bool?
    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    private var height: CGFloat { compact ? 36 : 44 }
    private var showsPlaying: Bool { requestedPlaying ?? playback.isPlaying }

    var body: some View {
        if !playback.canSendCommandsDirectly, service.automationAvailability?.access != .granted {
            HStack(spacing: 10) {
                toggleButton
                if service.automationAvailability?.access == .consent {
                    Button(FeatureStrings.notchMusicExtras(l10n.language).allowPlayback) { service.requestAutomationAccess() }
                        .disabled(service.requestingAutomation)
                    if service.requestingAutomation { ProgressView().controlSize(.small) }
                } else if service.automationAvailability?.access == .denied {
                    Button(l10n.s.permissionOpenSettings) { Permissions.shared.openAutomationSettings() }
                    Button { service.refreshAutomation() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel(FeatureStrings.notchMusicExtras(l10n.language).refresh)
                } else {
                    Button(FeatureStrings.notchMusicExtras(l10n.language).openPlayer) { RadialNowPlayingApplication.open(playback.track) }
                }
            }
            .buttonStyle(.borderless).font(.caption).frame(height: height)
        } else {
            transportButtons
        }
    }

    private var transportButtons: some View {
        HStack(spacing: slot == nil ? (compact ? 12 : 18) : 0) {
            if !service.lacksTrackSkipping(.previous) {
                playbackButton("backward.fill", title: text.mediaPrevious, command: .previous).frame(width: slot)
            } else if let slot {
                Color.clear.frame(width: slot)
            }
            toggleButton.frame(width: slot)
            if !service.lacksTrackSkipping(.next) {
                playbackButton("forward.fill", title: text.mediaNext, command: .next).frame(width: slot)
            } else if let slot {
                Color.clear.frame(width: slot)
            }
        }
        .frame(height: height)
    }

    private var toggleButton: some View {
        Button {
            if service.canPerform(.toggle) {
                let direct = playback.canSendCommandsDirectly
                if service.send(.toggle, context: playback.commandContext), direct { requestedPlaying = !showsPlaying }
            } else { service.requestAutomationAccess() }
        } label: {
            Image(systemName: showsPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: compact ? 22 : slot == nil ? 26 : 28, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: showsPlaying)
                .frame(width: height, height: height)
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: height / 2))
        .onChange(of: playback.isPlaying) { if playback.isPlaying == requestedPlaying { requestedPlaying = nil } }
        .onChange(of: playback.track) { requestedPlaying = nil }
        .task(id: requestedPlaying) {
            guard requestedPlaying != nil else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled { requestedPlaying = nil }
        }
        .disabled(!service.canPerform(.toggle)
                  && (service.automationAvailability?.access != .consent || service.requestingAutomation))
        .keyboardShortcut(preview ? nil : KeyboardShortcut(.space, modifiers: []))
        .accessibilityLabel(text.mediaPlayPause)
        .help(service.automationAvailability?.access == .consent
              ? FeatureStrings.notchMusicExtras(l10n.language).allowPlayback : text.mediaPlayPause)
    }

    private func playbackButton(_ symbol: String, title: String, command: NotchMusicService.Command) -> some View {
        Button { service.send(command, context: playback.commandContext) } label: {
            Image(systemName: symbol)
                .font(.system(size: compact ? 16 : 19, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: height, height: height)
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: height / 2))
        .disabled(!service.canPerform(command))
        .accessibilityLabel(title)
        .help(title)
    }
}

struct NotchMusicTimeline: View {
    let playback: NotchPlayback
    @ObservedObject var service: NotchMusicService
    var tint: Color = .white
    var timesBeside = false
    @ObservedObject private var l10n = L10n.shared
    @State private var scrubPosition: Double?
    @State private var scrubTrack: RadialNowPlayingSnapshot?
    @State private var scrubContext: NotchPlaybackContext?
    @State private var pendingSeek: UUID?

    var body: some View {
        if playback.duration > 0 {
            TimelineView(.animation(minimumInterval: 1, paused: !playback.isPlaying)) { context in
                let position = scrubPosition ?? playback.position(at: context.date)
                Group {
                    if timesBeside {
                        HStack(spacing: 8) {
                            ZStack(alignment: .leading) {
                                Text(timestamp(playback.duration)).hidden()
                                Text(timestamp(position))
                            }
                            bar(position)
                            ZStack(alignment: .trailing) {
                                Text("−" + timestamp(playback.duration)).hidden()
                                Text("−" + timestamp(playback.duration - position))
                            }
                        }
                    } else {
                        VStack(spacing: 3) {
                            bar(position)
                            HStack {
                                Text(timestamp(position))
                                Spacer()
                                Text("−" + timestamp(playback.duration - position))
                            }
                        }
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .frame(height: timesBeside ? NotchLayout.musicTimelineHeight : 30)
            .onChange(of: playback.track) { clearScrub() }
            .onChange(of: playback.commandContext) { clearScrub() }
            .onChange(of: playback.sampledAt) {
                if pendingSeek != nil, let scrubPosition,
                   abs(playback.position(at: Date()) - scrubPosition) <= 2 { clearScrub() }
            }
            .task(id: pendingSeek) {
                guard pendingSeek != nil else { return }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                clearScrub()
            }
        }
    }

    @ViewBuilder private func bar(_ position: TimeInterval) -> some View {
        if service.canSeek {
            NotchLevelSlider(
                value: Binding(get: { position }, set: {
                    if scrubTrack == nil {
                        scrubTrack = playback.track
                        scrubContext = playback.commandContext
                    }
                    scrubPosition = $0
                }),
                label: FeatureStrings.notch(l10n.language).playbackPosition,
                range: 0...playback.duration,
                tint: tint,
                valueLabel: timestamp(position),
                scrollable: false,
                onEditingChanged: { editing in
                    if editing {
                        pendingSeek = nil
                    } else if let scrubPosition, let scrubTrack {
                        service.seek(to: scrubPosition, in: scrubTrack, context: scrubContext)
                        pendingSeek = UUID()
                    }
                })
                .frame(height: 10)
                .disabled(service.commandPending)
        } else {
            NotchMeter(value: position / playback.duration, height: 6, tint: tint)
        }
    }

    private func clearScrub() {
        pendingSeek = nil
        scrubPosition = nil
        scrubTrack = nil
        scrubContext = nil
    }

    private func timestamp(_ interval: TimeInterval) -> String {
        let seconds = Int(min(604_800, max(0, interval)))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

