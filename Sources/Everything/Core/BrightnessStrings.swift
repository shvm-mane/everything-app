// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct BrightnessFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    let externalCaption: String
    let noDisplays: String
    let displayOff: String
    let turnOffDisplay: String
    let turnOnDisplay: String
    let lastDisplayCaption: String
    let switchUnavailable: String
    let switchFailed: String
    let openLidToEnable: String
    let keysToggle: String
    let keysCaption: String
    let keyStep: String
    let keyStepCaption: String
    let keyStepStandard: String
    let keyStepHalf: String
    let keyStepQuarter: String
    let osdToggle: String
    let osdCaption: String
    let displayBrightnessShortcuts: String
    let displayBrightnessShortcutCaption: String
    let displayBrightnessDecrease: String
    let displayBrightnessIncrease: String
    let keyboardLight: String
    let keyboardLightCaption: String
    let keyboardBrightnessShortcuts: String
    let keyboardBrightnessDecrease: String
    let keyboardBrightnessIncrease: String
    let softwareDimming: String
    let extendedDimming: String
    let islandPromptTitle: String
    let islandPromptMessage: String
    let islandPromptKeepOff: String
}

extension FeatureStrings {
    static func brightness(_ language: AppLanguage) -> BrightnessFeatureStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension BrightnessFeatureStrings {
    static let enUS = BrightnessFeatureStrings(
        pageTitle: "Displays",
        hubDescription: "Brightness and power controls for every display",
        enable: "Control displays",
        enableCaption: "Brightness and on or off controls for the built-in and external displays, here and in the menu bar panel.",
        externalCaption: "External displays are adjusted through the same protocol as their own buttons. When the connection cannot carry it, as with HDMI adapters, the slider dims the picture instead, so brightness control works either way.",
        noDisplays: "No display found.",
        displayOff: "Off",
        turnOffDisplay: "Turn off display",
        turnOnDisplay: "Turn on display",
        lastDisplayCaption: "At least one display must stay on.",
        switchUnavailable: "Display switching is unavailable on this Mac.",
        switchFailed: "Could not change this display.",
        openLidToEnable: "Open the lid to turn on the built-in display.",
        keysToggle: "Brightness keys follow the pointer",
        keysCaption: "The keyboard brightness keys change the display under the pointer.",
        keyStep: "Brightness key steps",
        keyStepCaption: "Smaller steps for each press of the brightness keys and display brightness keybinds.",
        keyStepStandard: "Standard",
        keyStepHalf: "Half steps",
        keyStepQuarter: "Quarter steps",
        osdToggle: "Show brightness when adjusting",
        osdCaption: "Shows the brightness percentage when you use the brightness keys or sliders.",
        displayBrightnessShortcuts: "Use display brightness keybinds",
        displayBrightnessShortcutCaption: "Keybinds adjust the primary display, or the display under the pointer when pointer following is on.",
        displayBrightnessDecrease: "Decrease display brightness",
        displayBrightnessIncrease: "Increase display brightness",
        keyboardLight: "Keyboard light",
        keyboardLightCaption: "Turns the keyboard backlight on or off.",
        keyboardBrightnessShortcuts: "Use keyboard brightness keybinds",
        keyboardBrightnessDecrease: "Decrease keyboard brightness",
        keyboardBrightnessIncrease: "Increase keyboard brightness",
        softwareDimming: "Dim the picture",
        extendedDimming: "Extra dimming",
        islandPromptTitle: "Show brightness in the Dynamic Island?",
        islandPromptMessage: "The Dynamic Island shows brightness changes only while “Control displays” is on in Displays settings.",
        islandPromptKeepOff: "Keep Off"
    )

}
