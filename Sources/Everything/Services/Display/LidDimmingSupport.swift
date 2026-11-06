// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LidDimmingSupport {
    enum Action: Equatable {
        case dim(save: Double)
        case restore(Double)
        case none
    }

    static func lidClosed(currentBrightness: Double?) -> Action {
        guard let currentBrightness, currentBrightness > 0 else { return .none }
        return .dim(save: currentBrightness)
    }

    static func restoring(saved: Double?) -> Action {
        guard let saved else { return .none }
        return .restore(saved)
    }
}
