// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchEditorStrings {
    let layout: String
    let content: String
    let activity: String
    let behavior: String
    let layoutHint: String
    let addButton: String
    let editButton: String
    let removeButton: String
    let buttonName: String
    let position: String
    let bottom: String
    let sectionActions: String
    let quickActions: String
    let findAction: String
    let reorderHint: String
    let opening: String
    let clickOpen: String
    let hoverPreview: String
    let hoverExpand: String
    let hiddenUntilHover: String
    let hiddenShowsActivity: String
    let hiddenShowsActivityHint: String
    let resting: String
    let destinations: String
    let separate: String
    let feedback: String
    let privacy: String
    let reopening: String
    let lastPage: String
    let openActivity: String
    let openActivityHint: String
    let activationTime: String
    let activationTimeHint: String
    let activationTimeFormat: String
    let closeTime: String
    let closeTimeHint: String
    let enableFeatureFormat: String
    let enableSettingFormat: String
    let showPageFormat: String
    let keyboardLightUnavailable: String
    let appPanelHint: String
    let hideMenuBarIcon: String
    let hideMenuBarIconHint: String
    let sections: String
    let sectionsHint: String
    let preview: String
    let hiddenInIsland: String
    let openFeatures: String
    let cameraPreview: String
    let noOptions: String
    let controlsSummary: String
    let mixerSummary: String
    let musicSummary: String
    let clipboardSummary: String
    let capturesSummary: String
    let filesSummary: String
    let systemSummary: String
    let toolsSummary: String
    let calendarSummary: String
    let notificationsSummary: String
    let timerSummary: String
    let cameraSummary: String
    let downloadsSummary: String
    let scratchpadSummary: String
    let agentsSummary: String
    let watchSummary: String

    func enableFeature(_ title: String) -> String { String(format: enableFeatureFormat, title) }
    func enableSetting(_ title: String) -> String { String(format: enableSettingFormat, title) }
    func showPage(_ title: String) -> String { String(format: showPageFormat, title) }

    func summary(_ module: NotchModule) -> String {
        switch module {
        case .controls: return controlsSummary
        case .mixer: return mixerSummary
        case .music: return musicSummary
        case .clipboard: return clipboardSummary
        case .captures: return capturesSummary
        case .files: return filesSummary
        case .system: return systemSummary
        case .tools: return toolsSummary
        case .calendar: return calendarSummary
        case .notifications: return notificationsSummary
        case .timer: return timerSummary
        case .camera: return cameraSummary
        case .downloads: return downloadsSummary
        case .scratchpad: return scratchpadSummary
        case .agents: return agentsSummary
        case .watch: return watchSummary
        }
    }
}

extension FeatureStrings {
    static func notchEditor(_ language: AppLanguage) -> NotchEditorStrings {
        switch language {
        case .enUS: return NotchEditorStrings(
            layout: "Layout",
            content: "Content",
            activity: "Activity",
            behavior: "Behavior",
            layoutHint: "Click + to add a button. Drag buttons around the island. Click a button to edit it.",
            addButton: "Add button",
            editButton: "Edit button",
            removeButton: "Remove button",
            buttonName: "Name",
            position: "Position",
            bottom: "Bottom",
            sectionActions: "Open a section",
            quickActions: "Quick actions",
            findAction: "Find an action",
            reorderHint: "Drag to reorder. Click the checkmark to show or hide.",
            opening: "Opening",
            clickOpen: "Click to open",
            hoverPreview: "Preview on hover",
            hoverExpand: "Expand on hover",
            hiddenUntilHover: "Hidden until hover",
            hiddenShowsActivity: "Show activity and indicators",
            hiddenShowsActivityHint: "Comes into view while an activity runs or an indicator shows, then hides again.",
            resting: "At rest",
            destinations: "Where things open",
            separate: "Separate window",
            feedback: "Indicators",
            privacy: "Privacy",
            reopening: "When reopening",
            lastPage: "Last page",
            openActivity: "Open the visible activity",
            openActivityHint: "When the closed island shows music, a timer or another activity, it opens on that page instead.",
            activationTime: "Activation time",
            activationTimeHint: "Keep the pointer over the island for this long to open it.",
            activationTimeFormat: "%.2f s",
            closeTime: "Closing time",
            closeTimeHint: "Wait this long after the pointer leaves the island before closing it.",
            enableFeatureFormat: "Enable “%@” in Features.",
            enableSettingFormat: "Enable “%@” in its settings.",
            showPageFormat: "Show “%@” on the Content tab.",
            keyboardLightUnavailable: "Keyboard backlight control is unavailable on this Mac.",
            appPanelHint: "Choose where clicking the EVERYTHING menu bar icon opens the app panel, on any display.",
            hideMenuBarIcon: "Hide the menu bar icon",
            hideMenuBarIconHint: "Settings and the app panel open from Dynamic Island. The icon returns when the island is off or hidden in full screen, or when an update is ready or the microphone is muted.",
            sections: "Sections",
            sectionsHint: "Drag to reorder. Uncheck a section to hide it from the island.",
            preview: "Preview",
            hiddenInIsland: "Hidden from the island",
            openFeatures: "Open Features",
            cameraPreview: "The camera turns on only in the island.",
            noOptions: "This section has no options.",
            controlsSummary: "Playback, volume, brightness and your keybinds.",
            mixerSummary: "The volume of each app, and where sound plays.",
            musicSummary: "The song playing now, with its controls.",
            clipboardSummary: "What you copied recently, ready to paste again.",
            capturesSummary: "Your latest screenshots and recordings.",
            filesSummary: "A shelf for the files you drop on the island.",
            systemSummary: "CPU, memory, disk, network and battery at a glance.",
            toolsSummary: "Tools and utilities, one click away.",
            calendarSummary: "Today’s events and the month ahead.",
            notificationsSummary: "Your Mac’s notifications, kept in the island.",
            timerSummary: "Timer, Pomodoro and stopwatch.",
            cameraSummary: "A mirror to check yourself before a call.",
            downloadsSummary: "Downloads in progress and just finished.",
            scratchpadSummary: "Quick notes that save by themselves.",
            agentsSummary: "Claude Code, Codex, OpenCode and GitHub Copilot usage, limits and costs.",
            watchSummary: "Any part of a window, read live, with an alert when it changes."
        )
        }
    }
}
