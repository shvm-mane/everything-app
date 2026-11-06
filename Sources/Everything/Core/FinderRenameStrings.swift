// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct FinderRenameFeatureStrings {
    let pageTitle: String
    let hubTitle: String
    let hubDescription: String
    let enableLabel: String
    let caption: String
    let shortcutLabel: String
}

extension FeatureStrings {
    static func finderRename(_ language: AppLanguage) -> FinderRenameFeatureStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension FinderRenameFeatureStrings {
    static let enUS = FinderRenameFeatureStrings(
        pageTitle: "Finder keybinds",
        hubTitle: "Rename keybind",
        hubDescription: "Rename the selected file or folder with a keybind you choose.",
        enableLabel: "Use a keybind to rename",
        caption: "The keybind only acts in Finder and leaves text fields alone. F2 works as a regular key; on keyboards where it controls brightness, use Fn-F2 or choose another keybind.",
        shortcutLabel: "Rename"
    )

}
