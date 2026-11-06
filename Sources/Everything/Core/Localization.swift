// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

enum CountAgreement {
    case oneAndMany
    case byLastDigits
    case byWholeNumber
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case enUS = "en-US"

    var id: String { rawValue }

    var countAgreement: CountAgreement { .oneAndMany }

    var displayName: String {
        switch self {
        case .enUS: return "English (US)"
        }
    }

    func formattingLocale(system: Locale = .autoupdatingCurrent) -> Locale {
        var components = Locale.Components(identifier: rawValue)
        components.region = system.region
        components.hourCycle = system.hourCycle
        components.firstDayOfWeek = system.firstDayOfWeek
        return Locale(components: components)
    }

    static var systemDefault: AppLanguage { .enUS }
}

final class L10n: ObservableObject {
    static let shared = L10n()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: DefaultsKey.language) }
    }

    var s: Strings { Strings.localized(language) }

    private init() {
        language = .enUS
    }

}

extension Strings {
    static func localized(_ language: AppLanguage) -> Strings { .enUS }
}

struct Strings {
    // MARK: Menu bar & context menu
    let statusIdleTooltip: String
    let statusActiveUntil: String
    let statusActiveIndefinite: String
    let menuEnableAwake: String
    let menuDisableAwake: String
    let menuActivateFor: String
    let menuSettings: String
    let menuAbout: String
    let menuQuit: String
    let menuHide: String
    let menuHideOthers: String
    let menuShowAll: String
    let menuEdit: String
    let menuUndo: String
    let menuRedo: String
    let actionClear: String
    let actionRemove: String
    let actionBack: String
    let actionSearch: String
    let actionMute: String
    let actionUnmute: String
    let actionPlay: String
    let actionPause: String
    let menuCut: String
    let menuCopy: String
    let menuPaste: String
    let menuSelectAll: String
    let menuWindow: String
    let menuMinimize: String
    let menuZoom: String
    let menuClose: String

    // MARK: Durations
    let minutes15: String
    let minutes30: String
    let hour1: String
    let hours2: String
    let hours4: String
    let hours8: String
    let indefinitely: String
    let indefinite: String

    // MARK: Panel — header & footer
    let panelSettings: String
    let panelQuit: String
    let panelHotkeyHint: String

    // MARK: Panel — keep awake card
    let keepAwakeTitle: String
    let keepAwakeEndsIn: String
    let keepAwakeUntilDisabled: String
    let keepAwakeNormalRules: String
    let keepAwakeUntilLabel: String
    let keepAwakeUntilStart: String
    let keepAwakeOptions: String
    let keepAwakeMouseJiggle: String
    let keepAwakeMouseJiggleCaption: String
    let keepAwakeMouseJiggleInterval: String
    let keepAwakeActiveIconLabel: String
    let keepAwakeActiveIconVorssaint: String
    let keepAwakeActiveIconCoffee: String
    let keepAwakeActiveIconEye: String
    let keepAwakeActiveIconMoon: String
    let keepAwakeActiveIconLight: String
    let keepAwakeIconTintLabel: String
    let keepAwakeIconTintOrange: String
    let keepAwakeIconTintGreen: String
    let keepAwakeIconTintBlue: String
    let keepAwakeIconTintPurple: String
    let keepAwakeIconTintPink: String
    let keepAwakeIconTintNone: String
    let durationLabel: String
    let clamshellTitle: String
    let clamshellOnCaption: String
    let clamshellNeedsSession: String
    let clamshellReady: String
    let clamshellNeedsPassword: String

    // MARK: Panel — system monitor
    let systemSection: String
    let temperatures: String
    let cpuLabel: String
    let gpuLabel: String
    let batteryLabel: String
    let usageSection: String
    let memorySection: String
    let memoryPressure: String
    let memorySwapUsed: String
    let memoryCompressed: String
    let memoryCachedFiles: String
    let pressureNormal: String
    let pressureWarning: String
    let pressureCritical: String
    let monitorUnavailable: String
    let energyAppsTitle: String
    let energyAppsIdle: String

    // MARK: Notifications
    let notifySessionEndedTitle: String
    let notifySessionEndedBody: String
    let notifyBatteryTitle: String
    let notifyBatteryBody: String

    // MARK: Administrator prompts (shown by macOS password dialogs)
    let adminPromptClamshellOn: String
    let adminPromptClamshellOff: String
    let adminPromptRecover: String
    let adminPromptUpdate: String
    let adminPromptSudoersInstall: String
    let adminPromptSudoersRemove: String

    // MARK: Settings — window & tabs
    let settingsTitle: String
    let tabGeneral: String
    let tabEnergy: String
    let tabMouse: String
    let tabSwitcher: String
    let tabAdvanced: String
    let tabAbout: String
    let tabReleaseNotes: String
    let releaseNotesOnUpdateToggle: String
    let minimalWindowPreviews: String
    let minimalWindowPreviewsCaption: String
    let previewSizeLabel: String
    let previewSizeNormal: String
    let previewSizeLarge: String
    let previewSizeXLarge: String
    let settingsGroupFeatures: String

    // MARK: Settings — advanced
    let advancedResetSection: String
    let advancedResetDescription: String
    let advancedClearButton: String
    let advancedCleared: String
    let advancedClearFailed: String
    let advancedClearConfirmTitle: String
    let advancedClearConfirmBody: String
    let advancedUninstallSection: String
    let advancedUninstallDescription: String
    let advancedUninstallButton: String
    let advancedUninstallConfirmTitle: String
    let advancedUninstallConfirmBody: String
    let advancedUninstallFailedTitle: String
    let advancedUninstallFailedBody: String

    // MARK: Settings — general
    let launchAtLogin: String
    let languageLabel: String
    let menuBarSection: String
    let showCountdown: String
    let globalHotkeySection: String
    let hotkeyToggle: String
    let hotkeyCaption: String

    // MARK: Settings — energy
    let sessionSection: String
    let defaultDurationLabel: String
    let keepAwakeAutoStart: String
    let keepAwakeAutoStartCaption: String
    let batteryProtectionSection: String
    let batteryDisableBelow: String
    let batteryNever: String
    let batteryProtectionCaption: String
    let clamshellSection: String
    let configuring: String
    let sudoersFailed: String
    let clamshellExplanation: String
    let dimScreenOnLidCloseTitle: String
    let dimScreenOnLidCloseCaption: String

    // MARK: Settings — mouse
    let scrollSection: String
    let invertMouseScroll: String
    let invertMouseScrollCaption: String
    let scrollTrackpadNote: String
    let scrollActiveNow: String
    let mouseNavigationActiveNow: String
    let smoothScrollName: String
    let smoothScrollCaption: String
    let smoothScrollStepLabel: String
    let mouseNavigationSection: String
    let mouseNavigationEnable: String
    let mouseNavigationCaption: String
    let middleClickSection: String
    let middleClickEnable: String
    let middleClickEnableCaption: String
    let middleClickDragConflict: String
    let middleClickNoTrackpad: String
    let middleClickTapPicker: String
    let middleClickTapOff: String
    let middleClickTapThreeFingers: String
    let middleClickTapFourFingers: String
    let middleClickTapCaption: String
    let quickToolsTab: String
    let quickToolShortcutToggle: String
    let ocrName: String
    let ocrCaption: String
    let ocrCopied: String
    let ocrNoText: String
    let colorPickerName: String
    let colorPickerCaption: String
    let colorPickerFormatLabel: String
    let colorPickerBareHexToggle: String
    let colorPickerPickNow: String
    let micMuteName: String
    let micUnmuteName: String
    let micMuteCaption: String
    let micMutedHUD: String
    let micUnmutedHUD: String
    let micMutePartialHUD: String
    let micUnmutePartialHUD: String
    let micMuteMenuBarToggle: String
    let micMuteMenuBarCaption: String
    let pastePlainName: String
    let pastePlainCaption: String
    let launcherName: String
    let launcherCaption: String
    let launcherOpenNow: String
    let launcherEditHint: String
    let launcherEmptyState: String
    let launcherAddSection: String
    let launcherKeysHint: String

    // MARK: Settings — switcher
    let switcherSection: String
    let switcherEnable: String
    let switcherEnableCaption: String
    let switcherUsageHint: String
    let switcherNoWindows: String
    let switcherIconRowMode: String
    let switcherIconRowModeCaption: String
    let switcherSimpleModeCaption: String
    let switcherShortcutHintApps: String
    let switcherShortcutHintWindows: String
    let switcherWindowShortcutCaption: String
    let switcherTakeOverSystemShortcuts: String
    let switcherTakeOverSystemShortcutsCaption: String
    let switcherAppearanceDelay: String
    let switcherAppearanceDelayCaption: String
    let switcherMaxColumns: String
    let switcherMaxColumnsCaption: String
    let switcherMaxColumnsAuto: String
    let switcherInstantSelection: String
    let switcherInstantSelectionCaption: String
    let switcherMergeTabs: String
    let switcherMergeTabsCaption: String
    let switcherWindowlessApps: String
    let switcherWindowlessAppsCaption: String
    let switcherWindowlessAppsOff: String
    let switcherWindowlessAppsFinder: String
    let switcherWindowlessAppsAll: String
    let switcherWindowlessAppsLockedFormat: String
    let switcherNoOpenWindow: String
    let switcherOtherDesktop: String
    let dockPreviewName: String
    let dockPreviewEnable: String
    let dockPreviewEnableCaption: String
    let dockPreviewCurrentSpaceOnlyCaption: String
    let dockPreviewBackgroundOpacity: String
    let dockPreviewBackgroundOpacityCaption: String
    let dockPreviewBackgroundOpacityGlassCaption: String
    let dockPreviewOpenDelay: String
    let dockPreviewOpenDelayCaption: String
    let dockPreviewQuitAppOnClose: String
    let dockPreviewQuitAppOnCloseCaption: String
    let dockPreviewKeepDockVisible: String
    let dockPreviewKeepDockVisibleCaption: String
    let dockPreviewOrderByCreation: String
    let dockPreviewOrderByCreationCaption: String
    let dockClickMinimize: String
    let dockClickMinimizeCaption: String
    let dockClickCycleWindows: String
    let dockClickCycleWindowsCaption: String
    let dockPreviewActiveNow: String
    let dockPreviewDockUnavailable: String
    let dockPreviewAutohideBeta: String
    let dockPreviewOpenWindow: String
    let dockPreviewCloseWindow: String
    let dockPreviewMinimizeWindow: String
    let dockPreviewRestoreWindow: String
    let dockPreviewPinPanel: String
    let dockPreviewUnpinPanel: String
    let dockPreviewPinned: String
    let dockPreviewClosePanel: String
    let dockPreviewPreviousWindow: String
    let dockPreviewNextWindow: String

    // MARK: Feature — cut & paste in Finder
    let cutPasteName: String
    let cutPasteEnable: String
    let cutPasteEnableCaption: String
    let cutPasteShowHUD: String
    let cutPasteShowHUDCaption: String
    let cutPasteHowTitle: String
    let cutPasteStep1: String
    let cutPasteStep2: String
    let cutPasteTextNote: String
    let cutPasteActiveNow: String
    let cutPasteAutomationNote: String
    let cutReadyTitle: String
    let cutReadyHint: String
    let cutCancel: String
    let cutDoneTitle: String
    let cutMovedSingular: String
    let cutMovedPluralFormat: String
    let cutSomeFailed: String
    let cutMovingTitle: String
    let cutMovingCountFormat: String

    // MARK: Feature — quit on last window close
    let autoQuitName: String
    let autoQuitEnable: String
    let autoQuitEnableCaption: String
    let autoQuitActiveNow: String
    let autoQuitHowTitle: String
    let autoQuitStep1: String
    let autoQuitStep2: String
    let autoQuitPredictableNote: String
    let autoQuitOngoingWorkNote: String
    let autoQuitExceptionsTitle: String
    let autoQuitExceptionsCaption: String
    let autoQuitExceptionsEmpty: String
    let autoQuitAddApp: String

    // MARK: Feature — complete app uninstaller
    let uninstallerName: String
    let uninstallerEnableCaption: String
    let uninstallerStep1: String
    let uninstallerStep2: String
    let uninstallerStep3: String
    let uninstallerMenuItem: String
    let uninstallerDropTitle: String
    let uninstallerDropSubtitle: String
    let uninstallerChoose: String
    let uninstallerPickerTitle: String
    let uninstallerPickerSearch: String
    let uninstallerPickerEmpty: String
    let uninstallerEmptyNote: String
    let uninstallerFDANote: String
    let uninstallerFDAGrant: String
    let uninstallerFDAHint: String
    let uninstallerFDARelaunch: String
    let uninstallerScanning: String
    let uninstallerRemoving: String
    let uninstallerFoundTitle: String
    let uninstallerSelectedFormat: String
    let uninstallerRemove: String
    let uninstallerCancel: String
    let uninstallerConfirmationExpired: String
    let uninstallerDoneTitle: String
    let uninstallerFreedFormat: String
    let uninstallerSomeFailed: String
    let uninstallerFailedNeedsFDA: String
    let uninstallerFailedMoreFormat: String
    let uninstallerAnother: String
    let uninstallerCatApp: String
    let uninstallerCatSupport: String
    let uninstallerCatCaches: String
    let uninstallerCatPreferences: String
    let uninstallerCatContainers: String
    let uninstallerCatLogs: String
    let uninstallerCatState: String
    let uninstallerCatOther: String
    let uninstallerCommandBarBrowseTitle: String
    let uninstallerCommandBarToggle: String
    let uninstallerCommandBarCaption: String
    let uninstallerCommandBarFinderTitle: String
    let uninstallerSelectionUnavailable: String
    let uninstallerRefusedNotApp: String
    let uninstallerRefusedSystemFormat: String
    let uninstallerRefusedSharedFormat: String
    let uninstallerRefusedNestedFormat: String
    let uninstallerRefusedSelfFormat: String
    let uninstallerRefusedLinkFormat: String
    let uninstallerRefusedUnidentifiedFormat: String
    let uninstallerPickerHiddenNote: String

    // MARK: Feature — URL cleaner
    let urlCleanerName: String
    let urlCleanerEnable: String
    let urlCleanerEnableCaption: String
    let urlCleanerActiveNow: String
    let urlCleanerManualTitle: String
    let urlCleanerInputPlaceholder: String
    let urlCleanerOutputPlaceholder: String
    let urlCleanerPasteButton: String
    let urlCleanerCopyButton: String
    let urlCleanerClearButton: String
    let urlCleanerNoURL: String
    let urlCleanerNoChange: String
    let urlCleanerCleaned: String
    let urlCleanerCopied: String
    let urlCleanerLocalNote: String

    // MARK: Feature — Homebrew manager
    let homebrewName: String
    let homebrewEnableCaption: String
    let homebrewMissingTitle: String
    let homebrewMissingBody: String
    let homebrewInstallHomebrew: String
    let homebrewInstallHomebrewCaption: String
    let homebrewInstallHomebrewOpened: String
    let homebrewShellSetupTitle: String
    let homebrewShellSetupBody: String
    let homebrewShellSetupButton: String
    let homebrewShellSetupOpened: String
    let homebrewRefresh: String
    let homebrewCheckPackages: String
    let homebrewTrustTitle: String
    let homebrewTrustCaption: String
    let homebrewTrustButton: String
    let homebrewSearchPlaceholder: String
    let homebrewKeyboardHint: String
    let homebrewSearchButton: String
    let homebrewSearchResults: String
    let homebrewInstalled: String
    let homebrewAll: String
    let homebrewFormulas: String
    let homebrewCasks: String
    let homebrewNoPackages: String
    let homebrewDependencies: String
    let homebrewGroupDependencies: String
    let homebrewOrphans: String
    let homebrewOrphansNote: String
    let homebrewDependencyUpdatesFormat: String
    let homebrewNoSelection: String
    let homebrewDetailsTitle: String
    let homebrewInstall: String
    let homebrewUninstall: String
    let homebrewUpgrade: String
    let homebrewUpgradeAll: String
    let homebrewUpdateHomebrew: String
    let homebrewAllPackages: String
    let homebrewOpenTerminal: String
    let homebrewCancelOperation: String
    let homebrewClearLog: String
    let homebrewLogTitle: String
    let homebrewVersion: String
    let homebrewDescription: String
    let homebrewHomepage: String
    let homebrewPopularity: String
    let homebrewPopularityFormat: String
    let homebrewInstalledBadge: String
    let homebrewNotInstalledBadge: String
    let homebrewUpdates: String
    let homebrewUpdateAvailableBadge: String
    let homebrewLatestVersion: String
    let homebrewConfirmInstallTitle: String
    let homebrewConfirmInstallBodyFormat: String
    let homebrewConfirmUninstallTitle: String
    let homebrewConfirmUninstallBodyFormat: String
    let homebrewConfirmUpgradeTitle: String
    let homebrewConfirmUpgradeBodyFormat: String
    let homebrewConfirmUpgradeAllTitle: String
    let homebrewConfirmUpgradeAllBody: String
    let homebrewConfirmUpdateHomebrewTitle: String
    let homebrewConfirmUpdateHomebrewBody: String
    let homebrewTerminalFallback: String
    let homebrewLoading: String
    let homebrewSearchEmpty: String
    let homebrewOperationInstallFormat: String
    let homebrewOperationUninstallFormat: String
    let homebrewOperationUpgradeFormat: String
    let homebrewOperationUpgradeAll: String
    let homebrewOperationUpdateHomebrew: String
    let homebrewOperationInstalledFormat: String
    let homebrewOperationUninstalledFormat: String
    let homebrewOperationUpgradedFormat: String
    let homebrewOperationUpgradedAll: String
    let homebrewOperationUpdatedHomebrew: String
    let homebrewOperationFailedFormat: String
    let homebrewOperationCancelled: String
    let homebrewOperationPreparing: String
    let homebrewOperationDownloading: String
    let homebrewOperationInstalling: String
    let homebrewOperationUninstalling: String
    let homebrewOperationUpgrading: String
    let homebrewOperationFinalizing: String
    let homebrewOperationRefreshing: String
    let homebrewOperationTerminal: String
    let homebrewOperationElapsedFormat: String
    let homebrewOperationShowDetails: String
    let homebrewOperationHideDetails: String
    let homebrewOperationTechnicalLog: String
    let homebrewOperationProgressUnknown: String

    // MARK: Feature — local media tools
    let mediaName: String
    let mediaEnableCaption: String
    let mediaLocalNote: String
    let mediaToolVideo: String
    let mediaToolGIF: String
    let mediaToolImage: String
    let mediaToolText: String
    let mediaSelectFile: String
    let mediaDropHint: String
    let mediaOutput: String
    let mediaOutputAutomatic: String
    let mediaChooseOutput: String
    let mediaStartVideo: String
    let mediaStartGIF: String
    let mediaStartImage: String
    let mediaStartConvertPDF: String
    let mediaStartText: String
    let mediaCancel: String
    let mediaStartTime: String
    let mediaEndTime: String
    let mediaQuality: String
    let mediaCompressionLow: String
    let mediaCompressionMedium: String
    let mediaCompressionHigh: String
    let mediaCompressionLowDescription: String
    let mediaCompressionMediumDescription: String
    let mediaCompressionHighDescription: String
    let mediaMaxSize: String
    let mediaSizingResolution: String
    let mediaSizingFileSize: String
    let mediaTargetSize: String
    let mediaTargetSizeHint: String
    let mediaErrorTargetTooSmall: String
    let mediaMegabytesSuffix: String
    let mediaWidth: String
    let mediaFPS: String
    let mediaKeepAudio: String
    let mediaCodec: String
    let mediaFormat: String
    let mediaStripMetadata: String
    let mediaLoopGIF: String
    let mediaOCRMode: String
    let mediaOCRAccurate: String
    let mediaOCRFast: String
    let mediaLanguageCorrection: String
    let mediaTextOutputNote: String
    let mediaRunning: String
    let mediaCompleted: String
    let mediaCancelled: String
    let mediaOpenInFinder: String
    let mediaCopyText: String
    let mediaRunAgain: String
    let mediaEmptyText: String
    let mediaResultSavedFormat: String
    let mediaResultSizeFormat: String
    let mediaResultGrewCaption: String
    let mediaErrorNoFile: String
    let mediaErrorNoVideo: String
    let mediaErrorSameOutput: String
    let mediaErrorUnsupported: String

    // MARK: Feature — temporary shelf
    let shelfName: String
    let shelfEnable: String
    let shelfEnableCaption: String
    let shelfHowTitle: String
    let shelfStep1: String
    let shelfStep2: String
    let shelfStep3: String
    let shelfShakeToggle: String
    let shelfShakeCaption: String
    let shelfDropZoneToggle: String
    let shelfDropZoneCaption: String
    let shelfDropZoneCaptionTopCenter: String
    let shelfDropZoneLabel: String
    let shelfDockPlacement: String
    let shelfDockMenuBar: String
    let shelfDockTopCenter: String
    let shelfDockIslandNote: String
    let shelfCollapse: String
    let shelfBehaviorTitle: String
    let shelfCloseAfterDrop: String
    let shelfCloseAfterDropCaption: String
    let shelfRemoveAfterDrop: String
    let shelfRemoveAfterDropCaption: String
    let shelfExclusionsTitle: String
    let shelfExclusionsEmpty: String
    let shelfExclusionsCaption: String
    let shelfPin: String
    let shelfUnpin: String
    let extraBrightnessName: String
    let extraBrightnessCaption: String
    let extraBrightnessLevelLabel: String
    let extraBrightnessUnsupported: String
    let shelfHotkeyLabel: String
    let shelfOpenNow: String
    let shelfNoPermission: String
    let shelfMenuItem: String
    let shelfTitle: String
    let shelfEmpty: String
    let shelfClearAll: String
    let shelfRemoveSelected: String
    let shelfSelectedFormat: String
    let shelfHint: String
    let shelfItemImage: String
    let shelfTooltipItemsFormat: String
    let shelfTooltipItemsFew: String
    let shelfTooltipImageSingular: String
    let shelfTooltipImageFew: String
    let shelfTooltipImagePlural: String
    let shelfTooltipFileSingular: String
    let shelfTooltipFileFew: String
    let shelfTooltipFilePlural: String
    let shelfTooltipNoteSingular: String
    let shelfTooltipNoteFew: String
    let shelfTooltipNotePlural: String
    let shelfTooltipLinkSingular: String
    let shelfTooltipLinkFew: String
    let shelfTooltipLinkPlural: String
    let shelfActionOpen: String
    let shelfActionOpenWith: String
    let shelfActionShare: String
    let shelfActionPin: String
    let shelfActionUnpin: String

    // MARK: Panel — per-app breakdown
    let breakdownMeasuring: String

    // MARK: Panel — volume mixer
    let mixerSection: String
    let mixerEmpty: String
    let mixerUnavailable: String
    let mixerPermissionBody: String
    let mixerResetTooltip: String
    let mixerOutputDefault: String
    let mixerOutputCurrent: String
    let mixerOutputUnavailable: String
    let mixerOutputFallback: String
    let mixerBypassedCaption: String
    let mixerOutputTooltip: String
    let mixerAirPlayChooseSpeaker: String
    let mixerSystemOutputTitle: String
    let mixerSystemOutputNoDevices: String
    let mixerSystemOutputTooltip: String
    let mixerSystemOutputErrorFormat: String
    let mixerLowerOnHeadphonesDisconnect: String
    let mixerLowerOnHeadphonesDisconnectCaption: String
    let mixerHeadphonesDisconnectVolume: String
    let preciseVolumeRollerEnable: String
    let preciseVolumeRollerCaption: String
    let preciseVolumeRollerTapFailed: String
    let soundOutputSwitcherTitle: String
    let soundOutputSwitcherEnable: String
    let soundOutputSwitcherCaption: String
    let soundOutputSwitcherDevices: String
    let soundOutputSwitcherNoAvailableSelection: String
    let mixerInputTitle: String
    let mixerInputNoDevices: String
    let mixerInputUnavailable: String
    let mixerInputFallback: String
    let mixerInputTooltip: String
    let mixerInputErrorFormat: String
    let mixerVisibleApps: String
    let mixerAllShown: String
    let mixerHiddenCountLabel: String
    let mixerHideFromList: String

    // MARK: Panel — audio device priority
    let audioPrioritySection: String
    let audioPriorityOutputEnable: String
    let audioPriorityInputEnable: String
    let audioPriorityOutputList: String
    let audioPriorityInputList: String
    let audioPriorityMoveUp: String
    let audioPriorityMoveDown: String
    let audioPriorityUnavailable: String
    let audioPriorityCurrent: String
    let audioPriorityCaption: String

    // MARK: Settings — updates
    let updatesSection: String
    let autoCheckToggle: String
    let includeBetaUpdatesToggle: String
    let includeBetaUpdatesCaption: String
    let betaBadgeLabel: String
    let checkNowButton: String
    let updateChecking: String
    let updateUpToDate: String
    let updateAvailablePrefix: String
    let updateInstallButton: String
    let updateDownloading: String
    let updateInstalling: String
    let updateFailedPrefix: String
    let updateLastChecked: String
    let updateNotifyTitle: String
    let updateInstallFailedBody: String
    let updateNeedsApplicationsTitle: String
    let updateNeedsApplicationsBody: String
    let menuCheckUpdates: String

    // MARK: Permissions (shared by Settings & onboarding)
    let permissionRequired: String
    let permissionAccessibility: String
    let permissionScreenRecording: String
    let permissionGranted: String
    let permissionMissing: String
    let permissionOpenSettings: String
    let permissionRequest: String
    let permissionRestartNote: String

    // MARK: Secure input
    let secureInputTitle: String
    let secureInputHeldFormat: String
    let secureInputUnattributed: String
    let secureInputUnidentified: String
    let secureInputRevealFormat: String
    let secureInputSwitcherHeldFormat: String
    let secureInputSwitcherUnattributed: String
    let secureInputSwitcherUnidentified: String

    // MARK: About
    let aboutDescription: String
    let versionPrefix: String
    let reviewIntro: String
    let reviewHighlights: String
    let viewOnGitHub: String

    // MARK: Onboarding
    let obContinue: String
    let obBack: String
    let obSkipStep: String
    let obStart: String
    let obStepWelcomeTitle: String
    let obStepWelcomeBody: String
    let obWelcomeBullet1Title: String
    let obWelcomeBullet1Body: String
    let obWelcomeBullet2Title: String
    let obWelcomeBullet2Body: String
    let obWelcomeBullet3Title: String
    let obWelcomeBullet3Body: String
    let obLanguageLabel: String
    let obStepAccessibilityTitle: String
    let obStepAccessibilityBody: String
    let obAccessibilityWhy: String
    let obStepRecordingTitle: String
    let obStepRecordingBody: String
    let obRecordingWhy: String
    let obStepMonitorTitle: String
    let obStepMonitorBody: String
    let obMonitorNoPermission: String
    let obStepOptionalTitle: String
    let obStepOptionalBody: String
    let obStepStatusTitle: String
    let obStepStatusBody: String
    let obStatusRecheck: String
    let obStepDoneTitle: String
    let obStepDoneBody: String
    let obDoneHint: String
    let obWhatsNewTitle: String
    let obWhatsNewFallback: String
    let obLanguageUpdateTitle: String
    let obLanguageUpdateBody: String
    let obPurposeTitle: String
    let obPurposeBody: String
    let obPurposeSkip: String

    // MARK: Settings — monitor / menu bar metrics
    let tabMonitor: String
    let monitorMenuBarSection: String
    let monitorMenuBarPreview: String
    let monitorMenuBarCaption: String
    let monitorCombineTemperatures: String
    let monitorCombineTemperaturesCaption: String
    let monitorSeparateMenuBarMetrics: String
    let monitorSeparateMenuBarMetricsCaption: String
    let monitorNetworkUploadFirst: String
    let monitorShowCPU: String
    let monitorShowMemory: String
    let monitorShowNetwork: String
    let monitorShowPowerLabel: String
    let monitorIntervalLabel: String
    let monitorInterval1: String
    let monitorInterval2: String
    let monitorInterval5: String
    let monitorPanelSection: String
    let panelNavigationMode: String
    let panelNavigationCaption: String
    let panelFooterSections: String
    let panelFooterList: String
    let betaBadge: String
    let betaFeatureWarning: String

    // MARK: Panel — network
    let networkSection: String
    let networkIPAddresses: String
    let networkLocalIP: String
    let networkDownload: String
    let networkUpload: String
    let networkThisSession: String
    let networkMeasuring: String
    let networkApps: String
    let networkAppsIdle: String

    // MARK: Panel — disk
    let diskSection: String
    let diskUsed: String
    let diskFree: String
    let diskMenuBarStyleLabel: String
    let diskMenuBarUsedPercentage: String
    let diskMenuBarAvailableSpace: String
    let diskMenuBarUsedSpace: String
    let diskAvailable: String
    let diskPurgeable: String
    let diskInternal: String
    let diskExternal: String
    let diskSelect: String
    let diskRead: String
    let diskWrite: String
    let diskSMARTStatus: String
    let diskSMARTUnavailable: String
    let diskTotalRead: String
    let diskTotalWritten: String
    let diskTemperature: String
    let diskHealth: String
    let diskPowerCycles: String
    let diskPowerOnHours: String
    let diskUnsafeShutdowns: String
    let diskMediaErrors: String
    let diskEject: String
    let diskEjectAll: String
    let diskEjecting: String
    let diskReadyToRemove: String
    let diskEjectFailed: String
    let diskProtectionCaption: String
    let diskNoExternal: String
    let diskOpenInFinder: String
    let diskStorageSettings: String
    let diskNoDisks: String

    // MARK: Panel — power
    let powerSection: String
    let powerSystem: String
    let powerAdapter: String
    let powerBattery: String
    let powerCharging: String
    let powerOnBattery: String
    let powerPluggedIn: String
    let powerUnavailable: String
    let powerAdapterMaxFormat: String
    let monitorShowGPU: String
    let monitorShowCPUTemperature: String
    let monitorShowGPUTemperature: String
    let monitorShowBatteryTemperature: String
    let monitorShowPeripheralBattery: String
    let peripheralBatteryNoDevices: String
    let monitorGraphsSection: String

    // MARK: Update notification + onboarding menu bar setup
    let updateBannerTitle: String
    let updateBannerAction: String
    let obStepMenuBarTitle: String
    let obStepMenuBarBody: String
    let obStepMenuBarNote: String
    let monitorMenuBarPresetLabel: String
    let menuBarPresetReadable: String
    let menuBarPresetDense: String
    let menuBarSpacingLabel: String
    let menuBarSpacingStandard: String
    let menuBarSpacingCompact: String
    let menuBarHideIconToggle: String
    let menuBarHideIconCaption: String
    let monitorLabelStyleLabel: String
    let menuBarLabelStyleCompact: String
    let menuBarLabelStyleClassic: String
    let monitorMemoryStyleLabel: String
    let monitorMemoryPressureDot: String
    let memoryStyleDot: String
    let memoryStylePercent: String
    let memoryStyleBoth: String
    // MARK: System uptime, battery health, speed test
    let systemUptime: String
    let batteryCharge: String
    let powerHealth: String
    let powerCycles: String
    let speedTestRun: String
    let speedTestAgain: String
    let speedTestLatency: String
    let speedTestTesting: String
    let speedTestFailed: String

    // MARK: Per-item panel config (Settings + onboarding)
    let monitorShowInPanel: String
    let disclosureExpanded: String
    let disclosureCollapsed: String
    let panelHideItem: String
    let panelShowItem: String
    let panelHiddenItem: String
    let monitorItemUptime: String
    let monitorItemNetSpeed: String
    let monitorItemNetTotals: String
    let monitorItemNetTest: String
    let monitorItemDiskUsage: String
    let monitorItemDiskActivity: String
    let monitorItemDiskSMART: String
    let monitorItemDiskProtection: String
    let monitorItemDiskTools: String
    let monitorPanelConfigHint: String
    let monitorOrderHint: String
    let obStepPanelTitle: String
    let obStepPanelBody: String
    let obStepPanelNavigationTitle: String
    let obStepPanelNavigationBody: String

    // MARK: Cleaning mode
    let cleaningMenuItem: String
    let utilitiesSection: String
    let quickControlsSection: String
    let panelCategoryWindows: String
    let panelCategoryInput: String
    let panelCategoryFiles: String
    let windowMaximizeName: String
    let windowMaximizeCaption: String
    let windowMaximizeActiveNow: String
    let windowMaximizeNeedsAccessibility: String
    let keyDebounceName: String
    let keyDebounceEnable: String
    let keyDebounceCaption: String
    let keyDebounceActiveNow: String
    let keyDebounceGlobalWindow: String
    let keyDebouncePerKeySection: String
    let keyDebouncePerKeyCaption: String
    let keyDebounceKeyLabel: String
    let keyDebounceWindowLabel: String
    let keyDebounceAddKey: String
    let keyDebounceNoOverrides: String
    let keyDebounceRemoveKey: String
    let cleaningPanelCaption: String
    let cleaningOverlayTitle: String
    let cleaningOverlaySubtitle: String
    let cleaningOverlayUnlock: String
    let cleaningOverlayMouseHint: String
    let cleaningKeepScreenVisibleToggle: String
    let cleaningKeepScreenVisibleCaption: String
    let cleaningStartNow: String
    let cleaningNeedsAxTitle: String
    let cleaningNeedsAxBody: String

    // MARK: Support / donate
    let tabSupport: String
    let shortcutsPageCaption: String
    let shortcutsPageTitle: String
    let settingsSearchPlaceholder: String
    let donateHeading: String
    let donateMessage: String
    let donateButton: String
    let donateThanks: String
    let supportIntroTitle: String
    let supportIntroMessage: String
    let supportIntroStarButton: String
    let supportIntroStarMessage: String
    let supportIntroStarHint: String
    let supportIntroCoffeeButton: String
    let supportIntroLaterButton: String
    let supportIntroDoneButton: String
    let discordIntroTitle: String
    let discordIntroMessage: String
    let discordIntroJoinButton: String
    let communityIntroTitle: String
    let communityIntroMessage: String
    let communityIntroFollowButton: String
    let homebrewOfficialIntroTitle: String
    let homebrewOfficialIntroMessage: String
    let homebrewOfficialIntroInstallLabel: String
    let homebrewOfficialIntroMigrationTitle: String
    let homebrewOfficialIntroMigrationMessage: String
    let homebrewOfficialIntroCopyButton: String
    let updateShowcaseTitle: String
    let updateShowcaseMessage: String
    let updateShowcaseUnavailable: String
    let updateShowcaseRestart: String
    let showMenuBarIcon: String
    let menuBarIconStillHiddenTitle: String
    let menuBarIconStillHiddenBody: String
    let menuBarIconManagerHintFormat: String
    let menuBarIconDisallowedBody: String

    // MARK: Configurable shortcuts
    let shortcutRecording: String
    let shortcutReset: String
    let shortcutNone: String
    let shortcutClear: String
    let shortcutInvalid: String
    let shortcutPressKeys: String
    let shortcutEscapeHint: String
    let shortcutDeleteHint: String
    let shortcutNotCaptured: String
    let shortcutConflictFormat: String
    let shortcutTakeOverOffer: String
    let shortcutTakeOverAction: String
    let shortcutTakeOverCaption: String
    let shortcutTakeOverDismiss: String
    let shortcutUnavailable: String
    let shelfShortcutToggle: String
    let switcherUsageHintFormat: String

    // MARK: Media keys
    let musicBlockSection: String
    let musicBlockTitle: String
    let musicBlockCaption: String
    let musicBlockUnavailable: String
    let musicBlockReplacementLabel: String
    let musicBlockReplacementNone: String
    let musicBlockReplacementBlocked: String
    let musicBlockChooseApp: String
    let musicBlockPlayReplacement: String

    // MARK: Cleaner
    let cleanerName: String
    let cleanerIntroTitle: String
    let cleanerIntroCaption: String
    let cleanerScan: String
    let cleanerScanning: String
    let cleanerCleaning: String
    let cleanerCatLeftovers: String
    let cleanerCatLoginItems: String
    let cleanerCatCaches: String
    let cleanerCatLogs: String
    let cleanerCatDeveloper: String
    let cleanerCatTrash: String
    let cleanerLeftoversNote: String
    let cleanerLoginItemsNote: String
    let cleanerTrashNote: String
    let cleanerCatDeviceBackups: String
    let cleanerDeviceBackupsCaption: String
    let cleanerCatScreenshots: String
    let cleanerScreenshotsCaptionFormat: String
    let cleanerScreenshotsSettingCaption: String
    let cleanerScreenshotsAfterFormat: String
    let cleanerNothingFound: String
    let cleanerClean: String
    let cleanerDoneNote: String
    let cleanerAgain: String
    let cleanerRevealInFinder: String
    let cleanerPanelCaption: String
    let cleanerSafeSection: String
    let cleanerOptionalSection: String
    let cleanerCatOtherCaches: String
    let cleanerCachesCaption: String
    let cleanerLogsCaption: String
    let cleanerDeveloperCaption: String
    let cleanerLoginItemsCaption: String
    let cleanerLeftoversCaption: String
    let cleanerOtherCachesCaption: String
    let cleanerCleanSizeFormat: String
    let cleanerScheduleTitle: String
    let cleanerScheduleOff: String
    let cleanerScheduleDaily: String
    let cleanerScheduleWeekly: String
    let cleanerScheduleCaption: String
    let cleanerScheduleLastFormat: String
    let cleanerAutoNotificationFormat: String
    let cleanerScheduleNextFormat: String
    let cleanerScheduleRanFormat: String
    let cleanerScheduleNotifyToggle: String
    let cleanerNotifDenied: String
    let cleanerNotifOpenSettings: String
    let launchAtLoginNeedsApplications: String
    let launchAtLoginNeedsApproval: String
    let ocrRemoveLineBreaksToggle: String
    let ocrRemoveLineBreaksCaption: String
    let ocrQRToggle: String
    let ocrQRCaption: String
    let ocrQRCopied: String
    let qrResultTitle: String
    let qrResultCopy: String
    let qrResultOpen: String
    let highlightsTitle: String
    let highlightsTitleClipboardRedesign: String
    let highlightsTitleWindowLayout: String
    let highlightsTitleQuitProtection: String
    let highlightsTitleRecorderBlur: String
    let highlightsCaptionDockPreview: String
    let highlightsCaptionScreenshot: String
    let highlightsCaptionSnippetLibrary: String
    let highlightsCaptionCapturePalette: String
    let highlightsCaptionClipboardRedesign: String
    let highlightsCaptionWindowLayout: String
    let highlightsCaptionQuitProtection: String
    let highlightsCaptionRecorderBlur: String
    let highlightsConfigure: String
    let highlightsTry: String
    let highlightsSeeAll: String
    let switcherCurrentSpaceOnly: String
    let switcherCurrentSpaceOnlyCaption: String
    let shelfFileMissing: String
    let previewSizeSmall: String
    let mixerSoundEffectsOutputTitle: String
    let mixerSoundEffectsOutputTooltip: String
    let monitorOpenActivityMonitor: String
    let dockClickHide: String
    let dockClickHideCaption: String
    let monitorMemoryMetricLabel: String
    let memoryMetricUsed: String
    let memoryMetricApp: String
    let keepAwakeRightClickToggle: String
    let keepAwakeRightClickToggleCaption: String
    let urlCleanerRulesTitle: String
    let urlCleanerRulesCaption: String
    let urlCleanerRulesCoverageCaption: String
    let urlCleanerRulesAllSites: String
    let urlCleanerRulesCountSingular: String
    let urlCleanerRulesCountPluralFormat: String
    let urlCleanerRulesAddSite: String
    let urlCleanerRulesParameterPlaceholder: String
    let urlCleanerRulesMatchCaption: String
    let urlCleanerRulesAddButton: String
    let urlCleanerRulesRemoveButton: String
    let urlCleanerRulesRemoveSiteButton: String
    let urlCleanerRulesRestoreSiteButton: String
    let urlCleanerRemovedFormat: String
    let switcherSearchPin: String
    let switcherSearchPinCaption: String
    let invertVerticalScroll: String
    let invertHorizontalScroll: String
    let scrollHorizontalName: String
    let zoomSection: String
    let zoomControlNote: String
    let pinchZoom: String
    let scrollHorizontalModifierLabel: String
    let scrollHorizontalCommandKey: String
    let scrollHorizontalCaption: String
    let switcherShowShortcutHints: String
    let switcherShowShortcutHintsCaption: String
    let uninstallerHomebrewPackageFormat: String
    let uninstallerHomebrewCheckFailed: String
    let shelfEdgeToggle: String
    let shelfEdgeCaption: String
    let focusFollowsMouseName: String
    let focusFollowsMouseCaption: String
    let focusFollowsMouseDelay: String
    let focusFollowsMouseRaise: String
    let focusFollowsMouseWaitForStop: String
    let switcherMinimizedPlacementLabel: String
    let switcherTreatHiddenAppsLikeMinimized: String
    let switcherMinimizedPlacementNormal: String
    let switcherMinimizedPlacementEnd: String
    let switcherMinimizedPlacementHidden: String
    let switcherShowFullscreenWindows: String
    let switcherScreenPlacementLabel: String
    let switcherScreenPlacementPointer: String
    let switcherScreenPlacementMenuBar: String
    let switcherScreenPlacementActiveWindow: String
    let switcherScreenPlacementCaption: String
    let switcherCurrentDisplayOnly: String
    let switcherCurrentDisplayOnlyCaption: String
    let smoothScrollResponseLabel: String
    let smoothScrollCoastLabel: String
    let mouseAccelerationName: String
    let mouseAccelerationCaption: String
    let linearScrollName: String
    let linearScrollCaption: String
    let linearScrollLinesLabel: String
    let shelfClearOnClose: String
    let shelfClearOnCloseCaption: String
    let shelfShortcutFinderSelection: String
    let shelfShortcutFinderSelectionCaption: String
    let spacesOrderName: String
    let spacesOrderCaption: String
    let quitAppsName: String
    let quitAppsCaption: String
}

// MARK: - Português (Brasil)

extension Strings {
}

// MARK: - English (US)

extension Strings {
    static let enUS = Strings(
        statusIdleTooltip: "EVERYTHING: normal sleep",
        statusActiveUntil: "EVERYTHING: awake until",
        statusActiveIndefinite: "EVERYTHING: awake indefinitely",
        menuEnableAwake: "Enable keep awake",
        menuDisableAwake: "Disable keep awake",
        menuActivateFor: "Activate for…",
        menuSettings: "Settings…",
        menuAbout: "About EVERYTHING",
        menuQuit: "Quit EVERYTHING",
        menuHide: "Hide EVERYTHING",
        menuHideOthers: "Hide Others",
        menuShowAll: "Show All",
        menuEdit: "Edit",
        menuUndo: "Undo",
        menuRedo: "Redo",
        actionClear: "Clear",
        actionRemove: "Remove",
        actionBack: "Back",
        actionSearch: "Search",
        actionMute: "Mute",
        actionUnmute: "Unmute",
        actionPlay: "Play",
        actionPause: "Pause",
        menuCut: "Cut",
        menuCopy: "Copy",
        menuPaste: "Paste",
        menuSelectAll: "Select All",
        menuWindow: "Window",
        menuMinimize: "Minimize",
        menuZoom: "Zoom",
        menuClose: "Close",

        minutes15: "15 minutes",
        minutes30: "30 minutes",
        hour1: "1 hour",
        hours2: "2 hours",
        hours4: "4 hours",
        hours8: "8 hours",
        indefinitely: "Indefinitely",
        indefinite: "Indefinite",

        panelSettings: "Settings",
        panelQuit: "Quit",
        panelHotkeyHint: "Keybind toggles",

        keepAwakeTitle: "Keep awake",
        keepAwakeEndsIn: "Ends in",
        keepAwakeUntilDisabled: "Active until you turn it off",
        keepAwakeNormalRules: "The Mac follows its normal energy rules",
        keepAwakeUntilLabel: "Until",
        keepAwakeUntilStart: "Start",
        keepAwakeOptions: "Options",
        keepAwakeMouseJiggle: "Move pointer slightly",
        keepAwakeMouseJiggleCaption: "During a session, moves the pointer a little at the chosen interval.",
        keepAwakeMouseJiggleInterval: "Interval",
        keepAwakeActiveIconLabel: "Active icon",
        keepAwakeActiveIconVorssaint: "EVERYTHING",
        keepAwakeActiveIconCoffee: "Coffee",
        keepAwakeActiveIconEye: "Eye",
        keepAwakeActiveIconMoon: "Moon",
        keepAwakeActiveIconLight: "Lightbulb",
        keepAwakeIconTintLabel: "Active icon color",
        keepAwakeIconTintOrange: "Orange",
        keepAwakeIconTintGreen: "Green",
        keepAwakeIconTintBlue: "Blue",
        keepAwakeIconTintPurple: "Purple",
        keepAwakeIconTintPink: "Pink",
        keepAwakeIconTintNone: "No color",
        durationLabel: "Duration",
        clamshellTitle: "Keep going with the lid closed",
        clamshellOnCaption: "Sleep fully disabled. Mind the power",
        clamshellNeedsSession: "Applied whenever “Keep awake” is active",
        clamshellReady: "Ready. Toggles without a password",
        clamshellNeedsPassword: "Will ask for the administrator password once",

        systemSection: "System",
        temperatures: "Temperatures",
        cpuLabel: "CPU",
        gpuLabel: "GPU",
        batteryLabel: "Battery",
        usageSection: "Hardware usage",
        memorySection: "Memory",
        memoryPressure: "Pressure",
        memorySwapUsed: "Swap used",
        memoryCompressed: "Compressed",
        memoryCachedFiles: "Cached files",
        pressureNormal: "Normal",
        pressureWarning: "Caution",
        pressureCritical: "Critical",
        monitorUnavailable: "Sensors unavailable on this Mac",
        energyAppsTitle: "Apps using significant energy",
        energyAppsIdle: "No significant energy use",

        notifySessionEndedTitle: "Session ended",
        notifySessionEndedBody: "Time is up. The Mac will sleep normally again.",
        notifyBatteryTitle: "EVERYTHING disabled",
        notifyBatteryBody: "Low battery. Normal sleep was restored to protect the charge.",
        adminPromptClamshellOn: "EVERYTHING needs your password to keep the Mac going with the lid closed.",
        adminPromptClamshellOff: "EVERYTHING needs your password to restore the Mac’s normal sleep.",
        adminPromptRecover: "EVERYTHING quit while the Mac’s sleep was disabled. Enter the password to restore normal sleep.",
        adminPromptUpdate: "EVERYTHING needs your password to install the update.",
        adminPromptSudoersInstall: "EVERYTHING will create a restricted rule (pmset disablesleep only) to toggle closed-lid mode without asking for a password. This is the only time the password is needed.",
        adminPromptSudoersRemove: "EVERYTHING will remove the password-free closed-lid rule.",

        settingsTitle: "EVERYTHING Settings",
        tabGeneral: "General",
        tabEnergy: "Energy",
        tabMouse: "Mouse & Trackpad",
        tabSwitcher: "Switcher",
        tabAdvanced: "Advanced",
        tabAbout: "About",
        tabReleaseNotes: "What’s New",
        releaseNotesOnUpdateToggle: "Show what’s new after updating",
        minimalWindowPreviews: "Minimal previews",
        minimalWindowPreviewsCaption: "Hide titles, buttons and decorative details in Dock and switcher previews. The selection stays visible.",
        previewSizeLabel: "Preview size",
        previewSizeNormal: "Normal",
        previewSizeLarge: "Large",
        previewSizeXLarge: "Extra large",
        settingsGroupFeatures: "Features",
        advancedResetSection: "Permissions",
        advancedResetDescription: "Removes every permission you granted EVERYTHING (Accessibility, Screen Recording, Full Disk Access and others), the login item and the closed-lid rule. Useful to start fresh or before uninstalling. The app stays installed.",
        advancedClearButton: "Clear all permissions",
        advancedCleared: "Permissions cleared.",
        advancedClearFailed: "Some permissions or the closed-lid rule could not be removed. Try again and allow the password request if it appears.",
        advancedClearConfirmTitle: "Clear all permissions?",
        advancedClearConfirmBody: "Features that need permissions will stop working until you grant them again. Your settings are kept.",
        advancedUninstallSection: "Uninstall",
        advancedUninstallDescription: "Does all of the above, then removes the preferences and moves EVERYTHING to the Trash, leaving nothing behind. The app quits when done. You can reinstall anytime.",
        advancedUninstallButton: "Uninstall EVERYTHING completely",
        advancedUninstallConfirmTitle: "Uninstall EVERYTHING?",
        advancedUninstallConfirmBody: "EVERYTHING will clear its permissions, remove its preferences and move to the Trash, then quit. This can’t be undone from the app, but it stays in the Trash until you empty it.",
        advancedUninstallFailedTitle: "Uninstall stopped",
        advancedUninstallFailedBody: "EVERYTHING could not put back a system setting it changed: sleep, fan speed, mouse acceleration or Space order. Nothing was removed. Try again and allow the password request if it appears.",

        launchAtLogin: "Launch at login",
        languageLabel: "Language",
        menuBarSection: "Menu bar",
        showCountdown: "Show remaining time next to the icon",
        globalHotkeySection: "Global keybind",
        hotkeyToggle: "Enable keybind for “Keep awake”",
        hotkeyCaption: "Works in any app, no extra permissions.",

        sessionSection: "Session",
        defaultDurationLabel: "Default duration",
        keepAwakeAutoStart: "Keep Awake when EVERYTHING opens",
        keepAwakeAutoStartCaption: "Starts a session with the default duration.",
        batteryProtectionSection: "Battery protection",
        batteryDisableBelow: "Disable when battery drops below",
        batteryNever: "Never",
        batteryProtectionCaption: "Keeps a forgotten session from draining the MacBook battery.",
        clamshellSection: "Closed lid",
        configuring: "Configuring…",
        sudoersFailed: "Couldn’t turn on closed-lid mode. Try again.",
        clamshellExplanation: "“Keep going with the lid closed” fully disables sleep while “Keep awake” is active and is reverted automatically when the session ends or the app quits. Prefer using it plugged in.",
        dimScreenOnLidCloseTitle: "Dim the display to zero",
        dimScreenOnLidCloseCaption: "Dims the display when the lid closes and brings the brightness back when it opens.",

        scrollSection: "Scrolling",
        invertMouseScroll: "Invert mouse scrolling",
        invertMouseScrollCaption: "Reverses the mouse wheel direction.",
        scrollTrackpadNote: "The trackpad is untouched: it keeps macOS natural scrolling.",
        scrollActiveNow: "Inverting mouse scrolling right now",
        mouseNavigationActiveNow: "Side buttons active right now",
        smoothScrollName: "Smooth scrolling",
        smoothScrollCaption: "Turns each mouse wheel step into a short, gentle glide. The trackpad is not affected.",
        smoothScrollStepLabel: "Scrolling speed",
        mouseNavigationSection: "Navigation",
        mouseNavigationEnable: "Use side buttons for Back and Forward",
        mouseNavigationCaption: "Turns the mouse Back and Forward buttons into navigation commands in Finder, browsers and compatible apps.",
        middleClickSection: "Trackpad middle click",
        middleClickEnable: "Three-finger click acts as middle click",
        middleClickEnableCaption: "Pressing the trackpad with three fingers works like a mouse wheel click: open links in a new tab, close tabs and everything else the middle button does.",
        middleClickDragConflict: "macOS three-finger drag is turned on and uses three fingers, so click with five fingers for the middle click. To use three, turn three-finger drag off in System Settings under Accessibility, Pointer Control, Trackpad Options.",
        middleClickNoTrackpad: "Can’t read trackpad touches. Connect a supported trackpad.",
        middleClickTapPicker: "A light tap also clicks",
        middleClickTapOff: "Off",
        middleClickTapThreeFingers: "3 fingers",
        middleClickTapFourFingers: "4 fingers",
        middleClickTapCaption: "A light tap with that many fingers, without pressing, also fires the middle click. Sliding never counts. If the macOS three-finger tap is assigned to Look Up, turn it off so both do not fire together.",
        quickToolsTab: "Quick panel",
        quickToolShortcutToggle: "Global keybind",
        ocrName: "Copy text from screen",
        ocrCaption: "Select an area of the screen and the recognized text is copied, ready to paste.",
        ocrCopied: "Text copied",
        ocrNoText: "No text found",
        colorPickerName: "Color picker",
        colorPickerCaption: "Grab the color of any pixel on screen and copy it in your favorite format.",
        colorPickerFormatLabel: "Copied format",
        colorPickerBareHexToggle: "Copy without the # prefix",
        colorPickerPickNow: "Pick color",
        micMuteName: "Mute microphone",
        micUnmuteName: "Unmute microphone",
        micMuteCaption: "Uses each microphone’s mute or input-volume controls. Siri and some apps may still hear you. This is not a privacy lock.",
        micMutedHUD: "Mic Mute on",
        micUnmutedHUD: "Mic Mute off",
        micMutePartialHUD: "Some microphones could not be muted",
        micUnmutePartialHUD: "Some microphones are still muted",
        micMuteMenuBarToggle: "Show in the menu bar while Mic Mute is on",
        micMuteMenuBarCaption: "The red mic in the menu bar indicates that Mic Mute is on. It does not guarantee that all apps stop capturing audio.",
        pastePlainName: "Paste as plain text",
        pastePlainCaption: "Pastes what you copied without colors, fonts or formatting. The original stays on the clipboard.",
        launcherName: "Quick panel",
        launcherCaption: "A floating panel with your favorite tools, summoned by a keybind from anywhere.",
        launcherOpenNow: "Open quick panel",
        launcherEditHint: "Use the tune button to choose, hide and drag the tools around.",
        launcherEmptyState: "All tools are hidden. Use the tune button to add them back.",
        launcherAddSection: "Add back",
        launcherKeysHint: "Arrows navigate, Enter opens, 1 to 9 open directly",

        switcherSection: "Window switcher",
        switcherEnable: "Use the EVERYTHING switcher",
        switcherEnableCaption: "Switch between apps and windows, including minimized windows and multiple windows from the same app.",
        switcherUsageHint: "Hold the keybind to navigate; release to activate the window. Shift or ← goes back; W closes the window; Q quits the app; Esc cancels.",
        switcherNoWindows: "No open windows",
        switcherIconRowMode: "Show %@ with large icons",
        switcherIconRowModeCaption: "Shows one icon per app with that app’s window previews above it.",
        switcherSimpleModeCaption: "Shows app icons and window titles, without previews or screen capture by the switcher.",
        switcherShortcutHintApps: "Apps",
        switcherShortcutHintWindows: "Windows",
        switcherWindowShortcutCaption: "Opens a switcher for the frontmost app’s windows. While the switcher is open, jumps between the selected app’s windows.",
        switcherTakeOverSystemShortcuts: "Replace macOS ⌘Tab and ⌘`",
        switcherTakeOverSystemShortcutsCaption: "Disables the matching macOS app and window keybinds only while EVERYTHING’s switcher is active. All running apps stay reachable.",
        switcherAppearanceDelay: "Appearance delay",
        switcherAppearanceDelayCaption: "How long the keybind must be held before the switcher appears.",
        switcherMaxColumns: "Maximum columns",
        switcherMaxColumnsCaption: "Wraps onto more rows after this many items. Useful on ultrawide displays.",
        switcherMaxColumnsAuto: "Auto",
        switcherInstantSelection: "Instant selection",
        switcherInstantSelectionCaption: "Moves the highlight and scroll position immediately as you browse apps and windows.",
        switcherMergeTabs: "Show one entry per app",
        switcherMergeTabsCaption: "Collapses all of an app’s windows into one entry in the switcher, instead of one entry per window.",
        switcherWindowlessApps: "Apps with no open window",
        switcherWindowlessAppsCaption: "Chooses which running apps with no window at all show up in the switcher.",
        switcherWindowlessAppsOff: "Do not show",
        switcherWindowlessAppsFinder: "Finder only",
        switcherWindowlessAppsAll: "All apps",
        switcherWindowlessAppsLockedFormat: "All running apps stay reachable while “%@” is on. Turn it off to choose.",
        switcherNoOpenWindow: "No open window",
        switcherOtherDesktop: "Other desktop",
        dockPreviewName: "Dock Preview",
        dockPreviewEnable: "Preview windows from the Dock",
        dockPreviewEnableCaption: "Hover over an open app in the Dock to see its windows, then click the one you want.",
        dockPreviewCurrentSpaceOnlyCaption: "When off, shows windows from all desktops. Choosing a window on another desktop takes you there.",
        dockPreviewBackgroundOpacity: "Panel background",
        dockPreviewBackgroundOpacityCaption: "Turn it down to see more of what sits behind the panel.",
        dockPreviewBackgroundOpacityGlassCaption: "Liquid Glass is on, so the panel’s transparency is set in System Settings > Appearance.",
        dockPreviewOpenDelay: "Open delay",
        dockPreviewOpenDelayCaption: "How long the pointer has to rest on an icon before its panel opens.",
        dockPreviewQuitAppOnClose: "Quit the app with the × button",
        dockPreviewQuitAppOnCloseCaption: "In Dock Preview, × quits the whole app instead of closing only that window.",
        dockPreviewKeepDockVisible: "Keep Dock visible (experimental)",
        dockPreviewKeepDockVisibleCaption: "Pauses auto-hide while the preview is open and restores it when you leave. May resize windows. If the app is interrupted, reopen it to restore the Dock.",
        dockPreviewOrderByCreation: "Order windows by creation time",
        dockPreviewOrderByCreationCaption: "Show older windows first instead of the ones you used most recently.",
        dockClickMinimize: "Click the Dock icon to minimize",
        dockClickMinimizeCaption: "The active app’s windows minimize when you click its Dock icon. Click again to bring them back.",
        dockClickCycleWindows: "Click the Dock icon to cycle windows",
        dockClickCycleWindowsCaption: "Click an active app’s Dock icon to rotate through its windows, like ⌘`.",
        dockPreviewActiveNow: "Active in the Dock",
        dockPreviewDockUnavailable: "Could not read Dock items.",
        dockPreviewAutohideBeta: "Beta. You may run into some bugs.",
        dockPreviewOpenWindow: "Open window",
        dockPreviewCloseWindow: "Close window",
        dockPreviewMinimizeWindow: "Minimize window",
        dockPreviewRestoreWindow: "Restore window",
        dockPreviewPinPanel: "Pin preview",
        dockPreviewUnpinPanel: "Unpin preview",
        dockPreviewPinned: "Pinned",
        dockPreviewClosePanel: "Close preview",
        dockPreviewPreviousWindow: "Previous window",
        dockPreviewNextWindow: "Next window",

        cutPasteName: "Cut & paste",
        cutPasteEnable: "Cut & paste files in Finder",
        cutPasteEnableCaption: "Use ⌘X to cut and ⌘V to move files and folders in Finder.",
        cutPasteShowHUD: "Show floating panel",
        cutPasteShowHUDCaption: "Display a floating indicator with the cut files while Finder is active.",
        cutPasteHowTitle: "How to use",
        cutPasteStep1: "Select items in Finder and press ⌘X to cut them.",
        cutPasteStep2: "Open the destination folder and press ⌘V to move them there.",
        cutPasteTextNote: "In text fields (like when renaming), ⌘X and ⌘V keep working as usual.",
        cutPasteActiveNow: "Ready to cut in Finder",
        cutPasteAutomationNote: "The first time, macOS asks for permission to control Finder.",
        cutReadyTitle: "Cut",
        cutReadyHint: "in the destination folder to move",
        cutCancel: "Cancel cut",
        cutDoneTitle: "Moved!",
        cutMovedSingular: "1 item moved",
        cutMovedPluralFormat: "%d items moved",
        cutSomeFailed: "Some items couldn’t be moved",
        cutMovingTitle: "Moving…",
        cutMovingCountFormat: "%d of %d",

        autoQuitName: "Quit on close",
        autoQuitEnable: "Quit an app when its last window closes",
        autoQuitEnableCaption: "Closing an app’s last window also quits it.",
        autoQuitActiveNow: "Active now",
        autoQuitHowTitle: "How it works",
        autoQuitStep1: "Close an app’s last window (⌘W or the red button).",
        autoQuitStep2: "The app quits on its own. “Save changes?” dialogs still appear.",
        autoQuitPredictableNote: "Apps that have not opened a window stay open. Menu bar apps stay open unless you explicitly allow them to quit.",
        autoQuitOngoingWorkNote: "Some apps close their last window while they keep working, such as a screen recorder once capture starts. Those are quit too, unless they are on the Exceptions list.",
        autoQuitExceptionsTitle: "Exceptions",
        autoQuitExceptionsCaption: "Apps on this list stay open even with no windows.",
        autoQuitExceptionsEmpty: "No exceptions",
        autoQuitAddApp: "Add app…",

        uninstallerName: "Uninstaller",
        uninstallerEnableCaption: "Removes an app together with the caches, preferences, logs and leftovers it leaves behind.",
        uninstallerStep1: "Drag an app onto Settings, or pick one from the list.",
        uninstallerStep2: "Review the files found and how much space they take.",
        uninstallerStep3: "Move what you want to the Trash. Nothing is deleted permanently.",
        uninstallerMenuItem: "Uninstall an app…",
        uninstallerDropTitle: "Drag an app here",
        uninstallerDropSubtitle: "or choose one to scan",
        uninstallerChoose: "Choose app…",
        uninstallerPickerTitle: "Choose app",
        uninstallerPickerSearch: "Search apps",
        uninstallerPickerEmpty: "No apps found",
        uninstallerEmptyNote: "Nothing is removed without your confirmation.",
        uninstallerFDANote: "Grant Full Disk Access for a more thorough scan.",
        uninstallerFDAGrant: "Grant access…",
        uninstallerFDAHint: "Turn EVERYTHING on in the list. If it isn’t there, click + and pick EVERYTHING from Applications. Access only applies after you reopen the app.",
        uninstallerFDARelaunch: "Relaunch now",
        uninstallerScanning: "Scanning files…",
        uninstallerRemoving: "Moving to the Trash…",
        uninstallerFoundTitle: "found",
        uninstallerSelectedFormat: "%d of %d selected",
        uninstallerRemove: "Move to Trash",
        uninstallerCancel: "Cancel",
        uninstallerConfirmationExpired: "This confirmation is no longer valid. Review the current items and confirm again.",
        uninstallerDoneTitle: "Done!",
        uninstallerFreedFormat: "%@ removed",
        uninstallerSomeFailed: "Some items couldn’t be moved to the Trash.",
        uninstallerFailedNeedsFDA: "Sandboxed app data can only be moved with Full Disk Access. The administrator password does not stand in for it.",
        uninstallerFailedMoreFormat: "and %d more",
        uninstallerAnother: "Uninstall another",
        uninstallerCatApp: "Application",
        uninstallerCatSupport: "Support",
        uninstallerCatCaches: "Caches",
        uninstallerCatPreferences: "Preferences",
        uninstallerCatContainers: "Containers",
        uninstallerCatLogs: "Logs",
        uninstallerCatState: "Saved state",
        uninstallerCatOther: "Other",
        uninstallerCommandBarBrowseTitle: "Uninstall Application",
        uninstallerCommandBarToggle: "Show in Command Bar",
        uninstallerCommandBarCaption: "Choose and uninstall apps in the Command Bar.",
        uninstallerCommandBarFinderTitle: "Uninstall app selected in Finder",
        uninstallerSelectionUnavailable: "Select an app that can be removed in Finder, or choose another from the list.",
        uninstallerRefusedNotApp: "Only apps can be uninstalled.",
        uninstallerRefusedSystemFormat: "%@ can’t be uninstalled because it’s part of macOS.",
        uninstallerRefusedSharedFormat: "%@ can’t be uninstalled here because it shares files with macOS or other apps.",
        uninstallerRefusedNestedFormat: "%@ can’t be uninstalled on its own because it’s part of another app.",
        uninstallerRefusedSelfFormat: "EVERYTHING can’t uninstall itself here. Use Settings › %@ instead.",
        uninstallerRefusedLinkFormat: "%@ can’t be uninstalled because it’s a link to an app stored elsewhere.",
        uninstallerRefusedUnidentifiedFormat: "%@ can’t be uninstalled because it can’t be identified as an app.",
        uninstallerPickerHiddenNote: "Apps that are part of macOS or made by Apple aren’t listed.",

        urlCleanerName: "Clean URL",
        urlCleanerEnable: "Clean URLs as you copy them",
        urlCleanerEnableCaption: "Removes tracking parameters from a link the moment it reaches the clipboard.",
        urlCleanerActiveNow: "Active now",
        urlCleanerManualTitle: "Clean now",
        urlCleanerInputPlaceholder: "Paste a URL",
        urlCleanerOutputPlaceholder: "The clean URL appears here",
        urlCleanerPasteButton: "Paste",
        urlCleanerCopyButton: "Copy",
        urlCleanerClearButton: "Clear field",
        urlCleanerNoURL: "Paste a valid URL.",
        urlCleanerNoChange: "Nothing to clean.",
        urlCleanerCleaned: "URL cleaned.",
        urlCleanerCopied: "Copied.",
        urlCleanerLocalNote: "Local. No network.",

        homebrewName: "Homebrew",
        homebrewEnableCaption: "Search, install and remove formulae and casks.",
        homebrewMissingTitle: "Homebrew not found",
        homebrewMissingBody: "EVERYTHING can open the official Homebrew installer in your terminal. It shows the steps and asks for your password if needed.",
        homebrewInstallHomebrew: "Install Homebrew",
        homebrewInstallHomebrewCaption: "When the installer finishes, come back here and click Refresh.",
        homebrewInstallHomebrewOpened: "Installer opened in your terminal.",
        homebrewShellSetupTitle: "Finish terminal setup",
        homebrewShellSetupBody: "Homebrew is installed, but your terminal may not find the brew command yet. EVERYTHING can open the setup command in your terminal.",
        homebrewShellSetupButton: "Set up terminal",
        homebrewShellSetupOpened: "Command opened in your terminal. Then come back here and click Refresh.",
        homebrewRefresh: "Refresh",
        homebrewCheckPackages: "Check packages",
        homebrewTrustTitle: "Tap not trusted yet",
        homebrewTrustCaption: "Homebrew now asks for your confirmation before using third party taps. Trust %@ to continue.",
        homebrewTrustButton: "Trust and continue",
        homebrewSearchPlaceholder: "Search packages",
        homebrewKeyboardHint: "Space or Return closes the macOS panel. Use the search button.",
        homebrewSearchButton: "Search",
        homebrewSearchResults: "Results",
        homebrewInstalled: "Installed",
        homebrewAll: "All",
        homebrewFormulas: "Formulae",
        homebrewCasks: "Casks",
        homebrewNoPackages: "No packages found",
        homebrewDependencies: "Dependencies",
        homebrewGroupDependencies: "Group dependencies",
        homebrewOrphans: "No longer needed",
        homebrewOrphansNote: "Installed as dependencies, but no installed package needs them any more.",
        homebrewDependencyUpdatesFormat: "Dependency updates: %d",
        homebrewNoSelection: "Select an installed package or search for a new one.",
        homebrewDetailsTitle: "Package details",
        homebrewInstall: "Install",
        homebrewUninstall: "Uninstall",
        homebrewUpgrade: "Update",
        homebrewUpgradeAll: "Update all",
        homebrewUpdateHomebrew: "Update Homebrew",
        homebrewAllPackages: "packages",
        homebrewOpenTerminal: "Open terminal",
        homebrewCancelOperation: "Cancel",
        homebrewClearLog: "Clear log",
        homebrewLogTitle: "Log",
        homebrewVersion: "Version",
        homebrewDescription: "Type",
        homebrewHomepage: "Open website",
        homebrewPopularity: "Popularity",
        homebrewPopularityFormat: "%@ installs in %@ days",
        homebrewInstalledBadge: "Installed",
        homebrewNotInstalledBadge: "Not installed",
        homebrewUpdates: "Updates",
        homebrewUpdateAvailableBadge: "Update available",
        homebrewLatestVersion: "Latest",
        homebrewConfirmInstallTitle: "Install with Homebrew?",
        homebrewConfirmInstallBodyFormat: "Homebrew will download and install %@. Dependencies may also be installed.",
        homebrewConfirmUninstallTitle: "Uninstall with Homebrew?",
        homebrewConfirmUninstallBodyFormat: "Homebrew will uninstall %@. Configuration files may remain on the system.",
        homebrewConfirmUpgradeTitle: "Update with Homebrew?",
        homebrewConfirmUpgradeBodyFormat: "Homebrew will download and apply the latest version of %@. Dependencies may also be updated.",
        homebrewConfirmUpgradeAllTitle: "Update all with Homebrew?",
        homebrewConfirmUpgradeAllBody: "Homebrew will download and apply the latest versions for packages with updates available. Dependencies may also be updated.",
        homebrewConfirmUpdateHomebrewTitle: "Update Homebrew?",
        homebrewConfirmUpdateHomebrewBody: "Homebrew will fetch the latest information and then reload your packages.",
        homebrewTerminalFallback: "This operation needs your terminal to ask for the administrator password. EVERYTHING does not capture passwords.",
        homebrewLoading: "Loading…",
        homebrewSearchEmpty: "No results",
        homebrewOperationInstallFormat: "Installing %@",
        homebrewOperationUninstallFormat: "Uninstalling %@",
        homebrewOperationUpgradeFormat: "Updating %@",
        homebrewOperationUpgradeAll: "Updating packages",
        homebrewOperationUpdateHomebrew: "Updating Homebrew",
        homebrewOperationInstalledFormat: "%@ installed.",
        homebrewOperationUninstalledFormat: "%@ uninstalled.",
        homebrewOperationUpgradedFormat: "%@ updated.",
        homebrewOperationUpgradedAll: "Packages updated.",
        homebrewOperationUpdatedHomebrew: "Homebrew updated.",
        homebrewOperationFailedFormat: "Could not finish %@.",
        homebrewOperationCancelled: "Operation cancelled.",
        homebrewOperationPreparing: "Preparing…",
        homebrewOperationDownloading: "Downloading files…",
        homebrewOperationInstalling: "Installing files…",
        homebrewOperationUninstalling: "Removing files…",
        homebrewOperationUpgrading: "Updating files…",
        homebrewOperationFinalizing: "Finishing…",
        homebrewOperationRefreshing: "Refreshing list…",
        homebrewOperationTerminal: "Continue in your terminal.",
        homebrewOperationElapsedFormat: "%@ elapsed",
        homebrewOperationShowDetails: "Show details",
        homebrewOperationHideDetails: "Hide details",
        homebrewOperationTechnicalLog: "Technical details",
        homebrewOperationProgressUnknown: "Homebrew has not reported a percentage yet.",

        mediaName: "Media",
        mediaEnableCaption: "Compress videos, convert and process images, make GIFs and extract text locally.",
        mediaLocalNote: "Local. No network.",
        mediaToolVideo: "Video",
        mediaToolGIF: "GIF",
        mediaToolImage: "Image",
        mediaToolText: "Text",
        mediaSelectFile: "Choose file",
        mediaDropHint: "Drop a file here or click to choose one.",
        mediaOutput: "Output",
        mediaOutputAutomatic: "Automatic",
        mediaChooseOutput: "Destination",
        mediaStartVideo: "Compress video",
        mediaStartGIF: "Make GIF",
        mediaStartImage: "Process image",
        mediaStartConvertPDF: "Convert to PDF",
        mediaStartText: "Extract text",
        mediaCancel: "Cancel",
        mediaStartTime: "Start",
        mediaEndTime: "End",
        mediaQuality: "Compression",
        mediaCompressionLow: "Low",
        mediaCompressionMedium: "Medium",
        mediaCompressionHigh: "High",
        mediaCompressionLowDescription: "High quality, large file size",
        mediaCompressionMediumDescription: "Balanced quality and file size",
        mediaCompressionHighDescription: "Low quality, small file size",
        mediaMaxSize: "Size",
        mediaSizingResolution: "Resolution",
        mediaSizingFileSize: "File size",
        mediaTargetSize: "Target size",
        mediaTargetSizeHint: "Resolution adapts to stay under the limit.",
        mediaErrorTargetTooSmall: "Target size too small for this clip. Trim it or raise the limit.",
        mediaMegabytesSuffix: " MB",
        mediaWidth: "Width",
        mediaFPS: "FPS",
        mediaKeepAudio: "Keep audio",
        mediaCodec: "Codec",
        mediaFormat: "Format",
        mediaStripMetadata: "Remove metadata",
        mediaLoopGIF: "Loop GIF",
        mediaOCRMode: "OCR",
        mediaOCRAccurate: "Accurate",
        mediaOCRFast: "Fast",
        mediaLanguageCorrection: "Language correction",
        mediaTextOutputNote: "Extracted text can be copied and saved as TXT.",
        mediaRunning: "Processing",
        mediaCompleted: "Done",
        mediaCancelled: "Cancelled.",
        mediaOpenInFinder: "Show",
        mediaCopyText: "Copy text",
        mediaRunAgain: "Run again",
        mediaEmptyText: "No text found.",
        mediaResultSavedFormat: "Saved as %@",
        mediaResultSizeFormat: "%@ to %@",
        mediaResultGrewCaption: "The converted file came out larger than the original.",
        mediaErrorNoFile: "Choose a file first.",
        mediaErrorNoVideo: "This file has no video track.",
        mediaErrorSameOutput: "Choose a destination different from the original file.",
        mediaErrorUnsupported: "Format not supported by macOS.",

        shelfName: "Shelf",
        shelfEnable: "Temporary area for dragging files",
        shelfEnableCaption: "A floating spot to gather files, images and text, then drag them anywhere later.",
        shelfHowTitle: "How to use",
        shelfStep1: "Open it with the keybind, or by shaking the mouse during a drag.",
        shelfStep2: "Drop files, images, links or text onto it to hold them.",
        shelfStep3: "Drag each item back out to any app when you need it.",
        shelfShakeToggle: "Open by shaking the mouse while dragging",
        shelfShakeCaption: "Shake the pointer quickly while holding an item to summon it near the cursor.",
        shelfDropZoneToggle: "Keep dragged files in the menu bar",
        shelfDropZoneCaption: "While you drag a file, the shelf appears below the menu bar icon. Whatever you drop is kept right there, in a button you shrink and open with a click that goes away once the shelf is empty.",
        shelfDropZoneCaptionTopCenter: "While you drag a file, the shelf appears as a badge at the top center of the screen. Whatever you drop is kept right there, in a badge you open with a click that goes away once the shelf is empty.",
        shelfDropZoneLabel: "Drop here",
        shelfDockPlacement: "Position",
        shelfDockMenuBar: "Below the menu bar icon",
        shelfDockTopCenter: "Top center of the screen",
        shelfDockIslandNote: "The Dynamic Island keeps the top center while it is on.",
        shelfCollapse: "Collapse",
        shelfBehaviorTitle: "After use",
        shelfCloseAfterDrop: "Close after dropping into another app",
        shelfCloseAfterDropCaption: "Closes the shelf when the destination accepts the items. The pin in the panel keeps it open.",
        shelfRemoveAfterDrop: "Remove items after dropping",
        shelfRemoveAfterDropCaption: "Items accepted by another app leave the shelf. Turn this off to keep a copy there. Pinned items always stay.",
        shelfExclusionsTitle: "Automatic exceptions",
        shelfExclusionsEmpty: "No apps added.",
        shelfExclusionsCaption: "Shake and the menu bar drop zone stay off for drags started in these apps. The keybind and Open now still work.",
        shelfPin: "Keep open",
        shelfUnpin: "Allow closing after use",
        extraBrightnessName: "Extra brightness",
        extraBrightnessCaption: "Uses the display’s HDR headroom to go past the maximum brightness. Uses more battery and the Mac can run warm.",
        extraBrightnessLevelLabel: "Intensity",
        extraBrightnessUnsupported: "Available only on XDR displays, such as the ones on the 14 and 16 inch MacBook Pro.",
        shelfHotkeyLabel: "Keybind",
        shelfOpenNow: "Open now",
        shelfNoPermission: "Requires no permissions.",
        shelfMenuItem: "Open shelf",
        shelfTitle: "Shelf",
        shelfEmpty: "Drag items here",
        shelfClearAll: "Clear all",
        shelfRemoveSelected: "Remove selected",
        shelfSelectedFormat: "%d selected",
        shelfHint: "Click to select. Drag out to use or right-click for more actions.",
        shelfItemImage: "Image",
        shelfTooltipItemsFormat: "%d items",
        shelfTooltipItemsFew: "%d items",
        shelfTooltipImageSingular: "%d image",
        shelfTooltipImageFew: "%d images",
        shelfTooltipImagePlural: "%d images",
        shelfTooltipFileSingular: "%d file",
        shelfTooltipFileFew: "%d files",
        shelfTooltipFilePlural: "%d files",
        shelfTooltipNoteSingular: "%d note",
        shelfTooltipNoteFew: "%d notes",
        shelfTooltipNotePlural: "%d notes",
        shelfTooltipLinkSingular: "%d link",
        shelfTooltipLinkFew: "%d links",
        shelfTooltipLinkPlural: "%d links",
        shelfActionOpen: "Open",
        shelfActionOpenWith: "Open With",
        shelfActionShare: "Share",
        shelfActionPin: "Pin",
        shelfActionUnpin: "Unpin",

        breakdownMeasuring: "Measuring…",

        mixerSection: "Volume mixer",
        mixerEmpty: "Apps that use audio show up here",
        mixerUnavailable: "Available on macOS 14.4 and later",
        mixerPermissionBody: "To adjust per-app volume, allow “Screen & System Audio Recording” in System Settings. Audio is never recorded.",
        mixerResetTooltip: "Reset to 100%",
        mixerOutputDefault: "Default",
        mixerOutputCurrent: "current",
        mixerOutputUnavailable: "Output unavailable",
        mixerOutputFallback: "Using default until this device returns.",
        mixerBypassedCaption: "This app manages its own audio.",
        mixerOutputTooltip: "Choose output",
        mixerAirPlayChooseSpeaker: "Choose AirPlay speaker…",
        mixerSystemOutputTitle: "Output",
        mixerSystemOutputNoDevices: "No outputs found",
        mixerSystemOutputTooltip: "Choose system output",
        mixerSystemOutputErrorFormat: "Could not switch: %@",
        mixerLowerOnHeadphonesDisconnect: "Lower volume when headphones disconnect",
        mixerLowerOnHeadphonesDisconnectCaption: "Adjusts output when wired or Bluetooth headphones disconnect.",
        mixerHeadphonesDisconnectVolume: "Volume after disconnect",
        preciseVolumeRollerEnable: "Use finer volume steps",
        preciseVolumeRollerCaption: "Turns volume wheels and keys into smaller system volume steps.",
        preciseVolumeRollerTapFailed: "Could not listen for volume keys.",
        soundOutputSwitcherTitle: "Output switcher",
        soundOutputSwitcherEnable: "Switch outputs with keybind",
        soundOutputSwitcherCaption: "Choose outputs and use the keybind to move to the next available one.",
        soundOutputSwitcherDevices: "Outputs in cycle",
        soundOutputSwitcherNoAvailableSelection: "Select at least one available output.",
        mixerInputTitle: "Microphone",
        mixerInputNoDevices: "No microphones found",
        mixerInputUnavailable: "Microphone unavailable",
        mixerInputFallback: "Using default until this microphone returns.",
        mixerInputTooltip: "Choose microphone",
        mixerInputErrorFormat: "Could not switch: %@",
        mixerVisibleApps: "Apps in the list",
        mixerAllShown: "All",
        mixerHiddenCountLabel: "Hidden",
        mixerHideFromList: "Hide from the list",
        audioPrioritySection: "Audio priority",
        audioPriorityOutputEnable: "Automatically switch to the highest-priority output",
        audioPriorityInputEnable: "Automatically switch to the highest-priority microphone",
        audioPriorityOutputList: "Output priority",
        audioPriorityInputList: "Microphone priority",
        audioPriorityMoveUp: "Move up",
        audioPriorityMoveDown: "Move down",
        audioPriorityUnavailable: "Unavailable",
        audioPriorityCurrent: "Current",
        audioPriorityCaption: "Devices are selected in priority order. When a higher-priority device connects, it becomes active. When the active one disconnects, the next available takes over.",

        updatesSection: "Updates",
        autoCheckToggle: "Check for updates automatically",
        includeBetaUpdatesToggle: "Receive beta updates",
        includeBetaUpdatesCaption: "Beta versions include features in development and may contain bugs or incomplete behavior.",
        betaBadgeLabel: "Beta",
        checkNowButton: "Check now",
        updateChecking: "Checking…",
        updateUpToDate: "You’re on the latest version.",
        updateAvailablePrefix: "Update available:",
        updateInstallButton: "Download and install",
        updateDownloading: "Downloading update…",
        updateInstalling: "Installing and restarting…",
        updateFailedPrefix: "Couldn’t check:",
        updateLastChecked: "Last checked:",
        updateNotifyTitle: "EVERYTHING update",
        updateInstallFailedBody: "The update was downloaded but could not be applied. Download the latest version from the GitHub releases page and drag the app over the current one.",
        updateNeedsApplicationsTitle: "Move EVERYTHING to Applications",
        updateNeedsApplicationsBody: "The app is running from a place that cannot be updated, such as the disk image or a temporary system location. Drag EVERYTHING to the Applications folder, open it from there and try again.",
        menuCheckUpdates: "Check for updates…",

        permissionRequired: "Permission required",
        permissionAccessibility: "Accessibility",
        permissionScreenRecording: "Screen Recording",
        permissionGranted: "Granted",
        permissionMissing: "Not granted",
        permissionOpenSettings: "Open System Settings…",
        permissionRequest: "Grant access",
        permissionRestartNote: "macOS may ask to reopen the app after granting.",
        secureInputTitle: "Secure input is on",
        secureInputHeldFormat: "%@ was the active app when it turned on and may be holding it, so EVERYTHING cannot type for you. Dismiss its password field, or quit it, to release it.",
        secureInputUnattributed: "The app holding it cannot be named, so EVERYTHING cannot type for you. Dismiss any open password field, or log out and back in, to clear it.",
        secureInputUnidentified: "The app holding it could not be identified, so EVERYTHING cannot type for you.",
        secureInputRevealFormat: "Show %@",
        secureInputSwitcherHeldFormat: "%@ was the active app when it turned on and may be holding it. Until it turns off, macOS hides your keystrokes from the switcher and ⌘Tab opens the macOS switcher instead. Dismiss its password field, or quit it, to release it.",
        secureInputSwitcherUnattributed: "The app holding it cannot be named. Until it turns off, macOS hides your keystrokes from the switcher and ⌘Tab opens the macOS switcher instead. Dismiss any open password field, or log out and back in, to clear it.",
        secureInputSwitcherUnidentified: "The app holding it could not be identified. Until it turns off, macOS hides your keystrokes from the switcher and ⌘Tab opens the macOS switcher instead.",

        aboutDescription: "A utility hub for your Mac.\nEnergy, system monitor, scrolling and a window switcher, right in the menu bar.",
        versionPrefix: "Version",
        reviewIntro: "Review introduction",
        reviewHighlights: "Review highlights",
        viewOnGitHub: "View on GitHub",

        obContinue: "Continue",
        obBack: "Back",
        obSkipStep: "Skip this step",
        obStart: "Open EVERYTHING",
        obStepWelcomeTitle: "Welcome to EVERYTHING",
        obStepWelcomeBody: "A discreet menu bar utility that makes everyday macOS more practical.",
        obWelcomeBullet1Title: "Energy under control",
        obWelcomeBullet1Body: "Keep the Mac awake for as long as you want, even with the lid closed.",
        obWelcomeBullet2Title: "A clear view of the system",
        obWelcomeBullet2Body: "CPU, GPU and battery temperatures, hardware usage and memory pressure in real time.",
        obWelcomeBullet3Title: "Mouse and windows, your way",
        obWelcomeBullet3Body: "Reversed mouse scrolling and a window switcher with thumbnails.",
        obLanguageLabel: "Language",
        obStepAccessibilityTitle: "Accessibility",
        obStepAccessibilityBody: "Needed to invert mouse scrolling and for the window switcher to respond to the keyboard.",
        obAccessibilityWhy: "The app only watches the mouse wheel and the switcher keybind. Nothing is recorded or sent anywhere.",
        obStepRecordingTitle: "Screen Recording",
        obStepRecordingBody: "Lets the switcher show real window thumbnails instead of icons only.",
        obRecordingWhy: "Thumbnails are generated on the fly, stay in memory and never leave your Mac. Without it, the switcher still works with icons.",
        obStepMonitorTitle: "System monitor",
        obStepMonitorBody: "The panel shows CPU, GPU and battery temperatures, hardware usage and memory pressure.",
        obMonitorNoPermission: "No permission needed. Sensors are read straight from the system.",
        obStepOptionalTitle: "Optional features",
        obStepOptionalBody: "Turn on what you want to use now. EVERYTHING can be changed later in Settings.",
        obStepStatusTitle: "Checkup",
        obStepStatusBody: "Make sure everything is ready for the features you want.",
        obStatusRecheck: "Check again",
        obStepDoneTitle: "All set!",
        obStepDoneBody: "EVERYTHING is already looking after your Mac.",
        obDoneHint: "Look for the black hole in the menu bar, at the top right of the screen.",
        obWhatsNewTitle: "What’s new in this version",
        obWhatsNewFallback: "This update includes the latest fixes and improvements.",
        obLanguageUpdateTitle: "Now in your language",
        obLanguageUpdateBody: "EVERYTHING now speaks several languages. Choose the one you’d like to use; you can change it anytime in Settings.",
        obPurposeTitle: "What brought you here?",
        obPurposeBody: "Choose a ready setup or select exactly what you want to use.",
        obPurposeSkip: "You can add or remove features later in Settings.",

        tabMonitor: "Monitor",
        monitorMenuBarSection: "In the menu bar",
        monitorMenuBarPreview: "Menu bar preview",
        monitorMenuBarCaption: "Choose what appears next to the icon in the menu bar.",
        monitorCombineTemperatures: "Combine usage and temperature",
        monitorCombineTemperaturesCaption: "When usage and temperature for the same item are enabled, show them in one block.",
        monitorSeparateMenuBarMetrics: "Separate metrics into their own items",
        monitorSeparateMenuBarMetricsCaption: "Separates active blocks in the menu bar and keeps usage and temperature together when combine is on.",
        monitorNetworkUploadFirst: "Upload above download",
        monitorShowCPU: "CPU",
        monitorShowMemory: "Memory",
        monitorShowNetwork: "Network",
        monitorShowPowerLabel: "Power",
        monitorIntervalLabel: "Update every",
        monitorInterval1: "1 second",
        monitorInterval2: "2 seconds",
        monitorInterval5: "5 seconds",
        monitorPanelSection: "In the panel",
        panelNavigationMode: "Navigate panel by sections",
        panelNavigationCaption: "Shows one section at a time. Choose List to see everything in one continuous scroll.",
        panelFooterSections: "Sections",
        panelFooterList: "List",
        betaBadge: "BETA",
        betaFeatureWarning: "Beta. You may run into some bugs.",

        networkSection: "Network",
        networkIPAddresses: "IP addresses",
        networkLocalIP: "Local IPv4",
        networkDownload: "Download",
        networkUpload: "Upload",
        networkThisSession: "This session",
        networkMeasuring: "Measuring…",
        networkApps: "Apps using network",
        networkAppsIdle: "No apps using network now",

        diskSection: "Disks",
        diskUsed: "used",
        diskFree: "free",
        diskMenuBarStyleLabel: "Disk display",
        diskMenuBarUsedPercentage: "Used percentage",
        diskMenuBarAvailableSpace: "Available space",
        diskMenuBarUsedSpace: "Used space",
        diskAvailable: "available",
        diskPurgeable: "purgeable",
        diskInternal: "Internal",
        diskExternal: "External",
        diskSelect: "Select disk",
        diskRead: "Read",
        diskWrite: "Write",
        diskSMARTStatus: "Status",
        diskSMARTUnavailable: "SMART unavailable for this disk",
        diskTotalRead: "Total read",
        diskTotalWritten: "Total written",
        diskTemperature: "Temperature",
        diskHealth: "Health",
        diskPowerCycles: "Power cycles",
        diskPowerOnHours: "Power on hours",
        diskUnsafeShutdowns: "Unsafe shutdowns",
        diskMediaErrors: "Media errors",
        diskEject: "Eject",
        diskEjectAll: "Eject all",
        diskEjecting: "Ejecting…",
        diskReadyToRemove: "Ready to remove",
        diskEjectFailed: "Could not eject",
        diskProtectionCaption: "Eject before unplugging.",
        diskNoExternal: "No external disk ready to eject.",
        diskOpenInFinder: "Open",
        diskStorageSettings: "Storage",
        diskNoDisks: "No mounted disks found.",

        powerSection: "Power",
        powerSystem: "System",
        powerAdapter: "Adapter",
        powerBattery: "Battery",
        powerCharging: "Charging",
        powerOnBattery: "On battery",
        powerPluggedIn: "Plugged in",
        powerUnavailable: "Power metrics unavailable on this Mac",
        powerAdapterMaxFormat: "%@ max",
        monitorShowGPU: "GPU",
        monitorShowCPUTemperature: "CPU temperature",
        monitorShowGPUTemperature: "GPU temperature",
        monitorShowBatteryTemperature: "Battery temperature",
        monitorShowPeripheralBattery: "Peripheral battery",
        peripheralBatteryNoDevices: "No devices found",
        monitorGraphsSection: "Graphs",

        updateBannerTitle: "Update available",
        updateBannerAction: "Update",
        obStepMenuBarTitle: "Metrics in the menu bar",
        obStepMenuBarBody: "Pick what to show next to the icon. The preview above updates live.",
        obStepMenuBarNote: "New: Network and Power blocks and graphs in the panel. Fine-tune it all later in Settings › Monitor.",
        monitorMenuBarPresetLabel: "Style",
        menuBarPresetReadable: "Readable",
        menuBarPresetDense: "Dense",
        menuBarSpacingLabel: "Menu bar spacing",
        menuBarSpacingStandard: "Standard",
        menuBarSpacingCompact: "Compact",
        menuBarHideIconToggle: "Hide the app icon while metrics are shown",
        menuBarHideIconCaption: "The icon returns by itself when metrics leave the bar and when there is something to signal (an update ready, “Keep awake” running or the microphone muted).",
        monitorLabelStyleLabel: "Labels",
        menuBarLabelStyleCompact: "Compact",
        menuBarLabelStyleClassic: "Classic",
        monitorMemoryStyleLabel: "Show memory as",
        monitorMemoryPressureDot: "Pressure dot",
        memoryStyleDot: "Dot",
        memoryStylePercent: "%",
        memoryStyleBoth: "Both",
        systemUptime: "Up for",
        batteryCharge: "Charge",
        powerHealth: "Battery health",
        powerCycles: "Cycles",
        speedTestRun: "Speed test",
        speedTestAgain: "Test again",
        speedTestLatency: "Latency",
        speedTestTesting: "Testing…",
        speedTestFailed: "Test failed",

        monitorShowInPanel: "Show in panel",
        disclosureExpanded: "Expanded",
        disclosureCollapsed: "Collapsed",
        panelHideItem: "Hide from panel",
        panelShowItem: "Show in panel",
        panelHiddenItem: "Hidden",
        monitorItemUptime: "Uptime",
        monitorItemNetSpeed: "Live speed",
        monitorItemNetTotals: "Session totals",
        monitorItemNetTest: "Speed test",
        monitorItemDiskUsage: "Disk usage",
        monitorItemDiskActivity: "Live activity",
        monitorItemDiskSMART: "SMART",
        monitorItemDiskProtection: "External protection",
        monitorItemDiskTools: "Tools",
        monitorPanelConfigHint: "Open a block to choose what it shows.",
        monitorOrderHint: "Drag to reorder the panel sections and use the eye to show or hide each one.",
        obStepPanelTitle: "What’s in the panel",
        obStepPanelBody: "Open each block and pick exactly what shows when you click the icon.",
        obStepPanelNavigationTitle: "Section-based panel",
        obStepPanelNavigationBody: "The panel can now show one section at a time. You can switch between Sections and List in Settings.",

        cleaningMenuItem: "Cleaning Mode",
        utilitiesSection: "Utilities",
        quickControlsSection: "Controls",
        panelCategoryWindows: "Windows",
        panelCategoryInput: "Mouse and keyboard",
        panelCategoryFiles: "Files",
        windowMaximizeName: "Maximize windows",
        windowMaximizeCaption: "The green button maximizes without creating another Space.",
        windowMaximizeActiveNow: "Green button override active",
        windowMaximizeNeedsAccessibility: "Needs Accessibility to work.",
        keyDebounceName: "Debounce",
        keyDebounceEnable: "Filter duplicate keys",
        keyDebounceCaption: "Filters very fast duplicate key presses.",
        keyDebounceActiveNow: "Filter active",
        keyDebounceGlobalWindow: "Global window",
        keyDebouncePerKeySection: "Specific keys",
        keyDebouncePerKeyCaption: "Per-key values override the global window. Use 0 ms to stop filtering a key.",
        keyDebounceKeyLabel: "Key",
        keyDebounceWindowLabel: "Window",
        keyDebounceAddKey: "Add key",
        keyDebounceNoOverrides: "No specific keys configured.",
        keyDebounceRemoveKey: "Remove key",
        cleaningPanelCaption: "Locks the keyboard so you can clean safely.",
        cleaningOverlayTitle: "Keyboard locked for cleaning",
        cleaningOverlaySubtitle: "Press Escape 5 times to unlock",
        cleaningOverlayUnlock: "Unlock",
        cleaningOverlayMouseHint: "Your mouse and trackpad still work",
        cleaningKeepScreenVisibleToggle: "Keep screen visible",
        cleaningKeepScreenVisibleCaption: "Shows a discreet indicator in the corner of the screen instead of blacking out content.",
        cleaningStartNow: "Lock keyboard now",
        cleaningNeedsAxTitle: "Accessibility needed",
        cleaningNeedsAxBody: "To lock the keyboard safely, EVERYTHING needs Accessibility permission. Grant it in System Settings and try again.",

        tabSupport: "Support",
        shortcutsPageCaption: "Edit every global keybind from the features installed on this Mac. Inactive keybinds stay saved but do not run.",
        shortcutsPageTitle: "Keyboard keybinds",
        settingsSearchPlaceholder: "Search settings",
        donateHeading: "Help EVERYTHING keep growing",
        donateMessage: "EVERYTHING stays free and local, with no ads or usage tracking. If it helps you, Buy Me a Coffee is the only way to help fund its development.",
        donateButton: "Support on Buy Me a Coffee",
        donateThanks: "Thank you for being here. 🖤",
        supportIntroTitle: "Help EVERYTHING keep growing",
        supportIntroMessage: "EVERYTHING stays free and local, with no ads or usage tracking. If it helps you, Buy Me a Coffee is the only way to help fund its development.",
        supportIntroStarButton: "Star EVERYTHING on GitHub",
        supportIntroStarMessage: "Financial support is never expected. A star on GitHub helps more people discover EVERYTHING and makes a real difference to its development.",
        supportIntroStarHint: "A star on GitHub also helps more people find EVERYTHING, and it means a lot.",
        supportIntroCoffeeButton: "Support on Buy Me a Coffee",
        supportIntroLaterButton: "Not now",
        supportIntroDoneButton: "Done",
        discordIntroTitle: "The EVERYTHING Discord community is just getting started",
        discordIntroMessage: "The EVERYTHING community is new and still being built. Join early to meet other users and help build a welcoming space around the app.",
        discordIntroJoinButton: "Join the Discord community",
        communityIntroTitle: "See it before everyone else",
        communityIntroMessage: "People who already followed me on X saw several changes in this update before anyone else. I post previews of what is coming and show how it works, so you already know the basics before the update ships. Follow along and see what comes next!",
        communityIntroFollowButton: "Follow @vorssaint on X",
        homebrewOfficialIntroTitle: "Now in the official Homebrew catalog",
        homebrewOfficialIntroMessage: "EVERYTHING can now be installed directly from the official Homebrew catalog.",
        homebrewOfficialIntroInstallLabel: "New installation",
        homebrewOfficialIntroMigrationTitle: "Used the old tap?",
        homebrewOfficialIntroMigrationMessage: "Remove the tap once. The app and your settings stay in place.",
        homebrewOfficialIntroCopyButton: "Copy command",
        updateShowcaseTitle: "What’s new in 3.1.4",
        updateShowcaseMessage: "Take a quick look at the main improvements in this update.",
        updateShowcaseUnavailable: "The video could not load right now. You can still continue.",
        updateShowcaseRestart: "Restart",
        showMenuBarIcon: "Show menu bar icon",
        menuBarIconStillHiddenTitle: "The icon is still hidden",
        menuBarIconStillHiddenBody: "The icon was rebuilt, but macOS did not give it a visible spot. The menu bar is probably out of room: remove some menu bar icons (or close apps with long menus) and try again.",
        menuBarIconManagerHintFormat: "%@ is open and may be keeping the icon in its hidden section. Look for EVERYTHING there, or set %@ to always show EVERYTHING.",
        menuBarIconDisallowedBody: "macOS is keeping EVERYTHING out of the menu bar. Open System Settings > Menu Bar, find EVERYTHING in the app list and turn on “Allow in the Menu Bar”. The icon appears as soon as the switch is on.",
        shortcutRecording: "Press the new keybind",
        shortcutReset: "Reset",
        shortcutNone: "None",
        shortcutClear: "Remove keybind",
        shortcutInvalid: "Use at least Control, Option or Command with a key.",
        shortcutPressKeys: "Press keys",
        shortcutEscapeHint: "Escape cancels.",
        shortcutDeleteHint: "Delete clears.",
        shortcutNotCaptured: "Nothing was captured. macOS or another app already uses that combination. Try another one.",
        shortcutConflictFormat: "This keybind is already used by %@.",
        shortcutTakeOverOffer: "macOS uses %@ for one of its own keybinds.",
        shortcutTakeOverAction: "Take over while EVERYTHING runs",
        shortcutTakeOverCaption: "macOS gets the key back whenever EVERYTHING is not running or this feature is off.",
        shortcutTakeOverDismiss: "Don’t take over",
        shortcutUnavailable: "macOS rejected this keybind. Choose another one.",
        shelfShortcutToggle: "Shelf keybind",
        switcherUsageHintFormat: "Hold %@ to navigate; release to activate the window. Shift or ← goes back; W closes the window; Q quits the app; Esc cancels.",
        musicBlockSection: "Media keys",
        musicBlockTitle: "Stop Music from opening on its own",
        musicBlockCaption: "Blocks the music app opening after a detected media key. Requires Accessibility access. Headphone commands without a detected key are left alone.",
        musicBlockUnavailable: "This protection is unavailable right now. Turn it off and on to try again.",
        musicBlockReplacementLabel: "Open instead",
        musicBlockReplacementNone: "None",
        musicBlockReplacementBlocked: "Music and iTunes are the apps being blocked, so they can’t open instead. Choose another app.",
        musicBlockChooseApp: "Choose app…",
        musicBlockPlayReplacement: "Play after opening replacement",
        cleanerName: "Cleaner",
        cleanerIntroTitle: "Clean up your Mac",
        cleanerIntroCaption: "Scans for leftovers from uninstalled apps, caches, logs and the Trash. You review everything first and removed items go to the Trash.",
        cleanerScan: "Scan",
        cleanerScanning: "Scanning…",
        cleanerCleaning: "Cleaning…",
        cleanerCatLeftovers: "Leftovers from uninstalled apps",
        cleanerCatLoginItems: "Orphaned startup items",
        cleanerCatCaches: "Caches",
        cleanerCatLogs: "Logs",
        cleanerCatDeveloper: "Developer junk",
        cleanerCatTrash: "Trash",
        cleanerLeftoversNote: "Found by analysis and left unchecked. Check the path before ticking.",
        cleanerLoginItemsNote: "The entry under Login Items disappears after restarting the Mac.",
        cleanerTrashNote: "Emptying the Trash is permanent.",
        cleanerCatDeviceBackups: "iPhone backups",
        cleanerDeviceBackupsCaption: "Old iPhone and iPad backups take a big slice of the storage macOS calls Other. Remove only the ones you no longer need; a new backup is made when you plug the device in again.",
        cleanerCatScreenshots: "Forgotten screenshots",
        cleanerScreenshotsCaptionFormat: "Screenshots you have not opened in %d days that still have the name and folder macOS gave them. Ones you renamed or moved never show up here.",
        cleanerScreenshotsSettingCaption: "The scan lists the screenshots you have not opened for this long, unchecked, with their total size.",
        cleanerScreenshotsAfterFormat: "After %d days",
        cleanerNothingFound: "Nothing to clean. Your Mac is tidy.",
        cleanerClean: "Clean",
        cleanerDoneNote: "Items went to the Trash and can be recovered from there.",
        cleanerAgain: "Scan again",
        cleanerRevealInFinder: "Reveal in Finder",
        cleanerPanelCaption: "App leftovers, caches and logs",
        cleanerSafeSection: "Safe cleanup",
        cleanerOptionalSection: "Optional, review first",
        cleanerCatOtherCaches: "Other caches",
        cleanerCachesCaption: "Temporary files apps rebuild on their own.",
        cleanerLogsCaption: "Old diagnostic logs.",
        cleanerDeveloperCaption: "Xcode build and simulator leftovers.",
        cleanerLoginItemsCaption: "Startup entries left by apps that no longer exist.",
        cleanerLeftoversCaption: "Files left behind by apps you uninstalled.",
        cleanerOtherCachesCaption: "Safe to remove, nothing breaks. Apps may open slower once and downloaded content, like offline music, downloads again.",
        cleanerCleanSizeFormat: "Clean %@",
        cleanerScheduleTitle: "Automatic cleanup",
        cleanerScheduleOff: "Off",
        cleanerScheduleDaily: "Daily",
        cleanerScheduleWeekly: "Weekly",
        cleanerScheduleCaption: "Cleans only the safe part on its own at the chosen time and sends everything to the Trash.",
        cleanerScheduleLastFormat: "The last automatic cleanup freed %@.",
        cleanerAutoNotificationFormat: "%@ freed and sent to the Trash.",
        cleanerScheduleNextFormat: "Next cleanup %@.",
        cleanerScheduleRanFormat: "Last automatic cleanup %@.",
        cleanerScheduleNotifyToggle: "Notify when done",
        cleanerNotifDenied: "EVERYTHING notifications are turned off in the system.",
        cleanerNotifOpenSettings: "Open Notification Settings…",
        launchAtLoginNeedsApplications: "The app is running from a place that cannot open at login. Drag EVERYTHING to the Applications folder, open it from there and turn this on again.",
        launchAtLoginNeedsApproval: "The login item is registered, but macOS still needs your approval. In System Settings, allow EVERYTHING to open at login and to run in the background.",
        ocrRemoveLineBreaksToggle: "Remove line breaks",
        ocrRemoveLineBreaksCaption: "Removes line breaks so copied text pastes as one paragraph.",
        ocrQRToggle: "Read QR codes",
        ocrQRCaption: "If the area has a QR code, its content is shown to copy or open.",
        ocrQRCopied: "QR code copied",
        qrResultTitle: "QR code",
        qrResultCopy: "Copy",
        qrResultOpen: "Open link",
        highlightsTitle: "New in this update",
        highlightsTitleClipboardRedesign: "Redesigned clipboard",
        highlightsTitleWindowLayout: "Window Layout",
        highlightsTitleQuitProtection: "Quit and close protection",
        highlightsTitleRecorderBlur: "Recording privacy blur",
        highlightsCaptionDockPreview: "Dock Preview now works with Dock magnification turned on",
        highlightsCaptionScreenshot: "The screenshot tool gained a pixel loupe and QR code reading",
        highlightsCaptionSnippetLibrary: "A searchable snippet menu types any snippet right at your cursor",
        highlightsCaptionCapturePalette: "One keybind now opens a floating palette for screenshots, recordings, screen text and colors with nearby controls.",
        highlightsCaptionClipboardRedesign: "Clipboard history now opens as a compact palette with uncluttered rows and an on-demand preview for reading or editing the full item.",
        highlightsCaptionWindowLayout: "Position windows with the directional ring using a keybind and pointer, or drag to screen edges to snap with custom gaps.",
        highlightsCaptionQuitProtection: "Avoid quitting apps or closing windows by accident with a hold, a double press or an extra modifier, customizable per app.",
        highlightsCaptionRecorderBlur: "Hide private details, passwords and sensitive areas anywhere across your recorded video before sharing or exporting.",
        highlightsConfigure: "Set up",
        highlightsTry: "Try it",
        highlightsSeeAll: "See all changes",
        switcherCurrentSpaceOnly: "Show only the current desktop",
        switcherCurrentSpaceOnlyCaption: "Lists windows from the current desktop. Fullscreen windows from other desktops also appear while “Show fullscreen windows” is on.",
        shelfFileMissing: "The file no longer exists",
        previewSizeSmall: "Small",
        mixerSoundEffectsOutputTitle: "System sounds",
        mixerSoundEffectsOutputTooltip: "Choose where alerts and sound effects play",
        monitorOpenActivityMonitor: "Open Activity Monitor",
        dockClickHide: "Click the Dock icon to hide the app",
        dockClickHideCaption: "The active app hides when you click its Dock icon. Click again to bring it back.",
        monitorMemoryMetricLabel: "Measure memory as",
        memoryMetricUsed: "Memory Used",
        memoryMetricApp: "App Memory",
        keepAwakeRightClickToggle: "Right-click the menu bar icon to toggle Keep Awake",
        keepAwakeRightClickToggleCaption: "Replaces the right-click context menu.",
        urlCleanerRulesTitle: "Cleaning rules",
        urlCleanerRulesCaption: "A site attaches these parameters to its own share links to track where the link came from. Switched on, a name is removed when a link is cleaned; switched off, it stays. Names you add can be deleted.",
        urlCleanerRulesCoverageCaption: "The list covers a site’s different share paths (the web page, the app, a live room), which is why it is long; a real link usually carries only two to four of them.",
        urlCleanerRulesAllSites: "All sites",
        urlCleanerRulesCountSingular: "1 parameter",
        urlCleanerRulesCountPluralFormat: "%d parameters",
        urlCleanerRulesAddSite: "Add a site",
        urlCleanerRulesParameterPlaceholder: "Parameter name",
        urlCleanerRulesMatchCaption: "Write the name to the left of the = , like utm_source. A name that matches takes that one parameter out of the link and leaves the rest as it was.",
        urlCleanerRulesAddButton: "Add",
        urlCleanerRulesRemoveButton: "Delete name",
        urlCleanerRulesRemoveSiteButton: "Turn off every rule for this site",
        urlCleanerRulesRestoreSiteButton: "Turn on every rule for this site",
        urlCleanerRemovedFormat: "Removed %@",
        switcherSearchPin: "Pin search with S",
        switcherSearchPinCaption: "S starts a search and pins the switcher open, so typing no longer produces special characters when your keybind uses ⌥, and a search starting with Q or W no longer closes the window or quits the app by mistake.",
        invertVerticalScroll: "Invert vertical scrolling",
        invertHorizontalScroll: "Invert horizontal scrolling",
        scrollHorizontalName: "Scroll sideways while holding a key",
        zoomSection: "Zoom",
        zoomControlNote: "Control + scroll performs app zoom instead of macOS screen zoom.",
        pinchZoom: "Pinch Zoom",
        scrollHorizontalModifierLabel: "Modifier key",
        scrollHorizontalCommandKey: "Command",
        scrollHorizontalCaption: "Hold only the selected modifier to scroll the vertical mouse wheel horizontally. Other key combinations are unchanged.",
        switcherShowShortcutHints: "Show keybind hints",
        switcherShowShortcutHintsCaption: "Shows the app and window keybinds below the icons.",
        uninstallerHomebrewPackageFormat: "%@ will also be removed from Homebrew.",
        uninstallerHomebrewCheckFailed: "Could not verify whether Homebrew manages this app. Refresh to try again, or uninstall it from Homebrew.",
        shelfEdgeToggle: "Open near a screen edge",
        shelfEdgeCaption: "Drag a file toward the screen edge to peek the shelf in. Drop it there, or pull back and it retreats.",
        focusFollowsMouseName: "Focus follows mouse",
        focusFollowsMouseCaption: "Focuses the window under the pointer.",
        focusFollowsMouseDelay: "Hover delay",
        focusFollowsMouseRaise: "Bring the window to the front",
        focusFollowsMouseWaitForStop: "Wait for the pointer to stop",
        switcherMinimizedPlacementLabel: "Minimized windows",
        switcherTreatHiddenAppsLikeMinimized: "Treat hidden apps like minimized windows",
        switcherMinimizedPlacementNormal: "Normal ordering",
        switcherMinimizedPlacementEnd: "Place at end",
        switcherMinimizedPlacementHidden: "Hide",
        switcherShowFullscreenWindows: "Show fullscreen windows",
        switcherScreenPlacementLabel: "Show on",
        switcherScreenPlacementPointer: "Display with the pointer",
        switcherScreenPlacementMenuBar: "Display with the menu bar",
        switcherScreenPlacementActiveWindow: "Display with the active window",
        switcherScreenPlacementCaption: "Which display the switcher opens on when more than one is connected.",
        switcherCurrentDisplayOnly: "Show only the current display",
        switcherCurrentDisplayOnlyCaption: "Lists only windows on the display under the pointer. If that display has no windows, the switcher does not open.",
        smoothScrollResponseLabel: "Response",
        smoothScrollCoastLabel: "Coast",
        mouseAccelerationName: "Disable mouse acceleration",
        mouseAccelerationCaption: "Removes pointer acceleration for connected mice. Your previous setting returns when this is turned off or EVERYTHING quits.",
        linearScrollName: "Linear scrolling",
        linearScrollCaption: "Every notch of the mouse wheel scrolls the same distance, no matter how fast it spins. The trackpad is not affected.",
        linearScrollLinesLabel: "Lines per step",
        shelfClearOnClose: "Clear when closed",
        shelfClearOnCloseCaption: "Empties the shelf only when you click its close button. Automatic hiding and collapsing keep the items.",
        shelfShortcutFinderSelection: "Add the Finder selection with the keybind",
        shelfShortcutFinderSelectionCaption: "With Finder in front, the keybind opens the shelf with the selected files already in it. With nothing selected, it opens as usual.",
        spacesOrderName: "Keep Spaces in a fixed order",
        spacesOrderCaption: "Stops macOS from rearranging Spaces by most recent use, so they stay in the order you set. Your previous setting returns when this is turned off. The Dock may restart once to apply the change.",
        quitAppsName: "Quit apps",
        quitAppsCaption: "Lists your open apps to quit one by one, all at once, or all but the one in front. Always shows the list before anything quits."
    )
}
