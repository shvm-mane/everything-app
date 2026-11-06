// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AppFeature: String, CaseIterable {
    case switcher, dockPreview, dockClick, windowMaximizer, windowLayout, autoQuit, spacesOrder
    case scrollInverter, scrollHorizontal, scrollZoom, focusFollowsMouse, smoothScroll, linearScroll, mouseAcceleration, mouseNavigation, mouseButtonShortcuts, middleClick,
         mouseClickDebounce, keyboardDebounce, textSnippets, superKey, quitWindowProtection
    case clipboardHistory, pastePlain, finderCutPaste, finderRename, shelf, urlCleaner,
         diskImageInstaller
    case mixer, soundOutputSwitcher, audioPriority, micMute, musicBlock
    case keepAwake, brightness, extraBrightness, bluetoothSleep
    case quickLauncher, quickToggles, quitApps, colorPicker, screenOCR, cleaningMode, mediaTools,
         cleaner, uninstaller, homebrew, appUpdates, screenshot, cameraPreview, radialMenu, scratchpad,
         commandBar, screenRecorder, wallpaper, killProcess, portManager
    case notch, notchCalendar, notchNotifications, notchGestures, notchTimer, notchAccessories, notchLyrics,
         notchQueue, notchLiveEqualizer, notchDownloads, notchAgents, notchWatch, notchMascot
    case monitorCPU, monitorGPU, monitorMemory, monitorNetwork, monitorDisk, monitorPower, connectedDevices, fanControl
}

enum FeatureGroup: String, CaseIterable {
    case windowsDock, mouseKeyboard, clipboardFiles, sound, energyDisplay, tools, dynamicIsland, monitor
}

enum AppPermission: String, CaseIterable {
    case accessibility, screenRecording, fullDiskAccess, filesAndFolders, notifications,
         automationFinder, automationPlayback, audioCapture, microphone, camera, appManagement, calendar
}

enum PermissionPollingSupport {
    static func interval(visibleSurfaceCount: Int,
                         accessibilityIsNeeded: Bool,
                         screenRecordingIsNeeded: Bool,
                         accessibilityIsGranted: Bool,
                         screenRecordingIsGranted: Bool) -> TimeInterval? {
        guard visibleSurfaceCount > 0 || accessibilityIsNeeded || screenRecordingIsNeeded else {
            return nil
        }
        if visibleSurfaceCount > 0
            || (accessibilityIsNeeded && !accessibilityIsGranted)
            || (screenRecordingIsNeeded && !screenRecordingIsGranted) {
            return 2.5
        }
        return 60
    }
}

extension AppFeature {
    func monitorsPermissionChanges(edgeSnapDisabledZones: String? = nil,
                                   boolFor: (String) -> Bool) -> Bool {
        switch self {
        case .windowLayout:
            return boolFor(DefaultsKey.windowLayoutShortcutsEnabled)
                || boolFor(DefaultsKey.windowGestureEnabled)
                || (boolFor(DefaultsKey.windowEdgeSnapEnabled)
                    && !WindowEdgeSnapZone.enabledZones(
                        from: edgeSnapDisabledZones
                    ).isEmpty)
        case .screenOCR, .cleaningMode, .screenshot, .commandBar, .screenRecorder, .wallpaper, .notchWatch,
             .notchMascot:
            return false
        default:
            return true
        }
    }

    var monitorsPermissionChanges: Bool {
        monitorsPermissionChanges(
            edgeSnapDisabledZones: UserDefaults.standard.string(
                forKey: DefaultsKey.windowEdgeSnapDisabledZones
            ),
            boolFor: UserDefaults.standard.bool(forKey:)
        )
    }

    var group: FeatureGroup {
        switch self {
        case .switcher, .dockPreview, .dockClick, .windowMaximizer, .windowLayout, .autoQuit, .spacesOrder:
            return .windowsDock
        case .scrollInverter, .scrollHorizontal, .scrollZoom, .focusFollowsMouse, .smoothScroll, .linearScroll, .mouseAcceleration, .mouseNavigation, .mouseButtonShortcuts, .middleClick,
             .keyboardDebounce, .textSnippets, .superKey, .quitWindowProtection, .mouseClickDebounce:
            return .mouseKeyboard
        case .clipboardHistory, .pastePlain, .finderCutPaste, .finderRename, .shelf, .urlCleaner,
             .diskImageInstaller:
            return .clipboardFiles
        case .mixer, .soundOutputSwitcher, .audioPriority, .micMute, .musicBlock:
            return .sound
        case .keepAwake, .brightness, .extraBrightness, .bluetoothSleep:
            return .energyDisplay
        case .quickLauncher, .quickToggles, .quitApps, .colorPicker, .screenOCR, .cleaningMode, .mediaTools,
             .cleaner, .uninstaller, .homebrew, .appUpdates, .screenshot, .cameraPreview, .radialMenu,
             .scratchpad, .commandBar, .screenRecorder, .wallpaper, .killProcess, .portManager:
            return .tools
        case .notch, .notchCalendar, .notchNotifications, .notchGestures, .notchTimer, .notchAccessories,
             .notchLyrics, .notchQueue, .notchLiveEqualizer, .notchDownloads, .notchAgents, .notchWatch,
             .notchMascot:
            return .dynamicIsland
        case .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower,
             .connectedDevices, .fanControl:
            return .monitor
        }
    }

    var symbolName: String {
        switch self {
        case .switcher: return "rectangle.on.rectangle"
        case .dockPreview: return "dock.rectangle"
        case .dockClick: return "dock.arrow.down.rectangle"
        case .windowMaximizer: return "arrow.up.left.and.arrow.down.right"
        case .windowLayout: return "rectangle.3.group"
        case .autoQuit: return "xmark.rectangle"
        case .spacesOrder: return "rectangle.split.3x1"
        case .scrollInverter: return "arrow.up.arrow.down"
        case .scrollHorizontal: return "arrow.triangle.swap"
        case .scrollZoom: return "plus.magnifyingglass"
        case .focusFollowsMouse: return "cursorarrow.and.square.on.square.dashed"
        case .smoothScroll: return "cursorarrow.motionlines"
        case .linearScroll: return "arrow.up.and.down.text.horizontal"
        case .mouseAcceleration: return "cursorarrow.rays"
        case .mouseNavigation: return "arrow.left.arrow.right"
        case .mouseButtonShortcuts: return "button.programmable"
        case .middleClick: return "hand.tap"
        case .keyboardDebounce: return "keyboard"
        case .textSnippets: return "text.append"
        case .superKey:
            return SuperKeySource.sanitized(
                UserDefaults.standard.string(forKey: DefaultsKey.superKeySource)
            ).systemImage
        case .mouseClickDebounce: return "cursorarrow.click"
        case .quitWindowProtection: return "shield.lefthalf.filled"
        case .clipboardHistory: return "doc.on.clipboard"
        case .pastePlain: return "doc.plaintext"
        case .finderCutPaste: return "scissors"
        case .finderRename: return "pencil"
        case .shelf: return "tray.full"
        case .urlCleaner: return "link"
        case .diskImageInstaller: return "externaldrive.badge.plus"
        case .mixer: return "speaker.wave.2"
        case .soundOutputSwitcher: return "hifispeaker"
        case .audioPriority: return "list.number"
        case .micMute: return "mic.slash"
        case .musicBlock: return "music.note"
        case .keepAwake: return "moon.zzz.fill"
        case .brightness: return "display.2"
        case .extraBrightness: return "sun.max.fill"
        case .bluetoothSleep: return "wave.3.right.circle"
        case .quickLauncher: return "wand.and.rays"
        case .quickToggles: return "togglepower"
        case .quitApps: return "xmark.app"
        case .colorPicker: return "eyedropper"
        case .screenOCR: return "text.viewfinder"
        case .cleaningMode: return "bubbles.and.sparkles"
        case .mediaTools: return "photo.on.rectangle.angled"
        case .cleaner: return "sparkles"
        case .uninstaller: return "trash"
        case .homebrew: return "shippingbox"
        case .appUpdates: return "arrow.down.app"
        case .screenshot: return "camera.viewfinder"
        case .screenRecorder: return "record.circle"
        case .cameraPreview: return "web.camera"
        case .wallpaper: return "photo.on.rectangle"
        case .notchGestures: return "hand.draw"
        case .notchTimer: return "timer"
        case .notchAccessories: return "battery.25percent"
        case .notchLyrics: return "quote.bubble"
        case .notchQueue: return "list.bullet"
        case .notchLiveEqualizer: return "waveform"
        case .notchDownloads: return "arrow.down.circle"
        case .notchNotifications: return "bell"
        case .notchCalendar: return "calendar"
        case .notchAgents: return "sparkles"
        case .notchWatch: return "eye"
        case .notchMascot: return "face.smiling"
        case .notch: return "macbook"
        case .radialMenu: return "circle.grid.cross"
        case .scratchpad: return "note.text"
        case .commandBar: return "command"
        case .killProcess: return "xmark.octagon"
        case .portManager: return "network"
        case .monitorCPU: return "cpu"
        case .monitorGPU: return "rectangle.connected.to.line.below"
        case .monitorMemory: return "memorychip"
        case .monitorNetwork: return "network"
        case .monitorDisk: return "internaldrive"
        case .monitorPower: return "bolt.fill"
        case .connectedDevices: return "cable.connector"
        case .fanControl: return "fanblades.fill"
        }
    }

    var availabilityKey: String { DefaultsKey.featureAvailable(rawValue) }

    var isBeta: Bool { self == .fanControl || self == .killProcess }

    var isAvailable: Bool {
        isAvailable(in: .standard)
    }

    static let everythingFeatures: Set<AppFeature> = [
        .notch, .notchAgents, .scratchpad,
        .mixer, .brightness, .diskImageInstaller,
        .colorPicker, .radialMenu,
    ]

    func isAvailable(in defaults: UserDefaults) -> Bool {
        Self.everythingFeatures.contains(self)
    }

    var enabledKeys: [String] {
        switch self {
        case .switcher: return [DefaultsKey.switcherEnabled]
        case .dockPreview: return [DefaultsKey.dockPreviewEnabled]
        case .dockClick: return [DefaultsKey.dockClickMinimize,
                                 DefaultsKey.dockClickHide,
                                 DefaultsKey.dockClickCycleWindows]
        case .windowMaximizer: return [DefaultsKey.windowMaximizeEnabled]
        case .autoQuit: return [DefaultsKey.autoQuitEnabled]
        case .spacesOrder: return [DefaultsKey.spacesOrderEnabled]
        case .scrollInverter: return [DefaultsKey.scrollInverterEnabled,
                                      DefaultsKey.scrollInverterHorizontalEnabled]
        case .scrollHorizontal: return [DefaultsKey.scrollHorizontalEnabled]
        case .scrollZoom: return [DefaultsKey.pinchZoomEnabled]
        case .focusFollowsMouse: return [DefaultsKey.focusFollowsMouseEnabled]
        case .smoothScroll: return [DefaultsKey.smoothScrollEnabled]
        case .linearScroll: return [DefaultsKey.linearScrollEnabled]
        case .mouseAcceleration: return [DefaultsKey.mouseAccelerationDisabled]
        case .mouseNavigation: return [DefaultsKey.mouseNavigationEnabled]
        case .mouseButtonShortcuts: return [DefaultsKey.mouseButtonShortcutsEnabled,
                                            DefaultsKey.mouseSpacesGestureEnabled]
        case .middleClick: return [DefaultsKey.middleClickEnabled]
        case .keyboardDebounce: return [DefaultsKey.keyboardDebounceEnabled]
        case .quitWindowProtection:
            return [DefaultsKey.quitProtectionQuitEnabled, DefaultsKey.quitProtectionCloseEnabled]
        case .textSnippets: return [DefaultsKey.textSnippetsEnabled, DefaultsKey.snippetLibraryEnabled]
        case .superKey: return [DefaultsKey.superKeyEnabled]
        case .mouseClickDebounce: return [DefaultsKey.mouseClickDebounceEnabled]
        case .notchGestures: return [DefaultsKey.notchGesturesEnabled]
        case .notchTimer: return [DefaultsKey.notchTimerEnabled]
        case .notchAccessories: return [DefaultsKey.notchAccessoriesEnabled]
        case .notchLyrics: return [DefaultsKey.notchLyricsEnabled]
        case .notchQueue: return [DefaultsKey.notchQueueEnabled]
        case .notchLiveEqualizer: return [DefaultsKey.notchLiveEqualizer]
        case .notchDownloads: return [DefaultsKey.notchDownloadsEnabled]
        case .notchNotifications: return [DefaultsKey.notchNotificationsEnabled]
        case .notchCalendar: return [DefaultsKey.notchCalendarEnabled]
        case .notchAgents: return [DefaultsKey.notchAgentsEnabled]
        case .notchWatch: return [DefaultsKey.notchWatchEnabled]
        case .notchMascot: return [DefaultsKey.notchMascotEnabled]
        case .notch: return [DefaultsKey.notchEnabled]
        case .radialMenu: return [DefaultsKey.radialMenuEnabled]
        case .clipboardHistory: return [DefaultsKey.clipboardHistoryEnabled]
        case .pastePlain: return [DefaultsKey.pastePlainEnabled]
        case .finderCutPaste: return [DefaultsKey.finderCutPasteEnabled,
                                      DefaultsKey.finderPasteImageAsFile]
        case .finderRename: return [DefaultsKey.finderRenameEnabled]
        case .shelf: return [DefaultsKey.shelfEnabled]
        case .urlCleaner: return [DefaultsKey.urlCleanerEnabled]
        case .soundOutputSwitcher: return [DefaultsKey.soundOutputSwitcherEnabled]
        case .audioPriority: return [DefaultsKey.audioPriorityOutputEnabled,
                                     DefaultsKey.audioPriorityInputEnabled]
        case .musicBlock: return [DefaultsKey.musicBlockEnabled]
        case .brightness: return [DefaultsKey.brightnessControlEnabled]
        case .extraBrightness: return [DefaultsKey.extraBrightnessEnabled]
        case .bluetoothSleep: return [DefaultsKey.bluetoothSleepEnabled]
        case .windowLayout, .diskImageInstaller, .mixer, .micMute, .keepAwake,
             .quickLauncher, .quickToggles, .quitApps, .colorPicker, .screenOCR, .cleaningMode, .mediaTools,
             .cleaner, .uninstaller, .homebrew, .appUpdates, .screenshot, .cameraPreview, .scratchpad,
             .commandBar, .screenRecorder, .wallpaper, .killProcess, .portManager,
             .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower,
             .connectedDevices, .fanControl:
            return []
        }
    }

    private var initialEnableKeys: [String] {
        switch self {
        case .windowLayout: return [DefaultsKey.windowLayoutShortcutsEnabled]
        case .audioPriority: return enabledKeys
        case .notchLiveEqualizer: return []
        default: return enabledKeys.first.map { [$0] } ?? []
        }
    }

    func enableOnFirstInstall(in defaults: UserDefaults, savedValues: [String: Any]) {
        let choices = self == .windowLayout
            ? [DefaultsKey.windowLayoutShortcutsEnabled, DefaultsKey.windowDirectionalEnabled,
               DefaultsKey.pointerDisplayEnabled, DefaultsKey.windowEdgeSnapEnabled,
               DefaultsKey.windowGestureEnabled]
            : enabledKeys
        guard !choices.contains(where: { savedValues[$0] != nil }) else { return }
        for key in initialEnableKeys {
            defaults.set(true, forKey: key)
        }
    }

    var permissions: [AppPermission] {
        switch self {
        case .notchGestures: return []
        case .notchTimer, .notchAccessories: return []
        case .notchLyrics, .notchQueue: return []
        case .notchAgents: return []
        case .notchMascot: return []
        case .notchLiveEqualizer: return [.audioCapture]
        case .notchDownloads: return [.filesAndFolders]
        case .notchWatch: return [.screenRecording, .notifications]
        case .notchNotifications: return [.accessibility]
        case .notchCalendar: return [.calendar]
        case .notch: return [.accessibility, .automationPlayback]
        case .mouseAcceleration, .spacesOrder:
            return []
        case .scrollInverter, .scrollHorizontal, .scrollZoom, .focusFollowsMouse, .smoothScroll, .linearScroll, .mouseNavigation, .mouseButtonShortcuts, .middleClick,
             .keyboardDebounce, .textSnippets, .superKey, .mouseClickDebounce,
             .dockClick, .windowMaximizer, .windowLayout,
             .autoQuit, .quitWindowProtection, .cleaningMode, .pastePlain, .radialMenu,
             .commandBar:
            return [.accessibility]
        case .finderCutPaste: return [.accessibility, .automationFinder]
        case .finderRename: return [.accessibility]
        case .quickToggles: return [.automationFinder]
        case .switcher: return [.accessibility, .screenRecording]
        case .dockPreview: return [.accessibility, .screenRecording]
        case .screenOCR: return [.screenRecording]
        case .screenshot: return [.screenRecording]
        case .screenRecorder: return [.screenRecording, .accessibility, .audioCapture, .microphone]
        case .cameraPreview: return [.camera]
        case .keepAwake: return [.accessibility]
        case .brightness: return [.accessibility]
        case .cleaner: return [.fullDiskAccess, .filesAndFolders, .notifications]
        case .uninstaller: return [.fullDiskAccess, .automationFinder]
        case .homebrew: return [.appManagement]
        case .appUpdates: return [.notifications, .appManagement]
        case .diskImageInstaller: return [.appManagement]
        case .mixer: return [.audioCapture, .accessibility]
        case .musicBlock: return [.accessibility]
        case .monitorCPU, .monitorMemory, .monitorDisk, .monitorPower: return [.notifications]
        case .clipboardHistory, .shelf, .urlCleaner,
             .soundOutputSwitcher, .audioPriority,
             .extraBrightness, .bluetoothSleep, .quickLauncher, .colorPicker, .micMute, .mediaTools,
             .scratchpad, .wallpaper, .monitorGPU, .monitorNetwork, .connectedDevices, .fanControl, .killProcess,
             .portManager,
             .quitApps:
            return []
        }
    }

    var onboardingPermissions: [AppPermission] {
        switch self {
        case .keepAwake, .brightness, .radialMenu, .quickToggles, .cleaner,
             .uninstaller, .homebrew, .appUpdates, .mixer, .cameraPreview,
             .micMute, .musicBlock, .notchWatch:
            return []
        default:
            return permissions.filter { $0 == .accessibility || $0 == .screenRecording }
        }
    }

    static func features(in group: FeatureGroup) -> [AppFeature] {
        allCases.filter { $0.group == group }
    }

    static var dynamicIslandExtensions: [AppFeature] {
        features(in: .dynamicIsland).filter { $0 != .notch }
    }

    static var dynamicIslandInitialExtensions: [AppFeature] {
        dynamicIslandExtensions.filter { $0 != .notchMascot && $0 != .notchAgents }
    }

    var initialInstallGroup: [AppFeature] {
        self == .notch ? [self] + Self.dynamicIslandInitialExtensions : [self]
    }

    static let offeredWhenNeverSwitchedOn: [AppFeature] = [
        .dockPreview, .dockClick, .windowMaximizer, .autoQuit,
        .scrollInverter, .linearScroll, .focusFollowsMouse, .mouseAcceleration, .mouseNavigation,
        .mouseButtonShortcuts, .middleClick, .keyboardDebounce, .mouseClickDebounce, .superKey,
        .finderCutPaste,
    ]

    static func neverSwitchedOn(isAvailable: (AppFeature) -> Bool,
                                boolFor: (String) -> Bool,
                                isSaved: (String) -> Bool) -> [AppFeature] {
        offeredWhenNeverSwitchedOn.filter { feature in
            isAvailable(feature)
                && !feature.enabledKeys.isEmpty
                && !feature.enabledKeys.contains(where: boolFor)
                && !feature.enabledKeys.contains { isSaved($0) && !savedOnEveryMac.contains($0) }
        }
    }

    private static let savedOnEveryMac: Set<String> = [DefaultsKey.scrollInverterHorizontalEnabled]

    var installedByDefault: Bool {
        switch self {
        case .switcher, .dockPreview, .dockClick, .windowMaximizer, .windowLayout, .autoQuit,
             .scrollInverter, .smoothScroll, .mouseAcceleration, .mouseNavigation, .mouseButtonShortcuts,
             .middleClick, .mouseClickDebounce, .keyboardDebounce, .textSnippets, .superKey,
             .quitWindowProtection,
             .clipboardHistory, .pastePlain, .finderCutPaste, .finderRename, .shelf, .urlCleaner,
             .mixer, .soundOutputSwitcher, .micMute, .musicBlock,
             .keepAwake, .brightness, .extraBrightness, .bluetoothSleep,
             .quickLauncher, .quickToggles, .colorPicker, .screenOCR, .cleaningMode, .mediaTools,
             .cleaner, .uninstaller, .homebrew, .appUpdates, .screenshot, .cameraPreview, .radialMenu,
             .scratchpad, .commandBar, .screenRecorder,
             .notch, .notchCalendar, .notchNotifications, .notchGestures, .notchTimer, .notchAccessories,
             .notchLyrics, .notchQueue, .notchLiveEqualizer, .notchDownloads, .notchAgents, .notchWatch,
             .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower,
             .connectedDevices:
            return true
        case .focusFollowsMouse, .scrollHorizontal, .scrollZoom, .linearScroll, .diskImageInstaller, .audioPriority,
             .wallpaper, .killProcess, .portManager, .fanControl, .notchMascot, .spacesOrder, .quitApps:
            return false
        }
    }

    static var availabilityDefaults: [String: Any] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.availabilityKey, $0.installedByDefault) })
    }

    static func activeFeatures(using permission: AppPermission,
                               isAvailable: (AppFeature) -> Bool,
                               boolFor: (String) -> Bool,
                               stringFor: (String) -> String?,
                               dataFor: (String) -> Data? = { _ in nil }) -> [AppFeature] {
        allCases.filter { feature in
            guard feature.permissions.contains(permission), isAvailable(feature) else { return false }
            let keys = feature.enabledKeys
            guard keys.isEmpty || keys.contains(where: boolFor) else { return false }
            switch (feature, permission) {
            case (.notch, .automationPlayback):
                return !(stringFor(DefaultsKey.notchHiddenModules) ?? "").split(separator: ",").contains("music")
            case (.switcher, .screenRecording):
                return !boolFor(DefaultsKey.switcherSimpleMode)
            case (.notchWatch, .screenRecording):
                return isAvailable(.notch) && boolFor(DefaultsKey.notchEnabled)
                    && !(stringFor(DefaultsKey.notchHiddenModules) ?? "").split(separator: ",").contains("watch")
            case (.notchNotifications, .accessibility):
                return isAvailable(.notch) && boolFor(DefaultsKey.notchEnabled)
                    && !(stringFor(DefaultsKey.notchHiddenModules) ?? "").split(separator: ",").contains("notifications")
            case (.notchDownloads, .filesAndFolders):
                return isAvailable(.notch) && boolFor(DefaultsKey.notchEnabled)
                    && dataFor(DefaultsKey.notchDownloadsFolderBookmark) != nil
                    && !(stringFor(DefaultsKey.notchHiddenModules) ?? "").split(separator: ",").contains("downloads")
            case (.notchCalendar, .calendar):
                return isAvailable(.notch) && boolFor(DefaultsKey.notchEnabled)
                    && !(stringFor(DefaultsKey.notchHiddenModules) ?? "").split(separator: ",").contains("calendar")
            case (.notch, .accessibility):
                return (boolFor(DefaultsKey.notchVolume) && isAvailable(.mixer))
                    || (boolFor(DefaultsKey.notchKeyboardLight) && isAvailable(.brightness))
                    || (boolFor(DefaultsKey.notchBrightness) && isAvailable(.brightness)
                        && boolFor(DefaultsKey.brightnessControlEnabled))
                    || (boolFor(DefaultsKey.notchClipboardWindow) && isAvailable(.clipboardHistory))
            case (.radialMenu, .accessibility):
                if let profiles = dataFor(DefaultsKey.radialMenuProfiles) {
                    return RadialMenuSupport.needsAccessibility(RadialMenuSupport.decodeProfiles(profiles))
                }
                return RadialMenuSupport.needsAccessibility(
                    RadialMenuSupport.decode(dataFor(DefaultsKey.radialMenuItems)))
                    || RadialMenuMouseTrigger.sanitized(
                        stringFor(DefaultsKey.radialMenuMouseButton)) != .off
            case (.keepAwake, .accessibility):
                return boolFor(DefaultsKey.keepAwakeMouseJiggleEnabled)
            case (.mixer, .accessibility):
                return boolFor(DefaultsKey.preciseVolumeRollerEnabled)
            case (.brightness, .accessibility):
                return boolFor(DefaultsKey.brightnessKeysEnabled)
                    || boolFor(DefaultsKey.brightnessOSDEnabled)
                    || BrightnessSupport.KeyStep.sanitized(stringFor(DefaultsKey.brightnessKeyStep)) != .standard
            case (.monitorCPU, .notifications):
                return boolFor(DefaultsKey.monitorAlertCPU) || boolFor(DefaultsKey.monitorAlertCPUTemperature)
            case (.monitorMemory, .notifications):
                return boolFor(DefaultsKey.monitorAlertMemory)
            case (.monitorDisk, .notifications):
                return boolFor(DefaultsKey.monitorAlertDisk)
            case (.monitorPower, .notifications):
                return boolFor(DefaultsKey.monitorAlertBattery)
                    || boolFor(DefaultsKey.monitorAlertBatteryTemperature)
            case (.appUpdates, .notifications):
                return AppUpdatesSupport.CheckFrequency
                    .sanitized(stringFor(DefaultsKey.appUpdatesCheckFrequency)) != .off
                    && boolFor(DefaultsKey.appUpdatesNotify)
            case (.cleaner, .filesAndFolders):
                return boolFor(DefaultsKey.whatsAppDownloadsEnabled)
            case (.cleaner, .notifications):
                let cleanerNotifies = (stringFor(DefaultsKey.cleanerScheduleFrequency) ?? "off") != "off"
                    && boolFor(DefaultsKey.cleanerScheduleNotify)
                let whatsAppNotifies = boolFor(DefaultsKey.whatsAppDownloadsEnabled)
                    && (boolFor(DefaultsKey.whatsAppDownloadsAutomaticEnabled)
                        || boolFor(DefaultsKey.whatsAppOrganizerEnabled))
                    && boolFor(DefaultsKey.whatsAppDownloadsNotify)
                return cleanerNotifies || whatsAppNotifies
            case (.notchLiveEqualizer, .audioCapture):
                return isAvailable(.notch) && boolFor(DefaultsKey.notchEnabled)
                    && !(stringFor(DefaultsKey.notchHiddenModules) ?? "").split(separator: ",").contains("music")
            case (.screenRecorder, .audioCapture):
                return boolFor(DefaultsKey.recorderSystemAudio)
            case (.screenRecorder, .microphone):
                return boolFor(DefaultsKey.recorderMicrophone)
            default:
                return true
            }
        }
    }

    static let monitorAlertPairs: [(key: String, feature: AppFeature)] = [
        (DefaultsKey.monitorAlertCPU, .monitorCPU),
        (DefaultsKey.monitorAlertCPUTemperature, .monitorCPU),
        (DefaultsKey.monitorAlertBatteryTemperature, .monitorPower),
        (DefaultsKey.monitorAlertMemory, .monitorMemory),
        (DefaultsKey.monitorAlertDisk, .monitorDisk),
        (DefaultsKey.monitorAlertBattery, .monitorPower),
    ]

    static func anyMonitorAlertEnabled(isAvailable: (AppFeature) -> Bool,
                                       boolFor: (String) -> Bool) -> Bool {
        monitorAlertPairs.contains { boolFor($0.key) && isAvailable($0.feature) }
    }

    static func activeFeatures(using permission: AppPermission,
                               defaults: UserDefaults = .standard) -> [AppFeature] {
        activeFeatures(using: permission,
                       isAvailable: { defaults.bool(forKey: $0.availabilityKey) },
                       boolFor: { defaults.bool(forKey: $0) },
                       stringFor: { defaults.string(forKey: $0) },
                       dataFor: { defaults.data(forKey: $0) })
    }
}

extension AppPermission {
    var symbolName: String {
        switch self {
        case .accessibility: return "accessibility"
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .fullDiskAccess: return "externaldrive.badge.person.crop"
        case .filesAndFolders: return "folder.badge.person.crop"
        case .notifications: return "bell.badge"
        case .automationFinder, .automationPlayback: return "gearshape.2"
        case .audioCapture: return "waveform"
        case .microphone: return "mic"
        case .calendar: return "calendar"
        case .camera: return "camera"
        case .appManagement: return "app.badge"
        }
    }
}
