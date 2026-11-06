// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct FeatureHubStrings {
    let pageTitle: String
    let intro: String
    let tabFeatures: String
    let tabPermissions: String
    let activeCountFormat: String
    let monitorAllOffNote: String
    let titleDockClick: String
    let titleMouseNavigation: String
    let titleMusicBlock: String
    let titleAudioPriority: String
    let groupWindowsDock: String
    let groupMouseKeyboard: String
    let groupClipboardFiles: String
    let groupSound: String
    let groupEnergyDisplay: String
    let groupTools: String
    let groupMonitor: String
    let experimentalBadge: String
    let permissionsIntro: String
    let usedByFormat: String
    let usedByNone: String
    let unusedBanner: String
    let statusGranted: String
    let statusMissing: String
    let statusUnknown: String
    let requestButton: String
    let openSystemSettings: String
    let permAccessibility: String
    let permScreenRecording: String
    let permFullDisk: String
    let permFilesAndFolders: String
    let permNotifications: String
    let permAutomationFinder: String
    let permAudioCapture: String
    let explainAccessibility: String
    let explainScreenRecording: String
    let explainFullDisk: String
    let explainFilesAndFolders: String
    let explainNotifications: String
    let explainAutomationFinder: String
    let explainAudioCapture: String
    let descSwitcher: String
    let descDockPreview: String
    let descDockClick: String
    let descWindowMaximizer: String
    let descWindowLayout: String
    let descAutoQuit: String
    let descScrollInverter: String
    let descSmoothScroll: String
    let descMouseNavigation: String
    let descMiddleClick: String
    let descKeyboardDebounce: String
    let descClipboardHistory: String
    let descPastePlain: String
    let descFinderCutPaste: String
    let descShelf: String
    let descURLCleaner: String
    let descMixer: String
    let descSoundOutputSwitcher: String
    let descAudioPriority: String
    let descMicMute: String
    let descMusicBlock: String
    let descKeepAwake: String
    let descExtraBrightness: String
    let descQuickLauncher: String
    let descColorPicker: String
    let descScreenOCR: String
    let descCleaningMode: String
    let descMediaTools: String
    let descCleaner: String
    let descUninstaller: String
    let descHomebrew: String
    let descMonitorCPU: String
    let descMonitorGPU: String
    let descMonitorMemory: String
    let descMonitorNetwork: String
    let descMonitorDisk: String
    let descMonitorPower: String
    let footerNote: String
    let restartNote: String
    let restartButton: String
    let installButton: String
    let uninstallButton: String
    let installAllButton: String
    let uninstallAllButton: String
    let presetsTitle: String
    let presetsCaption: String
    let presetEssentialName: String
    let presetEssentialDesc: String
    let presetWindowsName: String
    let presetWindowsDesc: String
    let presetBatteryName: String
    let presetBatteryDesc: String
    let presetApplyButton: String
    let presetConfirmFormat: String
    let presetConfirmApply: String
    let presetConfirmCancel: String
    let energyIdle: String
    let energyMouse: String
    let energyPointer: String
    let energyKeyboard: String
    let energyInputs: String
    let energyPeriodic: String
    let energyHelp: String
    let explainAppManagement: String
    let onboardingSelectedPermissionsTitle: String
    let onboardingNoSelectedPermissions: String
    let onboardingOtherPermissionsTitle: String
    let onboardingOtherPermissionsCaption: String
    let notchUninstallTitle: String
    let notchUninstallMessageFormat: String
    let notchUninstallWithExtensions: String
    let notchUninstallKeepExtensions: String
    let neverUsedTitle: String
    let neverUsedMessageFormat: String
    let neverUsedUninstall: String
    let neverUsedKeep: String
}

extension FeatureStrings {
    static func hub(_ language: AppLanguage) -> FeatureHubStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension FeatureHubStrings {
}

extension FeatureHubStrings {
    static let enUS = FeatureHubStrings(
        pageTitle: "Features",
        intro: "Install only what you use. Whatever you uninstall disappears from the whole app and stops loading.",
        tabFeatures: "Features",
        tabPermissions: "Permissions",
        activeCountFormat: "%1$d of %2$d features installed",
        monitorAllOffNote: "With everything off, the Monitor leaves the panel and the menu bar.",
        titleDockClick: "Dock clicks",
        titleMouseNavigation: "Side buttons",
        titleMusicBlock: "Music app blocker",
         titleAudioPriority: "Audio device priority",
        groupWindowsDock: "Windows and Dock",
        groupMouseKeyboard: "Mouse and keyboard",
        groupClipboardFiles: "Clipboard and files",
        groupSound: "Sound",
        groupEnergyDisplay: "Energy and display",
        groupTools: "Tools",
        groupMonitor: "System monitor",
        experimentalBadge: "Experimental",
        permissionsIntro: "What each permission does and which features use it. Other access is requested only when you use it.",
        usedByFormat: "Used by %@",
        usedByNone: "Nothing that is on uses this permission right now.",
        unusedBanner: "You granted this permission, but nothing that is on needs it. If you like, revoke it in System Settings.",
        statusGranted: "Granted",
        statusMissing: "Not granted",
        statusUnknown: "The app can’t check this one",
        requestButton: "Request",
        openSystemSettings: "Open System Settings",
        permAccessibility: "Accessibility",
        permScreenRecording: "Screen Recording",
        permFullDisk: "Full Disk Access",
        permFilesAndFolders: "Files & Folders",
        permNotifications: "Notifications",
        permAutomationFinder: "Finder automation",
        permAudioCapture: "App audio",
        explainAccessibility: "Lets features react to clicks and keys, and move windows.",
        explainScreenRecording: "Lets features show window thumbnails and read text on screen.",
        explainFullDisk: "Lets the cleaner and the uninstaller find leftover files everywhere.",
        explainFilesAndFolders: "Lets WhatsApp downloads cleanup and the experimental organizer inspect your Downloads folder.",
        explainNotifications: "Lets the app notify you about alerts you turned on.",
        explainAutomationFinder: "Lets the app ask Finder to move files for you.",
        explainAudioCapture: "Lets the mixer adjust each app’s volume, the Dynamic Island bars follow the music and screen recordings include the Mac’s sound.",
        descSwitcher: "Switch apps and windows with previews",
        descDockPreview: "Window previews when hovering the Dock",
        descDockClick: "Click a Dock icon to minimize or cycle windows",
        descWindowMaximizer: "The green button maximizes instead of full screen",
        descWindowLayout: "Arrange windows with keybinds or edge snapping, then adjust them by dragging",
        descAutoQuit: "Quit apps when their last window closes",
        descScrollInverter: "Invert the mouse wheel direction",
        descSmoothScroll: "Smooth, animated mouse scrolling",
        descMouseNavigation: "Side mouse buttons go back and forward",
        descMiddleClick: "Three finger click acts as a middle click",
        descKeyboardDebounce: "Ignore accidental double key presses",
        descClipboardHistory: "Keep a local history of what you copy",
        descPastePlain: "Paste text without formatting",
        descFinderCutPaste: "Cut and paste files in Finder",
        descShelf: "Drop files on the menu bar to hold them",
        descURLCleaner: "Copied links lose their tracking junk",
        descMixer: "Per-app volume, pinning and custom order",
        descSoundOutputSwitcher: "Cycle sound outputs with a keybind",
         descAudioPriority: "Automatically use your preferred audio devices",
        descMicMute: "Mute the microphone from anywhere",
        descMusicBlock: "Block music launches from detected media keys",
        descKeepAwake: "Keep the Mac awake on demand",
        descExtraBrightness: "Extra brightness on XDR displays",
        descQuickLauncher: "A floating panel with your favorite tools",
        descColorPicker: "Pick any color on screen",
        descScreenOCR: "Copy text or QR codes from anything on screen",
        descCleaningMode: "Lock keyboard and screen for cleaning",
        descMediaTools: "Compress videos, images and GIFs",
        descCleaner: "Clear caches and junk files",
        descUninstaller: "Remove apps and their leftovers",
        descHomebrew: "Keep Homebrew packages up to date",
        descMonitorCPU: "Processor usage and temperature",
        descMonitorGPU: "Graphics usage and temperature",
        descMonitorMemory: "Memory use and pressure",
        descMonitorNetwork: "Network speed and usage",
        descMonitorDisk: "Disk space and activity",
        descMonitorPower: "Battery, power and charging",
        footerNote: "Uninstalling deletes nothing: the feature just leaves the app and stops loading. Install it again anytime and everything returns as it was.",
        restartNote: "Features uninstalled in this session stay loaded until the app restarts. Restart to unload them from memory now.",
        restartButton: "Restart now",
        installButton: "Install",
        uninstallButton: "Uninstall",
        installAllButton: "Install all",
        uninstallAllButton: "Uninstall all",
        presetsTitle: "Start with a bundle",
        presetsCaption: "One click sets the app up for how you use your Mac. EVERYTHING else stays one click away.",
        presetEssentialName: "Essentials",
        presetEssentialDesc: "Volume mixer, system monitor and keep awake.",
        presetWindowsName: "Windows",
        presetWindowsDesc: "Window switcher, window layout and the Dock features.",
        presetBatteryName: "Battery and quiet",
        presetBatteryDesc: "A lean monitor with battery, memory and processor. Nothing listens to input.",
        presetApplyButton: "Apply",
        presetConfirmFormat: "Install the %1$@ bundle and uninstall the rest? Nothing is deleted, and everything comes back with one click.",
        presetConfirmApply: "Apply bundle",
        presetConfirmCancel: "Cancel",
        energyIdle: "Nothing at rest",
        energyMouse: "Listens to the mouse",
        energyPointer: "Listens to pointer input",
        energyKeyboard: "Listens to the keyboard",
        energyInputs: "Listens to mouse and keyboard",
        energyPeriodic: "Checks on an interval",
        energyHelp: "What the feature keeps alive while it is on. Uninstalled features load nothing at all.",
        explainAppManagement: "Lets updates replace or remove apps installed by the package manager.",
        onboardingSelectedPermissionsTitle: "Permissions for your choices",
        onboardingNoSelectedPermissions: "You do not need to grant any permission to finish setup.",
        onboardingOtherPermissionsTitle: "Other permissions",
        onboardingOtherPermissionsCaption: "Optional. Grant these now or later, when a feature needs them.",
        notchUninstallTitle: "Uninstall Dynamic Island",
        notchUninstallMessageFormat: "These extensions only work inside the Dynamic Island: %@. Uninstall them too? Nothing is deleted, and everything comes back with one click.",
        notchUninstallWithExtensions: "Uninstall extensions too",
        notchUninstallKeepExtensions: "Keep extensions",
        neverUsedTitle: "Never turned on",
        neverUsedMessageFormat: "These features are installed but have never been on: %@. Uninstalling them makes the panel and Settings shorter. Nothing is deleted, and each one comes back with one click.",
        neverUsedUninstall: "Uninstall these",
        neverUsedKeep: "Keep them"
    )

}

extension FeatureHubStrings {
}
