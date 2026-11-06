// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct SettingsPageStrings {
    let energyDescription: String
    let monitorDescription: String
    let mouseDescription: String
    let switcherDescription: String
    let dockTitle: String
    let dockDescription: String
    let switcherLayoutWindows: String
    let switcherLayoutWindowsCaption: String
    let switcherLayoutIcons: String
    let switcherLayoutSimple: String
}

extension FeatureStrings {
    static func settingsPages(_ language: AppLanguage) -> SettingsPageStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension SettingsPageStrings {

    static let enUS = SettingsPageStrings(
        energyDescription: "Keep the Mac awake, control your displays and save battery.",
        monitorDescription: "What the menu bar and the panel show about your Mac, and when to warn you.",
        mouseDescription: "Give the wheel, the side buttons and the trackpad new jobs.",
        switcherDescription: "Switch between apps and windows your way.",
        dockTitle: "Dock",
        dockDescription: "See an app’s windows from its Dock icon, and choose what a click on it does.",
        switcherLayoutWindows: "Window previews",
        switcherLayoutWindowsCaption: "One preview per window, minimized ones included.",
        switcherLayoutIcons: "Large icons",
        switcherLayoutSimple: "Simple list"
    )

}
