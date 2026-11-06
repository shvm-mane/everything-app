// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation

enum WindowServerWindowHitTest {
    static func candidate(at point: CGPoint,
                          pidIsEligible: (pid_t) -> Bool = { _ in true }) -> WindowServerWindowCandidate? {
        WindowServerSupport.windowCandidate(in: WindowServerSupport.onScreenWindowInfo(),
                                            at: point,
                                            ownProcessID: getpid(),
                                            pidIsEligible: pidIsEligible)
    }
}

enum WindowServerTrafficLightHitTest {
    static func candidate(at point: CGPoint,
                          button: TrafficLightButton,
                          pidIsEligible: (pid_t) -> Bool = { _ in true }) -> TrafficLightCandidate? {
        WindowServerSupport.trafficLightCandidate(in: WindowServerSupport.onScreenWindowInfo(),
                                                  at: point,
                                                  button: button,
                                                  ownProcessID: getpid(),
                                                  pidIsEligible: pidIsEligible)
    }
}
