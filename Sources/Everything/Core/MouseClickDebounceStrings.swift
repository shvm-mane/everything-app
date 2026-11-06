// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MouseClickDebounceStrings {
    let title: String
    let caption: String
    let moreOptions: String
    let windowLabel: String
    let windowCaption: String
}

extension FeatureStrings {
    static func mouseClickDebounce(_ language: AppLanguage) -> MouseClickDebounceStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension MouseClickDebounceStrings {
    static let enUS = MouseClickDebounceStrings(
        title: "Extra click filter",
        caption: "Ignores rapid extra clicks from worn mouse buttons without slowing normal clicks.",
        moreOptions: "More options",
        windowLabel: "Filter window",
        windowCaption: "A repeated click inside this interval is treated as an accidental duplicate."
    )

}
