// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchLockScreenStrings {
    let title: String
    let show: String
    let showHint: String
    let sounds: String
    let soundsHint: String
    let working: String
}

extension FeatureStrings {
    static func notchLockScreen(_ language: AppLanguage) -> NotchLockScreenStrings {
        switch language {
        case .enUS: return NotchLockScreenStrings(
            title: "Lock Screen",
            show: "Show on the Lock Screen",
            showHint: "Music and the Dynamic Island’s activities, like a timer, AI agents, downloads and your next event, appear above the password field. Anyone who can see your screen can read them.",
            sounds: "Lock and unlock sounds",
            soundsHint: "Play the macOS padlock sound when your Mac locks and unlocks.",
            working: "Working")
        }
    }
}
