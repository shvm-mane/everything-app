// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct KeepAwakeAutomationStrings {
    let automationSection: String
    let automationCaption: String
    let automationOff: String
    let externalDisplayToggle: String
    let externalDisplayActive: String
    let powerToggle: String
    let powerActive: String
    let runningAppsToggle: String
    let runningAppsActive: String
    let runningAppsListTitle: String
    let runningAppsAddButton: String
    let runningAppsRemoveButton: String
    let runningAppsListCaption: String
    let automationActive: String
    let pauseWhenLockedToggle: String
    let pauseWhenLockedCaption: String
    let matchAny: String
    let matchAll: String
    let automationCaptionAll: String

    func caption(requireAll: Bool) -> String {
        requireAll ? automationCaptionAll : automationCaption
    }

    func activeStatus(for conditions: Set<KeepAwakeAutomationCondition>) -> String {
        if conditions == [.externalDisplay] { return externalDisplayActive }
        if conditions == [.power] { return powerActive }
        if conditions == [.runningApps] { return runningAppsActive }
        return automationActive
    }
}

struct KeepAwakeDisplaySleepStrings {
    let allowDisplaySleep: String
    let allowDisplaySleepCaption: String
}

extension FeatureStrings {
    static func keepAwakeAutomation(_ language: AppLanguage) -> KeepAwakeAutomationStrings {
        switch language {
        case .enUS: return .enUS
        }
    }

    static func keepAwakeDisplaySleep(_ language: AppLanguage) -> KeepAwakeDisplaySleepStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension KeepAwakeDisplaySleepStrings {
    static let enUS = KeepAwakeDisplaySleepStrings(
        allowDisplaySleep: "Allow the display to sleep",
        allowDisplaySleepCaption: "Keeps the Mac awake while the display follows its normal sleep timer."
    )

}

extension KeepAwakeAutomationStrings {
    static let enUS = KeepAwakeAutomationStrings(
        automationSection: "Automation",
        automationCaption: "Starts when any selected condition is active.",
        automationOff: "Off",
        externalDisplayToggle: "External display",
        externalDisplayActive: "Active while an external display is connected",
        powerToggle: "Power",
        powerActive: "Active while connected to power",
        runningAppsToggle: "Applications",
        runningAppsActive: "Active while a selected app is running",
        runningAppsListTitle: "Selected apps",
        runningAppsAddButton: "Add an app…",
        runningAppsRemoveButton: "Remove",
        runningAppsListCaption: "Keep Awake starts while any of these apps is open, even in the background.",
        automationActive: "Active because an automatic condition is met",
        pauseWhenLockedToggle: "Pause while the Mac is locked",
        pauseWhenLockedCaption: "Follows normal sleep rules while locked and resumes the remaining session after you unlock.",
        matchAny: "Any",
        matchAll: "All",
        automationCaptionAll: "Starts only when every selected condition is active."
    )

}
