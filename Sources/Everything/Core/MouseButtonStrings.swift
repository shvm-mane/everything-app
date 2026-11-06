// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MouseButtonFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let enableLabel: String
    let enableCaption: String
    let addButton: String
    let captureWaiting: String
    let captureCancel: String
    let captureBlind: String
    let captureUnsupported: String
    let captureWheel: String
    let captureExists: String
    let captureHint: String
    let middleButtonName: String
    let backButtonName: String
    let forwardButtonName: String
    let otherButtonFormat: String
    let setShortcutButton: String
    let removeButton: String
    let emptyCaption: String
    let rowWheelNote: String
    let manageButton: String
    let panelCaption: String
    let sideWheelLeftName: String
    let sideWheelRightName: String
    let spacesEnableLabel: String
    let spacesEnableCaption: String
    let spacesPickButton: String
    let spacesShortcutsOffNote: String
    let spacesCaptureWaiting: String
    let spacesCaptureUnsupported: String
    let spacesCaptureExists: String
    let spacesFollowsDragLabel: String
    let spacesFollowsDragCaption: String
}

extension FeatureStrings {
    static func mouseButtons(_ language: AppLanguage) -> MouseButtonFeatureStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension MouseButtonFeatureStrings {
    static let enUS = MouseButtonFeatureStrings(
        pageTitle: "Mouse button keybinds",
        hubDescription: "Extra buttons and side-wheel directions press a key combination you choose.",
        enableLabel: "Use extra buttons as keybinds",
        enableCaption: "Each extra button or side-wheel direction can press a key combination for you. While it has a keybind, it stops doing what it did before.",
        addButton: "Add a button or side wheel",
        captureWaiting: "Now press an extra button or move the side wheel.",
        captureCancel: "Cancel",
        captureBlind: "EVERYTHING cannot watch the mouse right now.",
        captureUnsupported: "That input cannot take a keybind. Use an extra button or a side-wheel direction.",
        captureWheel: "That button already opens the radial menu. Pick another one, or free it there first.",
        captureExists: "That button or direction is already on the list below.",
        captureHint: "If nothing happens, your mouse’s own software may already be using that control.",
        middleButtonName: "Middle button",
        backButtonName: "Back side button",
        forwardButtonName: "Forward side button",
        otherButtonFormat: "Button %d",
        setShortcutButton: "Set keybind",
        removeButton: "Remove",
        emptyCaption: "No keybinds yet. Add a button or side-wheel direction.",
        rowWheelNote: "This button opens the radial menu now, so the keybind waits.",
        manageButton: "Set up…",
        panelCaption: "Extra buttons and side-wheel directions press key combinations you choose.",
        sideWheelLeftName: "Side wheel left",
        sideWheelRightName: "Side wheel right",
        spacesEnableLabel: "Switch Spaces by dragging a button",
        spacesEnableCaption: "Hold the chosen button and drag: left or right moves one Space over, up opens Mission Control, down opens App Exposé. A short click still does what it always did.",
        spacesPickButton: "Choose a button",
        spacesShortcutsOffNote: "The Mission Control keyboard keybinds are switched off in System Settings, so this gesture has nothing to ask for.",
        spacesCaptureWaiting: "Now press the middle button or an extra button.",
        spacesCaptureUnsupported: "That input cannot be held for a drag. Use the middle button or an extra button.",
        spacesCaptureExists: "That button already has a keybind. Pick another one.",
        spacesFollowsDragLabel: "Spaces follow the drag",
        spacesFollowsDragCaption: "Dragging right brings the Space on the left, the way a trackpad swipe carries it along with your fingers."
    )

}
