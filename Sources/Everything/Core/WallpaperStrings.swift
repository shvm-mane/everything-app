// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct WallpaperFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelDescription: String
    let filterAll: String
    let filterOwn: String
    let filterApple: String
    let applyAllDisplays: String
    let addImage: String
    let addFolder: String
    let removeAdded: String
    let doneRemoving: String
    let sourceUnavailable: String
    let addImagePrompt: String
    let addFolderPrompt: String
    let openSystemSettings: String
    let emptyAll: String
    let emptyOwn: String
    let emptyApple: String
    let downloading: String
    let downloadFailed: String
    let applyFailed: String
    let previousPage: String
    let nextPage: String
}

extension FeatureStrings {
    static func wallpaper(_ language: AppLanguage) -> WallpaperFeatureStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension WallpaperFeatureStrings {
    static let enUS = WallpaperFeatureStrings(
        pageTitle: "Wallpaper",
        hubDescription: "Pick a still wallpaper without opening System Settings",
        panelDescription: "Pick a still wallpaper without opening System Settings.",
        filterAll: "All",
        filterOwn: "Your pictures",
        filterApple: "Apple",
        applyAllDisplays: "Show on all Spaces",
        addImage: "Add image",
        addFolder: "Add folder",
        removeAdded: "Remove",
        doneRemoving: "Done",
        sourceUnavailable: "Unavailable",
        addImagePrompt: "Choose images to keep in EVERYTHING’s wallpaper list",
        addFolderPrompt: "Choose a folder of images to keep in EVERYTHING’s wallpaper list",
        openSystemSettings: "Open Wallpaper settings",
        emptyAll: "No wallpapers found",
        emptyOwn: "No pictures added yet",
        emptyApple: "No Apple stills found",
        downloading: "Downloading…",
        downloadFailed: "Could not download the wallpaper",
        applyFailed: "Could not set the wallpaper",
        previousPage: "Previous",
        nextPage: "Next"
    )

}
