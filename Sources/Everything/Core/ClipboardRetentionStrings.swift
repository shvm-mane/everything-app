// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ClipboardRetentionStrings {
    let title: String
    let forever: String
    let oneDay: String
    let daysFormat: String
    let caption: String

    func label(days: Int) -> String {
        switch days {
        case 0: return forever
        case 1: return oneDay
        default: return String(format: daysFormat, days)
        }
    }
}

extension FeatureStrings {
    static func clipboardRetention(_ language: AppLanguage) -> ClipboardRetentionStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension ClipboardRetentionStrings {
    static let enUS = ClipboardRetentionStrings(
        title: "Keep items for",
        forever: "Forever",
        oneDay: "1 day",
        daysFormat: "%d days",
        caption: "Older items are removed even below the limit. Pinned items are always kept."
    )

}
