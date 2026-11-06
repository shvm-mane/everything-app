// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct WindowLayoutIgnoredAppsStrings {
    let sectionTitle: String
    let listTitle: String
    let addButton: String
    let removeButton: String
    let caption: String
}

extension FeatureStrings {
    static func windowLayoutIgnoredApps(_ language: AppLanguage) -> WindowLayoutIgnoredAppsStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension WindowLayoutIgnoredAppsStrings {
    static let enUS = WindowLayoutIgnoredAppsStrings(sectionTitle: "Ignore apps", listTitle: "Pause in these apps", addButton: "Add an app…", removeButton: "Remove", caption: "Window Layout does not use mouse or keyboard input while one of these apps is focused.")
}
