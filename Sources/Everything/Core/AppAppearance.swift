// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    static let fallback: AppAppearance = .system

    static func sanitized(_ raw: String?) -> AppAppearance {
        guard let raw, let value = AppAppearance(rawValue: raw) else { return fallback }
        return value
    }

    func title(_ strings: AppearanceStrings) -> String {
        switch self {
        case .system: return strings.system
        case .light: return strings.light
        case .dark: return strings.dark
        }
    }
}
