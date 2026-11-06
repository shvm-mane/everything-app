// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct WhatsNewStrings {
    let updatedFromFormat: String
    let newFeatures: String
    let yourFeatures: String
    let notInstalled: String
    let kindNew: String
    let kindChanged: String
    let kindFixed: String
    let updated: String
    let chooseFeatureHint: String
    let skipPreviewCheckbox: String
    let showPreviewToggle: String
    let showPreviewCaption: String
}

extension FeatureStrings {
    static func whatsNew(_ language: AppLanguage) -> WhatsNewStrings {
        switch language {
        case .enUS:
            return WhatsNewStrings(
                updatedFromFormat: "Updated from %@",
                newFeatures: "New features",
                yourFeatures: "Your features",
                notInstalled: "Not installed",
                kindNew: "New",
                kindChanged: "Changed",
                kindFixed: "Fixed",
                updated: "Updated",
                chooseFeatureHint: "Choose a feature to see what changed in it.",
                skipPreviewCheckbox: "Don’t show what’s new before updating",
                showPreviewToggle: "Show what’s new before updating",
                showPreviewCaption: "What changed in your features still appears after each update.")
        }
    }
}
