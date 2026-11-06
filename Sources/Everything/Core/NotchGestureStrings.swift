// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchGestureStrings {
    let title: String
    let description: String
    let hint: String
}

extension FeatureStrings {
    static func notchGestures(_ language: AppLanguage) -> NotchGestureStrings {
        switch language {
        case .enUS: return NotchGestureStrings(
            title: "Dynamic Island Gestures",
            description: "Open and close the Dynamic Island with scrolling, and swipe to change tracks.",
            hint: "Scroll down to open. Scroll up over the top row to close. Swipe left or right over the music to change tracks. Lists keep their own scrolling.")
        }
    }
}
