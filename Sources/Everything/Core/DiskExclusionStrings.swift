// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct DiskExclusionStrings {
    let listTitle: String
    let addButton: String
    let otherDrive: String
    let removeButton: String
    let customPlaceholder: String
    let caption: String
}

extension FeatureStrings {
    static func diskExclusions(_ language: AppLanguage) -> DiskExclusionStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension DiskExclusionStrings {
    static let enUS = DiskExclusionStrings(
        listTitle: "Excluded drives",
        addButton: "Add drive…",
        otherDrive: "Other drive name…",
        removeButton: "Remove",
        customPlaceholder: "Drive or volume name",
        caption: "Drives in this list are never unmounted when using Eject all disks."
    )

}
