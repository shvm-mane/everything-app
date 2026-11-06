// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

enum LidDisplayDimmer {
    static func builtInDisplayID() -> CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static func currentBrightness() -> Double? {
        guard let id = builtInDisplayID(), let getBrightness = BrightnessBridge.getBrightness else { return nil }
        var value: Float = 0
        guard getBrightness(id, &value) == 0 else { return nil }
        return Double(value)
    }

    @discardableResult
    static func setBrightness(_ value: Double) -> Bool {
        guard let id = builtInDisplayID(), let setBrightness = BrightnessBridge.setBrightness else { return false }
        return setBrightness(id, Float(value)) == 0
    }
}
