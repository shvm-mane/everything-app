// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchFilesStrings {
    let archive: String
    let archiveHint: String
    let saved: String
    let downloadsTitle: String
    let downloadsDescription: String
    let downloadsHint: String
    let chooseFolder: String
    let folderUnavailable: String
    let waiting: String
    let inProgress: String
    let totalUnknown: String
    let completed: String
    let clearFolder: String
    let optimizeMedia: String
    let optimizeDropHint: String
    let resumeMedia: String
}

extension FeatureStrings {
    static func notchFiles(_ language: AppLanguage) -> NotchFilesStrings {
        switch language {
        case .enUS: return NotchFilesStrings(
            archive: "Create ZIP",
            archiveHint: "Each selected item is saved as a separate ZIP. Originals stay unchanged.",
            saved: "Saved",
            downloadsTitle: "Downloads",
            downloadsDescription: "See files arriving in a folder you choose, directly in the Dynamic Island.",
            downloadsHint: "Choose the folder where your browser saves downloads. Only that folder is watched.",
            chooseFolder: "Choose Folder…",
            folderUnavailable: "This folder is unavailable. Choose it again to restore access.",
            waiting: "No files in this folder",
            inProgress: "Downloading",
            totalUnknown: "Total size unavailable",
            completed: "Download complete",
            clearFolder: "Forget Folder",
            optimizeMedia: "Optimize media",
            optimizeDropHint: "Drag images or one video onto the island, then drop on Optimize media to choose how to save a copy.",
            resumeMedia: "Return to media")
        }
    }
}
