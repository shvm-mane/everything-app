// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct SwitcherShortcutStrings {
    let allWindows: String
    let allWindowsCaption: String
}

extension FeatureStrings {
    static func switcherShortcuts(_ language: AppLanguage) -> SwitcherShortcutStrings {
        switch language {
        case .enUS:
            return .init(allWindows: "All windows",
                         allWindowsCaption: "Use a separate keybind to cycle through windows from all apps in any layout. Your window filters still apply.")
        }
    }
}
