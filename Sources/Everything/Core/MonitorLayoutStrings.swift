// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MonitorLayoutFeatureStrings {
    let shared: String
    let networkSpeedUnit: String
}

extension FeatureStrings {
    static func monitorLayout(_ language: AppLanguage) -> MonitorLayoutFeatureStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension MonitorLayoutFeatureStrings {
    static let enUS = MonitorLayoutFeatureStrings(
        shared: "Readings and alerts",
        networkSpeedUnit: "Network speed unit"
    )

}
