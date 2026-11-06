// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MiddleClickClickAction: Equatable {
    case transform
    case passThrough
    case swallow
}

enum MiddleClickSupport {
    static let fingerFreshness: TimeInterval = 0.25

    static let minimumSettle: TimeInterval = 0.04

    static let repeatGuard: TimeInterval = 0.30

    static func actionForClick(fingerCount: Int,
                               frameAge: TimeInterval,
                               settledFor: TimeInterval,
                               sinceLastTransformEnd: TimeInterval?,
                               systemDragGestureEnabled: Bool) -> MiddleClickClickAction {
        let pressFingers = systemDragGestureEnabled ? 4 : 3
        guard fingerCount == pressFingers, frameAge >= 0, frameAge <= fingerFreshness else {
            return .passThrough
        }
        if let sinceLastTransformEnd, sinceLastTransformEnd >= 0,
           sinceLastTransformEnd < repeatGuard {
            return .swallow
        }
        guard settledFor >= minimumSettle else { return .passThrough }
        return .transform
    }

    // MARK: - Tap to middle click (issue #161, opt-in)

    static let tapMaxDuration: TimeInterval = 0.35

    static let tapMovementLimit: Float = 0.03

    static let tapSpreadChangeLimit: Float = 0.04

    static let tapKeyboardIdle: TimeInterval = 0.5

    static func tapShouldFire(duration: TimeInterval,
                              maxMovement: Float,
                              maxSpreadChange: Float,
                              exceededFingerCount: Bool,
                              buttonPressedDuring: Bool,
                              positionUnavailable: Bool,
                              systemDragGestureEnabled: Bool,
                              tapFingers: Int,
                              secondsSinceLastKeyDown: TimeInterval = .infinity) -> Bool {
        guard (3...5).contains(tapFingers) else { return false }
        guard !exceededFingerCount, !buttonPressedDuring, !positionUnavailable else { return false }
        guard secondsSinceLastKeyDown >= tapKeyboardIdle else { return false }
        guard duration > 0, duration <= tapMaxDuration * (tapFingers == 5 ? 1.3 : 1) else { return false }
        let slack: Float = tapFingers == 5 ? 1.5 : 1
        guard maxMovement <= tapMovementLimit * slack else { return false }
        guard maxSpreadChange <= tapSpreadChangeLimit * slack else { return false }
        if tapFingers == 3, systemDragGestureEnabled { return false }
        return true
    }

    static func radialMenuTapFingers(radialMenuWantsTap: Bool, middleClickTapFingers: Int) -> Int {
        radialMenuWantsTap && middleClickTapFingers != 5 ? 5 : 0
    }
}
