// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct WindowPreviewExclusionStrings {
    let sectionTitle: String
    let listTitle: String
    let addButton: String
    let removeButton: String
    let caption: String
}

extension FeatureStrings {
    static func windowPreviewExclusions(_ language: AppLanguage) -> WindowPreviewExclusionStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension WindowPreviewExclusionStrings {
    static let enUS = WindowPreviewExclusionStrings(
        sectionTitle: "Window thumbnails",
        listTitle: "Pause in these apps",
        addButton: "Add an app…",
        removeButton: "Remove",
        caption: "Window thumbnails stop while one of these apps is in front."
    )

}
