// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum SessionActivitySupport {
    static func isOnConsole(_ session: [String: Any]?) -> Bool {
        guard let value = session?[kCGSessionOnConsoleKey as String] else { return true }
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return true
    }

    static func tapShouldRun(featureWanted: Bool,
                             accessibilityGranted: Bool,
                             sessionIsActive: Bool) -> Bool {
        featureWanted && accessibilityGranted && sessionIsActive
    }

    enum DisabledTapRecovery: Equatable {
        case rearm
        case tearDown
        case leaveStopped
    }

    static func disabledTapRecovery(tapHeld: Bool, tapShouldRun: Bool) -> DisabledTapRecovery {
        guard tapHeld else { return .leaveStopped }
        return tapShouldRun ? .rearm : .tearDown
    }
}
