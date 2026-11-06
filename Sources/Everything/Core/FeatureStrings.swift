// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FeatureStrings {
    static func settingsCategories(_ language: AppLanguage) -> SettingsCategoryStrings {
        switch language {
        case .enUS: return .enUS
        }
    }

    static func clipboard(_ language: AppLanguage) -> ClipboardFeatureStrings {
        switch language {
        case .enUS: return .enUS
        }
    }

    static func windowLayout(_ language: AppLanguage) -> WindowLayoutFeatureStrings {
        switch language {
        case .enUS: return .enUS
        }
    }

    static func monitorAlerts(_ language: AppLanguage) -> MonitorAlertFeatureStrings {
        switch language {
        case .enUS: return .enUS
        }
    }

    static func mixer(_ language: AppLanguage) -> MixerFeatureStrings {
        switch language {
        case .enUS: return .enUS
        }
    }

    static func whatsAppDownloads(_ language: AppLanguage) -> WhatsAppDownloadStrings {
        WhatsAppDownloadStrings.localized(language)
    }
}

struct MixerFeatureStrings {
    let hideInactiveApps: String
    let pin: String
    let unpin: String
    let moveUp: String
    let moveDown: String
    let pinFirst: String
    let moveLeft: String
    let moveRight: String
    let arrange: String
    let actions: String

    static let enUS = MixerFeatureStrings(hideInactiveApps: "Hide inactive apps", pin: "Pin to Top", unpin: "Unpin", moveUp: "Move Up", moveDown: "Move Down", pinFirst: "Pin to Front", moveLeft: "Move Left", moveRight: "Move Right", arrange: "Hold Command and drag to reorder", actions: "Actions")
}

extension SettingsCategoryStrings {
}

extension ClipboardFeatureStrings {
}

extension WindowLayoutFeatureStrings {
}

extension MonitorAlertFeatureStrings {
}

struct SettingsCategoryStrings {
    let essentials: String
    let windowsControls: String
    let files: String
    let utilities: String
    let app: String
    let appManagement: String

    static let enUS = SettingsCategoryStrings(
        essentials: "Essentials",
        windowsControls: "Window controls",
        files: "Files",
        utilities: "Utilities",
        app: "App",
        appManagement: "App management"
    )

}

struct ClipboardFeatureStrings {
    let title: String
    let enable: String
    let caption: String
    let localNote: String
    let skipSensitive: String
    let skipSensitiveCaption: String
    let limit: String
    let limitUnlimited: String
    let showInPanel: String
    let shortcut: String
    let shortcutCaption: String
    let shortcutHint: String
    let clickRowShortcut: String
    let commandClickShortcut: String
    let pinned: String
    let recent: String
    let pin: String
    let unpin: String
    let clearRecent: String
    let clearRecentKeywords: String
    let empty: String
    let disabled: String
    let search: String
    let copy: String
    let copied: String
    let delete: String
    let selectMultiple: String
    let unselectMultiple: String
    let selectShortcutAction: String
    let pasteSelectedFormat: String
    let copySelectedFormat: String
    let clearSelection: String
    let moveUp: String
    let moveDown: String
    let noResults: String
    let active: String
    let includeImagesFiles: String
    let includeImagesFilesCaption: String
    let imageEntryLabel: String
    let fileCountFormat: String
    let pasteImageAsFile: String
    let pasteImageAsFileCaption: String
    let previewLabel: String
    let edit: String
    let cancel: String
    let save: String
    let autoClearEnable: String
    let autoClearSecondsSuffix: String
    let autoClearOnSleep: String
    let autoClearOnDisplaySleep: String
    let autoClearOnScreenLock: String
    let autoClearCaption: String
    let deleteSelectedFormat: String
    let menuBarPreview: String
    let menuBarPreviewCaption: String
    let menuBarPreviewLength: String
    let menuBarPreviewLengthSuffix: String
    let clearRecentConfirmFormat: String
    let clearRecentConfirmMessage: String
    let historyLayout: String
    let historyLayoutCards: String
    let historyLayoutList: String
    let showSourceAppIconsInList: String

    static let enUS = ClipboardFeatureStrings(
        title: "Clipboard",
        enable: "Save clipboard history",
        caption: "Stores copied text so you can reuse it later. EVERYTHING stays local and can be cleared anytime.",
        localNote: "EVERYTHING stays on this Mac. Very large items are ignored.",
        skipSensitive: "Skip text that looks sensitive",
        skipSensitiveCaption: "May skip ordinary text that resembles passwords or tokens. Content marked as confidential by its source app is always excluded.",
        limit: "Limit",
        limitUnlimited: "Unlimited",
        showInPanel: "Show in panel",
        shortcut: "History keybind",
        shortcutCaption: "Opens a quick window with search, pinned items and ⌘1 to ⌘9 keybinds for pasting into the previous app.",
        shortcutHint: "Click a row to paste it into the previous app. ⌘-click selects several; ⌘C copies without pasting.",
        clickRowShortcut: "Click row",
        commandClickShortcut: "⌘ Click",
        pinned: "Pinned",
        recent: "Recent",
        pin: "Pin",
        unpin: "Unpin",
        clearRecent: "Clear unpinned",
        clearRecentKeywords: "Clear recent",
        empty: "No saved text",
        disabled: "Enable history to start saving copied text.",
        search: "Search copied text",
        copy: "Copy",
        copied: "Copied",
        delete: "Delete item",
        selectMultiple: "Add to pile",
        unselectMultiple: "Remove from pile",
        selectShortcutAction: "Select",
        pasteSelectedFormat: "Paste %d",
        copySelectedFormat: "Copy %d",
        clearSelection: "Clear selection",
        moveUp: "Move up",
        moveDown: "Move down",
        noResults: "No results",
        active: "Saving new text",
        includeImagesFiles: "Also save copied images and files",
        includeImagesFilesCaption: "Images join the history and files are remembered as links to their location. Pin and paste them like any text item.",
        imageEntryLabel: "Image",
        fileCountFormat: "%d files",
        pasteImageAsFile: "Paste copied images as files",
        pasteImageAsFileCaption: "When Finder is active, ⌘V saves a copied image as a PNG in the current folder.",
        previewLabel: "Preview",
        edit: "Edit",
        cancel: "Cancel",
        save: "Save",
        autoClearEnable: "Auto clear clipboard with a delay of",
        autoClearSecondsSuffix: "seconds",
        autoClearOnSleep: "Clear clipboard on computer sleep",
        autoClearOnDisplaySleep: "Clear clipboard on display sleep",
        autoClearOnScreenLock: "Clear clipboard on screen lock",
        autoClearCaption: "Clears the system clipboard only. Items already saved stay in the history.",
        deleteSelectedFormat: "Delete %d",
        menuBarPreview: "Show latest copy in the menu bar",
        menuBarPreviewCaption: "Shows a shortened preview of your last copy next to the icon. Click it to open the history.",
        menuBarPreviewLength: "Preview length",
        menuBarPreviewLengthSuffix: "characters",
        clearRecentConfirmFormat: "Clear unpinned (%d)?",
        clearRecentConfirmMessage: "Pinned items stay, and so does anything copied after this. This can’t be undone.",
        historyLayout: "History layout",
        historyLayoutCards: "Cards",
        historyLayoutList: "List",
        showSourceAppIconsInList: "Show source app icons in list view"
    )

}

struct WindowLayoutFeatureStrings {
    let title: String
    let caption: String
    let showInPanel: String
    let gestureSection: String
    let gestureEnable: String
    let gestureCaption: String
    let gestureModifiers: String
    let gestureMove: String
    let gestureResize: String
    let gestureResizeHint: String
    let gestureRaiseWindow: String
    let shortcuts: String
    let shortcutsCaption: String
    let permissionCaption: String
    let noWindow: String
    let missingPermission: String
    let failed: String
    let done: String
    let restored: String
    let noRestore: String
    let target: String
    let halves: String
    let thirds: String
    let quarterRows: String
    let quarterColumns: String
    let sixths: String
    let corners: String
    let other: String
    let leftHalf: String
    let rightHalf: String
    let topHalf: String
    let bottomHalf: String
    let centerHalf: String
    let leftThird: String
    let centerThird: String
    let rightThird: String
    let leftTwoThirds: String
    let rightTwoThirds: String
    let centerTwoThirds: String
    let topThird: String
    let middleThird: String
    let bottomThird: String
    let topTwoThirds: String
    let bottomTwoThirds: String
    let topQuarter: String
    let upperMiddleQuarter: String
    let lowerMiddleQuarter: String
    let bottomQuarter: String
    let leftQuarter: String
    let leftMiddleQuarter: String
    let rightMiddleQuarter: String
    let rightQuarter: String
    let topLeftSixth: String
    let topCenterSixth: String
    let topRightSixth: String
    let bottomLeftSixth: String
    let bottomCenterSixth: String
    let bottomRightSixth: String
    let topLeft: String
    let topRight: String
    let bottomLeft: String
    let bottomRight: String
    let maximize: String
    let center: String
    let nextDisplay: String
    let restore: String
    let fullScreen: String
    let previousDisplay: String
    let edgeSnapEnable: String
    let edgeSnapCaption: String
    let edgeSnapSystemConflict: String
    let edgeSnapOpenSystemSettings: String
    let edgeSnapWaitingForSystem: String
    let edgeSnapUseCorner: String
    let edgeSnapUseEdge: String
    let edgeSnapAreasOnEdge: String
    let marginMaximize: String
    let marginPerEdge: String
    let gapsSection: String
    let gapsCaption: String
    let windowGap: String
    let screenGap: String
    let sideRepeatCycle: String
    let sideRepeatCycleCaption: String
    let gapNone: String
    let gapTiny: String
    let gapSmall: String
    let gapMedium: String
    let gapLarge: String
    let gapExtraLarge: String

    static let enUS = WindowLayoutFeatureStrings(
        title: "Window layout",
        caption: "Arrange windows into screen sections or move and resize them with a trackpad or mouse.",
        showInPanel: "Show in panel",
        gestureSection: "Window dragging",
        gestureEnable: "Move and resize by dragging",
        gestureCaption: "On a trackpad or mouse, hold the shown modifier keys and drag anywhere inside a window.",
        gestureModifiers: "Keys to move",
        gestureMove: "Drag to move",
        gestureResize: "Add Shift and drag to resize",
        gestureResizeHint: "The starting point chooses the nearest edge or corner. On a mouse, right-button drag also resizes.",
        gestureRaiseWindow: "Bring the dragged window to front",
        shortcuts: "Keybinds",
        shortcutsCaption: "Use global keybinds to arrange the active window without opening the panel.",
        permissionCaption: "Uses Accessibility only to move and resize windows.",
        noWindow: "No active window found.",
        missingPermission: "Grant Accessibility to move windows.",
        failed: "Could not move this window.",
        done: "Window arranged.",
        restored: "Window restored.",
        noRestore: "No previous layout to restore.",
        target: "Active window",
        halves: "Halves",
        thirds: "Thirds",
        quarterRows: "Quarter rows",
        quarterColumns: "Quarter columns",
        sixths: "Sixths",
        corners: "Corners",
        other: "Actions",
        leftHalf: "Left",
        rightHalf: "Right",
        topHalf: "Top",
        bottomHalf: "Bottom",
        centerHalf: "Center half",
        leftThird: "Left 1/3",
        centerThird: "Center 1/3",
        rightThird: "Right 1/3",
        leftTwoThirds: "Left 2/3",
        rightTwoThirds: "Right 2/3",
        centerTwoThirds: "Center 2/3",
        topThird: "Top 1/3",
        middleThird: "Middle 1/3",
        bottomThird: "Bottom 1/3",
        topTwoThirds: "Top 2/3",
        bottomTwoThirds: "Bottom 2/3",
        topQuarter: "Top 1/4",
        upperMiddleQuarter: "Upper middle 1/4",
        lowerMiddleQuarter: "Lower middle 1/4",
        bottomQuarter: "Bottom 1/4",
        leftQuarter: "Left 1/4",
        leftMiddleQuarter: "Left middle 1/4",
        rightMiddleQuarter: "Right middle 1/4",
        rightQuarter: "Right 1/4",
        topLeftSixth: "Top left 1/6",
        topCenterSixth: "Top center 1/6",
        topRightSixth: "Top right 1/6",
        bottomLeftSixth: "Bottom left 1/6",
        bottomCenterSixth: "Bottom center 1/6",
        bottomRightSixth: "Bottom right 1/6",
        topLeft: "Top left",
        topRight: "Top right",
        bottomLeft: "Bottom left",
        bottomRight: "Bottom right",
        maximize: "Maximize",
        center: "Center",
        nextDisplay: "Next display",
        restore: "Restore",
        fullScreen: "Full Screen",
        previousDisplay: "Previous display",
        edgeSnapEnable: "Snap windows at screen edges",
        edgeSnapCaption: "Turn this on and drag a window title bar to a highlighted area below. A window moved by holding the modifier keys snaps too. Click an area to choose where the window goes.",
        edgeSnapSystemConflict: "macOS is using the same edges. Turn off window tiling in Desktop & Dock so EVERYTHING can take over.",
        edgeSnapOpenSystemSettings: "Open Desktop & Dock",
        edgeSnapWaitingForSystem: "Enabled in EVERYTHING. It starts working as soon as macOS tiling is off.",
        edgeSnapUseCorner: "Use this corner",
        edgeSnapUseEdge: "Use this edge",
        edgeSnapAreasOnEdge: "Areas on this edge",
        marginMaximize: "Maximize with Margin",
        marginPerEdge: "Margin per edge",
        gapsSection: "Gaps",
        gapsCaption: "Space between snapped windows, and between windows and the screen edge.",
        windowGap: "Window gap",
        screenGap: "Screen gap",
        sideRepeatCycle: "Repeat Left or Right to cycle sizes",
        sideRepeatCycleCaption: "Half, then two thirds, then one third on the same display. Off, with more than one display, the repeat moves the window to the next display on that side.",
        gapNone: "None",
        gapTiny: "Tiny",
        gapSmall: "Small",
        gapMedium: "Medium",
        gapLarge: "Large",
        gapExtraLarge: "Extra large"
    )

}

struct MonitorAlertFeatureStrings {
    let section: String
    let caption: String
    let notificationsDenied: String
    let cpu: String
    let cpuTemperature: String
    let memory: String
    let disk: String
    let battery: String
    let cpuThreshold: String
    let cpuTemperatureThreshold: String
    let diskThreshold: String
    let batteryThreshold: String
    let cooldown: String
    let cooldown2: String
    let cooldown5: String
    let cooldown15: String
    let cooldown30: String
    let cooldown60: String
    let cpuTitle: String
    let cpuBodyFormat: String
    let cpuTemperatureTitle: String
    let cpuTemperatureBodyFormat: String
    let memoryTitle: String
    let memoryBody: String
    let diskTitle: String
    let diskBodyFormat: String
    let batteryTitle: String
    let batteryBodyFormat: String
    let batteryTemperature: String
    let batteryTemperatureThreshold: String
    let batteryTemperatureTitle: String
    let batteryTemperatureBodyFormat: String

    static let enUS = MonitorAlertFeatureStrings(
        section: "Alerts",
        caption: "Alerts fire when their selected limits are reached. CPU use and temperature alerts ignore spikes shorter than about 12 seconds. The repeat setting only limits repeats of the same alert.",
        notificationsDenied: "Notifications for EVERYTHING are off in System Settings, so alerts cannot appear.",
        cpu: "High CPU",
        cpuTemperature: "High CPU temperature",
        memory: "Critical memory pressure",
        disk: "Low disk space",
        battery: "Low battery",
        cpuThreshold: "CPU above",
        cpuTemperatureThreshold: "Temperature above",
        diskThreshold: "Free space below",
        batteryThreshold: "Battery below",
        cooldown: "Repeat the same alert after",
        cooldown2: "2 minutes",
        cooldown5: "5 minutes",
        cooldown15: "15 minutes",
        cooldown30: "30 minutes",
        cooldown60: "1 hour",
        cpuTitle: "High CPU",
        cpuBodyFormat: "CPU stayed above %d%% for a few seconds.",
        cpuTemperatureTitle: "Hot CPU",
        cpuTemperatureBodyFormat: "CPU reached %@.",
        memoryTitle: "Critical memory",
        memoryBody: "Memory pressure reached the critical level.",
        diskTitle: "Low disk space",
        diskBodyFormat: "%@ has less than %d%% free.",
        batteryTitle: "Low battery",
        batteryBodyFormat: "Battery is at %d%%.",
        batteryTemperature: "High battery temperature",
        batteryTemperatureThreshold: "Temperature above",
        batteryTemperatureTitle: "Hot battery",
        batteryTemperatureBodyFormat: "Battery reached %@."
    )

}

extension SettingsCategoryStrings {
}

extension ClipboardFeatureStrings {
}

extension WindowLayoutFeatureStrings {
}

extension MonitorAlertFeatureStrings {
}

extension MixerFeatureStrings {
}
