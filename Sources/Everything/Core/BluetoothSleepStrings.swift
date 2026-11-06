// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct BluetoothSleepStrings {
    let pageTitle: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    let restoreToggle: String
    let restoreCaption: String
    let unsupported: String
}

extension FeatureStrings {
    static func bluetoothSleep(_ language: AppLanguage) -> BluetoothSleepStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension BluetoothSleepStrings {
    static let enUS = BluetoothSleepStrings(
        pageTitle: "Bluetooth on sleep",
        hubDescription: "Switches Bluetooth off while the Mac sleeps, so headphones in a bag stop connecting to it.",
        enable: "Turn Bluetooth off when the Mac sleeps",
        enableCaption: "Bluetooth already off before sleep is left alone and stays off on wake.",
        restoreToggle: "Turn Bluetooth back on when the Mac wakes",
        restoreCaption: "Only when EVERYTHING was the one that switched it off.",
        unsupported: "This Mac has no Bluetooth controller."
    )

}
