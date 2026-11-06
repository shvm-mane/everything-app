// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

extension NotchControlItem {
    func title(_ l10n: L10n) -> String {
        switch self {
        case .volume: return FeatureStrings.notch(l10n.language).volume
        case .brightness: return FeatureStrings.notch(l10n.language).brightness
        case .keyboardLight: return FeatureStrings.brightness(l10n.language).keyboardLight
        case .keepAwake: return l10n.s.keepAwakeTitle
        case .microphone: return l10n.s.micMuteName
        case .screenshot: return FeatureStrings.recentCaptures(l10n.language).screenshot
        case .recording: return FeatureStrings.recorder(l10n.language).pageTitle
        case .speedTest: return l10n.s.speedTestRun
        case .panel: return FeatureStrings.notch(l10n.language).panel
        case .mixer: return l10n.s.mixerSection
        case .commandBar: return FeatureStrings.commandBar(l10n.language).pageTitle
        case .scratchpad: return FeatureStrings.scratchpad(l10n.language).pageTitle
        case .music: return NotchModule.music.title(l10n.language)
        case .timer: return NotchModule.timer.title(l10n.language)
        case .calendar: return NotchModule.calendar.title(l10n.language)
        }
    }
}

struct NotchAudioControls: View {
    @ObservedObject var notch: NotchService = .shared
    @ObservedObject private var mixer = AppVolumeMixer.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var level: Double? { mixer.systemOutputVolume.map { mixer.systemOutputMuted == true ? 0 : $0 } }
    private var deviceName: String {
        mixer.outputDevices.first(where: { $0.uid == mixer.currentOutputDeviceUID })?.name ?? l10n.s.mixerSystemOutputTitle
    }

    var body: some View {
        HStack(spacing: 6) {
            mute
            slider
            NotchLevelChooser(title: l10n.s.mixerSystemOutputTitle, items: outputItems)
                .accessibilityValue(deviceName)
        }
        .frame(height: 28)
        .help(mixer.outputSwitchError ?? deviceName)
    }

    private func adjustOutput(volume: Double? = nil, muted: Bool? = nil) {
        notch.noteOwnLevelAdjustment(.volume)
        mixer.requestOutputAdjustment(volume: volume, muted: muted)
    }

    private var mute: some View {
        Button {
            if let muted = mixer.systemOutputMuted { adjustOutput(muted: !muted) }
        } label: {
            Image(systemName: mixer.systemOutputMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(mixer.systemOutputMuted == true ? Color.red : Color.white)
                .contentTransition(.symbolEffect(.replace))
                .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: mixer.systemOutputMuted)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 6))
        .disabled(mixer.systemOutputMuted == nil)
        .accessibilityLabel(mixer.systemOutputMuted == true ? l10n.s.actionUnmute : l10n.s.actionMute)
    }

    @ViewBuilder private var slider: some View {
        if let level {
            NotchLevelSlider(value: Binding(get: { level }, set: { adjustOutput(volume: $0) }),
                             label: FeatureStrings.notch(l10n.language).volume, trackThickness: 8, easesChanges: true)
                .frame(height: 24)
        } else {
            Text(l10n.s.mixerOutputUnavailable).font(.system(size: 10)).foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        }
    }

    private var outputItems: [NotchMenuItem] { Self.outputItems(mixer: mixer, notch: notch, l10n: l10n) }

    static func outputItems(mixer: AppVolumeMixer, notch: NotchService, l10n: L10n) -> [NotchMenuItem] {
        mixer.outputDevices.filter(\.canBeDefaultOutput).map { device in
            NotchMenuItem(title: device.name, checked: device.uid == mixer.currentOutputDeviceUID) {
                _ = mixer.setUniversalOutputDeviceUID(device.uid)
            }
        }
    }
}

private struct NotchLevelChooser: View {
    let title: String
    let items: [NotchMenuItem]

    var body: some View {
        NotchMenuButton(title: title, items: items) {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

enum NotchTileAccent {
    case selection, alert, awake, timer

    var fill: Color {
        switch self {
        case .selection: return .white
        case .alert: return .red
        case .awake: return .yellow
        case .timer: return .orange
        }
    }

    var glyph: Color {
        switch self {
        case .selection, .awake, .timer: return .black
        case .alert: return .white
        }
    }
}

struct NotchActionTile: View {
    let symbol: String
    let title: String
    var reading: String?
    var readingCountsDown = false
    var compactTitle: String?
    var active = false
    var accent: NotchTileAccent = .selection
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                    .foregroundStyle(active ? accent.glyph : .white.opacity(0.85))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 40, height: 40)
                    .background(active ? accent.fill : Color.white.opacity(0.075), in: Circle())
                    .animation(reduceMotion ? nil : .smooth(duration: 0.26), value: symbol)
                label
                    .frame(maxWidth: .infinity)
                    .frame(height: 28, alignment: .top)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: NotchLayout.shortcutHeight)
            .animation(reduceMotion ? nil : .smooth(duration: 0.26), value: active)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 14))
        .accessibilityLabel(title)
        .accessibilityValue(reading ?? "")
        .accessibilityAddTraits(active ? .isSelected : [])
        .help(title)
    }

    @ViewBuilder private var label: some View {
        if let reading {
            VStack(spacing: 1) {
                Text(reading).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.white)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.7)
                    .modifier(NotchRollingDigits(value: reading, countsDown: readingCountsDown))
                ViewThatFits(in: .horizontal) {
                    readingTitle(title)
                    if let compactTitle { readingTitle(compactTitle) }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        } else {
            Text(title).font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2).multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func readingTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
    }
}

