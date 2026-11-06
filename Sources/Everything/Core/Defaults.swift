// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Carbon.HIToolbox
import Foundation

enum DefaultsKey {
    static let language = "appLanguage"
    static let appearance = "appAppearance"
    static let liquidGlassEnabled = "liquidGlassEnabled"
    static let notchLiquidGlassEnabled = "notchLiquidGlassEnabled"
    static let clamshellPreferred = "clamshellPreferred"
    static let dimScreenOnLidClose = "dimScreenOnLidClose"
    static let onboardingStep = "onboardingStep"
    static let featuresOnboardingVersion = "featuresOnboardingVersion"
    static let lastUpdateIntroVersion = "lastUpdateIntroVersion"
    static let supportUpdateIntroVersion = "supportUpdateIntroVersion"
    static let updateHighlightsSeenVersion = "updateHighlightsSeenVersion"
    static let featureHubKeptFeatures = "featureHubKeptFeatures"
    static let brightnessUpdatePromptState = "brightnessUpdatePromptState"
    static let updateShowcaseIntroVersion = "updateShowcaseIntroVersion"
    static let updateShowcaseMediaOverride = "updateShowcaseMediaOverride"
    static let defaultDuration = "defaultDurationMinutes"
    static let batteryLimit = "batteryLimitPercent"
    static let keepAwakeAutoStart = "keepAwakeAutoStart"
    static let keepAwakeRightClickToggle = "keepAwakeRightClickToggle"
    static let keepAwakeAllowDisplaySleep = "keepAwakeAllowDisplaySleep"
    static let keepAwakeExternalDisplay = "keepAwakeExternalDisplay"
    static let keepAwakeConnectedToPower = "keepAwakeConnectedToPower"
    static let keepAwakeRunningApps = "keepAwakeRunningApps"
    static let keepAwakeRunningAppBundleIDs = "keepAwakeRunningAppBundleIDs"
    static let keepAwakeAutomationRequireAll = "keepAwakeAutomationRequireAll"
    static let keepAwakePauseWhenLocked = "keepAwakePauseWhenLocked"
    static let keepAwakeSwitchUsesUntil = "keepAwakeSwitchUsesUntil"
    static let keepAwakeUntilTime = "keepAwakeUntilTime"
    static let keepAwakeMouseJiggleEnabled = "keepAwakeMouseJiggleEnabled"
    static let keepAwakeMouseJiggleInterval = "keepAwakeMouseJiggleIntervalMinutes"
    static let hotkeyEnabled = "hotkeyEnabled"
    static let launchAtLoginWanted = "launchAtLoginWanted"
    static let keepAwakeShortcut = "keepAwakeShortcut"
    static let keepAwakeIconTint = "keepAwakeIconTint"
    static let keepAwakeActiveIcon = "keepAwakeActiveIcon"
    static let showCountdown = "showCountdownInMenuBar"
    static let statusItemPlacementGeneration = "statusItemPlacementGeneration"
    static let hasOnboarded = "hasOnboarded"
    static let sleepDisabledFlag = "vorssDisabledSleep"
    static let dimmedDisplaySavedBrightness = "vorssDimmedDisplaySavedBrightness"
    static let scrollInverterEnabled = "scrollInverterEnabled"
    static let scrollInverterHorizontalEnabled = "scrollInverterHorizontalEnabled"
    static let scrollHorizontalEnabled = "scrollHorizontalEnabled"
    static let scrollHorizontalModifier = "scrollHorizontalModifier"
    static let pinchZoomEnabled = "pinchZoomEnabled"
    static let pinchZoomModifier = "pinchZoomModifier"
    static let focusFollowsMouseEnabled = "focusFollowsMouseEnabled"
    static let focusFollowsMouseDelay = "focusFollowsMouseDelayMilliseconds"
    static let focusFollowsMouseRaise = "focusFollowsMouseRaise"
    static let focusFollowsMouseWaitForStop = "focusFollowsMouseWaitForStop"
    static let focusFollowsMouseExceptions = "focusFollowsMouseExceptions"
    static let smoothScrollEnabled = "smoothScrollEnabled"
    static let smoothScrollStep = "smoothScrollStep"
    static let linearScrollEnabled = "linearScrollEnabled"
    static let linearScrollLines = "linearScrollLines"
    static let mouseAccelerationDisabled = "mouseAccelerationDisabled"
    static let smoothScrollResponse = "smoothScrollResponse"
    static let smoothScrollCoast = "smoothScrollCoast"
    static let mouseNavigationEnabled = "mouseNavigationEnabled"
    static let mouseButtonShortcutsEnabled = "mouseButtonShortcutsEnabled"
    static let mouseButtonShortcuts = "mouseButtonShortcuts"
    static let mouseSpacesGestureEnabled = "mouseSpacesGestureEnabled"
    static let mouseSpacesGestureButton = "mouseSpacesGestureButton"
    static let mouseSpacesGestureFollowsDrag = "mouseSpacesGestureFollowsDrag"
    static let mouseClickDebounceEnabled = "mouseClickDebounceEnabled"
    static let mouseClickDebounceWindowMs = "mouseClickDebounceWindowMs"
    static let superKeyEnabled = "superKeyEnabled"
    static let superKeySource = "superKeySource"
    static let superKeyModifiers = "superKeyModifiers"
    static let superKeySoloAction = "superKeySoloAction"
    static let superKeyMappingApplied = "superKeyMappingApplied"
    static let superKeyMappedSource = "superKeyMappedSource"
    static let smoothScrollExceptions = "smoothScrollExceptions"
    static let linearScrollExceptions = "linearScrollExceptions"
    static let scrollInverterExceptions = "scrollInverterExceptions"
    static let mouseNavigationExceptions = "mouseNavigationExceptions"
    static let mouseButtonExceptions = "mouseButtonExceptions"
    static let middleClickExceptions = "middleClickExceptions"
    static let superKeyExceptions = "superKeyExceptions"
    static let switcherEnabled = "switcherEnabled"
    static let switcherTakeOverSystemShortcuts = "switcherTakeOverSystemShortcuts"
    static let switcherNativeHotkeysSuppressed = "switcherNativeHotkeysSuppressed"
    static let systemShortcutsSuppressed = "systemShortcutsSuppressed"
    static let systemShortcutTakeOverKeys = "systemShortcutTakeOverKeys"
    static let switcherShortcut = "switcherShortcut"
    static let switcherWindowShortcut = "switcherWindowShortcut"
    static let switcherAllWindowsShortcut = "switcherAllWindowsShortcut"
    static let switcherAllWindowsShortcutEnabled = "switcherAllWindowsShortcutEnabled"
    static let switcherIconRowMode = "switcherIconRowMode"
    static let switcherSimpleMode = "switcherSimpleMode"
    static let switcherMergeTabs = "switcherMergeTabs"
    static let switcherShowWindowlessFinder = "switcherShowWindowlessFinder"
    static let switcherWindowlessApps = "switcherWindowlessApps"
    static let switcherMinimizedPlacement = "switcherMinimizedPlacement"
    static let switcherTreatHiddenAppsLikeMinimized = "switcherTreatHiddenAppsLikeMinimized"
    static let switcherShowFullscreenWindows = "switcherShowFullscreenWindows"
    static let switcherAppRules = "switcherAppRules"
    static let switcherCurrentSpaceOnly = "switcherCurrentSpaceOnly"
    static let switcherSearchPinEnabled = "switcherSearchPinEnabled"
    static let switcherShowShortcutHints = "switcherShowShortcutHints"
    static let switcherAppearanceDelay = "switcherAppearanceDelay"
    static let switcherInstantSelection = "switcherInstantSelection"
    static let switcherScreenPlacement = "switcherScreenPlacement"
    static let switcherCurrentDisplayOnly = "switcherCurrentDisplayOnly"
    static let switcherMaxColumns = "switcherMaxColumns"
    static let minimalWindowPreviews = "minimalWindowPreviews"
    static let dockPreviewEnabled = "dockPreviewEnabled"
    static let dockPreviewKeepDockVisible = "dockPreviewKeepDockVisible"
    static let dockPreviewRestoreAutohide = "dockPreviewRestoreAutohide"
    static let dockPreviewCurrentSpaceOnly = "dockPreviewCurrentSpaceOnly"
    static let dockPreviewBackgroundOpacity = "dockPreviewBackgroundOpacity"
    static let dockPreviewOpenDelay = "dockPreviewOpenDelay"
    static let dockPreviewQuitAppOnClose = "dockPreviewQuitAppOnClose"
    static let dockPreviewOrderByCreation = "dockPreviewOrderByCreation"
    static let dockClickMinimize = "dockClickMinimize"
    static let dockClickHide = "dockClickHide"
    static let dockClickCycleWindows = "dockClickCycleWindows"
    static let spacesOrderEnabled = "spacesOrderEnabled"
    static let spacesOrderRestore = "spacesOrderRestore"
    static let spacesOrderRestartPending = "spacesOrderRestartPending"
    static let middleClickEnabled = "middleClickEnabled"
    static let middleClickTapFingers = "middleClickTapFingers"
    static let previewSize = "previewSize"
    static let switcherPreviewSize = "switcherPreviewSize"
    static let autoCheckUpdates = "autoCheckUpdates"
    static let includeBetaUpdates = "includeBetaUpdates"
    static let releaseNotesOnUpdate = "releaseNotesOnUpdate"
    static let showReleaseNotesBeforeUpdate = "showReleaseNotesBeforeUpdate"
    static let whatsNewPendingVersion = "whatsNewPendingVersion"
    static let whatsNewSeenVersion = "whatsNewSeenVersion"
    static let whatsNewKnownFeatures = "whatsNewKnownFeatures"
    static let appVolumes = "appVolumes"
    static let appVolumesArePositions = "appVolumesArePositions"
    static let appOutputDevices = "appOutputDevices"
    static let mixerCallAppVolumeEnabled = "mixerCallAppVolumeEnabled"
    static let mixerUniversalOutputDevice = "mixerUniversalOutputDevice"
    static let mixerShowFinder = "mixerShowFinder"
    static let mixerAppArrangement = "mixerAppArrangement"
    static let mixerHideInactiveApps = "mixerHideInactiveApps"
    static let mixerHiddenApps = "mixerHiddenApps"
    static let mixerLowerVolumeOnHeadphonesDisconnect = "mixerLowerVolumeOnHeadphonesDisconnect"
    static let mixerHeadphonesDisconnectVolumePercent = "mixerHeadphonesDisconnectVolumePercent"
    static let mixerHeadphonesDisconnectSilenceAllowed = "mixerHeadphonesDisconnectSilenceAllowed"
    static let preciseVolumeRollerEnabled = "preciseVolumeRollerEnabled"
    static let soundOutputSwitcherEnabled = "soundOutputSwitcherEnabled"
    static let soundOutputSwitcherShortcut = "soundOutputSwitcherShortcut"
    static let soundOutputSwitcherDeviceUIDs = "soundOutputSwitcherDeviceUIDs"
    static let audioPriorityOutputEnabled = "audioPriorityOutputEnabled"
    static let audioPriorityInputEnabled = "audioPriorityInputEnabled"
    static let audioPriorityOutputUIDs = "audioPriorityOutputUIDs"
    static let audioPriorityInputUIDs = "audioPriorityInputUIDs"
    static let audioPriorityDeviceNames = "audioPriorityDeviceNames"
    static let preferredInputDevice = "preferredInputDevice"
    static let finderCutPasteEnabled = "finderCutPasteEnabled"
    static let finderCutPasteShowHUD = "finderCutPasteShowHUD"
    static let finderRenameEnabled = "finderRenameEnabled"
    static let finderRenameShortcut = "finderRenameShortcut"
    static let diskImageInstallerTrashesDownload = "diskImageInstallerTrashesDownload"
    static let diskImageInstallerRevealsApp = "diskImageInstallerRevealsApp"
    static let finderPasteImageAsFile = "finderPasteImageAsFile"
    static let diskImageInstallerUseUserApplications = "diskImageInstallerUseUserApplications"
    static let autoQuitEnabled = "autoQuitEnabled"
    static let autoQuitExceptions = "autoQuitExceptions"
    static let autoQuitDockApps = "autoQuitDockApps"
    static let quitProtectionQuitEnabled = "quitProtectionQuitEnabled"
    static let quitProtectionQuitMode = "quitProtectionQuitMode"
    static let quitProtectionQuitHoldDurationMs = "quitProtectionQuitHoldDurationMs"
    static let quitProtectionQuitDoubleIntervalMs = "quitProtectionQuitDoubleIntervalMs"
    static let quitProtectionQuitExtraModifier = "quitProtectionQuitExtraModifier"
    static let quitProtectionQuitScope = "quitProtectionQuitScope"
    static let quitProtectionQuitExceptions = "quitProtectionQuitExceptions"
    static let quitProtectionQuitShowFeedback = "quitProtectionQuitShowFeedback"
    static let quitProtectionCloseEnabled = "quitProtectionCloseEnabled"
    static let quitProtectionCloseMode = "quitProtectionCloseMode"
    static let quitProtectionCloseHoldDurationMs = "quitProtectionCloseHoldDurationMs"
    static let quitProtectionCloseDoubleIntervalMs = "quitProtectionCloseDoubleIntervalMs"
    static let quitProtectionCloseExtraModifier = "quitProtectionCloseExtraModifier"
    static let quitProtectionCloseScope = "quitProtectionCloseScope"
    static let quitProtectionCloseExceptions = "quitProtectionCloseExceptions"
    static let quitProtectionCloseShowFeedback = "quitProtectionCloseShowFeedback"
    static let shelfEnabled = "shelfEnabled"
    static let shelfShortcutEnabled = "shelfShortcutEnabled"
    static let shelfShortcut = "shelfShortcut"
    static let shelfShakeToOpen = "shelfShakeToOpen"
    static let shelfDropZoneEnabled = "shelfDropZoneEnabled"
    static let shelfDockPlacement = "shelfDockPlacement"
    static let shelfEdgeDragEnabled = "shelfEdgeDragEnabled"
    static let shelfCloseAfterDrop = "shelfCloseAfterDrop"
    static let shelfRemoveAfterDrop = "shelfRemoveAfterDrop"
    static let shelfClearOnClose = "shelfClearOnClose"
    static let shelfShortcutAddsFinderSelection = "shelfShortcutAddsFinderSelection"
    static let shelfAutomaticExclusions = "shelfAutomaticExclusions"
    static let extraBrightnessEnabled = "extraBrightnessEnabled"
    static let extraBrightnessLevel = "extraBrightnessLevel"
    static let brightnessControlEnabled = "brightnessControlEnabled"
    static let brightnessKeysEnabled = "brightnessKeysEnabled"
    static let brightnessOSDEnabled = "brightnessOSDEnabled"
    static let brightnessKeyStep = "brightnessKeyStep"
    static let displayBrightnessShortcutsEnabled = "displayBrightnessShortcutsEnabled"
    static let displayBrightnessDecreaseShortcut = "displayBrightnessDecreaseShortcut"
    static let displayBrightnessIncreaseShortcut = "displayBrightnessIncreaseShortcut"
    static let keyboardBrightnessShortcutsEnabled = "keyboardBrightnessShortcutsEnabled"
    static let keyboardBrightnessDecreaseShortcut = "keyboardBrightnessDecreaseShortcut"
    static let keyboardBrightnessIncreaseShortcut = "keyboardBrightnessIncreaseShortcut"
    static let brightnessDDCWriteOnlyPaths = "brightnessDDCWriteOnlyPaths"
    static let brightnessDDCWriteOnlyPathsRechecked = "brightnessDDCWriteOnlyPathsRechecked"
    static let notchMascotBetaInstalled = "notchMascotBetaInstalled"
    static let brightnessForcedSoftwarePaths = "brightnessForcedSoftwarePaths"
    static let brightnessExtendedDimmingPaths = "brightnessExtendedDimmingPaths"
    static let displaysSwitchedOff = "displaysSwitchedOff"
    static let displaysSwitchedOffFingerprints = "displaysSwitchedOffFingerprints"
    static let startupDidNotFinish = "startupDidNotFinish"
    static let bluetoothSleepEnabled = "bluetoothSleepEnabled"
    static let bluetoothSleepRestoreOnWake = "bluetoothSleepRestoreOnWake"
    static let bluetoothSleepRestorePending = "bluetoothSleepRestorePending"
    static let musicBlockEnabled = "musicBlockEnabled"
    static let musicBlockReplacementPath = "musicBlockReplacementPath"
    static let musicBlockPlayReplacement = "musicBlockPlayReplacement"
    static let cleanerScheduleFrequency = "cleanerScheduleFrequency"
    static let cleanerScheduleHour = "cleanerScheduleHour"
    static let cleanerScheduleMinute = "cleanerScheduleMinute"
    static let cleanerScheduleWeekday = "cleanerScheduleWeekday"
    static let cleanerScheduleNotify = "cleanerScheduleNotify"
    static let cleanerLastAutoRun = "cleanerLastAutoRun"
    static let cleanerLastAutoFreed = "cleanerLastAutoFreed"
    static let cleanerLastAutoFailed = "cleanerLastAutoFailed"
    static let cleanerScreenshotAgeDays = "cleanerScreenshotAgeDays"
    static let whatsAppDownloadsEnabled = "whatsAppDownloadsEnabled"
    static let whatsAppDownloadsAutomaticEnabled = "whatsAppDownloadsAutomaticEnabled"
    static let whatsAppDownloadsCategories = "whatsAppDownloadsCategories"
    static let whatsAppDownloadsRetentionDays = "whatsAppDownloadsRetentionDays"
    static let whatsAppDownloadsNotify = "whatsAppDownloadsNotify"
    static let whatsAppDownloadsIncludeExisting = "whatsAppDownloadsIncludeExisting"
    static let whatsAppDownloadsAutomaticStartDate = "whatsAppDownloadsAutomaticStartDate"
    static let whatsAppDownloadsLastAutoRun = "whatsAppDownloadsLastAutoRun"
    static let whatsAppDownloadsLastCleanup = "whatsAppDownloadsLastCleanup"
    static let whatsAppDownloadsLastCleanupCount = "whatsAppDownloadsLastCleanupCount"
    static let whatsAppDownloadsLastCleanupBytes = "whatsAppDownloadsLastCleanupBytes"
    static let whatsAppDownloadsLastCleanupFailed = "whatsAppDownloadsLastCleanupFailed"
    static let whatsAppDownloadsLastCleanupAutomatic = "whatsAppDownloadsLastCleanupAutomatic"
    static let whatsAppDownloadsExclusions = "whatsAppDownloadsExclusions"
    static let whatsAppDownloadsAccessConfirmed = "whatsAppDownloadsAccessConfirmed"
    static let whatsAppOrganizerEnabled = "whatsAppOrganizerEnabled"
    static let whatsAppOrganizerDestinationPath = "whatsAppOrganizerDestinationPath"
    static let whatsAppOrganizerDelayMinutes = "whatsAppOrganizerDelayMinutes"
    static let whatsAppOrganizerCategories = "whatsAppOrganizerCategories"
    static let whatsAppOrganizerLayout = "whatsAppOrganizerLayout"
    static let whatsAppOrganizerDuplicateAction = "whatsAppOrganizerDuplicateAction"
    static let whatsAppOrganizerRecords = "whatsAppOrganizerRecords"
    static let whatsAppOrganizerUndoTransaction = "whatsAppOrganizerUndoTransaction"
    static let whatsAppOrganizerLastRun = "whatsAppOrganizerLastRun"
    static let whatsAppOrganizerLastMoved = "whatsAppOrganizerLastMoved"
    static let whatsAppOrganizerLastDuplicates = "whatsAppOrganizerLastDuplicates"
    static let whatsAppOrganizerLastFailed = "whatsAppOrganizerLastFailed"
    static let settingsWindowWidth = "settingsWindowWidth"
    static let settingsWindowHeight = "settingsWindowHeight"
    static let shelfItems = "shelfItems"
    static let urlCleanerEnabled = "urlCleanerEnabled"
    static let urlCleanerCustomParameters = "urlCleanerCustomParameters"
    static let urlCleanerSiteParameters = "urlCleanerSiteParameters"
    static let urlCleanerDisabledParameters = "urlCleanerDisabledParameters"
    static let windowMaximizeEnabled = "windowMaximizeEnabled"
    static let windowMaximizeExcludedApps = "windowMaximizeExcludedApps"
    static let keyboardDebounceEnabled = "keyboardDebounceEnabled"
    static let keyboardDebounceWindowMs = "keyboardDebounceWindowMs"
    static let keyboardDebounceKeyWindows = "keyboardDebounceKeyWindows"
    static let panelUtilityCleaning = "panelUtilityCleaning"
    static let cleaningModeKeepScreenVisible = "cleaningModeKeepScreenVisible"
    static let panelUtilityURLCleaner = "panelUtilityURLCleaner"
    static let panelUtilityUninstaller = "panelUtilityUninstaller"
    static let uninstallerCommandBarEnabled = "uninstallerCommandBarEnabled"
    static let killProcessCommandBarEnabled = "killProcessCommandBarEnabled"
    static let killProcessGroupRelated = "killProcessGroupRelated"
    static let killProcessSortBy = "killProcessSortBy"
    static let killProcessSortAscending = "killProcessSortAscending"
    static let panelUtilityCleaner = "panelUtilityCleaner"
    static let panelUtilityHomebrew = "panelUtilityHomebrew"
    static let homebrewGroupDependencies = "homebrewGroupDependencies"
    static let panelUtilityAppUpdates = "panelUtilityAppUpdates"
    static let appUpdatesCheckFrequency = "appUpdatesCheckFrequency"
    static let appUpdatesIncludeHomebrewApps = "appUpdatesIncludeHomebrewApps"
    static let appUpdatesIncludeAppStore = "appUpdatesIncludeAppStore"
    static let appUpdatesIncludeOnlineCatalog = "appUpdatesIncludeOnlineCatalog"
    static let appUpdatesNotify = "appUpdatesNotify"
    static let appUpdatesRules = "appUpdatesRules"
    static let appUpdatesLastCheck = "appUpdatesLastCheck"
    static let appUpdatesLastCount = "appUpdatesLastCount"
    static let appUpdatesNotifiedIDs = "appUpdatesNotifiedIDs"
    static let panelUtilityMedia = "panelUtilityMedia"
    static let panelUtilityClipboard = "panelUtilityClipboard"
    static let panelUtilityWindowLayout = "panelUtilityWindowLayout"
    static let panelControlMouseScroll = "panelControlMouseScroll"
    static let panelControlFocusFollowsMouse = "panelControlFocusFollowsMouse"
    static let panelControlMouseNavigation = "panelControlMouseNavigation"
    static let panelControlSwitcher = "panelControlSwitcher"
    static let panelControlDockPreview = "panelControlDockPreview"
    static let panelControlCutPaste = "panelControlCutPaste"
    static let panelControlAutoQuit = "panelControlAutoQuit"
    static let panelControlShelf = "panelControlShelf"
    static let panelControlWindowMaximize = "panelControlWindowMaximize"
    static let panelControlKeyDebounce = "panelControlKeyDebounce"
    static let panelControlDockClick = "panelControlDockClick"
    static let panelControlDockClickHide = "panelControlDockClickHide"
    static let panelControlDockClickCycle = "panelControlDockClickCycle"
    static let panelControlMiddleClick = "panelControlMiddleClick"
    static let panelControlTextSnippets = "panelControlTextSnippets"
    static let panelControlSuperKey = "panelControlSuperKey"
    static let panelControlRadialMenu = "panelControlRadialMenu"
    static let panelControlMouseButtonShortcuts = "panelControlMouseButtonShortcuts"
    static let panelControlMouseAcceleration = "panelControlMouseAcceleration"
    static let panelControlLinearScroll = "panelControlLinearScroll"
    static let panelControlMouseClickDebounce = "panelControlMouseClickDebounce"
    static let panelControlSpacesOrder = "panelControlSpacesOrder"
    static let panelControlWindowsExpanded = "panelControlWindowsExpanded"
    static let panelControlInputExpanded = "panelControlInputExpanded"
    static let panelControlFilesExpanded = "panelControlFilesExpanded"
    static let panelShowKeepAwake = "panelShowKeepAwake"
    static let panelShowBrightness = "panelShowBrightness"
    static let panelShowUtilities = "panelShowUtilities"
    static let panelShowControls = "panelShowControls"
    static let panelShowToggles = "panelShowToggles"
    static let panelShowWallpaper = "panelShowWallpaper"
    static let panelToggleDarkMode = "panelToggleDarkMode"
    static let panelToggleKeyboardLight = "panelToggleKeyboardLight"
    static let panelToggleMicMute = "panelUtilityMicMute"
    static let panelToggleEmptyTrash = "panelToggleEmptyTrash"
    static let panelToggleQuitAllApps = "panelToggleQuitAllApps"
    static let panelToggleEjectDisks = "panelToggleEjectDisks"
    static let panelToggleHiddenFiles = "panelToggleHiddenFiles"
    static let panelToggleDesktopIcons = "panelToggleDesktopIcons"
    static let panelToggleLockScreen = "panelToggleLockScreen"
    static let panelToggleDisplayOff = "panelToggleDisplayOff"
    static let panelToggleScreenSaver = "panelToggleScreenSaver"

    static let menuBarCPU = "menuBarCPU"
    static let menuBarGPU = "menuBarGPU"
    static let menuBarMemory = "menuBarMemory"
    static let menuBarCPUTemperature = "menuBarCPUTemperature"
    static let menuBarGPUTemperature = "menuBarGPUTemperature"
    static let menuBarBatteryTemperature = "menuBarBatteryTemperature"
    static let menuBarTemperature = "menuBarTemperature"
    static let menuBarNetwork = "menuBarNetwork"
    static let menuBarDiskUsage = "menuBarDiskUsage"
    static let menuBarDiskActivity = "menuBarDiskActivity"
    static let menuBarBattery = "menuBarBattery"
    static let menuBarBatteryTime = "menuBarBatteryTime"
    static let menuBarPeripheralBattery = "menuBarPeripheralBattery"
    static let menuBarConnectedDevices = "menuBarConnectedDevices"
    static let menuBarPower = "menuBarPower"
    static let menuBarFanSpeed = "menuBarFanSpeed"
    static let menuBarPreset = "menuBarPreset"
    static let menuBarMetricSpacing = "menuBarMetricSpacing"
    static let menuBarMetricAppearance = "menuBarMetricAppearance"
    static let menuBarUsageBarNormalColor = "menuBarUsageBarNormalColor"
    static let menuBarUsageBarElevatedColor = "menuBarUsageBarElevatedColor"
    static let menuBarUsageBarCriticalColor = "menuBarUsageBarCriticalColor"
    static let menuBarUsageBarMediumThreshold = "menuBarUsageBarMediumThreshold"
    static let menuBarUsageBarHighThreshold = "menuBarUsageBarHighThreshold"
    static let menuBarHideIconWithMetrics = "menuBarHideIconWithMetrics"
    static let menuBarIconSymbol = "menuBarIconSymbol"
    static let menuBarMetricOrder = "menuBarMetricOrder"
    static let menuBarCombineTemperatures = "menuBarCombineTemperatures"
    static let menuBarSeparateMetrics = "menuBarSeparateMetrics"
    static let menuBarNetworkUploadFirst = "menuBarNetworkUploadFirst"
    static let menuBarLabelStyle = "menuBarLabelStyle"
    static let menuBarMemoryStyle = "menuBarMemoryStyle"
    static let menuBarDiskStyle = "menuBarDiskStyle"
    static let monitorMemoryMetric = "monitorMemoryMetric"
    static let monitorInterval = "monitorIntervalSeconds"
    static let temperatureUnit = "temperatureUnit"
    static let monitorShowSystem = "monitorShowSystem"
    static let monitorShowNetwork = "monitorShowNetwork"
    static let monitorShowDisk = "monitorShowDisk"
    static let monitorShowPower = "monitorShowPower"
    static let monitorShowMixer = "monitorShowMixer"
    static let panelShowFanControl = "panelShowFanControl"
    static let fanControlMode = "fanControlMode"
    static let fanControlCoolingLevel = "fanControlCoolingLevel"
    static let fanControlCurves = "fanControlCurves"
    static let fanControlResume = "fanControlResume"
    static let fanControlResumeConfiguration = "fanControlResumeConfiguration"
    static let monitorShowFanControlBeta = "monitorShowFanControlBeta"
    static let fanControlRecoveryNeeded = "fanControlRecoveryNeeded"
    static let fanControlHelperVersion = "fanControlHelperVersion"
    static let monitorGraphCPU = "monitorGraphCPU"
    static let monitorGraphGPU = "monitorGraphGPU"
    static let monitorGraphMemory = "monitorGraphMemory"
    static let monitorGraphNetwork = "monitorGraphNetwork"
    static let monitorGraphDisk = "monitorGraphDisk"
    static let monitorGraphPower = "monitorGraphPower"
    static let monitorGraphBattery = "monitorGraphBattery"
    static let monitorGraphScale = "monitorGraphScale"
    static let monitorSysTemps = "monitorSysTemps"
    static let monitorSysCPU = "monitorSysCPU"
    static let monitorSysCPUCores = "monitorSysCPUCores"
    static let monitorSysGPU = "monitorSysGPU"
    static let monitorSysBattery = "monitorSysBattery"
    static let monitorSysMemory = "monitorSysMemory"
    static let monitorSysAlerts = "monitorSysAlerts"
    static let monitorSysUptime = "monitorSysUptime"
    static let monitorSysConnectedDevices = "monitorSysConnectedDevices"
    static let monitorNetSpeed = "monitorNetSpeed"
    static let monitorNetApps = "monitorNetApps"
    static let monitorNetTotals = "monitorNetTotals"
    static let monitorNetAddresses = "monitorNetAddresses"
    static let monitorNetTest = "monitorNetTest"
    static let networkSpeedUnit = "networkSpeedUnit"
    static let monitorDiskUsage = "monitorDiskUsage"
    static let monitorDiskActivity = "monitorDiskActivity"
    static let monitorDiskSMART = "monitorDiskSMART"
    static let monitorDiskProtection = "monitorDiskProtection"
    static let monitorDiskTools = "monitorDiskTools"
    static let monitorPwrTemperature = "monitorPwrTemperature"
    static let monitorPwrSystem = "monitorPwrSystem"
    static let monitorPwrAdapter = "monitorPwrAdapter"
    static let monitorPwrBattery = "monitorPwrBattery"
    static let monitorPwrTimeRemaining = "monitorPwrTimeRemaining"
    static let monitorPwrHealth = "monitorPwrHealth"
    static let monitorPwrPeripherals = "monitorPwrPeripherals"
    static let monitorAlertCPU = "monitorAlertCPU"
    static let monitorAlertCPUTemperature = "monitorAlertCPUTemperature"
    static let monitorAlertBatteryTemperature = "monitorAlertBatteryTemperature"
    static let monitorAlertMemory = "monitorAlertMemory"
    static let monitorAlertDisk = "monitorAlertDisk"
    static let monitorAlertBattery = "monitorAlertBattery"
    static let monitorAlertCPUThreshold = "monitorAlertCPUThreshold"
    static let monitorAlertCPUTemperatureThreshold = "monitorAlertCPUTemperatureThreshold"
    static let monitorAlertBatteryTemperatureThreshold = "monitorAlertBatteryTemperatureThreshold"
    static let monitorAlertDiskFreePercent = "monitorAlertDiskFreePercent"
    static let monitorAlertBatteryPercent = "monitorAlertBatteryPercent"
    static let monitorAlertCooldownMinutes = "monitorAlertCooldownMinutes"
    static let panelSectionOrder = "panelSectionOrder"
    static let panelUtilityOrder = "panelUtilityOrder"
    static let panelControlOrder = "panelControlOrder"
    static let panelToggleOrder = "panelToggleOrder"
    static let panelSystemOrder = "panelSystemOrder"
    static let panelNetworkOrder = "panelNetworkOrder"
    static let panelDiskOrder = "panelDiskOrder"
    static let panelPowerOrder = "panelPowerOrder"
    static let panelNavigationEnabled = "panelNavigationEnabled"
    static let updateLastInstallFailure = "updateLastInstallFailure"
    static let windowLayoutHiddenActions = "windowLayoutHiddenActions"
    static let windowLayoutWindowGap = "windowLayoutWindowGap"
    static let windowLayoutScreenGap = "windowLayoutScreenGap"
    static let windowReserveStageManagerSpace = "windowReserveStageManagerSpace"
    static let windowLayoutMarginPercent = "windowLayoutMarginPercent"
    static let windowLayoutSideRepeatCyclesThirds = "windowLayoutSideRepeatCyclesThirds"
    static let windowLayoutIgnoredApps = "windowLayoutIgnoredApps"
    static let panelCollapsedSections = "panelCollapsedSections"
    static let panelCollapsedResetVersion = "panelCollapsedResetVersion"

    static let mediaLastTool = "mediaLastTool"
    static let mediaVideoStart = "mediaVideoStart"
    static let mediaVideoEnd = "mediaVideoEnd"
    static let mediaVideoQuality = "mediaVideoQuality"
    static let mediaVideoMaxDimension = "mediaVideoMaxDimension"
    static let mediaVideoFPS = "mediaVideoFPS"
    static let mediaVideoKeepAudio = "mediaVideoKeepAudio"
    static let mediaVideoCodec = "mediaVideoCodec"
    static let mediaVideoSizing = "mediaVideoSizing"
    static let mediaVideoTargetMegabytes = "mediaVideoTargetMegabytes"
    static let mediaGIFStart = "mediaGIFStart"
    static let mediaGIFEnd = "mediaGIFEnd"
    static let mediaGIFQuality = "mediaGIFQuality"
    static let mediaGIFWidth = "mediaGIFWidth"
    static let mediaGIFFPS = "mediaGIFFPS"
    static let mediaGIFLoops = "mediaGIFLoops"
    static let mediaGIFSizing = "mediaGIFSizing"
    static let mediaGIFTargetMegabytes = "mediaGIFTargetMegabytes"
    static let mediaImageQuality = "mediaImageQuality"
    static let mediaImageMaxDimension = "mediaImageMaxDimension"
    static let mediaImageFormat = "mediaImageFormat"
    static let mediaImageStripMetadata = "mediaImageStripMetadata"
    static let mediaImageResizeKind = "mediaImageResizeKind"
    static let mediaImageResizeWidth = "mediaImageResizeWidth"
    static let mediaImageResizeHeight = "mediaImageResizeHeight"
    static let mediaImageExactResizeMode = "mediaImageExactResizeMode"
    static let mediaImageWatermarkKind = "mediaImageWatermarkKind"
    static let mediaImageWatermarkText = "mediaImageWatermarkText"
    static let mediaImageWatermarkLogoPath = "mediaImageWatermarkLogoPath"
    static let mediaImageWatermarkPosition = "mediaImageWatermarkPosition"
    static let mediaImageWatermarkOpacity = "mediaImageWatermarkOpacity"
    static let mediaImageWatermarkMargin = "mediaImageWatermarkMargin"
    static let mediaImageWatermarkScale = "mediaImageWatermarkScale"
    static let mediaImageRenamePattern = "mediaImageRenamePattern"
    static let mediaImageBackground = "mediaImageBackground"
    static let mediaImagePreserveModificationDate = "mediaImagePreserveModificationDate"
    static let mediaImageSaveInSubfolder = "mediaImageSaveInSubfolder"
    static let mediaImageProfiles = "mediaImageProfiles"
    static let mediaImageSelectedProfileID = "mediaImageSelectedProfileID"
    static let mediaTextAccurate = "mediaTextAccurate"
    static let mediaTextLanguageCorrection = "mediaTextLanguageCorrection"

    static let clipboardHistoryEnabled = "clipboardHistoryEnabled"
    static let clipboardHistoryEntries = "clipboardHistoryEntries"
    static let clipboardHistoryLimit = "clipboardHistoryLimit"
    static let clipboardHistoryRetentionDays = "clipboardHistoryRetentionDays"
    static let clipboardHistoryFilterSensitiveText = "clipboardHistoryFilterSensitiveText"
    static let clipboardHistoryIncludeImagesFiles = "clipboardHistoryIncludeImagesFiles"
    static let clipboardHistoryIgnoredApps = "clipboardHistoryIgnoredApps"
    static let clipboardHistoryQuickPreview = "clipboardHistoryQuickPreview"
    static let clipboardHistoryShowSourceAppIcons = "clipboardHistoryShowSourceAppIcons"
    static let clipboardHistoryLayout = "clipboardHistoryLayout"
    static let clipboardHistoryWindowWidth = "clipboardHistoryWindowWidth"
    static let clipboardHistoryWindowHeight = "clipboardHistoryWindowHeight"
    static let clipboardHistoryMenuBarPreview = "clipboardHistoryMenuBarPreview"
    static let clipboardHistoryMenuBarPreviewLength = "clipboardHistoryMenuBarPreviewLength"

    static let clipboardAutoClearOnDelay = "clipboardAutoClearOnDelay"
    static let clipboardAutoClearDelay = "clipboardAutoClearDelaySeconds"
    static let clipboardAutoClearOnSleep = "clipboardAutoClearOnSleep"
    static let clipboardAutoClearOnDisplaySleep = "clipboardAutoClearOnDisplaySleep"
    static let clipboardAutoClearOnScreenLock = "clipboardAutoClearOnScreenLock"

    static let windowPreviewExcludedApps = "windowPreviewExcludedApps"
    static let switcherPreviewExcludedApps = "switcherPreviewExcludedApps"
    static let diskEjectExcludedVolumes = "diskEjectExcludedVolumes"
    static let pastePlainEnabled = "pastePlainEnabled"
    static let pastePlainShortcut = "pastePlainShortcut"
    static let colorPickerShortcutEnabled = "colorPickerShortcutEnabled"
    static let colorPickerShortcut = "colorPickerShortcut"
    static let colorPickerFormat = "colorPickerFormat"
    static let colorPickerBareHex = "colorPickerBareHex"
    static let screenOCRShortcutEnabled = "screenOCRShortcutEnabled"
    static let screenOCRShortcut = "screenOCRShortcut"
    static let screenOCRRemoveLineBreaks = "screenOCRRemoveLineBreaks"
    static let screenOCRDetectQRCodes = "screenOCRDetectQRCodes"
    static let micMuteShortcutEnabled = "micMuteShortcutEnabled"
    static let micMuteShortcut = "micMuteShortcut"
    static let quitAppsShortcutEnabled = "quitAppsShortcutEnabled"
    static let quitAppsShortcut = "quitAppsShortcut"
    static let quitAppsExceptFrontShortcutEnabled = "quitAppsExceptFrontShortcutEnabled"
    static let quitAppsExceptFrontShortcut = "quitAppsExceptFrontShortcut"
    static let quitAppsKeptApps = "quitAppsKeptApps"
    static let cameraPreviewShortcutEnabled = "cameraPreviewShortcutEnabled"
    static let cameraPreviewShortcut = "cameraPreviewShortcut"
    static let wallpaperApplyAllDisplays = "wallpaperApplyAllDisplays"
    static let wallpaperFilter = "wallpaperFilter"
    static let wallpaperOwnBookmarks = "wallpaperOwnBookmarks"
    static let wallpaperExcludedOwnPaths = "wallpaperExcludedOwnPaths"
    static let scratchpadShortcutEnabled = "scratchpadShortcutEnabled"
    static let scratchpadShortcut = "scratchpadShortcut"
    static let commandBarShortcutEnabled = "commandBarShortcutEnabled"
    static let commandBarShortcut = "commandBarShortcut"
    static let commandBarCompactMode = "commandBarCompactMode"
    static let commandBarASCIILayoutEnabled = "commandBarASCIILayoutEnabled"
    static let commandBarUsage = "commandBarUsage"
    static let commandBarQueryHabits = "commandBarQueryHabits"
    static let commandBarQueryHabitKey = "commandBarQueryHabitKey"
    static let commandBarDisabledSources = "commandBarDisabledSources"
    static let commandBarAliases = "commandBarAliases"
    static let commandBarPins = "commandBarPins"
    static let commandBarHidden = "commandBarHidden"
    static let commandBarLinks = "commandBarLinks"
    static let commandBarRowShortcuts = "commandBarRowShortcuts"
    static let commandBarPositionOffset = "commandBarPositionOffset"
    static let commandBarEmojiSkinTone = "commandBarEmojiSkinTone"
    static let commandBarFileScopes = "commandBarFileScopes"
    static let commandBarFileIgnores = "commandBarFileIgnores"
    static let panelUtilityCommandBar = "panelUtilityCommandBar"
    static let scratchpadRetention = "scratchpadRetention"
    static let scratchpadCloseOnClickOutside = "scratchpadCloseOnClickOutside"
    static let scratchpadBackgroundOpacity = "scratchpadBackgroundOpacity"
    static let scratchpadDocument = "scratchpadDocument"
    static let scratchpadTextSize = "scratchpadTextSize"
    static let micMuteActive = "micMuteActive"
    static let micMuteSavedVolume = "micMuteSavedVolume"
    static let micMuteSavedVolumes = "micMuteSavedVolumes"
    static let micMuteSavedChannelVolumes = "micMuteSavedChannelVolumes"
    static let micMuteMutedDevices = "micMuteMutedDevices"
    static let micMuteMenuBarIndicator = "micMuteMenuBarIndicator"
    static let quickLauncherShortcutEnabled = "quickLauncherShortcutEnabled"
    static let quickLauncherShortcut = "quickLauncherShortcut"
    static let quickLauncherItemOrder = "quickLauncherItemOrder"
    static let quickLauncherHiddenItems = "quickLauncherHiddenItems"
    static let panelUtilityQuickLauncher = "panelUtilityQuickLauncher"
    static let panelUtilityColorPicker = "panelUtilityColorPicker"
    static let panelUtilityScreenOCR = "panelUtilityScreenOCR"
    static let panelUtilityCameraPreview = "panelUtilityCameraPreview"
    static let panelUtilityScratchpad = "panelUtilityScratchpad"
    static let clipboardHistoryShortcutEnabled = "clipboardHistoryShortcutEnabled"
    static let clipboardHistoryShortcut = "clipboardHistoryShortcut"
    static let screenshotShowCaptureMenuOnShortcut = "screenshotShowCaptureMenuOnShortcut"
    static let recorderShowCaptureMenuOnShortcut = "recorderShowCaptureMenuOnShortcut"
    static let screenOCRShowCaptureMenuOnShortcut = "screenOCRShowCaptureMenuOnShortcut"
    static let colorPickerShowCaptureMenuOnShortcut = "colorPickerShowCaptureMenuOnShortcut"
    static let screenshotShortcutEnabled = "screenshotShortcutEnabled"
    static let screenshotShortcut = "screenshotShortcut"
    static let unifiedScreenCaptureShortcutMigrated = "unifiedScreenCaptureShortcutMigrated"
    static let restoredScreenCaptureShortcutsMigrated = "restoredScreenCaptureShortcutsMigrated"
    static let orphanedCaptureShortcutMigrated = "orphanedCaptureShortcutMigrated"
    static let screenshotFullScreenShortcutEnabled = "screenshotFullScreenShortcutEnabled"
    static let screenshotFullScreenShortcut = "screenshotFullScreenShortcut"
    static let screenshotLastCaptureShortcutEnabled = "screenshotLastCaptureShortcutEnabled"
    static let screenshotLastCaptureShortcut = "screenshotLastCaptureShortcut"
    static let recentCapturesShortcutEnabled = "recentCapturesShortcutEnabled"
    static let recentCapturesShortcut = "recentCapturesShortcut"
    static let screenshotClipboardShortcutEnabled = "screenshotClipboardShortcutEnabled"
    static let screenshotClipboardShortcut = "screenshotClipboardShortcut"
    static let screenshotFreeze = "screenshotFreeze"
    static let screenshotHideVorssaintWindows = "screenshotHideVorssaintWindows"
    static let screenshotSaveFolder = "screenshotSaveFolder"
    static let screenshotSaveSubfolder = "screenshotSaveSubfolder"
    static let screenshotFileNamePattern = "screenshotFileNamePattern"
    static let screenshotFileNumberStart = "screenshotFileNumberStart"
    static let screenshotFileNumberNext = "screenshotFileNumberNext"
    static let screenshotDefaultAction = "screenshotDefaultAction"
    static let screenshotIncludePointer = "screenshotIncludePointer"
    static let screenshotShowLastRegion = "screenshotShowLastRegion"
    static let screenshotHighlightWindows = "screenshotHighlightWindows"
    static let screenshotLoupeStartsOn = "screenshotLoupeStartsOn"
    static let screenshotLoupeRememberZoom = "screenshotLoupeRememberZoom"
    static let screenshotLoupeDefaultZoom = "screenshotLoupeDefaultZoom"
    static let screenshotLoupeLastZoom = "screenshotLoupeLastZoom"
    static let screenshotLoupeSteppedZoomByDefault = "screenshotLoupeSteppedZoomByDefault"
    static let screenshotDownscale = "screenshotDownscale"
    static let screenshotDelay = "screenshotDelay"
    static let screenshotLastTool = "screenshotLastTool"
    static let screenshotLastColor = "screenshotLastColor"
    static let screenshotLastStroke = "screenshotLastStroke"
    static let screenshotLastTextSize = "screenshotLastTextSize"
    static let screenshotLastBlurLevel = "screenshotLastBlurLevel"
    static let screenshotLastBlurStyle = "screenshotLastBlurStyle"
    static let screenshotLastBlurTextOnly = "screenshotLastBlurTextOnly"
    static let screenshotSpotlightDim = "screenshotSpotlightDim"
    static let screenshotLastArrowStyle = "screenshotLastArrowStyle"
    static let screenshotLastSticker = "screenshotLastSticker"
    static let screenshotAnnotationShadows = "screenshotAnnotationShadows"
    static let screenshotToolOrder = "screenshotToolOrder"
    static let screenshotToolShortcuts = "screenshotToolShortcuts"
    static let screenshotToolShortcutsEnabled = "screenshotToolShortcutsEnabled"
    static let screenshotBackdropStyle = "screenshotBackdropStyle"
    static let screenshotBackdropPresets = "screenshotBackdropPresets"
    static let screenshotWatermarkStyle = "screenshotWatermarkStyle"
    static let screenshotWatermarkPresets = "screenshotWatermarkPresets"
    static let screenshotOpenEditorDirectly = "screenshotOpenEditorDirectly"
    static let screenshotCopyToClipboard = "screenshotCopyToClipboard"
    static let screenshotCopyImageOnly = "screenshotCopyImageOnly"
    static let screenshotAddToShelf = "screenshotAddToShelf"
    static let screenshotPreviewPosition = "screenshotPreviewPosition"
    static let screenshotPreviewTakesFocus = "screenshotPreviewTakesFocus"
    static let screenshotUploadShortcutEnabled = "screenshotUploadShortcutEnabled"
    static let screenshotUploadShortcut = "screenshotUploadShortcut"
    static let screenshotUploadDuration = "screenshotUploadDuration"
    static let screenshotPreviewEnabled = "screenshotPreviewEnabled"
    static let screenshotPreviewDuration = "screenshotPreviewDuration"
    static let screenshotSharingEnabled = "screenshotSharingEnabled"
    static let screenshotSharingDeveloperEndpoint = "screenshotSharingDeveloperEndpoint"
    static let panelUtilityScreenshot = "panelUtilityScreenshot"

    static let recorderShortcutEnabled = "recorderShortcutEnabled"
    static let recorderShortcut = "recorderShortcut"
    static let recorderCountdown = "recorderCountdown"
    static let recorderQuality = "recorderQuality"
    static let recorderFrameRate = "recorderFrameRate"
    static let recorderSystemAudio = "recorderSystemAudio"
    static let recorderMicrophone = "recorderMicrophone"
    static let recorderSystemAudioTapVerified = "recorderSystemAudioTapVerified"
    static let recorderSaveFolder = "recorderSaveFolder"
    static let recorderOpenEditor = "recorderOpenEditor"
    static let recorderAutomaticZoom = "recorderAutomaticZoom"
    static let recorderGIFSize = "recorderGIFSize"
    static let recorderGIFFrameRate = "recorderGIFFrameRate"
    static let recorderEditorPresets = "recorderEditorPresets"
    static let recorderSharingEnabled = "recorderSharingEnabled"
    static let panelUtilityScreenRecorder = "panelUtilityScreenRecorder"
    static let panelUtilityPortManager = "panelUtilityPortManager"

    static let windowLayoutShortcutsEnabled = "windowLayoutShortcutsEnabled"
    static let windowDirectionalEnabled = "windowDirectionalEnabled"
    static let windowDirectionalShortcut = "windowDirectionalShortcut"
    static let pointerDisplayEnabled = "pointerDisplayEnabled"
    static let pointerDisplayShortcut = "pointerDisplayShortcut"
    static let windowEdgeSnapEnabled = "windowEdgeSnapEnabled"
    static let windowEdgeSnapDisabledZones = "windowEdgeSnapDisabledZones"
    static let windowEdgeSnapZoneActions = "windowEdgeSnapZoneActions"
    static let windowGestureEnabled = "windowGestureEnabled"
    static let windowGestureModifiers = "windowGestureModifiers"
    static let windowGestureRaiseWindow = "windowGestureRaiseWindow"
    static let windowLayoutShortcutLeft = "windowLayoutShortcutLeft"
    static let windowLayoutShortcutRight = "windowLayoutShortcutRight"
    static let windowLayoutShortcutTop = "windowLayoutShortcutTop"
    static let windowLayoutShortcutBottom = "windowLayoutShortcutBottom"
    static let windowLayoutShortcutCenterHalf = "windowLayoutShortcutCenterHalf"
    static let windowLayoutShortcutTopLeft = "windowLayoutShortcutTopLeft"
    static let windowLayoutShortcutTopRight = "windowLayoutShortcutTopRight"
    static let windowLayoutShortcutBottomLeft = "windowLayoutShortcutBottomLeft"
    static let windowLayoutShortcutBottomRight = "windowLayoutShortcutBottomRight"
    static let windowLayoutShortcutMaximize = "windowLayoutShortcutMaximize"
    static let windowLayoutShortcutMarginMaximize = "windowLayoutShortcutMarginMaximize"
    static let windowLayoutShortcutCenter = "windowLayoutShortcutCenter"
    static let windowLayoutShortcutRestore = "windowLayoutShortcutRestore"
    static let windowLayoutShortcutLeftThird = "windowLayoutShortcutLeftThird"
    static let windowLayoutShortcutCenterThird = "windowLayoutShortcutCenterThird"
    static let windowLayoutShortcutRightThird = "windowLayoutShortcutRightThird"
    static let windowLayoutShortcutLeftTwoThirds = "windowLayoutShortcutLeftTwoThirds"
    static let windowLayoutShortcutRightTwoThirds = "windowLayoutShortcutRightTwoThirds"
    static let windowLayoutShortcutCenterTwoThirds = "windowLayoutShortcutCenterTwoThirds"
    static let windowLayoutShortcutTopThird = "windowLayoutShortcutTopThird"
    static let windowLayoutShortcutMiddleThird = "windowLayoutShortcutMiddleThird"
    static let windowLayoutShortcutBottomThird = "windowLayoutShortcutBottomThird"
    static let windowLayoutShortcutTopTwoThirds = "windowLayoutShortcutTopTwoThirds"
    static let windowLayoutShortcutBottomTwoThirds = "windowLayoutShortcutBottomTwoThirds"
    static let windowLayoutShortcutTopQuarter = "windowLayoutShortcutTopQuarter"
    static let windowLayoutShortcutUpperMiddleQuarter = "windowLayoutShortcutUpperMiddleQuarter"
    static let windowLayoutShortcutLowerMiddleQuarter = "windowLayoutShortcutLowerMiddleQuarter"
    static let windowLayoutShortcutBottomQuarter = "windowLayoutShortcutBottomQuarter"
    static let windowLayoutShortcutLeftQuarter = "windowLayoutShortcutLeftQuarter"
    static let windowLayoutShortcutLeftMiddleQuarter = "windowLayoutShortcutLeftMiddleQuarter"
    static let windowLayoutShortcutRightMiddleQuarter = "windowLayoutShortcutRightMiddleQuarter"
    static let windowLayoutShortcutRightQuarter = "windowLayoutShortcutRightQuarter"
    static let windowLayoutShortcutPreviousDisplay = "windowLayoutShortcutPreviousDisplay"
    static let windowLayoutShortcutNextDisplay = "windowLayoutShortcutNextDisplay"
    static let windowLayoutShortcutFullScreen = "windowLayoutShortcutFullScreen"
    static let windowLayoutShortcutTopLeftSixth = "windowLayoutShortcutTopLeftSixth"
    static let windowLayoutShortcutTopCenterSixth = "windowLayoutShortcutTopCenterSixth"
    static let windowLayoutShortcutTopRightSixth = "windowLayoutShortcutTopRightSixth"
    static let windowLayoutShortcutBottomLeftSixth = "windowLayoutShortcutBottomLeftSixth"
    static let windowLayoutShortcutBottomCenterSixth = "windowLayoutShortcutBottomCenterSixth"
    static let windowLayoutShortcutBottomRightSixth = "windowLayoutShortcutBottomRightSixth"

    static let textSnippetsEnabled = "textSnippetsEnabled"
    static let textSnippets = "textSnippets"
    static let snippetLibraryEnabled = "snippetLibraryEnabled"
    static let snippetLibraryShortcut = "snippetLibraryShortcut"
    static let snippetSoundEnabled = "snippetSoundEnabled"
    static let snippetSoundName = "snippetSoundName"

    static let notchShowPlayingMusic = "notchShowPlayingMusic"
    static let notchIncludeOtherPlayers = "notchIncludeOtherPlayers"
    static let notchMusicShowVolume = "notchMusicShowVolume"
    static let notchPreferredPlayer = "notchPreferredPlayer"
    static let notchDefaultProfileInitialized = "notchDefaultProfileInitialized"
    static let notchInitialExtensionsInstalled = "notchInitialExtensionsInstalled"
    static let notchAgentsOptInMigrated = "notchAgentsOptInMigrated"
    static let notchIdleContent = "notchIdleContent"
    static let notchHiddenControls = "notchHiddenControls"
    static let notchScratchpadControlHidden = "notchScratchpadControlHidden"
    static let notchKeyboardLightControlHidden = "notchKeyboardLightControlHidden"
    static let notchControlOrder = "notchControlOrder"
    static let notchSize = "notchSize"
    static let notchOutlineEnabled = "notchOutlineEnabled"
    static let notchHideMenuBarGap = "notchHideMenuBarGap"
    static let notchCustomWidth = "notchCustomWidth"
    static let notchCustomHeight = "notchCustomHeight"
    static let notchCameraFitWidth = "notchCameraFitWidth"
    static let notchCameraFitHeight = "notchCameraFitHeight"
    static let notchHapticFeedback = "notchHapticFeedback"
    static let notchTranslucentBackground = "notchTranslucentBackground"
    static let notchShelf = "notchShelf"
    static let notchDragReveal = "notchDragReveal"
    static let notchCaptureControls = "notchCaptureControls"
    static let notchQuickPanel = "notchQuickPanel"
    static let notchAppPanel = "notchAppPanel"
    static let notchHidesMenuBarIcon = "notchHidesMenuBarIcon"
    static let notchKeepAwakeActivity = "notchKeepAwakeActivity"
    static let notchScratchpad = "notchScratchpad"
    static let notchHoverExpands = "notchHoverExpands"
    static let notchGesturesEnabled = "notchGesturesEnabled"
    static let notchKeyboardLight = "notchKeyboardLight"
    static let notchNotificationsEnabled = "notchNotificationsEnabled"
    static let notchDismissNativeNotifications = "notchDismissNativeNotifications"
    static let notchTimerEnabled = "notchTimerEnabled"
    static let notchTimerMode = "notchTimerMode"
    static let notchTimerMinutes = "notchTimerMinutes"
    static let notchTimerSoundEnabled = "notchTimerSoundEnabled"
    static let notchHideTimerCountdown = "notchHideTimerCountdown"
    static let notchPomodoroFocusMinutes = "notchPomodoroFocusMinutes"
    static let notchPomodoroShortBreakMinutes = "notchPomodoroShortBreakMinutes"
    static let notchPomodoroLongBreakMinutes = "notchPomodoroLongBreakMinutes"
    static let notchPomodoroLongBreakInterval = "notchPomodoroLongBreakInterval"
    static let notchPomodoroTotalSessions = "notchPomodoroTotalSessions"
    static let notchCameraEnabled = "notchCameraEnabled"
    static let notchAccessoriesEnabled = "notchAccessoriesEnabled"
    static let notchLyricsEnabled = "notchLyricsEnabled"
    static let notchLyricsOnline = "notchLyricsOnline"
    static let notchBrowserCovers = "notchBrowserCovers"
    static let notchLiveEqualizer = "notchLiveEqualizer"
    static let notchQueueEnabled = "notchQueueEnabled"
    static let notchDownloadsEnabled = "notchDownloadsEnabled"
    static let notchDownloadsFolderBookmark = "notchDownloadsFolderBookmark"
    static let notchWatchEnabled = "notchWatchEnabled"
    static let notchWatchSound = "notchWatchSound"
    static let notchWatchCondition = "notchWatchCondition"
    static let notchCalendarEnabled = "notchCalendarEnabled"
    static let notchCalendarCountdown = "notchCalendarCountdown"
    static let notchCalendarCountdownLead = "notchCalendarCountdownLead"
    static let notchCalendarTimeLeft = "notchCalendarTimeLeft"
    static let notchCalendarWeekNumbers = "notchCalendarWeekNumbers"
    static let notchCalendarExcluded = "notchCalendarExcluded"
    static let notchCalendarChosenCountdowns = "notchCalendarChosenCountdowns"
    static let notchAgentsEnabled = "notchAgentsEnabled"
    static let notchAgentsClaude = "notchAgentsClaude"
    static let notchAgentsClaudeProfile = "notchAgentsClaudeProfile"
    static let notchAgentsCodex = "notchAgentsCodex"
    static let notchAgentsCodexProfiles = "notchAgentsCodexProfiles"
    static let notchAgentsOpenCode = "notchAgentsOpenCode"
    static let notchAgentsCopilot = "notchAgentsCopilot"
    static let notchAgentsCardOrder = "notchAgentsCardOrder"
    static let notchAgentsHiddenCards = "notchAgentsHiddenCards"
    static let notchAgentsPeriod = "notchAgentsPeriod"
    static let notchAgentsLimitDisplay = "notchAgentsLimitDisplay"
    static let notchAgentsLimitFocus = "notchAgentsLimitFocus"
    static let notchAgentsLiveActivity = "notchAgentsLiveActivity"
    static let notchAgentsReadout = "notchAgentsReadout"
    static let notchAgentsFinishAlert = "notchAgentsFinishAlert"
    static let notchAgentsFinishMinimum = "notchAgentsFinishMinimum"
    static let notchAgentsLimitAlert = "notchAgentsLimitAlert"
    static let notchAgentsLimitThreshold = "notchAgentsLimitThreshold"
    static let notchAgentsDailyBudget = "notchAgentsDailyBudget"
    static let notchAgentsPriceUpdates = "notchAgentsPriceUpdates"
    static let notchEnabled = "notchEnabled"
    static let notchDisplay = "notchDisplay"
    static let notchSilhouette = "notchSilhouette"
    static let notchCapsuleFitWidth = "notchCapsuleFitWidth"
    static let notchCapsuleFitHeight = "notchCapsuleFitHeight"
    static let notchCapsuleFitDrop = "notchCapsuleFitDrop"
    static let notchOpenOnHover = "notchOpenOnHover"
    static let notchShortcutEnabled = "notchShortcutEnabled"
    static let notchShortcut = "notchShortcut"
    static let notchHideInFullscreen = "notchHideInFullscreen"
    static let notchHoverInFullscreen = "notchHoverInFullscreen"
    static let notchHideUntilHover = "notchHideUntilHover"
    static let notchHiddenShowsActivity = "notchHiddenShowsActivity"
    static let notchCoversMenus = "notchCoversMenus"
    static let notchLowBatteryTint = "notchLowBatteryTint"
    static let notchLowBatteryThreshold = "notchLowBatteryThreshold"
    static let notchLowBatteryEarly = "notchLowBatteryEarly"
    static let notchLowBatteryEarlyThreshold = "notchLowBatteryEarlyThreshold"
    static let notchLowBatteryMenuBar = "notchLowBatteryMenuBar"
    static let notchHoverDelay = "notchHoverDelay"
    static let notchCloseDelay = "notchCloseDelay"
    static let notchReturnHome = "notchReturnHome"
    static let notchHomeModule = "notchHomeModule"
    static let notchOpensActivity = "notchOpensActivity"
    static let notchHiddenModules = "notchHiddenModules"
    static let notchModuleOrder = "notchModuleOrder"
    static let notchQuickAccessLayout = "notchQuickAccessLayout"
    static let notchQuickAccessSide = "notchQuickAccessSide"
    static let notchQuickAccessSecond = "notchQuickAccessSecond"
    static let notchQuickAccessThird = "notchQuickAccessThird"
    static let notchVolume = "notchVolume"
    static let notchInputSource = "notchInputSource"
    static let notchMicrophone = "notchMicrophone"
    static let notchBrightness = "notchBrightness"
    static let notchBattery = "notchBattery"
    static let notchClipboard = "notchClipboard"
    static let notchClipboardWindow = "notchClipboardWindow"
    static let notchClipboardCardSize = "notchClipboardCardSize"
    static let notchCapture = "notchCapture"
    static let notchTrackChange = "notchTrackChange"
    static let notchMusicActivity = "notchMusicActivity"
    static let notchShowInCaptures = "notchShowInCaptures"
    static let notchLockScreen = "notchLockScreen"
    static let notchLockSounds = "notchLockSounds"
    static let notchMascotEnabled = "notchMascotEnabled"
    static let notchMascotVisits = "notchMascotVisits"
    static let notchMascotReactions = "notchMascotReactions"
    static let notchMascotStyle = "notchMascotStyle"
    static let notchMascotShape = "notchMascotShape"
    static let notchMascotPalette = "notchMascotPalette"
    static let notchMascotSide = "notchMascotSide"
    static let notchMascotVisitFrequency = "notchMascotVisitFrequency"
    static let notchMascotHidesWhenIdle = "notchMascotHidesWhenIdle"
    static let notchCommandBar = "notchCommandBar"
    static let notchCommandBarStyle = "notchCommandBarStyle"
    static let notchHideInCaptures = "notchHideInCaptures"
    static let panelControlNotch = "panelControlNotch"

    static let radialMenuEnabled = "radialMenuEnabled"
    static let radialMenuShortcut = "radialMenuShortcut"
    static let radialMenuAtPointer = "radialMenuAtPointer"
    static let radialMenuMouseButton = "radialMenuMouseButton"
    static let radialMenuActivationMode = "radialMenuActivationMode"
    static let radialMenuItems = "radialMenuItems"
    static let radialMenuProfiles = "radialMenuProfiles"

    static let simulateUpdate = "simulateUpdate"
    static let simulateBetaUI = "simulateBetaUI"

    static func featureAvailable(_ id: String) -> String { "featureAvailable.\(id)" }
}

enum KeepAwakeIconTint: String, CaseIterable, Identifiable {
    case orange, green, blue, purple, pink, none

    var id: String { rawValue }

    static var current: KeepAwakeIconTint {
        Defaults.sanitizedKeepAwakeIconTint(
            UserDefaults.standard.string(forKey: DefaultsKey.keepAwakeIconTint)
        )
    }

    func title(_ strings: Strings) -> String {
        switch self {
        case .orange: return strings.keepAwakeIconTintOrange
        case .green: return strings.keepAwakeIconTintGreen
        case .blue: return strings.keepAwakeIconTintBlue
        case .purple: return strings.keepAwakeIconTintPurple
        case .pink: return strings.keepAwakeIconTintPink
        case .none: return strings.keepAwakeIconTintNone
        }
    }
}

enum KeepAwakeActiveIcon: String, CaseIterable, Identifiable {
    case vorssaint, coffee, eye, moon, light

    var id: String { rawValue }

    static var current: KeepAwakeActiveIcon {
        Defaults.sanitizedKeepAwakeActiveIcon(
            UserDefaults.standard.string(forKey: DefaultsKey.keepAwakeActiveIcon)
        )
    }

    var systemSymbolName: String? {
        switch self {
        case .vorssaint: return nil
        case .coffee: return "cup.and.saucer.fill"
        case .eye: return "eye.fill"
        case .moon: return "moon.fill"
        case .light: return "lightbulb.fill"
        }
    }

    var menuBarDrop: CGFloat {
        switch self {
        case .coffee: return 1
        case .light: return 0.5
        case .vorssaint, .eye, .moon: return 0
        }
    }

    func title(_ strings: Strings) -> String {
        switch self {
        case .vorssaint: return strings.keepAwakeActiveIconVorssaint
        case .coffee: return strings.keepAwakeActiveIconCoffee
        case .eye: return strings.keepAwakeActiveIconEye
        case .moon: return strings.keepAwakeActiveIconMoon
        case .light: return strings.keepAwakeActiveIconLight
        }
    }
}

enum PreviewSizing {
    static func sanitized(_ value: String) -> String {
        Defaults.allowedPreviewSizes.contains(value) ? value : "normal"
    }

    static func scale(for value: String) -> CGFloat {
        switch sanitized(value) {
        case "small": return 0.75
        case "large": return 1.4
        case "xlarge": return 1.8
        default: return 1.0
        }
    }

    static var scale: CGFloat {
        scale(for: UserDefaults.standard.string(forKey: DefaultsKey.previewSize) ?? "normal")
    }

    static var switcherScale: CGFloat {
        scale(for: UserDefaults.standard.string(forKey: DefaultsKey.switcherPreviewSize) ?? "normal")
    }
}

enum Defaults {
    static let finderBundleIdentifier = "com.apple.finder"
    static let phoneBundleIdentifier = "com.apple.mobilephone"
    static let mandatoryAutoQuitExceptionBundleIDs = [
        finderBundleIdentifier,
        phoneBundleIdentifier,
    ]

    static let allowedDurations = [0, 15, 30, 60, 120, 240, 480]
    static let allowedKeepAwakeMouseJiggleIntervals = [1, 2, 5, 10, 15]
    static let allowedBatteryLimits = [0, 5, 10, 15, 20]
    static let allowedMonitorIntervals = [1, 2, 5]
    static let defaultKeyboardDebounceWindowMs = 5
    static let defaultSnippetSoundName = "Tink"
    static let allowedKeyboardDebounceWindowRange = 0...500
    static let keyboardDebounceWindowStep = 1
    static let defaultMouseClickDebounceWindowMs = 25
    static let allowedMouseClickDebounceWindowRange = 5...100
    static let allowedMenuBarPresets = ["dense"]
    static let allowedMenuBarMetricSpacings = ["standard", "compact"]
    static let allowedMenuBarMetricAppearances = ["values", "bars"]
    static let defaultMenuBarMetricOrder = [
        "cpu", "cpuTemperature",
        "gpu", "gpuTemperature",
        "memory",
        "battery", "batteryTime", "batteryTemperature", "peripheralBattery",
        "network", "diskUsage", "diskActivity", "connectedDevices", "power", "fanSpeed",
    ]
    static let allowedMenuBarLabelStyles = ["compact", "classic"]
    static let allowedMenuBarMemoryStyles = ["dot", "percent", "both"]
    static let allowedMonitorMemoryMetrics = ["used", "app"]
    static let allowedPreviewSizes = ["small", "normal", "large", "xlarge"]
    static let allowedClipboardHistoryLimits = [20, 50, 100, 250, 500, 1_000, 10_000, 0]
    static let allowedClipboardHistoryRetentionDays = [1, 7, 30, 90, 365, 0]
    static let allowedClipboardAutoClearDelayRange = 5...3_600
    static let defaultClipboardAutoClearDelay = 20
    static let allowedClipboardMenuBarPreviewLengthRange = 5...50
    static let defaultClipboardMenuBarPreviewLength = 20
    static let allowedMonitorAlertCooldowns = [2, 5, 15, 30, 60]

    static let registeredDefaults: [String: Any] = [
        DefaultsKey.appearance: AppAppearance.fallback.rawValue,
        DefaultsKey.liquidGlassEnabled: false,
        DefaultsKey.notchLiquidGlassEnabled: false,
        DefaultsKey.clamshellPreferred: false,
        DefaultsKey.dimScreenOnLidClose: false,
        DefaultsKey.defaultDuration: 0,
        DefaultsKey.batteryLimit: 10,
        DefaultsKey.keepAwakeAutoStart: false,
        DefaultsKey.keepAwakeRightClickToggle: false,
        DefaultsKey.keepAwakeAllowDisplaySleep: false,
        DefaultsKey.keepAwakeExternalDisplay: false,
        DefaultsKey.keepAwakeConnectedToPower: false,
        DefaultsKey.keepAwakeRunningApps: false,
        DefaultsKey.keepAwakeRunningAppBundleIDs: [String](),
        DefaultsKey.keepAwakeAutomationRequireAll: false,
        DefaultsKey.keepAwakePauseWhenLocked: false,
        DefaultsKey.keepAwakeSwitchUsesUntil: false,
        DefaultsKey.keepAwakeUntilTime: 0.0,
        DefaultsKey.keepAwakeMouseJiggleEnabled: false,
        DefaultsKey.keepAwakeMouseJiggleInterval: 5,
        DefaultsKey.hotkeyEnabled: true,
        DefaultsKey.launchAtLoginWanted: false,
        DefaultsKey.keepAwakeShortcut: "control+option+command:40",
        DefaultsKey.keepAwakeIconTint: KeepAwakeIconTint.orange.rawValue,
        DefaultsKey.keepAwakeActiveIcon: KeepAwakeActiveIcon.vorssaint.rawValue,
        DefaultsKey.showCountdown: false,
        DefaultsKey.scrollInverterEnabled: false,
        DefaultsKey.scrollInverterHorizontalEnabled: false,
        DefaultsKey.scrollHorizontalEnabled: false,
        DefaultsKey.scrollHorizontalModifier: ScrollHorizontalModifier.shift.rawValue,
        DefaultsKey.pinchZoomEnabled: false,
        DefaultsKey.pinchZoomModifier: ScrollZoomModifier.control.rawValue,
        DefaultsKey.focusFollowsMouseEnabled: false,
        DefaultsKey.focusFollowsMouseDelay: FocusFollowsMouseSupport.defaultDelayMilliseconds,
        DefaultsKey.focusFollowsMouseRaise: true,
        DefaultsKey.focusFollowsMouseWaitForStop: true,
        DefaultsKey.smoothScrollEnabled: false,
        DefaultsKey.smoothScrollStep: 40,
        DefaultsKey.linearScrollEnabled: false,
        DefaultsKey.linearScrollLines: ScrollWheelSupport.defaultLinesPerNotch,
        DefaultsKey.mouseAccelerationDisabled: false,
        DefaultsKey.smoothScrollResponse: SmoothScrollSupport.defaultResponse,
        DefaultsKey.smoothScrollCoast: SmoothScrollSupport.defaultCoast,
        DefaultsKey.mouseNavigationEnabled: false,
        DefaultsKey.mouseButtonShortcutsEnabled: false,
        DefaultsKey.mouseButtonShortcuts: [String: String](),
        DefaultsKey.mouseSpacesGestureEnabled: false,
        DefaultsKey.mouseSpacesGestureButton: 0,
        DefaultsKey.mouseSpacesGestureFollowsDrag: false,
        DefaultsKey.mouseClickDebounceEnabled: false,
        DefaultsKey.mouseClickDebounceWindowMs: defaultMouseClickDebounceWindowMs,
        DefaultsKey.superKeyEnabled: false,
        DefaultsKey.superKeySource: SuperKeySource.capsLock.rawValue,
        DefaultsKey.superKeyModifiers: SuperKeySupport.defaultModifierStorageValue,
        DefaultsKey.superKeySoloAction: SuperKeySoloAction.none.rawValue,
        DefaultsKey.smoothScrollExceptions: [String](),
        DefaultsKey.linearScrollExceptions: [String](),
        DefaultsKey.scrollInverterExceptions: [String](),
        DefaultsKey.focusFollowsMouseExceptions: [String](),
        DefaultsKey.mouseNavigationExceptions: [String](),
        DefaultsKey.mouseButtonExceptions: [String](),
        DefaultsKey.middleClickExceptions: [String](),
        DefaultsKey.superKeyExceptions: [String](),
        DefaultsKey.switcherEnabled: true,
        DefaultsKey.switcherTakeOverSystemShortcuts: false,
        DefaultsKey.switcherShortcut: "command:48",
        DefaultsKey.switcherWindowShortcut: GlobalShortcut.switcherWindowDefault.storageValue,
        DefaultsKey.switcherAllWindowsShortcut: GlobalShortcut.switcherAllWindowsDefault.storageValue,
        DefaultsKey.switcherAllWindowsShortcutEnabled: false,
        DefaultsKey.switcherIconRowMode: false,
        DefaultsKey.switcherSimpleMode: false,
        DefaultsKey.switcherMergeTabs: false,
        DefaultsKey.switcherShowWindowlessFinder: true,
        DefaultsKey.switcherWindowlessApps: SwitcherWindowlessApps.fallback.rawValue,
        DefaultsKey.switcherMinimizedPlacement: WindowSwitchMinimizedPlacement.normal.rawValue,
        DefaultsKey.switcherTreatHiddenAppsLikeMinimized: true,
        DefaultsKey.switcherShowFullscreenWindows: true,
        DefaultsKey.switcherAppRules: [String: String](),
        DefaultsKey.switcherCurrentSpaceOnly: false,
        DefaultsKey.switcherSearchPinEnabled: false,
        DefaultsKey.switcherShowShortcutHints: true,
        DefaultsKey.switcherAppearanceDelay: SwitcherSupport.defaultAppearanceDelayMilliseconds,
        DefaultsKey.switcherInstantSelection: false,
        DefaultsKey.switcherScreenPlacement: SwitcherScreenPlacement.fallback.rawValue,
        DefaultsKey.switcherCurrentDisplayOnly: false,
        DefaultsKey.switcherMaxColumns: 0,
        DefaultsKey.minimalWindowPreviews: false,
        DefaultsKey.dockPreviewEnabled: false,
        DefaultsKey.dockPreviewCurrentSpaceOnly: false,
        DefaultsKey.dockPreviewKeepDockVisible: false,
        DefaultsKey.dockPreviewBackgroundOpacity: 1.0,
        DefaultsKey.dockPreviewOpenDelay: DockPreviewSupport.defaultOpenDelayMilliseconds,
        DefaultsKey.dockPreviewQuitAppOnClose: false,
        DefaultsKey.dockPreviewOrderByCreation: false,
        DefaultsKey.dockClickMinimize: false,
        DefaultsKey.dockClickHide: false,
        DefaultsKey.dockClickCycleWindows: false,
        DefaultsKey.spacesOrderEnabled: false,
        DefaultsKey.middleClickEnabled: false,
        DefaultsKey.middleClickTapFingers: 0,
        DefaultsKey.previewSize: "normal",
        DefaultsKey.switcherPreviewSize: "normal",
        DefaultsKey.autoCheckUpdates: true,
        DefaultsKey.includeBetaUpdates: false,
        DefaultsKey.releaseNotesOnUpdate: true,
        DefaultsKey.showReleaseNotesBeforeUpdate: true,
        DefaultsKey.updateShowcaseIntroVersion: "",
        DefaultsKey.updateShowcaseMediaOverride: "",
        DefaultsKey.mixerShowFinder: true,
        DefaultsKey.mixerHideInactiveApps: false,
        DefaultsKey.mixerAppArrangement: "",
        DefaultsKey.mixerLowerVolumeOnHeadphonesDisconnect: false,
        DefaultsKey.mixerHeadphonesDisconnectVolumePercent: defaultMixerHeadphonesDisconnectVolumePercent,
        DefaultsKey.mixerHeadphonesDisconnectSilenceAllowed: false,
        DefaultsKey.preciseVolumeRollerEnabled: false,
        DefaultsKey.soundOutputSwitcherEnabled: false,
        DefaultsKey.soundOutputSwitcherShortcut: GlobalShortcut.soundOutputSwitcherDefault.storageValue,
        DefaultsKey.audioPriorityOutputEnabled: true,
        DefaultsKey.audioPriorityInputEnabled: true,
        DefaultsKey.audioPriorityOutputUIDs: [String](),
        DefaultsKey.audioPriorityInputUIDs: [String](),
        DefaultsKey.audioPriorityDeviceNames: [String: String](),
        DefaultsKey.autoQuitExceptions: mandatoryAutoQuitExceptionBundleIDs,
        DefaultsKey.autoQuitDockApps: [String](),
        DefaultsKey.quitProtectionQuitEnabled: false,
        DefaultsKey.quitProtectionQuitMode: QuitProtectionMode.hold.rawValue,
        DefaultsKey.quitProtectionQuitHoldDurationMs: QuitProtectionSupport.defaultHoldDurationMilliseconds,
        DefaultsKey.quitProtectionQuitDoubleIntervalMs: QuitProtectionSupport.defaultDoublePressIntervalMilliseconds,
        DefaultsKey.quitProtectionQuitExtraModifier: QuitProtectionExtraModifier.shift.rawValue,
        DefaultsKey.quitProtectionQuitScope: QuitProtectionScope.all.rawValue,
        DefaultsKey.quitProtectionQuitExceptions: [String](),
        DefaultsKey.quitProtectionQuitShowFeedback: true,
        DefaultsKey.quitProtectionCloseEnabled: false,
        DefaultsKey.quitProtectionCloseMode: QuitProtectionMode.hold.rawValue,
        DefaultsKey.quitProtectionCloseHoldDurationMs: QuitProtectionSupport.defaultHoldDurationMilliseconds,
        DefaultsKey.quitProtectionCloseDoubleIntervalMs: QuitProtectionSupport.defaultDoublePressIntervalMilliseconds,
        DefaultsKey.quitProtectionCloseExtraModifier: QuitProtectionExtraModifier.shift.rawValue,
        DefaultsKey.quitProtectionCloseScope: QuitProtectionScope.all.rawValue,
        DefaultsKey.quitProtectionCloseExceptions: [String](),
        DefaultsKey.quitProtectionCloseShowFeedback: true,
        DefaultsKey.shelfShortcutEnabled: true,
        DefaultsKey.shelfShortcut: "control+option+command:2",
        DefaultsKey.shelfShakeToOpen: true,
        DefaultsKey.shelfDropZoneEnabled: true,
        DefaultsKey.shelfDockPlacement: ShelfDockPlacement.menuBar.rawValue,
        DefaultsKey.shelfEdgeDragEnabled: false,
        DefaultsKey.shelfCloseAfterDrop: false,
        DefaultsKey.shelfRemoveAfterDrop: true,
        DefaultsKey.shelfClearOnClose: false,
        DefaultsKey.shelfShortcutAddsFinderSelection: false,
        DefaultsKey.shelfAutomaticExclusions: [String](),
        DefaultsKey.extraBrightnessEnabled: false,
        DefaultsKey.extraBrightnessLevel: 100,
        DefaultsKey.brightnessControlEnabled: true,
        DefaultsKey.brightnessKeysEnabled: false,
        DefaultsKey.brightnessOSDEnabled: false,
        DefaultsKey.brightnessKeyStep: BrightnessSupport.KeyStep.standard.rawValue,
        DefaultsKey.displayBrightnessShortcutsEnabled: false,
        DefaultsKey.displayBrightnessDecreaseShortcut: "shift+command:27",
        DefaultsKey.displayBrightnessIncreaseShortcut: "shift+command:24",
        DefaultsKey.keyboardBrightnessShortcutsEnabled: false,
        DefaultsKey.keyboardBrightnessDecreaseShortcut: "option+command:27",
        DefaultsKey.keyboardBrightnessIncreaseShortcut: "option+command:24",
        DefaultsKey.bluetoothSleepEnabled: false,
        DefaultsKey.bluetoothSleepRestoreOnWake: true,
        DefaultsKey.bluetoothSleepRestorePending: false,
        DefaultsKey.musicBlockEnabled: false,
        DefaultsKey.musicBlockReplacementPath: "",
        DefaultsKey.musicBlockPlayReplacement: true,
        DefaultsKey.cleanerScheduleFrequency: "off",
        DefaultsKey.cleanerScheduleHour: 9,
        DefaultsKey.cleanerScheduleMinute: 0,
        DefaultsKey.cleanerScheduleWeekday: 2,
        DefaultsKey.cleanerScheduleNotify: true,
        DefaultsKey.cleanerLastAutoRun: 0.0,
        DefaultsKey.cleanerLastAutoFreed: 0,
        DefaultsKey.cleanerLastAutoFailed: 0,
        DefaultsKey.whatsAppDownloadsEnabled: false,
        DefaultsKey.whatsAppDownloadsAutomaticEnabled: false,
        DefaultsKey.whatsAppDownloadsCategories: "image,video,audio",
        DefaultsKey.whatsAppDownloadsRetentionDays: 7,
        DefaultsKey.whatsAppDownloadsNotify: true,
        DefaultsKey.whatsAppDownloadsIncludeExisting: false,
        DefaultsKey.whatsAppDownloadsAutomaticStartDate: 0.0,
        DefaultsKey.whatsAppDownloadsLastAutoRun: 0.0,
        DefaultsKey.whatsAppDownloadsLastCleanup: 0.0,
        DefaultsKey.whatsAppDownloadsLastCleanupCount: 0,
        DefaultsKey.whatsAppDownloadsLastCleanupBytes: 0,
        DefaultsKey.whatsAppDownloadsLastCleanupFailed: 0,
        DefaultsKey.whatsAppDownloadsLastCleanupAutomatic: false,
        DefaultsKey.whatsAppDownloadsExclusions: [String](),
        DefaultsKey.whatsAppDownloadsAccessConfirmed: false,
        DefaultsKey.whatsAppOrganizerEnabled: false,
        DefaultsKey.whatsAppOrganizerDestinationPath: "",
        DefaultsKey.whatsAppOrganizerDelayMinutes: 5,
        DefaultsKey.whatsAppOrganizerCategories: "image,video,audio,document,archive,other",
        DefaultsKey.whatsAppOrganizerLayout: "flat",
        DefaultsKey.whatsAppOrganizerDuplicateAction: "trashNew",
        DefaultsKey.whatsAppOrganizerRecords: Data(),
        DefaultsKey.whatsAppOrganizerUndoTransaction: Data(),
        DefaultsKey.whatsAppOrganizerLastRun: 0.0,
        DefaultsKey.whatsAppOrganizerLastMoved: 0,
        DefaultsKey.whatsAppOrganizerLastDuplicates: 0,
        DefaultsKey.whatsAppOrganizerLastFailed: 0,
        DefaultsKey.urlCleanerEnabled: false,
        DefaultsKey.urlCleanerCustomParameters: "",
        DefaultsKey.urlCleanerSiteParameters: "",
        DefaultsKey.urlCleanerDisabledParameters: "",
        DefaultsKey.textSnippetsEnabled: false,
        DefaultsKey.snippetLibraryEnabled: false,
        DefaultsKey.snippetLibraryShortcut: GlobalShortcut.snippetLibraryDefault.storageValue,
        DefaultsKey.snippetSoundEnabled: false,
        DefaultsKey.snippetSoundName: defaultSnippetSoundName,
        DefaultsKey.notchShowPlayingMusic: true,
        DefaultsKey.notchIncludeOtherPlayers: true,
        DefaultsKey.notchMusicShowVolume: false,
        DefaultsKey.notchPreferredPlayer: "",
        DefaultsKey.notchIdleContent: NotchIdleContent.music.rawValue,
        DefaultsKey.notchHiddenControls: NotchControlItem.defaultHidden,
        DefaultsKey.notchScratchpadControlHidden: false,
        DefaultsKey.notchKeyboardLightControlHidden: false,
        DefaultsKey.notchControlOrder: "",
        DefaultsKey.notchSize: NotchSize.spacious.rawValue,
        DefaultsKey.notchOutlineEnabled: false,
        DefaultsKey.notchHideMenuBarGap: false,
        DefaultsKey.notchCustomWidth: NotchSize.defaultWidth,
        DefaultsKey.notchCustomHeight: NotchSize.defaultHeight,
        DefaultsKey.notchCameraFitWidth: 0.0,
        DefaultsKey.notchCameraFitHeight: 0.0,
        DefaultsKey.notchHapticFeedback: true,
        DefaultsKey.notchTranslucentBackground: false,
        DefaultsKey.notchShelf: true,
        DefaultsKey.notchDragReveal: true,
        DefaultsKey.notchCaptureControls: true,
        DefaultsKey.notchQuickPanel: true,
        DefaultsKey.notchAppPanel: false,
        DefaultsKey.notchHidesMenuBarIcon: false,
        DefaultsKey.notchKeepAwakeActivity: false,
        DefaultsKey.notchScratchpad: true,
        DefaultsKey.notchHoverExpands: true,
        DefaultsKey.notchGesturesEnabled: true,
        DefaultsKey.notchKeyboardLight: true,
        DefaultsKey.notchNotificationsEnabled: true,
        DefaultsKey.notchDismissNativeNotifications: false,
        DefaultsKey.notchTimerEnabled: true,
        DefaultsKey.notchTimerMode: NotchTimerMode.timer.rawValue,
        DefaultsKey.notchTimerMinutes: 15,
        DefaultsKey.notchTimerSoundEnabled: true,
        DefaultsKey.notchHideTimerCountdown: false,
        DefaultsKey.notchPomodoroFocusMinutes: 25,
        DefaultsKey.notchPomodoroShortBreakMinutes: 5,
        DefaultsKey.notchPomodoroLongBreakMinutes: 15,
        DefaultsKey.notchPomodoroLongBreakInterval: 4,
        DefaultsKey.notchPomodoroTotalSessions: 4,
        DefaultsKey.notchCameraEnabled: true,
        DefaultsKey.notchAccessoriesEnabled: true,
        DefaultsKey.notchCalendarEnabled: true,
        DefaultsKey.notchCalendarCountdown: false,
        DefaultsKey.notchCalendarCountdownLead: NotchCalendarSupport.defaultCountdownLeadMinutes,
        DefaultsKey.notchCalendarTimeLeft: false,
        DefaultsKey.notchCalendarWeekNumbers: false,
        DefaultsKey.notchCalendarExcluded: [String](),
        DefaultsKey.notchAgentsEnabled: true,
        DefaultsKey.notchAgentsClaude: true,
        DefaultsKey.notchAgentsClaudeProfile: "",
        DefaultsKey.notchAgentsCodex: true,
        DefaultsKey.notchAgentsCodexProfiles: "",
        DefaultsKey.notchAgentsOpenCode: true,
        DefaultsKey.notchAgentsCopilot: true,
        DefaultsKey.notchAgentsCardOrder: "",
        DefaultsKey.notchAgentsHiddenCards: "",
        DefaultsKey.notchAgentsPeriod: AgentPeriod.today.rawValue,
        DefaultsKey.notchAgentsLimitDisplay: NotchAgentLimitDisplay.remaining.rawValue,
        DefaultsKey.notchAgentsLimitFocus: NotchAgentLimitFocus.mostUsed.rawValue,
        DefaultsKey.notchAgentsLiveActivity: true,
        DefaultsKey.notchAgentsReadout: NotchAgentReadout.elapsed.rawValue,
        DefaultsKey.notchAgentsFinishAlert: true,
        DefaultsKey.notchAgentsFinishMinimum: NotchAgentSupport.defaultFinishMinimum,
        DefaultsKey.notchAgentsLimitAlert: true,
        DefaultsKey.notchAgentsLimitThreshold: NotchAgentSupport.defaultLimitThreshold,
        DefaultsKey.notchAgentsDailyBudget: 0.0,
        DefaultsKey.notchAgentsPriceUpdates: true,
        DefaultsKey.notchLyricsEnabled: true,
        DefaultsKey.notchLyricsOnline: false,
        DefaultsKey.notchBrowserCovers: false,
        DefaultsKey.notchLiveEqualizer: false,
        DefaultsKey.notchQueueEnabled: true,
        DefaultsKey.notchDownloadsEnabled: true,
        DefaultsKey.notchWatchEnabled: true,
        DefaultsKey.notchWatchSound: true,
        DefaultsKey.notchWatchCondition: NotchWatchCondition.changes.rawValue,
        DefaultsKey.notchEnabled: true,
        DefaultsKey.notchDisplay: NotchDisplay.automatic.rawValue,
        DefaultsKey.notchSilhouette: NotchSilhouette.capsule.rawValue,
        DefaultsKey.notchCapsuleFitWidth: 0.0,
        DefaultsKey.notchCapsuleFitHeight: 0.0,
        DefaultsKey.notchCapsuleFitDrop: 0.0,
        DefaultsKey.notchOpenOnHover: false,
        DefaultsKey.notchShortcutEnabled: false,
        DefaultsKey.notchShortcut: GlobalShortcut.notchDefault.storageValue,
        DefaultsKey.notchHideInFullscreen: false,
        DefaultsKey.notchHoverInFullscreen: false,
        DefaultsKey.notchHideUntilHover: false,
        DefaultsKey.notchHiddenShowsActivity: false,
        DefaultsKey.notchCoversMenus: true,
        DefaultsKey.notchLowBatteryTint: false,
        DefaultsKey.notchLowBatteryThreshold: NotchSupport.defaultLowBatteryThreshold,
        DefaultsKey.notchLowBatteryEarly: false,
        DefaultsKey.notchLowBatteryEarlyThreshold: NotchSupport.defaultEarlyBatteryThreshold,
        DefaultsKey.notchLowBatteryMenuBar: true,
        DefaultsKey.notchHoverDelay: NotchSupport.defaultHoverDelay,
        DefaultsKey.notchCloseDelay: NotchSupport.defaultCloseDelay,
        DefaultsKey.notchReturnHome: false,
        DefaultsKey.notchHomeModule: NotchModule.controls.rawValue,
        DefaultsKey.notchOpensActivity: true,
        DefaultsKey.notchHiddenModules: "",
        DefaultsKey.notchModuleOrder: "",
        DefaultsKey.notchQuickAccessLayout: Data(),
        DefaultsKey.notchVolume: true,
        DefaultsKey.notchInputSource: true,
        DefaultsKey.notchMicrophone: true,
        DefaultsKey.notchBrightness: true,
        DefaultsKey.notchBattery: true,
        DefaultsKey.notchClipboard: true,
        DefaultsKey.notchClipboardWindow: true,
        DefaultsKey.notchClipboardCardSize: NotchClipboardCardSize.comfortable.rawValue,
        DefaultsKey.notchCapture: true,
        DefaultsKey.notchTrackChange: true,
        DefaultsKey.notchMusicActivity: false,
        DefaultsKey.notchShowInCaptures: true,
        DefaultsKey.notchLockScreen: false,
        DefaultsKey.notchLockSounds: false,
        DefaultsKey.notchMascotEnabled: false,
        DefaultsKey.notchMascotVisits: true,
        DefaultsKey.notchMascotReactions: true,
        DefaultsKey.notchMascotStyle: NotchMascotStyle.minimal.rawValue,
        DefaultsKey.notchMascotShape: NotchMascotShape.ball.rawValue,
        DefaultsKey.notchMascotPalette: NotchMascotPalette.pearl.rawValue,
        DefaultsKey.notchMascotSide: NotchMascotSide.left.rawValue,
        DefaultsKey.notchMascotVisitFrequency: NotchMascotVisitFrequency.normal.rawValue,
        DefaultsKey.notchMascotHidesWhenIdle: true,
        DefaultsKey.notchCommandBar: true,
        DefaultsKey.notchCommandBarStyle: NotchCommandBarStyle.droplet.rawValue,
        DefaultsKey.notchHideInCaptures: false,
        DefaultsKey.panelControlNotch: true,
        DefaultsKey.radialMenuEnabled: true,
        DefaultsKey.radialMenuShortcut: GlobalShortcut.radialMenuDefault.storageValue,
        DefaultsKey.radialMenuAtPointer: true,
        DefaultsKey.radialMenuMouseButton: RadialMenuMouseTrigger.off.rawValue,
        DefaultsKey.radialMenuActivationMode: RadialMenuActivationMode.pressOrHold.rawValue,
        DefaultsKey.windowMaximizeEnabled: false,
        DefaultsKey.windowMaximizeExcludedApps: [String](),
        DefaultsKey.keyboardDebounceEnabled: false,
        DefaultsKey.keyboardDebounceWindowMs: defaultKeyboardDebounceWindowMs,
        DefaultsKey.keyboardDebounceKeyWindows: "",
        DefaultsKey.panelUtilityCleaning: true,
        DefaultsKey.cleaningModeKeepScreenVisible: false,
        DefaultsKey.panelUtilityURLCleaner: true,
        DefaultsKey.panelUtilityUninstaller: true,
        DefaultsKey.uninstallerCommandBarEnabled: false,
        DefaultsKey.killProcessCommandBarEnabled: true,
        DefaultsKey.killProcessGroupRelated: true,
        DefaultsKey.killProcessSortBy: "cpu",
        DefaultsKey.killProcessSortAscending: false,
        DefaultsKey.panelUtilityCleaner: true,
        DefaultsKey.panelUtilityHomebrew: true,
        DefaultsKey.homebrewGroupDependencies: true,
        DefaultsKey.panelUtilityAppUpdates: true,
        DefaultsKey.appUpdatesCheckFrequency: AppUpdatesSupport.CheckFrequency.off.rawValue,
        DefaultsKey.appUpdatesIncludeHomebrewApps: true,
        DefaultsKey.appUpdatesIncludeAppStore: true,
        DefaultsKey.appUpdatesIncludeOnlineCatalog: true,
        DefaultsKey.appUpdatesNotify: true,
        DefaultsKey.appUpdatesRules: "[]",
        DefaultsKey.appUpdatesLastCheck: 0.0,
        DefaultsKey.appUpdatesLastCount: 0,
        DefaultsKey.appUpdatesNotifiedIDs: [String](),
        DefaultsKey.panelUtilityMedia: true,
        DefaultsKey.panelUtilityClipboard: true,
        DefaultsKey.panelUtilityWindowLayout: true,
        DefaultsKey.panelControlMouseScroll: true,
        DefaultsKey.panelControlFocusFollowsMouse: true,
        DefaultsKey.panelControlMouseNavigation: true,
        DefaultsKey.panelControlSwitcher: true,
        DefaultsKey.panelControlDockPreview: true,
        DefaultsKey.panelControlCutPaste: true,
        DefaultsKey.panelControlAutoQuit: true,
        DefaultsKey.panelControlShelf: true,
        DefaultsKey.panelControlWindowMaximize: true,
        DefaultsKey.panelControlKeyDebounce: true,
        DefaultsKey.panelControlDockClick: true,
        DefaultsKey.panelControlDockClickHide: true,
        DefaultsKey.panelControlDockClickCycle: true,
        DefaultsKey.panelControlMiddleClick: true,
        DefaultsKey.panelControlTextSnippets: true,
        DefaultsKey.panelControlSuperKey: true,
        DefaultsKey.panelControlRadialMenu: true,
        DefaultsKey.panelControlMouseButtonShortcuts: true,
        DefaultsKey.panelControlMouseAcceleration: true,
        DefaultsKey.panelControlLinearScroll: true,
        DefaultsKey.panelControlMouseClickDebounce: true,
        DefaultsKey.panelControlSpacesOrder: true,
        DefaultsKey.panelControlWindowsExpanded: false,
        DefaultsKey.panelControlInputExpanded: false,
        DefaultsKey.panelControlFilesExpanded: false,
        DefaultsKey.panelShowKeepAwake: true,
        DefaultsKey.panelShowBrightness: true,
        DefaultsKey.panelShowUtilities: true,
        DefaultsKey.panelShowControls: true,
        DefaultsKey.panelShowToggles: true,
        DefaultsKey.panelShowWallpaper: true,
        DefaultsKey.panelToggleDarkMode: true,
        DefaultsKey.panelToggleKeyboardLight: true,
        DefaultsKey.panelToggleMicMute: true,
        DefaultsKey.panelToggleEmptyTrash: true,
        DefaultsKey.panelToggleQuitAllApps: true,
        DefaultsKey.panelToggleEjectDisks: true,
        DefaultsKey.panelToggleHiddenFiles: true,
        DefaultsKey.panelToggleDesktopIcons: true,
        DefaultsKey.panelToggleLockScreen: true,
        DefaultsKey.panelToggleDisplayOff: true,
        DefaultsKey.panelToggleScreenSaver: true,
        DefaultsKey.monitorInterval: 2,
        DefaultsKey.temperatureUnit: TemperatureUnit.celsius.rawValue,
        DefaultsKey.menuBarCPUTemperature: false,
        DefaultsKey.menuBarGPUTemperature: false,
        DefaultsKey.menuBarBatteryTemperature: false,
        DefaultsKey.menuBarBatteryTime: false,
        DefaultsKey.menuBarDiskUsage: false,
        DefaultsKey.menuBarDiskActivity: false,
        DefaultsKey.menuBarPeripheralBattery: false,
        DefaultsKey.menuBarConnectedDevices: false,
        DefaultsKey.menuBarFanSpeed: false,
        DefaultsKey.menuBarPreset: "dense",
        DefaultsKey.menuBarMetricSpacing: "compact",
        DefaultsKey.menuBarMetricAppearance: "values",
        DefaultsKey.menuBarUsageBarNormalColor: "#64D2FF",
        DefaultsKey.menuBarUsageBarElevatedColor: "#FFD60A",
        DefaultsKey.menuBarUsageBarCriticalColor: "#FF453A",
        DefaultsKey.menuBarUsageBarMediumThreshold: 70,
        DefaultsKey.menuBarUsageBarHighThreshold: 90,
        DefaultsKey.menuBarHideIconWithMetrics: false,
        DefaultsKey.menuBarIconSymbol: "",
        DefaultsKey.windowLayoutHiddenActions: "",
        DefaultsKey.windowLayoutWindowGap: 0,
        DefaultsKey.windowLayoutScreenGap: 0,
        DefaultsKey.windowReserveStageManagerSpace: false,
        DefaultsKey.windowLayoutMarginPercent: 5.0,
        DefaultsKey.windowLayoutSideRepeatCyclesThirds: false,
        DefaultsKey.menuBarMetricOrder: defaultMenuBarMetricOrder.joined(separator: ","),
        DefaultsKey.menuBarCombineTemperatures: true,
        DefaultsKey.menuBarSeparateMetrics: false,
        DefaultsKey.menuBarNetworkUploadFirst: false,
        DefaultsKey.menuBarLabelStyle: "compact",
        DefaultsKey.menuBarMemoryStyle: "percent",
        DefaultsKey.menuBarDiskStyle: "percent",
        DefaultsKey.monitorMemoryMetric: "used",
        DefaultsKey.monitorShowSystem: true,
        DefaultsKey.monitorShowNetwork: true,
        DefaultsKey.monitorShowDisk: true,
        DefaultsKey.monitorShowPower: true,
        DefaultsKey.monitorShowMixer: true,
        DefaultsKey.panelShowFanControl: true,
        DefaultsKey.fanControlMode: FanControlMode.system.rawValue,
        DefaultsKey.fanControlCoolingLevel: FanControlPolicy.defaultCoolingLevel,
        DefaultsKey.fanControlCurves: FanControlConfiguration.defaultCurvesStorage,
        DefaultsKey.fanControlResume: false,
        DefaultsKey.fanControlResumeConfiguration: "",
        DefaultsKey.fanControlRecoveryNeeded: false,
        DefaultsKey.fanControlHelperVersion: "",
        DefaultsKey.panelNavigationEnabled: true,
        DefaultsKey.monitorGraphCPU: true,
        DefaultsKey.monitorGraphGPU: true,
        DefaultsKey.monitorGraphMemory: true,
        DefaultsKey.monitorGraphNetwork: true,
        DefaultsKey.monitorGraphDisk: true,
        DefaultsKey.monitorGraphPower: true,
        DefaultsKey.monitorGraphBattery: true,
        DefaultsKey.monitorGraphScale: true,
        DefaultsKey.monitorSysTemps: true,
        DefaultsKey.monitorSysCPU: true,
        DefaultsKey.monitorSysCPUCores: true,
        DefaultsKey.monitorSysGPU: true,
        DefaultsKey.monitorSysBattery: true,
        DefaultsKey.monitorSysMemory: true,
        DefaultsKey.monitorSysAlerts: true,
        DefaultsKey.monitorSysUptime: true,
        DefaultsKey.monitorSysConnectedDevices: true,
        DefaultsKey.monitorNetSpeed: true,
        DefaultsKey.monitorNetApps: true,
        DefaultsKey.monitorNetTotals: true,
        DefaultsKey.monitorNetAddresses: true,
        DefaultsKey.monitorNetTest: true,
        DefaultsKey.networkSpeedUnit: NetworkSpeedUnit.bytes.rawValue,
        DefaultsKey.monitorDiskUsage: true,
        DefaultsKey.monitorDiskActivity: true,
        DefaultsKey.monitorDiskSMART: true,
        DefaultsKey.monitorDiskProtection: true,
        DefaultsKey.monitorDiskTools: true,
        DefaultsKey.monitorPwrTemperature: true,
        DefaultsKey.monitorPwrSystem: true,
        DefaultsKey.monitorPwrAdapter: true,
        DefaultsKey.monitorPwrBattery: true,
        DefaultsKey.monitorPwrTimeRemaining: true,
        DefaultsKey.monitorPwrHealth: true,
        DefaultsKey.monitorPwrPeripherals: false,
        DefaultsKey.monitorAlertCPU: false,
        DefaultsKey.monitorAlertCPUTemperature: false,
        DefaultsKey.monitorAlertBatteryTemperature: false,
        DefaultsKey.monitorAlertMemory: false,
        DefaultsKey.monitorAlertDisk: false,
        DefaultsKey.monitorAlertBattery: false,
        DefaultsKey.monitorAlertCPUThreshold: 90,
        DefaultsKey.monitorAlertCPUTemperatureThreshold: 90,
        DefaultsKey.monitorAlertBatteryTemperatureThreshold: 40,
        DefaultsKey.monitorAlertDiskFreePercent: 10,
        DefaultsKey.monitorAlertBatteryPercent: 15,
        DefaultsKey.monitorAlertCooldownMinutes: 15,
        DefaultsKey.mediaLastTool: MediaTool.videoCompressor.rawValue,
        DefaultsKey.mediaVideoStart: 0.0,
        DefaultsKey.mediaVideoEnd: 0.0,
        DefaultsKey.mediaVideoQuality: 0.68,
        DefaultsKey.mediaVideoMaxDimension: 1280,
        DefaultsKey.mediaVideoFPS: 30.0,
        DefaultsKey.mediaVideoKeepAudio: true,
        DefaultsKey.mediaVideoCodec: MediaVideoCodec.h264.rawValue,
        DefaultsKey.mediaVideoSizing: MediaSizingMode.resolution.rawValue,
        DefaultsKey.mediaVideoTargetMegabytes: 20,
        DefaultsKey.mediaGIFStart: 0.0,
        DefaultsKey.mediaGIFEnd: 0.0,
        DefaultsKey.mediaGIFQuality: 0.74,
        DefaultsKey.mediaGIFWidth: 720,
        DefaultsKey.mediaGIFFPS: 12.0,
        DefaultsKey.mediaGIFLoops: true,
        DefaultsKey.mediaGIFSizing: MediaSizingMode.resolution.rawValue,
        DefaultsKey.mediaGIFTargetMegabytes: 10,
        DefaultsKey.mediaImageQuality: 0.72,
        DefaultsKey.mediaImageMaxDimension: 1600,
        DefaultsKey.mediaImageFormat: MediaImageFormat.jpeg.rawValue,
        DefaultsKey.mediaImageStripMetadata: true,
        DefaultsKey.mediaImageResizeKind: MediaImageResizeKind.maxDimension.rawValue,
        DefaultsKey.mediaImageResizeWidth: 1600,
        DefaultsKey.mediaImageResizeHeight: 1200,
        DefaultsKey.mediaImageExactResizeMode: MediaImageExactResizeMode.stretch.rawValue,
        DefaultsKey.mediaImageWatermarkKind: MediaImageWatermarkKind.off.rawValue,
        DefaultsKey.mediaImageWatermarkText: "",
        DefaultsKey.mediaImageWatermarkLogoPath: "",
        DefaultsKey.mediaImageWatermarkPosition: MediaImageWatermarkPosition.bottomRight.rawValue,
        DefaultsKey.mediaImageWatermarkOpacity: 0.45,
        DefaultsKey.mediaImageWatermarkMargin: 32,
        DefaultsKey.mediaImageWatermarkScale: 0.18,
        DefaultsKey.mediaImageRenamePattern: "",
        DefaultsKey.mediaImageBackground: MediaImageBackground.transparent.rawValue,
        DefaultsKey.mediaImagePreserveModificationDate: false,
        DefaultsKey.mediaImageSaveInSubfolder: false,
        DefaultsKey.mediaImageProfiles: "[]",
        DefaultsKey.mediaImageSelectedProfileID: "",
        DefaultsKey.mediaTextAccurate: true,
        DefaultsKey.mediaTextLanguageCorrection: true,
        DefaultsKey.clipboardHistoryEnabled: false,
        DefaultsKey.clipboardHistoryLimit: 50,
        DefaultsKey.clipboardHistoryRetentionDays: 0,
        DefaultsKey.clipboardHistoryFilterSensitiveText: false,
        DefaultsKey.clipboardHistoryIncludeImagesFiles: true,
        DefaultsKey.clipboardHistoryIgnoredApps: [String](),
        DefaultsKey.windowLayoutIgnoredApps: [String](),
        DefaultsKey.clipboardHistoryQuickPreview: false,
        DefaultsKey.clipboardHistoryShowSourceAppIcons: false,
        DefaultsKey.clipboardHistoryLayout: ClipboardHistoryLayout.list.rawValue,
        DefaultsKey.clipboardHistoryWindowWidth: 0.0,
        DefaultsKey.clipboardHistoryWindowHeight: 0.0,
        DefaultsKey.clipboardHistoryMenuBarPreview: false,
        DefaultsKey.clipboardHistoryMenuBarPreviewLength: Defaults.defaultClipboardMenuBarPreviewLength,
        DefaultsKey.clipboardAutoClearOnDelay: false,
        DefaultsKey.clipboardAutoClearDelay: Defaults.defaultClipboardAutoClearDelay,
        DefaultsKey.clipboardAutoClearOnSleep: false,
        DefaultsKey.clipboardAutoClearOnDisplaySleep: false,
        DefaultsKey.clipboardAutoClearOnScreenLock: false,
        DefaultsKey.finderCutPasteShowHUD: true,
        DefaultsKey.finderPasteImageAsFile: false,
        DefaultsKey.windowPreviewExcludedApps: [String](),
        DefaultsKey.switcherPreviewExcludedApps: [String](),
        DefaultsKey.diskEjectExcludedVolumes: [String](),
        DefaultsKey.pastePlainEnabled: false,
        DefaultsKey.pastePlainShortcut: GlobalShortcut.pastePlainDefault.storageValue,
        DefaultsKey.finderRenameEnabled: false,
        DefaultsKey.finderRenameShortcut: GlobalShortcut.finderRenameDefault.storageValue,
        DefaultsKey.diskImageInstallerUseUserApplications: false,
        DefaultsKey.diskImageInstallerTrashesDownload: true,
        DefaultsKey.diskImageInstallerRevealsApp: false,
        DefaultsKey.colorPickerShortcutEnabled: false,
        DefaultsKey.colorPickerShortcut: GlobalShortcut.colorPickerDefault.storageValue,
        DefaultsKey.colorPickerFormat: "hex",
        DefaultsKey.colorPickerBareHex: false,
        DefaultsKey.screenOCRShortcutEnabled: false,
        DefaultsKey.screenOCRShortcut: GlobalShortcut.screenOCRDefault.storageValue,
        DefaultsKey.screenOCRRemoveLineBreaks: false,
        DefaultsKey.screenOCRDetectQRCodes: true,
        DefaultsKey.micMuteShortcutEnabled: false,
        DefaultsKey.micMuteShortcut: GlobalShortcut.micMuteDefault.storageValue,
        DefaultsKey.quitAppsShortcutEnabled: false,
        DefaultsKey.quitAppsShortcut: GlobalShortcut.quitAllDefault.storageValue,
        DefaultsKey.quitAppsExceptFrontShortcutEnabled: false,
        DefaultsKey.quitAppsExceptFrontShortcut: GlobalShortcut.quitAllExceptFrontDefault.storageValue,
        DefaultsKey.quitAppsKeptApps: mandatoryAutoQuitExceptionBundleIDs,
        DefaultsKey.cameraPreviewShortcutEnabled: false,
        DefaultsKey.cameraPreviewShortcut: GlobalShortcut.cameraPreviewDefault.storageValue,
        DefaultsKey.wallpaperApplyAllDisplays: true,
        DefaultsKey.wallpaperFilter: "all",
        DefaultsKey.scratchpadShortcutEnabled: true,
        DefaultsKey.scratchpadShortcut: GlobalShortcut.scratchpadDefault.storageValue,
        DefaultsKey.commandBarShortcutEnabled: false,
        DefaultsKey.commandBarCompactMode: false,
        DefaultsKey.commandBarASCIILayoutEnabled: false,
        DefaultsKey.commandBarDisabledSources: "",
        DefaultsKey.commandBarAliases: "",
        DefaultsKey.commandBarPins: "",
        DefaultsKey.commandBarHidden: "",
        DefaultsKey.commandBarFileScopes: "",
        DefaultsKey.commandBarFileIgnores: "",
        DefaultsKey.commandBarShortcut: GlobalShortcut.commandBarDefault.storageValue,
        DefaultsKey.commandBarPositionOffset: "",
        DefaultsKey.commandBarEmojiSkinTone: "",
        DefaultsKey.panelUtilityCommandBar: true,
        DefaultsKey.scratchpadRetention: ScratchpadRetention.never.rawValue,
        DefaultsKey.scratchpadCloseOnClickOutside: true,
        DefaultsKey.scratchpadBackgroundOpacity: 0.0,
        DefaultsKey.scratchpadTextSize: ScratchpadSupport.defaultTextSize,
        DefaultsKey.micMuteActive: false,
        DefaultsKey.micMuteSavedVolume: 0.75,
        DefaultsKey.micMuteMenuBarIndicator: true,
        DefaultsKey.quickLauncherShortcutEnabled: true,
        DefaultsKey.quickLauncherShortcut: GlobalShortcut.quickLauncherDefault.storageValue,
        DefaultsKey.quickLauncherHiddenItems: "",
        DefaultsKey.panelUtilityQuickLauncher: true,
        DefaultsKey.panelUtilityColorPicker: true,
        DefaultsKey.panelUtilityScreenOCR: true,
        DefaultsKey.panelUtilityCameraPreview: true,
        DefaultsKey.panelUtilityScratchpad: true,
        DefaultsKey.clipboardHistoryShortcutEnabled: true,
        DefaultsKey.clipboardHistoryShortcut: GlobalShortcut.clipboardDefault.storageValue,
        DefaultsKey.recorderShortcutEnabled: false,
        DefaultsKey.recorderShortcut: GlobalShortcut.screenRecorderDefault.storageValue,
        DefaultsKey.recorderCountdown: 3,
        DefaultsKey.recorderQuality: RecorderSupport.Quality.balanced.rawValue,
        DefaultsKey.recorderFrameRate: 60,
        DefaultsKey.recorderSystemAudio: true,
        DefaultsKey.recorderMicrophone: false,
        DefaultsKey.recorderSaveFolder: "",
        DefaultsKey.recorderOpenEditor: true,
        DefaultsKey.recorderAutomaticZoom: true,
        DefaultsKey.recorderGIFSize: RecorderSupport.GIFSize.medium.rawValue,
        DefaultsKey.recorderGIFFrameRate: 12,
        DefaultsKey.recorderEditorPresets: Data(),
        DefaultsKey.recorderSharingEnabled: true,
        DefaultsKey.panelUtilityScreenRecorder: true,
        DefaultsKey.panelUtilityPortManager: true,
        DefaultsKey.screenshotShowCaptureMenuOnShortcut: true,
        DefaultsKey.recorderShowCaptureMenuOnShortcut: true,
        DefaultsKey.screenOCRShowCaptureMenuOnShortcut: true,
        DefaultsKey.colorPickerShowCaptureMenuOnShortcut: true,
        DefaultsKey.screenshotShortcutEnabled: false,
        DefaultsKey.screenshotShortcut: GlobalShortcut.screenshotDefault.storageValue,
        DefaultsKey.unifiedScreenCaptureShortcutMigrated: false,
        DefaultsKey.restoredScreenCaptureShortcutsMigrated: false,
        DefaultsKey.screenshotFullScreenShortcutEnabled: false,
        DefaultsKey.screenshotFullScreenShortcut: GlobalShortcut.screenshotFullScreenDefault.storageValue,
        DefaultsKey.screenshotLastCaptureShortcutEnabled: false,
        DefaultsKey.screenshotLastCaptureShortcut: GlobalShortcut.screenshotLastCaptureDefault.storageValue,
        DefaultsKey.recentCapturesShortcutEnabled: false,
        DefaultsKey.recentCapturesShortcut: GlobalShortcut.recentCapturesDefault.storageValue,
        DefaultsKey.screenshotClipboardShortcutEnabled: false,
        DefaultsKey.screenshotClipboardShortcut: GlobalShortcut.screenshotClipboardDefault.storageValue,
        DefaultsKey.screenshotFreeze: true,
        DefaultsKey.screenshotHideVorssaintWindows: true,
        DefaultsKey.screenshotSaveFolder: "",
        DefaultsKey.screenshotSaveSubfolder: "",
        DefaultsKey.screenshotFileNamePattern: "",
        DefaultsKey.screenshotFileNumberStart: 1,
        DefaultsKey.screenshotFileNumberNext: 1,
        DefaultsKey.screenshotDefaultAction: "",
        DefaultsKey.screenshotIncludePointer: false,
        DefaultsKey.screenshotShowLastRegion: true,
        DefaultsKey.screenshotHighlightWindows: true,
        DefaultsKey.screenshotLoupeStartsOn: false,
        DefaultsKey.screenshotLoupeRememberZoom: false,
        DefaultsKey.screenshotLoupeDefaultZoom: 1.0,
        DefaultsKey.screenshotLoupeLastZoom: 1.0,
        DefaultsKey.screenshotLoupeSteppedZoomByDefault: false,
        DefaultsKey.screenshotDownscale: false,
        DefaultsKey.screenshotDelay: 0,
        DefaultsKey.screenshotLastTool: "arrow",
        DefaultsKey.screenshotLastColor: "red",
        DefaultsKey.screenshotLastStroke: "medium",
        DefaultsKey.screenshotLastTextSize: ScreenshotSupport.defaultTextSize,
        DefaultsKey.screenshotLastBlurLevel: ScreenshotSupport.BlurStrength.defaultLevel,
        DefaultsKey.screenshotLastBlurStyle: "pixelate",
        DefaultsKey.screenshotLastBlurTextOnly: false,
        DefaultsKey.screenshotSpotlightDim: Double(ScreenshotSupport.defaultSpotlightDim),
        DefaultsKey.screenshotLastArrowStyle: "filled",
        DefaultsKey.screenshotLastSticker: "check",
        DefaultsKey.screenshotAnnotationShadows: false,
        DefaultsKey.screenshotToolOrder: ScreenshotSupport.Tool.defaultOrderStorage,
        DefaultsKey.screenshotToolShortcutsEnabled: true,
        DefaultsKey.screenshotToolShortcuts: "",
        DefaultsKey.screenshotBackdropStyle: "",
        DefaultsKey.screenshotBackdropPresets: "[]",
        DefaultsKey.screenshotWatermarkStyle: "",
        DefaultsKey.screenshotWatermarkPresets: "[]",
        DefaultsKey.screenshotOpenEditorDirectly: false,
        DefaultsKey.screenshotCopyToClipboard: false,
        DefaultsKey.screenshotCopyImageOnly: false,
        DefaultsKey.screenshotAddToShelf: false,
        DefaultsKey.screenshotPreviewPosition: ScreenshotSupport.QuickPreviewPosition.automatic.rawValue,
        DefaultsKey.screenshotPreviewTakesFocus: true,
        DefaultsKey.screenshotUploadShortcutEnabled: false,
        DefaultsKey.screenshotUploadShortcut: GlobalShortcut.screenshotUploadDefault.storageValue,
        DefaultsKey.screenshotUploadDuration: ScreenshotShareDuration.oneHour.rawValue,
        DefaultsKey.screenshotPreviewEnabled: true,
        DefaultsKey.screenshotPreviewDuration: ScreenshotSupport.defaultConfirmationPreviewDuration,
        DefaultsKey.screenshotSharingEnabled: true,
        DefaultsKey.panelUtilityScreenshot: true,
        DefaultsKey.windowLayoutShortcutsEnabled: false,
        DefaultsKey.windowDirectionalEnabled: false,
        DefaultsKey.windowDirectionalShortcut: GlobalShortcut.windowDirectionalDefault.storageValue,
        DefaultsKey.pointerDisplayEnabled: false,
        DefaultsKey.pointerDisplayShortcut: GlobalShortcut.pointerNextDisplayDefault.storageValue,
        DefaultsKey.windowEdgeSnapEnabled: false,
        DefaultsKey.windowEdgeSnapDisabledZones: "",
        DefaultsKey.windowEdgeSnapZoneActions: "",
        DefaultsKey.windowGestureEnabled: false,
        DefaultsKey.windowGestureModifiers: WindowGestureSupport.defaultModifierStorageValue,
        DefaultsKey.windowGestureRaiseWindow: false,
        DefaultsKey.windowLayoutShortcutLeft: GlobalShortcut.windowLayoutLeftDefault.storageValue,
        DefaultsKey.windowLayoutShortcutRight: GlobalShortcut.windowLayoutRightDefault.storageValue,
        DefaultsKey.windowLayoutShortcutTop: GlobalShortcut.windowLayoutTopDefault.storageValue,
        DefaultsKey.windowLayoutShortcutBottom: GlobalShortcut.windowLayoutBottomDefault.storageValue,
        DefaultsKey.windowLayoutShortcutCenterHalf: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutTopLeft: GlobalShortcut.windowLayoutTopLeftDefault.storageValue,
        DefaultsKey.windowLayoutShortcutTopRight: GlobalShortcut.windowLayoutTopRightDefault.storageValue,
        DefaultsKey.windowLayoutShortcutBottomLeft: GlobalShortcut.windowLayoutBottomLeftDefault.storageValue,
        DefaultsKey.windowLayoutShortcutBottomRight: GlobalShortcut.windowLayoutBottomRightDefault.storageValue,
        DefaultsKey.windowLayoutShortcutMaximize: GlobalShortcut.windowLayoutMaximizeDefault.storageValue,
        DefaultsKey.windowLayoutShortcutMarginMaximize: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutCenter: GlobalShortcut.windowLayoutCenterDefault.storageValue,
        DefaultsKey.windowLayoutShortcutRestore: GlobalShortcut.windowLayoutRestoreDefault.storageValue,
        DefaultsKey.windowLayoutShortcutLeftThird: GlobalShortcut.windowLayoutLeftThirdDefault.storageValue,
        DefaultsKey.windowLayoutShortcutCenterThird: GlobalShortcut.windowLayoutCenterThirdDefault.storageValue,
        DefaultsKey.windowLayoutShortcutRightThird: GlobalShortcut.windowLayoutRightThirdDefault.storageValue,
        DefaultsKey.windowLayoutShortcutLeftTwoThirds: GlobalShortcut.windowLayoutLeftTwoThirdsDefault.storageValue,
        DefaultsKey.windowLayoutShortcutRightTwoThirds: GlobalShortcut.windowLayoutRightTwoThirdsDefault.storageValue,
        DefaultsKey.windowLayoutShortcutCenterTwoThirds: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutTopThird: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutMiddleThird: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutBottomThird: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutTopTwoThirds: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutBottomTwoThirds: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutTopQuarter: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutUpperMiddleQuarter: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutLowerMiddleQuarter: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutBottomQuarter: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutLeftQuarter: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutLeftMiddleQuarter: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutRightMiddleQuarter: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutRightQuarter: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutPreviousDisplay: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutNextDisplay: GlobalShortcut.windowLayoutNextDisplayDefault.storageValue,
        DefaultsKey.windowLayoutShortcutTopLeftSixth: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutTopCenterSixth: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutTopRightSixth: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutBottomLeftSixth: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutBottomCenterSixth: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutBottomRightSixth: WindowLayoutAction.clearedShortcutStorageValue,
        DefaultsKey.windowLayoutShortcutFullScreen: WindowLayoutAction.clearedShortcutStorageValue,
    ]

    static func register() {
        let defaults = UserDefaults.standard
        migrateClipboardSensitiveTextOptIn(in: defaults)
        migrateNotchAgentsOptIn(in: defaults)
        migrateExistingNotchDefaults(in: defaults)
        migrateLiquidGlassIsland(in: defaults)
        migrateFanControlVisibility(in: defaults)
        migrateScrollInverterAxes(in: defaults)
        migrateLinearScrollAvailability(in: defaults)
        migrateWhatsAppDownloadsEnabled(in: defaults)
        migrateBatteryTemperatureVisibility(in: defaults)
        migratePowerPeripheralsVisibility(in: defaults)
        migrateSwitcherPreviewSize(in: defaults)
        migrateSwitcherPreviewExcludedApps(in: defaults)
        migrateNotchWatchAvailability(in: defaults)
        defaults.register(defaults: registeredDefaults)
        defaults.register(defaults: AppFeature.availabilityDefaults)
        activateBetaChannelIfRunningBeta(in: defaults)
        installCompanionForBetaCommandBar(in: defaults)
        migrateLegacyMenuBarTemperatureMetric(in: defaults)
        migrateLegacySwitcherWindowShortcut(in: defaults)
        migrateLegacyKeyboardDebounceWindow(in: defaults)
        migrateUtilityOrderForScreenshot(in: defaults)
        migrateUtilityOrderForAppUpdates(in: defaults)
        migrateScreenshotOpenEditorDirectly(in: defaults)
        migrateUnifiedScreenCaptureShortcut(in: defaults)
        migrateRestoredScreenCaptureShortcuts(in: defaults)
        migrateOrphanedCaptureShortcut(in: defaults)
        migrateSilentHeadphonesDisconnectVolume(in: defaults)
        migrateAppVolumesToPositions(in: defaults)
        migrateSwitcherWindowlessFinder(in: defaults)
        recheckBrightnessDDCWriteOnlyPaths(in: defaults)
        hideScratchpadControlOnce(in: defaults)
        hideKeyboardLightControlOnce(in: defaults)
        defaults.removeObject(forKey: DefaultsKey.mixerUniversalOutputDevice)
    }

    static func migrateClipboardSensitiveTextOptIn(in defaults: UserDefaults) {
        defaults.removeObject(forKey: "clipboardHistorySkipSensitive")
    }

    static func migrateNotchAgentsOptIn(in defaults: UserDefaults,
                                       domainName: String? = Bundle.main.bundleIdentifier) {
        guard let domainName else { return }
        let saved = defaults.persistentDomain(forName: domainName) ?? [:]
        guard saved[DefaultsKey.notchAgentsOptInMigrated] == nil else { return }
        if saved[DefaultsKey.notchDefaultProfileInitialized] as? Bool == true,
           saved[DefaultsKey.notchAgentsEnabled] == nil {
            defaults.set(true, forKey: DefaultsKey.notchAgentsEnabled)
        }
        defaults.set(true, forKey: DefaultsKey.notchAgentsOptInMigrated)
    }

    static func migrateLiquidGlassIsland(in defaults: UserDefaults,
                                         domainName: String? = Bundle.main.bundleIdentifier) {
        guard let domainName else { return }
        let saved = defaults.persistentDomain(forName: domainName) ?? [:]
        guard saved[DefaultsKey.notchLiquidGlassEnabled] == nil else { return }
        defaults.set(saved[DefaultsKey.liquidGlassEnabled] as? Bool ?? false,
                     forKey: DefaultsKey.notchLiquidGlassEnabled)
    }

    static func migrateExistingNotchDefaults(in defaults: UserDefaults,
                                             domainName: String? = Bundle.main.bundleIdentifier) {
        guard let domainName else { return }
        let saved = defaults.persistentDomain(forName: domainName) ?? [:]
        guard saved[DefaultsKey.notchDefaultProfileInitialized] == nil else {
            if saved[DefaultsKey.notchSize] == nil {
                defaults.set(NotchSize.compact.rawValue, forKey: DefaultsKey.notchSize)
            }
            return
        }
        let automaticKeys: Set<String> = [DefaultsKey.notchScratchpadControlHidden,
                                          DefaultsKey.notchKeyboardLightControlHidden,
                                          DefaultsKey.notchHidesMenuBarIcon,
                                          DefaultsKey.notchAgentsOptInMigrated]
        let wasConfigured = saved.keys.contains {
            $0.hasPrefix("notch") && !automaticKeys.contains($0)
                && ($0 != DefaultsKey.notchHiddenControls
                    || saved[$0] as? String != NotchControlItem.defaultHidden)
        } || saved[DefaultsKey.notchHidesMenuBarIcon] as? Bool == true
        if wasConfigured {
            defaults.set(true, forKey: DefaultsKey.notchInitialExtensionsInstalled)
            let previous: [String: Any] = [
                DefaultsKey.notchSize: NotchSize.spacious.rawValue,
                DefaultsKey.notchAppPanel: true,
                DefaultsKey.notchKeyboardLight: false,
                DefaultsKey.notchNotificationsEnabled: false,
                DefaultsKey.notchCameraEnabled: false,
                DefaultsKey.notchAccessoriesEnabled: false,
                DefaultsKey.notchAgentsEnabled: false,
                DefaultsKey.notchLyricsEnabled: false,
                DefaultsKey.notchLiveEqualizer: false,
                DefaultsKey.notchQueueEnabled: false,
                DefaultsKey.notchDownloadsEnabled: false,
                DefaultsKey.notchOpenOnHover: true,
                DefaultsKey.notchClipboard: false,
                DefaultsKey.notchCapture: false,
                DefaultsKey.notchTrackChange: false,
            ]
            for (key, value) in previous where saved[key] == nil {
                defaults.set(value, forKey: key)
            }
        }
        if !wasConfigured {
            defaults.set(NotchSize.spacious.rawValue, forKey: DefaultsKey.notchSize)
        }
        defaults.set(true, forKey: DefaultsKey.notchDefaultProfileInitialized)
    }

    static func hideScratchpadControlOnce(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: DefaultsKey.notchScratchpadControlHidden) else { return }
        defaults.set(true, forKey: DefaultsKey.notchScratchpadControlHidden)
        guard let saved = defaults.string(forKey: DefaultsKey.notchHiddenControls) else { return }
        var hidden = saved.split(separator: ",").map(String.init)
        guard !hidden.contains(NotchControlItem.scratchpad.rawValue) else { return }
        hidden.append(NotchControlItem.scratchpad.rawValue)
        defaults.set(hidden.joined(separator: ","), forKey: DefaultsKey.notchHiddenControls)
    }

    static func hideKeyboardLightControlOnce(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: DefaultsKey.notchKeyboardLightControlHidden) else { return }
        defaults.set(true, forKey: DefaultsKey.notchKeyboardLightControlHidden)
        guard let saved = defaults.string(forKey: DefaultsKey.notchHiddenControls) else { return }
        var hidden = saved.split(separator: ",").map(String.init)
        guard !hidden.contains(NotchControlItem.keyboardLight.rawValue) else { return }
        hidden.append(NotchControlItem.keyboardLight.rawValue)
        defaults.set(hidden.joined(separator: ","), forKey: DefaultsKey.notchHiddenControls)
    }

    static func recheckBrightnessDDCWriteOnlyPaths(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: DefaultsKey.brightnessDDCWriteOnlyPathsRechecked) else {
            return
        }
        defaults.set(true, forKey: DefaultsKey.brightnessDDCWriteOnlyPathsRechecked)
        defaults.removeObject(forKey: DefaultsKey.brightnessDDCWriteOnlyPaths)
    }

    static func migrateSwitcherPreviewSize(in defaults: UserDefaults) {
        guard defaults.object(forKey: DefaultsKey.switcherPreviewSize) == nil else { return }
        defaults.set(defaults.string(forKey: DefaultsKey.previewSize) ?? "normal",
                     forKey: DefaultsKey.switcherPreviewSize)
    }

    static func migrateSwitcherPreviewExcludedApps(in defaults: UserDefaults) {
        guard defaults.object(forKey: DefaultsKey.switcherPreviewExcludedApps) == nil else { return }
        defaults.set(defaults.stringArray(forKey: DefaultsKey.windowPreviewExcludedApps) ?? [],
                     forKey: DefaultsKey.switcherPreviewExcludedApps)
    }

    static func migrateBatteryTemperatureVisibility(in defaults: UserDefaults) {
        guard defaults.object(forKey: DefaultsKey.monitorPwrTemperature) == nil else { return }
        defaults.set(defaults.object(forKey: DefaultsKey.monitorSysTemps) as? Bool ?? true,
                     forKey: DefaultsKey.monitorPwrTemperature)
    }

    static func migratePowerPeripheralsVisibility(in defaults: UserDefaults) {
        guard defaults.object(forKey: DefaultsKey.monitorPwrPeripherals) == nil else { return }
        defaults.set(defaults.bool(forKey: DefaultsKey.menuBarPeripheralBattery),
                     forKey: DefaultsKey.monitorPwrPeripherals)
    }

    static func activateBetaChannelIfRunningBeta(in defaults: UserDefaults,
                                                 version: String = AppInfo.version,
                                                 isBeta: Bool = AppInfo.isBeta) {
        let isPre = isBeta || {
            let v = version.lowercased()
            return v.contains("-beta") || v.contains("-rc") || v.contains("-alpha")
        }()
        guard isPre else { return }
        let markerKey = "betaChannelActivatedFor.\(version)"
        guard !defaults.bool(forKey: markerKey) else { return }
        defaults.set(true, forKey: markerKey)
        defaults.set(true, forKey: DefaultsKey.includeBetaUpdates)
    }

    static func installsCompanionForBeta(in defaults: UserDefaults, isBeta: Bool = AppInfo.isBeta) -> Bool {
        isBeta && defaults.bool(forKey: DefaultsKey.hasOnboarded)
            && !defaults.bool(forKey: DefaultsKey.notchMascotBetaInstalled)
            && AppFeature.commandBar.isAvailable(in: defaults)
            && AppFeature.notch.isAvailable(in: defaults)
    }

    static func installCompanionForBetaCommandBar(in defaults: UserDefaults, isBeta: Bool = AppInfo.isBeta) {
        guard installsCompanionForBeta(in: defaults, isBeta: isBeta) else { return }
        defaults.set(true, forKey: DefaultsKey.notchMascotBetaInstalled)
        defaults.set(true, forKey: AppFeature.notchMascot.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.notchMascotEnabled)
    }

    static func migrateWhatsAppDownloadsEnabled(in defaults: UserDefaults) {
        guard defaults.object(forKey: DefaultsKey.whatsAppDownloadsEnabled) == nil else {
            return
        }
        let alreadyUsing = defaults.bool(forKey: DefaultsKey.whatsAppDownloadsAutomaticEnabled)
            || defaults.bool(forKey: DefaultsKey.whatsAppOrganizerEnabled)
        if alreadyUsing {
            defaults.set(true, forKey: DefaultsKey.whatsAppDownloadsEnabled)
        }
    }

    static func migrateScrollInverterAxes(in defaults: UserDefaults) {
        guard defaults.object(forKey: DefaultsKey.scrollInverterHorizontalEnabled) == nil else {
            return
        }
        defaults.set(defaults.bool(forKey: DefaultsKey.scrollInverterEnabled),
                     forKey: DefaultsKey.scrollInverterHorizontalEnabled)
    }

    static func migrateNotchWatchAvailability(in defaults: UserDefaults) {
        guard defaults.object(forKey: AppFeature.notchWatch.availabilityKey) == nil,
              defaults.object(forKey: AppFeature.notch.availabilityKey) as? Bool == false
        else { return }
        defaults.set(false, forKey: AppFeature.notchWatch.availabilityKey)
    }

    static func migrateLinearScrollAvailability(in defaults: UserDefaults) {
        guard defaults.object(forKey: AppFeature.linearScroll.availabilityKey) == nil,
              defaults.object(forKey: DefaultsKey.linearScrollEnabled) as? Bool == true
        else { return }
        defaults.set(true, forKey: AppFeature.linearScroll.availabilityKey)
    }

    static func migrateFanControlVisibility(in defaults: UserDefaults) {
        if let oldValue = defaults.object(forKey: DefaultsKey.monitorShowFanControlBeta) as? Bool {
            if defaults.object(forKey: DefaultsKey.panelShowFanControl) == nil {
                defaults.set(oldValue, forKey: DefaultsKey.panelShowFanControl)
            }
            if oldValue,
               defaults.object(forKey: AppFeature.fanControl.availabilityKey) == nil {
                defaults.set(true, forKey: AppFeature.fanControl.availabilityKey)
            }
        }
        defaults.removeObject(forKey: DefaultsKey.monitorShowFanControlBeta)
    }

    static func migrateSwitcherWindowlessFinder(in defaults: UserDefaults) {
        let showsWindowlessFinder = defaults.bool(forKey: DefaultsKey.switcherShowWindowlessFinder)
        guard !showsWindowlessFinder else { return }
        defaults.set(true, forKey: DefaultsKey.switcherShowWindowlessFinder)
        let mode = SwitcherWindowlessApps.migrated(showsWindowlessFinder: showsWindowlessFinder)
        defaults.set(mode.rawValue, forKey: DefaultsKey.switcherWindowlessApps)
    }

    static func migrateScreenshotOpenEditorDirectly(in defaults: UserDefaults) {
        guard defaults.bool(forKey: DefaultsKey.screenshotOpenEditorDirectly) else { return }
        defaults.set(false, forKey: DefaultsKey.screenshotOpenEditorDirectly)
        let action = defaults.string(forKey: DefaultsKey.screenshotDefaultAction) ?? ""
        guard action.isEmpty else { return }
        defaults.set(ScreenshotDefaultAction.edit.rawValue,
                     forKey: DefaultsKey.screenshotDefaultAction)
    }

    static func migrateUnifiedScreenCaptureShortcut(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: DefaultsKey.unifiedScreenCaptureShortcutMigrated) else {
            return
        }
        defer {
            defaults.set(true, forKey: DefaultsKey.unifiedScreenCaptureShortcutMigrated)
        }
        guard !defaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled) else { return }

        let legacyChoices: [(enabled: String, shortcut: String, fallback: GlobalShortcut)] = [
            (DefaultsKey.recorderShortcutEnabled,
             DefaultsKey.recorderShortcut,
             .screenRecorderDefault),
            (DefaultsKey.screenOCRShortcutEnabled,
             DefaultsKey.screenOCRShortcut,
             .screenOCRDefault),
            (DefaultsKey.colorPickerShortcutEnabled,
             DefaultsKey.colorPickerShortcut,
             .colorPickerDefault),
        ]
        guard let choice = legacyChoices.first(where: {
            defaults.bool(forKey: $0.enabled)
        }) else { return }
        let shortcut = defaults.string(forKey: choice.shortcut) ?? choice.fallback.storageValue
        defaults.set(true, forKey: DefaultsKey.screenshotShortcutEnabled)
        defaults.set(shortcut, forKey: DefaultsKey.screenshotShortcut)
    }

    static func migrateRestoredScreenCaptureShortcuts(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: DefaultsKey.restoredScreenCaptureShortcutsMigrated) else {
            return
        }
        defer {
            defaults.set(true, forKey: DefaultsKey.restoredScreenCaptureShortcutsMigrated)
        }
        guard defaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled),
              let generalShortcut = defaults.string(forKey: DefaultsKey.screenshotShortcut)
        else { return }

        let dedicatedKeys = [
            (DefaultsKey.recorderShortcutEnabled, DefaultsKey.recorderShortcut),
            (DefaultsKey.screenOCRShortcutEnabled, DefaultsKey.screenOCRShortcut),
            (DefaultsKey.colorPickerShortcutEnabled, DefaultsKey.colorPickerShortcut),
        ]
        guard dedicatedKeys.contains(where: { enabledKey, shortcutKey in
            defaults.bool(forKey: enabledKey)
                && defaults.string(forKey: shortcutKey) == generalShortcut
        }) else { return }
        defaults.set(false, forKey: DefaultsKey.screenshotShortcutEnabled)
    }

    static func migrateOrphanedCaptureShortcut(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: DefaultsKey.orphanedCaptureShortcutMigrated) else {
            return
        }
        defer {
            defaults.set(true, forKey: DefaultsKey.orphanedCaptureShortcutMigrated)
        }
        guard defaults.bool(forKey: DefaultsKey.screenshotShortcutEnabled),
              !defaults.bool(forKey: AppFeature.screenshot.availabilityKey)
        else { return }
        let shortcut = defaults.string(forKey: DefaultsKey.screenshotShortcut)
            ?? GlobalShortcut.screenshotDefault.storageValue

        let candidates: [(feature: AppFeature, enabled: String,
                          shortcut: String, unset: String)] = [
            (.screenRecorder, DefaultsKey.recorderShortcutEnabled,
             DefaultsKey.recorderShortcut,
             GlobalShortcut.screenRecorderDefault.storageValue),
            (.screenOCR, DefaultsKey.screenOCRShortcutEnabled,
             DefaultsKey.screenOCRShortcut,
             GlobalShortcut.screenOCRDefault.storageValue),
            (.colorPicker, DefaultsKey.colorPickerShortcutEnabled,
             DefaultsKey.colorPickerShortcut,
             GlobalShortcut.colorPickerDefault.storageValue),
        ]
        guard let target = candidates.first(where: {
            defaults.bool(forKey: $0.feature.availabilityKey)
                && !defaults.bool(forKey: $0.enabled)
                && (defaults.string(forKey: $0.shortcut) ?? $0.unset) == $0.unset
        }) else { return }
        defaults.set(true, forKey: target.enabled)
        defaults.set(shortcut, forKey: target.shortcut)
        defaults.set(false, forKey: DefaultsKey.screenshotShortcutEnabled)
    }

    static func migrateLegacySwitcherWindowShortcut(in defaults: UserDefaults) {
        let wrongDeveloperDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_Grave),
                                                   modifiers: [.control, .option, .command]).storageValue
        guard defaults.string(forKey: DefaultsKey.switcherWindowShortcut) == wrongDeveloperDefault else {
            return
        }
        defaults.set(GlobalShortcut.switcherWindowDefault.storageValue,
                     forKey: DefaultsKey.switcherWindowShortcut)
    }

    static func migrateLegacyKeyboardDebounceWindow(in defaults: UserDefaults) {
        guard let storedWindow = defaults.object(forKey: DefaultsKey.keyboardDebounceWindowMs) as? Int,
              storedWindow == 30 || storedWindow == 10,
              defaults.bool(forKey: DefaultsKey.keyboardDebounceEnabled) == false,
              (defaults.string(forKey: DefaultsKey.keyboardDebounceKeyWindows) ?? "").isEmpty
        else { return }
        defaults.set(defaultKeyboardDebounceWindowMs, forKey: DefaultsKey.keyboardDebounceWindowMs)
    }

    static func migrateUtilityOrderForScreenshot(in defaults: UserDefaults) {
        guard let storedOrder = defaults.object(forKey: DefaultsKey.panelUtilityOrder) as? String else {
            return
        }
        let ids = storedOrder.split(separator: ",").map(String.init)
        guard !ids.contains("screenshot") else { return }
        defaults.set((["screenshot"] + ids).joined(separator: ","),
                     forKey: DefaultsKey.panelUtilityOrder)
    }

    static func migrateUtilityOrderForAppUpdates(in defaults: UserDefaults) {
        guard let storedOrder = defaults.object(forKey: DefaultsKey.panelUtilityOrder) as? String else {
            return
        }
        defaults.set(utilityOrderWithAppUpdates(storedOrder).joined(separator: ","),
                     forKey: DefaultsKey.panelUtilityOrder)
    }

    static func utilityOrderWithAppUpdates(_ storedOrder: String) -> [String] {
        var ids = storedOrder.split(separator: ",").map(String.init)
        guard !ids.contains("appUpdates") else { return ids }
        let anchor = ids.firstIndex(of: "cleaner") ?? min(1, ids.count)
        ids.insert("appUpdates", at: anchor)
        return ids
    }

    static func sanitizedDefaultDuration(_ minutes: Int) -> Int {
        allowedDurations.contains(minutes) ? minutes : 0
    }

    static func sanitizedBatteryLimit(_ percent: Int) -> Int {
        allowedBatteryLimits.contains(percent) ? percent : 10
    }

    static func sanitizedKeepAwakeMouseJiggleInterval(_ minutes: Int) -> Int {
        allowedKeepAwakeMouseJiggleIntervals.contains(minutes) ? minutes : 5
    }

    static func sanitizedKeepAwakeIconTint(_ rawValue: String?) -> KeepAwakeIconTint {
        guard let rawValue,
              let tint = KeepAwakeIconTint(rawValue: rawValue) else {
            return .orange
        }
        return tint
    }

    static func sanitizedKeepAwakeActiveIcon(_ rawValue: String?) -> KeepAwakeActiveIcon {
        guard let rawValue,
              let icon = KeepAwakeActiveIcon(rawValue: rawValue) else {
            return .vorssaint
        }
        return icon
    }

    static func sanitizedMenuBarIconSymbol(_ rawValue: String?) -> String {
        rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func menuBarIconSymbolToSave(typed: String?, opening: String,
                                        exists: (String) -> Bool) -> String {
        let name = sanitizedMenuBarIconSymbol(typed)
        return name.isEmpty || exists(name) ? name : opening
    }

    static let menuBarIconGallery = [
        "bolt.fill", "star.fill", "heart.fill", "flame.fill", "sparkles", "leaf.fill",
        "drop.fill", "snowflake", "sun.max.fill", "moon.stars.fill", "cloud.fill", "mountain.2.fill",
        "circle.fill", "square.fill", "triangle.fill", "diamond.fill", "hexagon.fill", "seal.fill",
        "circle.lefthalf.filled", "circle.hexagongrid.fill", "infinity",
        "command", "cpu.fill", "memorychip.fill", "gauge.with.dots.needle.67percent",
        "fanblades.fill", "gearshape.fill", "terminal.fill", "waveform",
        "wand.and.stars", "key.fill", "crown.fill", "gamecontroller.fill", "headphones",
        "music.note", "paperplane.fill", "pawprint.fill", "cat.fill", "hare.fill", "tortoise.fill",
    ]

    static func sanitizedMonitorInterval(_ seconds: Int) -> Int {
        allowedMonitorIntervals.contains(seconds) ? seconds : 2
    }

    static func sanitizedMiddleClickTapFingers(_ raw: Int) -> Int {
        raw == 3 || raw == 4 ? raw : 0
    }

    static func sanitizedKeyboardDebounceWindow(_ milliseconds: Int) -> Int {
        allowedKeyboardDebounceWindowRange.contains(milliseconds)
            ? milliseconds
            : defaultKeyboardDebounceWindowMs
    }

    static func sanitizedMouseClickDebounceWindow(_ milliseconds: Int) -> Int {
        allowedMouseClickDebounceWindowRange.contains(milliseconds)
            ? milliseconds
            : defaultMouseClickDebounceWindowMs
    }

    static func sanitizedClipboardAutoClearDelay(_ seconds: Int) -> Int {
        min(max(seconds, allowedClipboardAutoClearDelayRange.lowerBound),
            allowedClipboardAutoClearDelayRange.upperBound)
    }

    static func sanitizedClipboardMenuBarPreviewLength(_ characters: Int) -> Int {
        min(max(characters, allowedClipboardMenuBarPreviewLengthRange.lowerBound),
            allowedClipboardMenuBarPreviewLengthRange.upperBound)
    }

    static func sanitizedMenuBarPreset(_ preset: String) -> String {
        allowedMenuBarPresets.contains(preset) ? preset : "dense"
    }

    static func sanitizedMenuBarMetricSpacing(_ spacing: String) -> String {
        allowedMenuBarMetricSpacings.contains(spacing) ? spacing : "compact"
    }

    static func sanitizedMenuBarMetricAppearance(_ appearance: String) -> String {
        allowedMenuBarMetricAppearances.contains(appearance) ? appearance : "values"
    }

    static func sanitizedMenuBarMetricOrder(_ raw: String) -> [String] {
        let defaults = defaultMenuBarMetricOrder
        var seen = Set<String>()
        var result: [String] = []
        for rawValue in raw.split(separator: ",").map({ String($0) }) {
            let values = rawValue == "temperature"
                ? ["cpuTemperature", "gpuTemperature", "batteryTemperature"]
                : [rawValue]
            for value in values {
                guard defaults.contains(value), !seen.contains(value) else { continue }
                seen.insert(value)
                result.append(value)
            }
        }
        for value in defaults where !seen.contains(value) {
            result.append(value)
        }
        return result
    }

    private static func migrateLegacyMenuBarTemperatureMetric(in defaults: UserDefaults) {
        guard let domainName = Bundle.main.bundleIdentifier,
              let domain = defaults.persistentDomain(forName: domainName),
              let legacyEnabled = domain[DefaultsKey.menuBarTemperature] as? Bool
        else { return }

        let newKeys = [
            DefaultsKey.menuBarCPUTemperature,
            DefaultsKey.menuBarGPUTemperature,
            DefaultsKey.menuBarBatteryTemperature,
        ]
        let alreadyMigrated = newKeys.contains { domain[$0] != nil }
        if legacyEnabled, !alreadyMigrated {
            for key in newKeys {
                defaults.set(true, forKey: key)
            }
        }
        if let rawOrder = domain[DefaultsKey.menuBarMetricOrder] as? String {
            defaults.set(sanitizedMenuBarMetricOrder(rawOrder).joined(separator: ","),
                         forKey: DefaultsKey.menuBarMetricOrder)
        }
        defaults.removeObject(forKey: DefaultsKey.menuBarTemperature)
    }

    static func sanitizedMenuBarLabelStyle(_ style: String) -> String {
        allowedMenuBarLabelStyles.contains(style) ? style : "compact"
    }

    static func sanitizedMenuBarMemoryStyle(_ style: String) -> String {
        allowedMenuBarMemoryStyles.contains(style) ? style : "percent"
    }

    static func sanitizedMonitorMemoryMetric(_ metric: String) -> String {
        allowedMonitorMemoryMetrics.contains(metric) ? metric : "used"
    }

    static func sanitizedClipboardHistoryLimit(_ value: Int) -> Int {
        allowedClipboardHistoryLimits.contains(value) ? value : 50
    }

    static func sanitizedClipboardHistoryRetentionDays(_ value: Int) -> Int {
        allowedClipboardHistoryRetentionDays.contains(value) ? value : 0
    }

    static func sanitizedMonitorAlertCooldown(_ value: Int) -> Int {
        allowedMonitorAlertCooldowns.contains(value) ? value : 15
    }

    static func sanitizedPercent(_ value: Int, fallback: Int, range: ClosedRange<Int>) -> Int {
        range.contains(value) ? value : fallback
    }

    static func sanitizedBundleIdentifierList(_ bundleIDs: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in bundleIDs {
            let bundleID = MouseAppExceptionSupport.isExecutablePathIdentity(raw)
                ? raw
                : raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty, !seen.contains(bundleID) else { continue }
            seen.insert(bundleID)
            result.append(bundleID)
        }
        return result
    }

    static func sanitizedAutoQuitExceptions(_ bundleIDs: [String]) -> [String] {
        sanitizedBundleIdentifierList(mandatoryAutoQuitExceptionBundleIDs + bundleIDs)
    }

    static func sanitizedAutoQuitDockApps(_ bundleIDs: [String]) -> [String] {
        sanitizedBundleIdentifierList(bundleIDs).filter {
            !mandatoryAutoQuitExceptionBundleIDs.contains($0)
        }
    }

    static func sanitizedDiskExclusionList(_ list: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in list {
            let item = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = item.lowercased()
            guard !item.isEmpty, seen.insert(lower).inserted else { continue }
            result.append(item)
        }
        return result
    }

    static func sanitizedPanelItemOrder(_ raw: String, defaultOrder: [String]) -> [String] {
        let allowed = Set(defaultOrder)
        var seen = Set<String>()
        var result: [String] = []
        for id in raw.split(separator: ",").map(String.init) {
            guard allowed.contains(id), seen.insert(id).inserted else { continue }
            result.append(id)
        }
        for id in defaultOrder where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    static func sanitizedAppVolume(_ volume: Double) -> Double {
        guard volume.isFinite else { return 1 }
        return min(max(volume, 0), 1)
    }

    static let minimumMixerHeadphonesDisconnectVolumePercent = 0
    static let defaultMixerHeadphonesDisconnectVolumePercent = 25
    static let legacyMixerHeadphonesDisconnectVolumeFloor = 10

    static func sanitizedMixerHeadphonesDisconnectVolumePercent(_ percent: Int) -> Int {
        min(max(percent, minimumMixerHeadphonesDisconnectVolumePercent), 100)
    }

    static func migrateSilentHeadphonesDisconnectVolume(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: DefaultsKey.mixerHeadphonesDisconnectSilenceAllowed) else { return }
        if let stored = defaults.object(forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent) as? Int,
           stored < legacyMixerHeadphonesDisconnectVolumeFloor {
            defaults.set(defaultMixerHeadphonesDisconnectVolumePercent,
                         forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent)
        }
        defaults.set(true, forKey: DefaultsKey.mixerHeadphonesDisconnectSilenceAllowed)
    }

    static func migrateAppVolumesToPositions(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: DefaultsKey.appVolumesArePositions) else { return }
        defer { defaults.set(true, forKey: DefaultsKey.appVolumesArePositions) }
        guard let saved = defaults.dictionary(forKey: DefaultsKey.appVolumes), !saved.isEmpty else { return }
        var positions: [String: Double] = [:]
        for (id, value) in saved {
            guard let gain = (value as? NSNumber)?.doubleValue, gain.isFinite else { continue }
            positions[id] = MixerRoutingSupport.volume(forGain: sanitizedAppVolume(gain))
        }
        defaults.set(positions, forKey: DefaultsKey.appVolumes)
    }

    static func sanitizedAppOutputDeviceUID(_ value: Any?) -> String? {
        MixerRoutingSupport.sanitizedDeviceUID(value)
    }

    static func sanitizedAppOutputDevices(_ raw: [String: Any]) -> [String: String] {
        MixerRoutingSupport.sanitizedRouteMap(raw)
    }

    static func sanitizedSoundOutputSwitcherDeviceUIDs(_ raw: [Any]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in raw {
            guard let uid = MixerRoutingSupport.sanitizedDeviceUID(value),
                  seen.insert(uid).inserted else { continue }
            result.append(uid)
        }
        return result
    }

    static func sanitizedPreferredInputDeviceUID(_ value: Any?) -> String? {
        MixerRoutingSupport.sanitizedDeviceUID(value)
    }

    static let audioPriorityMaxListSize = 64

    static func sanitizedAudioPriorityUIDs(_ raw: [Any]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in raw {
            guard let uid = MixerRoutingSupport.sanitizedDeviceUID(value),
                  seen.insert(uid).inserted else { continue }
            result.append(uid)
            if result.count >= audioPriorityMaxListSize { break }
        }
        return result
    }

    static func sanitizedAudioPriorityDeviceNames(_ raw: [String: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (rawUID, rawName) in raw {
            guard let uid = MixerRoutingSupport.sanitizedDeviceUID(rawUID),
                  let name = MixerRoutingSupport.sanitizedDeviceUID(rawName) else { continue }
            result[uid] = name
        }
        return result
    }
}
