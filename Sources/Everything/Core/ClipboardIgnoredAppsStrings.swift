// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ClipboardIgnoredAppsStrings {
    let listTitle: String
    let addButton: String
    let removeButton: String
    let caption: String
}

extension FeatureStrings {
    static func clipboardIgnoredApps(_ language: AppLanguage) -> ClipboardIgnoredAppsStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension ClipboardIgnoredAppsStrings {
    static let enUS = ClipboardIgnoredAppsStrings(
        listTitle: "Apps to skip",
        addButton: "Add an app…",
        removeButton: "Remove",
        caption: "Nothing you copy in these apps is saved to the history."
    )

}
