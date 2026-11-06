// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchTourStrings {
    let preview: String
    let caption: String
}

extension FeatureStrings {
    static func notchTour(_ language: AppLanguage) -> NotchTourStrings {
        switch language {
        case .enUS: return NotchTourStrings(preview: "Preview for 3.4",
            caption: "Control music, timers, volume and brightness. Choose the floating keybinds you use most.")
        }
    }
}
