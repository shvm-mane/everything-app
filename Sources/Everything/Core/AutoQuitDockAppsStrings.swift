// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct AutoQuitDockAppsStrings {
    let listTitle: String
    let caption: String
    let addButton: String
    let removeButton: String
    let emptyNote: String
}

extension FeatureStrings {
    static func autoQuitDockApps(_ language: AppLanguage) -> AutoQuitDockAppsStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension AutoQuitDockAppsStrings {
    static let enUS = AutoQuitDockAppsStrings(
        listTitle: "Menu bar apps to quit",
        caption: "Menu bar apps stay open by default. Apps you select here can quit after their last window closes while they are in the Dock. Exceptions still keep them open.",
        addButton: "Add an app…",
        removeButton: "Remove",
        emptyNote: "No menu bar apps available to add."
    )

}
