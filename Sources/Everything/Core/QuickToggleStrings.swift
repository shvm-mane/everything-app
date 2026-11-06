// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct QuickToggleFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelCaption: String
    let darkModeToDark: String
    let darkModeToLight: String
    let darkModeCaption: String
    let emptyTrashTitle: String
    let emptyTrashCaption: String
    let emptyTrashConfirmTitle: String
    let emptyTrashConfirmMessage: String
    let emptyTrashConfirmButton: String
    let quitAllTitle: String
    let quitOthersTitle: String
    let quitAppsHeader: String
    let quitAppsQuitAll: String
    let quitAppsQuitAllExcept: String
    let quitAppsQuitOne: String
    let quitAppsFrontBadge: String
    let quitAppsKeptBadge: String
    let quitAppsEmpty: String
    let exceptionsTitle: String
    let exceptionsCaption: String
    let ejectTitle: String
    let ejectCaption: String
    let hiddenFilesShow: String
    let hiddenFilesHide: String
    let desktopIconsHide: String
    let desktopIconsShow: String
    let finderRestartCaption: String
    let lockScreenTitle: String
    let lockScreenCaption: String
    let displayOffTitle: String
    let displayOffCaption: String
    let screenSaverTitle: String
    let screenSaverCaption: String
    let actionFailed: String
}

extension FeatureStrings {
    static func quickToggles(_ language: AppLanguage) -> QuickToggleFeatureStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension QuickToggleFeatureStrings {
    static let enUS = QuickToggleFeatureStrings(
        pageTitle: "Quick toggles",
        hubDescription: "One-click actions like dark mode and Trash",
        panelCaption: "One-click system actions in the menu bar panel and in the quick panel.",
        darkModeToDark: "Switch to dark mode",
        darkModeToLight: "Switch to light mode",
        darkModeCaption: "Changes the appearance of the whole system.",
        emptyTrashTitle: "Empty the Trash",
        emptyTrashCaption: "Removes everything from the Trash.",
        emptyTrashConfirmTitle: "Empty the Trash?",
        emptyTrashConfirmMessage: "All items in the Trash will be removed. This cannot be undone.",
        emptyTrashConfirmButton: "Empty the Trash",
        quitAllTitle: "Quit all apps",
        quitOthersTitle: "Quit all apps except the front one",
        quitAppsHeader: "Open apps",
        quitAppsQuitAll: "Quit all",
        quitAppsQuitAllExcept: "Quit all except %@",
        quitAppsQuitOne: "Quit %@",
        quitAppsFrontBadge: "Front",
        quitAppsKeptBadge: "Kept",
        quitAppsEmpty: "No other apps are open.",
        exceptionsTitle: "Kept apps",
        exceptionsCaption: "Quit all leaves these apps running. Finder, EVERYTHING and Phone are always kept. You can still quit a kept app from its own row.",
        ejectTitle: "Eject all disks",
        ejectCaption: "Safely ejects every external disk.",
        hiddenFilesShow: "Show hidden files",
        hiddenFilesHide: "Hide hidden files",
        desktopIconsHide: "Hide desktop icons",
        desktopIconsShow: "Show desktop icons",
        finderRestartCaption: "The Finder restarts to apply it.",
        lockScreenTitle: "Lock the screen",
        lockScreenCaption: "Asks for the password to come back.",
        displayOffTitle: "Turn off the display",
        displayOffCaption: "The Mac keeps running with the display off.",
        screenSaverTitle: "Start the screen saver",
        screenSaverCaption: "Starts right away, on every display.",
        actionFailed: "Could not complete."
    )

}
