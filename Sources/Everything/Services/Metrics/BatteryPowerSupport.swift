// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BatteryPowerSupport {
    enum State: Equatable {
        case charging
        case externalPower
        case onBattery
        case unavailable
    }

    static func state(isCharging: Bool, externalConnected: Bool, hasBattery: Bool) -> State {
        if isCharging { return .charging }
        if externalConnected { return .externalPower }
        return hasBattery ? .onBattery : .unavailable
    }

    static func menuBarSymbol(percent: Int, isCharging: Bool, externalConnected: Bool) -> String {
        if isCharging || externalConnected { return "battery.100.bolt" }
        switch percent {
        case 85...: return "battery.100"
        case 60..<85: return "battery.75"
        case 35..<60: return "battery.50"
        case 10..<35: return "battery.25"
        default: return "battery.0"
        }
    }
}
