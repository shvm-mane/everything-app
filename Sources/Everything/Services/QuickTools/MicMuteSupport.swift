// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MicMuteSupport {
    static let ownDeviceNames: Set<String> = ["EVERYTHING Mixer", "EVERYTHING AirPlay", "EVERYTHING Island Levels",
                                              "EVERYTHING Recorder"]

    static let fallbackVolume: Float = 0.75

    static func isOwnDevice(name: String) -> Bool {
        ownDeviceNames.contains(name)
    }

    static func shouldSaveVolume(_ volume: Float?) -> Bool {
        guard let volume else { return false }
        return volume > 0.01
    }

    static func volumeToRestore(uid: String,
                                saved: [String: Double],
                                legacy: Double) -> Float {
        if let value = saved[uid], value > 0.01 { return Float(value) }
        if legacy > 0.01 { return Float(legacy) }
        return fallbackVolume
    }

    static func restoreTargets(recorded: [String]?, present: [String]) -> [String] {
        guard let recorded else { return present }
        let wanted = Set(recorded)
        return present.filter { wanted.contains($0) }
    }

    static func absentClaims(recorded: [String]?, present: [String]) -> [String] {
        let here = Set(present)
        return (recorded ?? []).filter { !here.contains($0) }
    }
}
