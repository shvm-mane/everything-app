// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum MouseSpacesGestureSupport {
    // MARK: - Calibration

    static let spaceStep: CGFloat = 220

    static let overviewStep: CGFloat = 150

    static let spaceRepeatCooldown: TimeInterval = 0.35

    static let bankedTravelLimit: CGFloat = spaceStep

    // MARK: - Decisions

    enum Action: Equatable {
        case spaceLeft
        case spaceRight
        case missionControl
        case appExpose
    }

    static func resolved(_ action: Action, followsDrag: Bool) -> Action {
        guard followsDrag else { return action }
        switch action {
        case .spaceLeft: return .spaceRight
        case .spaceRight: return .spaceLeft
        case .missionControl, .appExpose: return action
        }
    }

    enum Axis: Equatable {
        case horizontal
        case vertical
    }

    struct Tracker {
        private(set) var axis: Axis?
        private(set) var didFire = false

        private var lastPoint: CGPoint
        private var accumulatedX: CGFloat = 0
        private var accumulatedY: CGFloat = 0
        private var lastFiredAt: TimeInterval?

        init(origin: CGPoint) {
            lastPoint = origin
        }

        mutating func advance(to point: CGPoint, now: TimeInterval) -> Action? {
            guard point.x.isFinite, point.y.isFinite else { return nil }
            let deltaX = point.x - lastPoint.x
            let deltaY = point.y - lastPoint.y
            lastPoint = point
            accumulatedX += deltaX
            accumulatedY += deltaY

            guard let resolved = axis ?? committedAxis() else { return nil }
            switch resolved {
            case .vertical:
                axis = .vertical
                guard !didFire else { return nil }
                didFire = true
                return accumulatedY < 0 ? .missionControl : .appExpose
            case .horizontal:
                axis = .horizontal
                if let lastFiredAt, now - lastFiredAt < MouseSpacesGestureSupport.spaceRepeatCooldown {
                    accumulatedX = min(max(accumulatedX, -MouseSpacesGestureSupport.bankedTravelLimit),
                                       MouseSpacesGestureSupport.bankedTravelLimit)
                    return nil
                }
                guard abs(accumulatedX) >= MouseSpacesGestureSupport.spaceStep else { return nil }
                let goesLeft = accumulatedX < 0
                accumulatedX += goesLeft ? MouseSpacesGestureSupport.spaceStep
                                         : -MouseSpacesGestureSupport.spaceStep
                lastFiredAt = now
                didFire = true
                return goesLeft ? .spaceLeft : .spaceRight
            }
        }

        private func committedAxis() -> Axis? {
            let horizontal = abs(accumulatedX) / MouseSpacesGestureSupport.spaceStep
            let vertical = abs(accumulatedY) / MouseSpacesGestureSupport.overviewStep
            if horizontal >= 1, horizontal >= vertical { return .horizontal }
            if vertical >= 1 { return .vertical }
            return nil
        }
    }

    static func canBind(_ input: Int64) -> Bool {
        input == 2 || MouseButtonShortcutSupport.buttonRange.contains(input)
    }

    static func boundButton(isAvailable: Bool,
                            isEnabled: Bool,
                            button: Int64,
                            hasShortcut: (Int64) -> Bool,
                            claimedByWheel: (Int64) -> Bool) -> Int64? {
        guard isAvailable, isEnabled, canBind(button),
              !hasShortcut(button), !claimedByWheel(button) else { return nil }
        return button
    }
}
