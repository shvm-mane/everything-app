// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

enum SmoothScrollSupport {
    struct Axes: Equatable {
        let vertical: Double
        let horizontal: Double
    }

    struct Target: Equatable {
        let point: CGPoint
        let processID: Int32
        let windowNumber: Int
    }

    struct TargetLatch {
        static let driftTolerance: CGFloat = 24

        private(set) var target: Target?

        mutating func update(_ input: Target) -> Bool {
            defer { target = input }
            guard let target else { return true }
            return target.processID != input.processID
                || target.windowNumber != input.windowNumber
                || hypot(input.point.x - target.point.x, input.point.y - target.point.y) > Self.driftTolerance
        }

        mutating func reset() {
            target = nil
        }
    }

    struct Frame {
        let vertical: Double
        let horizontal: Double
        let finished: Bool
    }

    struct Engine {
        private(set) var remainingVertical: Double = 0
        private(set) var remainingHorizontal: Double = 0
        private(set) var glideVertical: Double = 0
        private(set) var glideHorizontal: Double = 0

        var isActive: Bool {
            remainingVertical != 0 || remainingHorizontal != 0
        }

        mutating func add(vertical: Double, horizontal: Double) {
            Self.add(vertical, to: &remainingVertical, glide: &glideVertical)
            Self.add(horizontal, to: &remainingHorizontal, glide: &glideHorizontal)
        }

        mutating func advance(elapsed: TimeInterval, response: Int, coast: Int = 0) -> Frame {
            let vertical = SmoothScrollSupport.frameDelta(
                remaining: remainingVertical,
                elapsed: elapsed,
                response: response,
                coast: coast,
                glide: glideVertical
            )
            let horizontal = SmoothScrollSupport.frameDelta(
                remaining: remainingHorizontal,
                elapsed: elapsed,
                response: response,
                coast: coast,
                glide: glideHorizontal
            )
            remainingVertical -= vertical
            remainingHorizontal -= horizontal
            return Frame(vertical: vertical, horizontal: horizontal, finished: !isActive)
        }

        mutating func reset() {
            remainingVertical = 0
            remainingHorizontal = 0
            glideVertical = 0
            glideHorizontal = 0
        }

        private static func add(_ distance: Double, to remaining: inout Double, glide: inout Double) {
            guard distance.isFinite, distance != 0 else { return }
            remaining = SmoothScrollSupport.directionsOppose(distance, remaining)
                ? distance : remaining + distance
            glide = abs(remaining)
        }
    }

    static let frameInterval: TimeInterval = 1.0 / 60.0

    static let maximumFrameInterval: TimeInterval = 1.0 / 20.0

    static let finishThreshold: Double = 1.0

    static let stepRange = 20...100
    static let defaultStep = 40

    static let responseRange = 0...100
    static let defaultResponse = 65
    static let coastRange = 0...100
    static let defaultCoast = 0
    private static let slowResponseTime: TimeInterval = 0.16
    private static let fastResponseTime: TimeInterval = 0.04
    private static let fullCoastStretch = 3.0
    private static let minimumGlideSpeed = 60.0

    static func ticks(line: Double, fixedPoint: Double) -> Double {
        fixedPoint != 0 ? fixedPoint : line
    }

    static func continuousDistance(fixedPointDelta: Double,
                                   pointDelta: Double,
                                   step: Double) -> Double {
        guard fixedPointDelta.isFinite, pointDelta.isFinite, step.isFinite else { return 0 }
        let pixels = pointDelta != 0
            ? pointDelta
            : fixedPointDelta * ScrollWheelSupport.pointsPerLine
        return pixels * (step / Double(defaultStep))
    }

    static func linearContinuousDistance(fixedPointDelta: Double,
                                         pointDelta: Double,
                                         step: Double,
                                         linesPerNotch: Int) -> Double {
        let lines = ScrollWheelSupport.linearLines(
            ticks: ScrollWheelSupport.continuousTicks(fixedPointDelta: fixedPointDelta,
                                                      pointDelta: pointDelta),
            linesPerNotch: linesPerNotch)
        return continuousDistance(fixedPointDelta: lines, pointDelta: 0, step: step)
    }

    static func wholePixels(_ distance: Double, carry: Double) -> (pixels: Double, carry: Double) {
        let total = distance + carry
        guard total.isFinite else { return (0, 0) }
        let whole = total.rounded(.towardZero)
        return (whole, total - whole)
    }

    static func finalPixels(_ distance: Double, carry: Double) -> Double {
        let total = distance + carry
        guard total.isFinite else { return 0 }
        return total.rounded(.toNearestOrAwayFromZero)
    }

    static func carry(_ current: Double, continuing distance: Double) -> Double {
        directionsOppose(current, distance) ? 0 : current
    }

    private static func directionsOppose(_ lhs: Double, _ rhs: Double) -> Bool {
        lhs != 0 && rhs != 0 && (lhs < 0) != (rhs < 0)
    }

    static func axes(vertical: Double, horizontal: Double, shiftPressed: Bool) -> Axes {
        guard shiftPressed, vertical != 0, horizontal == 0 else {
            return Axes(vertical: vertical, horizontal: horizontal)
        }
        return Axes(vertical: 0, horizontal: vertical)
    }

    static func frameDelta(remaining: Double,
                           elapsed: TimeInterval,
                           response: Int,
                           coast: Int = 0,
                           glide: Double = 0) -> Double {
        guard remaining.isFinite, remaining != 0,
              elapsed.isFinite, elapsed > 0 else { return 0 }
        let magnitude = abs(remaining)
        let stretch = coastStretch(coast: coast, remaining: magnitude, glide: glide)
        if magnitude <= finishThreshold / stretch { return remaining }
        let clampedElapsed = min(elapsed, maximumFrameInterval)
        let normalizedResponse = Double(sanitizedResponse(response) - responseRange.lowerBound)
            / Double(responseRange.upperBound - responseRange.lowerBound)
        let responseTime = (slowResponseTime
            - normalizedResponse * (slowResponseTime - fastResponseTime)) * stretch
        let eased = magnitude * (1 - exp(-clampedElapsed / responseTime))
        let emitted = min(magnitude, max(eased, minimumGlideSpeed / stretch * clampedElapsed))
        return remaining < 0 ? -emitted : emitted
    }

    static func sanitizedStep(_ value: Int) -> Int {
        guard value != 0 else { return defaultStep }
        return min(max(value, stepRange.lowerBound), stepRange.upperBound)
    }

    static func sanitizedResponse(_ value: Int) -> Int {
        min(max(value, responseRange.lowerBound), responseRange.upperBound)
    }

    static func coastStretch(coast: Int, remaining: Double, glide: Double) -> Double {
        guard glide.isFinite, glide > remaining, remaining >= 0 else { return 1 }
        let normalizedCoast = Double(sanitizedCoast(coast) - coastRange.lowerBound)
            / Double(coastRange.upperBound - coastRange.lowerBound)
        let travelled = 1 - remaining / glide
        return 1 + normalizedCoast * (fullCoastStretch - 1) * travelled * travelled
    }

    static func sanitizedCoast(_ value: Int) -> Int {
        min(max(value, coastRange.lowerBound), coastRange.upperBound)
    }
}
