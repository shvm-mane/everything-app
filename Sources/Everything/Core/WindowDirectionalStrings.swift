// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct WindowDirectionalStrings {
    let title: String
    let caption: String

    static func localized(_ language: AppLanguage) -> WindowDirectionalStrings {
        switch language {
        case .enUS: return .init(title: "Keybind + pointer layout", caption: "Hold the keybind, move the pointer toward an edge or corner, then release to place the active window.")
        }
    }
}
