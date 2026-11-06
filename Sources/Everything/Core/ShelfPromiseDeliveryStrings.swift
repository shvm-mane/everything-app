// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct ShelfPromiseDeliveryStrings {
    let failedTitle: String
    let failedBody: String
    let fullTitle: String
    let fullBody: String
    let okButton: String

    static func localized(_ language: AppLanguage) -> ShelfPromiseDeliveryStrings {
        switch language {
        case .enUS:
            return .init(
                failedTitle: "Couldn’t add attachment",
                failedBody: "The file never finished saving to the shelf.",
                fullTitle: "Shelf is full",
                fullBody: "The attachment finished saving but there is no room left on the shelf.",
                okButton: "OK")
        }
    }
}
