// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FeaturePreset: String, CaseIterable, Identifiable {
    case essential, windows, battery

    var id: String { rawValue }

    static func prepareFirstRunAvailability(in defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: DefaultsKey.hasOnboarded),
              defaults.integer(forKey: DefaultsKey.onboardingStep) == 0
        else { return }
        let selected = FeaturePreset.essential.features
        for feature in AppFeature.allCases {
            defaults.set(selected.contains(feature), forKey: feature.availabilityKey)
        }
    }

    var features: Set<AppFeature> {
        switch self {
        case .essential:
            return [.mixer, .keepAwake,
                    .monitorCPU, .monitorGPU, .monitorMemory,
                    .monitorNetwork, .monitorDisk, .monitorPower]
        case .windows:
            return [.switcher, .windowLayout, .dockPreview, .dockClick, .windowMaximizer]
        case .battery:
            return [.monitorCPU, .monitorMemory, .monitorPower]
        }
    }

    var enableKeys: [String] {
        switch self {
        case .essential, .battery:
            return []
        case .windows:
            return [DefaultsKey.switcherEnabled,
                    DefaultsKey.dockPreviewEnabled,
                    DefaultsKey.dockClickMinimize,
                    DefaultsKey.windowMaximizeEnabled]
        }
    }

    var symbolName: String {
        switch self {
        case .essential: return "star.fill"
        case .windows: return "macwindow.on.rectangle"
        case .battery: return "battery.75percent"
        }
    }
}

enum FeatureEnergyProfile: String {
    case idle
    case mouse
    case pointer
    case keyboard
    case inputs
    case periodic
}

extension AppFeature {
    var energyProfile: FeatureEnergyProfile {
        switch self {
        case .scrollInverter, .scrollHorizontal, .scrollZoom, .focusFollowsMouse, .smoothScroll, .linearScroll, .windowMaximizer, .middleClick,
             .mouseNavigation, .mouseButtonShortcuts, .mouseClickDebounce,
             .dockPreview, .dockClick, .shelf:
            return .mouse
        case .keyboardDebounce, .finderCutPaste, .finderRename, .quitWindowProtection, .musicBlock:
            return .keyboard
        case .switcher, .superKey, .textSnippets, .autoQuit:
            return .inputs
        case .windowLayout:
            let edgeSnapRuns = UserDefaults.standard.bool(forKey: DefaultsKey.windowEdgeSnapEnabled)
                && !WindowEdgeSnapZone.enabledZones(
                    from: UserDefaults.standard.string(
                        forKey: DefaultsKey.windowEdgeSnapDisabledZones)
                ).isEmpty
            let pointerTapRuns = UserDefaults.standard.bool(forKey: DefaultsKey.windowGestureEnabled)
                || edgeSnapRuns
            let modifierTapRuns = UserDefaults.standard.bool(forKey: DefaultsKey.windowDirectionalEnabled)
                && UserDefaults.standard.string(forKey: DefaultsKey.windowDirectionalShortcut)
                    .flatMap(WindowDirectionalTrigger.init(storageValue:))
                    .map { if case .modifiers = $0 { return true }; return false } == true
            if modifierTapRuns { return .inputs }
            return pointerTapRuns ? .pointer : .idle
        case .radialMenu:
            return RadialMenuSupport.opensFromMouseOrTrackpad(
                UserDefaults.standard.data(forKey: DefaultsKey.radialMenuProfiles))
                ? .mouse : .idle
        case .notchNotifications, .notchGestures, .notchTimer, .notchQueue, .notchDownloads: return .idle
        case .notchWatch: return .idle
        case .notchMascot: return .periodic
        case .notchAccessories: return .periodic
        case .notch, .notchCalendar, .notchLyrics, .notchLiveEqualizer, .notchAgents: return .periodic
        case .clipboardHistory, .urlCleaner, .extraBrightness,
             .monitorCPU, .monitorGPU, .monitorMemory,
             .monitorNetwork, .monitorDisk, .monitorPower, .connectedDevices:
            return .periodic
        case .mixer:
            return UserDefaults.standard.bool(forKey: DefaultsKey.preciseVolumeRollerEnabled)
                ? .keyboard : .idle
        case .brightness:
            let defaults = UserDefaults.standard
            return defaults.bool(forKey: DefaultsKey.brightnessKeysEnabled)
                || defaults.bool(forKey: DefaultsKey.brightnessOSDEnabled)
                || BrightnessSupport.KeyStep.sanitized(
                    defaults.string(forKey: DefaultsKey.brightnessKeyStep)) != .standard
                ? .keyboard : .idle
        case .mouseAcceleration, .spacesOrder, .pastePlain, .soundOutputSwitcher, .audioPriority, .micMute,
             .bluetoothSleep, .keepAwake, .quickLauncher, .quickToggles, .quitApps, .colorPicker,
             .screenOCR, .cleaningMode, .mediaTools, .cleaner, .uninstaller, .homebrew, .screenshot,
             .cameraPreview, .scratchpad, .commandBar, .screenRecorder, .wallpaper, .fanControl,
             .diskImageInstaller, .killProcess, .portManager:
            return .idle
        case .appUpdates:
            return AppUpdatesSupport.CheckFrequency.sanitized(
                UserDefaults.standard.string(forKey: DefaultsKey.appUpdatesCheckFrequency)) == .off
                ? .idle : .periodic
        }
    }
}
