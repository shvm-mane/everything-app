// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct SwitcherAppRulesStrings {
    let listTitle: String
    let addButton: String
    let removeButton: String
    let behaviorLabel: String
    let showWithoutWindows: String
    let windowsOnly: String
    let hidden: String
    let caption: String
}

extension FeatureStrings {
    static func switcherAppRules(_ language: AppLanguage) -> SwitcherAppRulesStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension SwitcherAppRulesStrings {
    static let enUS = SwitcherAppRulesStrings(
        listTitle: "Rules by app",
        addButton: "Add an app…",
        removeButton: "Remove",
        behaviorLabel: "Switcher behavior",
        showWithoutWindows: "Show without windows",
        windowsOnly: "Windows only",
        hidden: "Never show",
        caption: "Choose how each app appears. Apps without a rule use the choice above."
    )

}
