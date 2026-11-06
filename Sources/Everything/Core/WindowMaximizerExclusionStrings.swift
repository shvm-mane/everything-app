// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct WindowMaximizerExclusionStrings {
    let listTitle: String
    let addButton: String
    let removeButton: String
    let caption: String
}

extension FeatureStrings {
    static func windowMaximizerExclusions(_ language: AppLanguage) -> WindowMaximizerExclusionStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension WindowMaximizerExclusionStrings {
    static let enUS = WindowMaximizerExclusionStrings(
        listTitle: "Keep full screen in these apps",
        addButton: "Add an app…",
        removeButton: "Remove",
        caption: "The green button keeps its macOS behavior in these apps, so games, emulators and video players can still enter full screen."
    )

}
