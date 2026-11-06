// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct QuitProtectionStrings {
    let name: String
    let description: String
    let intro: String
    let enabled: String
    let enabledCaption: String
    let mode: String
    let hold: String
    let doublePress: String
    let extraModifier: String
    let holdDuration: String
    let doublePressInterval: String
    let modifier: String
    let appScope: String
    let allApps: String
    let selectedOnly: String
    let allExceptSelected: String
    let exceptions: String
    let noExceptions: String
    let addApp: String
    let feedback: String
    let accessibilityCaption: String
    let holdQuitHUDFormat: String
    let holdCloseHUDFormat: String
    let doubleQuitHUDFormat: String
    let doubleCloseHUDFormat: String
    let extraQuitHUDFormat: String
    let extraCloseHUDFormat: String
    let cancelHint: String
    let releaseHint: String
    let shiftKey: String
    let optionKey: String
    let controlKey: String

    func holdHUDFormat(for shortcut: QuitProtectionShortcut) -> String {
        shortcut == .quit ? holdQuitHUDFormat : holdCloseHUDFormat
    }

    func doubleHUDFormat(for shortcut: QuitProtectionShortcut) -> String {
        shortcut == .quit ? doubleQuitHUDFormat : doubleCloseHUDFormat
    }

    func extraHUDFormat(for shortcut: QuitProtectionShortcut) -> String {
        shortcut == .quit ? extraQuitHUDFormat : extraCloseHUDFormat
    }

    static func make(_ language: AppLanguage) -> QuitProtectionStrings {
        FeatureStrings.quitProtection(language)
    }
}

extension FeatureStrings {
    static func quitProtection(_ language: AppLanguage) -> QuitProtectionStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension QuitProtectionStrings {
    static let enUS = QuitProtectionStrings(
        name: "Quit & close protection",
        description: "Protects ⌘Q and ⌘W from accidental presses",
        intro: "Configure each keybind independently. The original action passes only after the selected confirmation.",
        enabled: "Protect this keybind",
        enabledCaption: "Other Command keybinds continue to work normally.",
        mode: "Confirmation mode",
        hold: "Hold to confirm",
        doublePress: "Double press",
        extraModifier: "Require extra modifier",
        holdDuration: "Hold duration",
        doublePressInterval: "Double press interval",
        modifier: "Extra modifier",
        appScope: "Applications",
        allApps: "All applications",
        selectedOnly: "Selected applications only",
        allExceptSelected: "All except selected applications",
        exceptions: "Selected applications",
        noExceptions: "No applications selected",
        addApp: "Add application…",
        feedback: "Show visual feedback",
        accessibilityCaption: "Protection uses Accessibility to observe only ⌘Q and ⌘W globally.",
        holdQuitHUDFormat: "Hold %@ to quit",
        holdCloseHUDFormat: "Hold %@ to close",
        doubleQuitHUDFormat: "Press %@ again to quit",
        doubleCloseHUDFormat: "Press %@ again to close",
        extraQuitHUDFormat: "Use %@ to quit",
        extraCloseHUDFormat: "Use %@ to close",
        cancelHint: "Esc cancels",
        releaseHint: "Release to confirm",
        shiftKey: "Shift",
        optionKey: "Option",
        controlKey: "Control"
    )

}
