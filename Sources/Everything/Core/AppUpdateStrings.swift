// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct AppUpdateStrings {
    let pageTitle: String
    let hubDescription: String
    let caption: String
    let panelCaption: String
    let checkNow: String
    let checking: String
    let lastCheckFormat: String
    let neverChecked: String
    let upToDate: String
    let partialUpToDate: String
    let coverageNote: String
    let selectAll: String
    let clearSelection: String
    let updateSelectedFormat: String
    let updateOne: String
    let openAppStore: String
    let appStoreBadge: String
    let storeHint: String
    let frequencyLabel: String
    let frequencyOff: String
    let frequencyDaily: String
    let frequencyWeekly: String
    let nextCheckFormat: String
    let notifyToggle: String
    let includeStoreToggle: String
    let includeStoreCaption: String
    let packageMissing: String
    let notificationBodyFormat: String
    let notificationBodyOne: String
    let showInPanel: String
    let homebrewBadge: String
    let sourcesTitle: String
    let includeHomebrewToggle: String
    let onlineBadge: String
    let openApp: String
    let openAppHint: String
    let includeOnlineToggle: String
    let includeOnlineCaption: String
    let incompleteCheck: String
    let onlineUnavailable: String
    let skipVersionFormat: String
    let excludeApp: String
    let rulesTitle: String
    let addException: String
    let skippedVersionFormat: String
    let excludedApp: String
    let removeRule: String
    let rulesHint: String
    let noVisibleUpdates: String
    let uncomparableVersions: String
    let uncomparableVersionsNote: String
}

extension FeatureStrings {
    static func appUpdates(_ language: AppLanguage) -> AppUpdateStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension AppUpdateStrings {
    static let enUS = AppUpdateStrings(
        pageTitle: "App updates",
        hubDescription: "Find and install updates for the apps you have",
        caption: "Looks for newer versions of the apps on this Mac and helps you finish each update from its original source.",
        panelCaption: "See which apps have a newer version",
        checkNow: "Check now",
        checking: "Checking",
        lastCheckFormat: "Last checked %@",
        neverChecked: "Not checked yet",
        upToDate: "No updates found",
        partialUpToDate: "No updates found in this partial check",
        coverageNote: "Checks the original sources of installed apps and a public catalog. Updates install through their original source.",
        selectAll: "Select all",
        clearSelection: "Clear",
        updateSelectedFormat: "Update %d",
        updateOne: "Update",
        openAppStore: "Open the App Store",
        appStoreBadge: "App Store",
        storeHint: "Opens the App Store, where this update is installed",
        frequencyLabel: "Check in the background",
        frequencyOff: "Off",
        frequencyDaily: "Every day",
        frequencyWeekly: "Every week",
        nextCheckFormat: "Next check %@",
        notifyToggle: "Tell me when an app has an update",
        includeStoreToggle: "Include apps from the App Store",
        includeStoreCaption: "Checks store versions using this Mac’s region. Apple installs these updates.",
        packageMissing: "Homebrew is not installed, so apps cannot be updated from here yet.",
        notificationBodyFormat: "%@ apps have a newer version.",
        notificationBodyOne: "One app has a newer version.",
        showInPanel: "Show in panel",
        homebrewBadge: "Homebrew",
        sourcesTitle: "Sources",
        includeHomebrewToggle: "Include Homebrew apps",
        onlineBadge: "Online",
        openApp: "Open",
        openAppHint: "Opens the app so its own updater can finish",
        includeOnlineToggle: "Include other installed apps",
        includeOnlineCaption: "Checks directly with app developers when supported, then uses a public catalog. The app’s own updater installs the update.",
        incompleteCheck: "Check incomplete",
        onlineUnavailable: "The online check could not be completed. Other results are still shown.",
        skipVersionFormat: "Skip version %@",
        excludeApp: "Don’t check this app",
        rulesTitle: "Update exceptions",
        addException: "Add an app that should not be checked",
        skippedVersionFormat: "Skipped version %@",
        excludedApp: "Not checked until this rule is removed",
        removeRule: "Remove",
        rulesHint: "Skipping a version still allows newer releases. After removing an app exclusion, use Check now to refresh it.",
        noVisibleUpdates: "No updates outside your rules",
        uncomparableVersions: "Versions not compared",
        uncomparableVersionsNote: "No update is shown when an app’s own version can’t be compared with the catalog. Check for updates in the app itself."
    )

}
