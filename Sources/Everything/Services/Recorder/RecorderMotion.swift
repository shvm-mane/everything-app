// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum RecorderMotion {
    // MARK: - Track

    struct Sample: Equatable {
        var time: Double
        var point: CGPoint
        var shapeIndex: Int
        var isPointerVisible: Bool

        init(time: Double,
             point: CGPoint,
             shapeIndex: Int = 0,
             isPointerVisible: Bool = true) {
            self.time = time
            self.point = point
            self.shapeIndex = shapeIndex
            self.isPointerVisible = isPointerVisible
        }
    }

    struct Click: Equatable {
        var time: Double
        var isDown: Bool
    }

    // MARK: - Uniform grid

    static func resampled(_ samples: [Sample], frameRate: Int, duration: Double) -> [CGPoint] {
        let count = max(1, Int((duration * Double(max(1, frameRate))).rounded()))
        guard let first = samples.first else {
            return Array(repeating: .zero, count: count)
        }
        guard samples.count > 1 else {
            return Array(repeating: first.point, count: count)
        }
        var result: [CGPoint] = []
        result.reserveCapacity(count)
        var cursor = 0
        let step = 1.0 / Double(max(1, frameRate))
        for index in 0..<count {
            let time = Double(index) * step
            while cursor + 1 < samples.count, samples[cursor + 1].time <= time {
                cursor += 1
            }
            if cursor + 1 >= samples.count {
                result.append(samples[samples.count - 1].point)
                continue
            }
            let a = samples[cursor]
            let b = samples[cursor + 1]
            let span = b.time - a.time
            let t = span > 0 ? min(1, max(0, (time - a.time) / span)) : 0
            result.append(CGPoint(x: a.point.x + (b.point.x - a.point.x) * t,
                                  y: a.point.y + (b.point.y - a.point.y) * t))
        }
        return result
    }

    static func resampledVisibility(_ samples: [Sample],
                                    frameRate: Int,
                                    duration: Double) -> [Bool] {
        let count = max(1, Int((duration * Double(max(1, frameRate))).rounded()))
        guard !samples.isEmpty else { return Array(repeating: true, count: count) }
        var result: [Bool] = []
        result.reserveCapacity(count)
        var cursor = 0
        let step = 1.0 / Double(max(1, frameRate))
        for index in 0..<count {
            let time = Double(index) * step
            while cursor + 1 < samples.count, samples[cursor + 1].time <= time {
                cursor += 1
            }
            result.append(samples[cursor].isPointerVisible)
        }
        return result
    }

    static func resampledShapes(_ samples: [Sample], frameRate: Int, duration: Double) -> [Int] {
        let count = max(1, Int((duration * Double(max(1, frameRate))).rounded()))
        guard !samples.isEmpty else { return Array(repeating: 0, count: count) }
        var result: [Int] = []
        result.reserveCapacity(count)
        var cursor = 0
        let step = 1.0 / Double(max(1, frameRate))
        for index in 0..<count {
            let time = Double(index) * step
            while cursor + 1 < samples.count, samples[cursor + 1].time <= time {
                cursor += 1
            }
            result.append(samples[cursor].shapeIndex)
        }
        return result
    }

    // MARK: - Zero-phase smoothing

    enum Smoothing: String, CaseIterable {
        case off, light, smooth, cinematic

        var cutoff: Double {
            switch self {
            case .off: return 0
            case .light: return 4.0
            case .smooth: return 2.0
            case .cinematic: return 1.2
            }
        }
    }

    static func sanitizedSmoothing(_ raw: String?) -> Smoothing {
        Smoothing(rawValue: raw ?? "") ?? .smooth
    }

    static let filtfiltWidening = 1.553773974

    static func onePoleAlpha(cutoff: Double, dt: Double) -> Double {
        guard cutoff > 0, dt > 0 else { return 1 }
        return 1 - exp(-2 * .pi * cutoff * dt)
    }

    static func filtfilt(_ values: [Double], alpha: Double) -> [Double] {
        guard values.count > 1, alpha > 0, alpha < 1 else { return values }
        let padding = min(values.count, max(1, Int((3 / alpha).rounded())))
        var padded = Array(repeating: values[0], count: padding)
            + values
            + Array(repeating: values[values.count - 1], count: padding)

        var carry = padded[0]
        for index in padded.indices {
            carry += alpha * (padded[index] - carry)
            padded[index] = carry
        }
        carry = padded[padded.count - 1]
        for index in padded.indices.reversed() {
            carry += alpha * (padded[index] - carry)
            padded[index] = carry
        }
        return Array(padded[padding..<(padding + values.count)])
    }

    static func smoothedPath(_ points: [CGPoint],
                             smoothing: Smoothing,
                             frameRate: Int) -> [CGPoint] {
        guard smoothing != .off, points.count > 1 else { return points }
        let dt = 1.0 / Double(max(1, frameRate))
        let alpha = onePoleAlpha(cutoff: smoothing.cutoff * filtfiltWidening, dt: dt)
        let xs = filtfilt(points.map { Double($0.x) }, alpha: alpha)
        let ys = filtfilt(points.map { Double($0.y) }, alpha: alpha)
        return zip(xs, ys).map { CGPoint(x: $0, y: $1) }
    }

    // MARK: - Click anchoring

    static let clickAnchorWindow: Double = 0.12

    static func anchorWeight(at time: Double, clicks: [Click]) -> Double {
        var cursor = 0
        return anchorWeight(at: time, clicks: clicks, cursor: &cursor)
    }

    static func anchorWeight(at time: Double, clicks: [Click], cursor: inout Int) -> Double {
        var weight: Double = 0
        var pressedAt: Double?
        var settled = cursor
        var index = cursor
        while index < clicks.count {
            let click = clicks[index]
            if pressedAt == nil, click.time > time + clickAnchorWindow { break }
            index += 1
            if click.isDown {
                pressedAt = click.time
            } else {
                if let down = pressedAt {
                    if time >= down, time <= click.time { weight = 1 }
                    pressedAt = nil
                }
                if click.time + clickAnchorWindow < time { settled = index }
            }
            let distance = abs(time - click.time)
            guard distance <= clickAnchorWindow else { continue }
            weight = max(weight, smoothstep(1 - distance / clickAnchorWindow))
        }
        cursor = settled
        if let last = clicks.last, last.isDown, time >= last.time { return 1 }
        return weight
    }

    static func anchored(_ smoothed: [CGPoint],
                         raw: [CGPoint],
                         clicks: [Click],
                         frameRate: Int) -> [CGPoint] {
        guard !clicks.isEmpty, smoothed.count == raw.count else { return smoothed }
        let step = 1.0 / Double(max(1, frameRate))
        var cursor = 0
        return smoothed.indices.map { index in
            let weight = anchorWeight(at: Double(index) * step, clicks: clicks, cursor: &cursor)
            guard weight > 0 else { return smoothed[index] }
            return CGPoint(x: smoothed[index].x + (raw[index].x - smoothed[index].x) * weight,
                           y: smoothed[index].y + (raw[index].y - smoothed[index].y) * weight)
        }
    }

    // MARK: - Shaking

    static let shakeWindow: Double = 0.1
    static let shakeDistance: Double = 0.015
    static let shakeReversals = 3

    static func isShaking(_ points: [CGPoint], around index: Int, frameRate: Int) -> Bool {
        let span = max(2, Int((shakeWindow * Double(max(1, frameRate))).rounded()))
        let lower = max(0, index - span / 2)
        let upper = min(points.count - 1, index + span / 2)
        guard upper - lower >= 3 else { return false }

        var travel: Double = 0
        var reversals = 0
        var previousSign: Int = 0
        for i in (lower + 1)...upper {
            let dx = Double(points[i].x - points[i - 1].x)
            let dy = Double(points[i].y - points[i - 1].y)
            travel += (dx * dx + dy * dy).squareRoot()
            let sign = dx > 0 ? 1 : (dx < 0 ? -1 : 0)
            if sign != 0, previousSign != 0, sign != previousSign {
                reversals += 1
            }
            if sign != 0 { previousSign = sign }
        }
        return travel > shakeDistance * 4 && reversals >= shakeReversals
    }

    // MARK: - Easing

    static func smoothstep(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }

    static func smootherstep(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        return x * x * x * (10 - 15 * x + 6 * x * x)
    }

    static func overlayOpacity(at time: Double,
                               start: Double,
                               end: Double,
                               fade: Double) -> Double {
        let duration = end - start
        guard duration > 0, time >= start, time <= end else { return 0 }
        let ramp = min(fade, duration / 2)
        guard ramp > 0 else { return 1 }
        if time < start + ramp { return smoothstep((time - start) / ramp) }
        if time > end - ramp { return smoothstep((end - time) / ramp) }
        return 1
    }

    // MARK: - Zoom segments

    struct ZoomSegment: Equatable {
        var start: Double
        var end: Double

        var duration: Double { max(0, end - start) }
    }

    static let zoomLeadIn: Double = 0.3
    static let zoomHold: Double = 2.5
    static let zoomMinimumDuration: Double = 0.9
    static let zoomIgnoreTail: Double = 1.0
    static let zoomEndMargin: Double = 0.8
    static let typingZoomTail: Double = 1.4
    static let typingZoomContinuation: Double = 8.0

    static func zoomSegments(clicks: [Click],
                             typingTimes: [Double] = [],
                             duration: Double) -> [ZoomSegment] {
        guard duration > 0 else { return [] }
        let presses = clicks
            .filter { $0.isDown && $0.time < duration - zoomIgnoreTail }
            .map(\.time)
            .sorted()
        guard !presses.isEmpty else { return [] }

        var merged: [ZoomSegment] = []
        for press in presses {
            let segment = ZoomSegment(start: max(0.001, press - zoomLeadIn),
                                      end: press + zoomHold)
            if var last = merged.last, segment.start - last.end <= zoomHold {
                last.end = max(last.end, segment.end)
                merged[merged.count - 1] = last
            } else {
                merged.append(segment)
            }
        }
        for time in typingTimes.filter({ $0.isFinite }).sorted() {
            guard let index = merged.lastIndex(where: {
                time >= $0.start && time <= $0.end + typingZoomContinuation
            }) else { continue }
            merged[index].end = max(merged[index].end, time + typingZoomTail)
        }
        let limit = max(0, duration - zoomEndMargin)
        return merged.compactMap { segment in
            var clamped = segment
            clamped.end = min(clamped.end, limit)
            guard clamped.duration >= zoomMinimumDuration else { return nil }
            return clamped
        }
    }

    static let zoomRampIn: Double = 0.42
    static let zoomRampOut: Double = 0.65

    static func zoomProgress(at time: Double, segments: [ZoomSegment]) -> Double {
        for segment in segments where time >= segment.start - 0.001 && time <= segment.end + zoomRampOut {
            if time <= segment.start + zoomRampIn {
                return smootherstep((time - segment.start) / zoomRampIn)
            }
            if time >= segment.end {
                return smootherstep(1 - (time - segment.end) / zoomRampOut)
            }
            return 1
        }
        return 0
    }

    // MARK: - Viewport

    static let edgeBand: Double = 0.25

    static func travelParameter(focus: Double) -> Double {
        let band = edgeBand
        return min(1, max(0, (focus - band) / (1 - 2 * band)))
    }

    static func travelParameter(exactFocus focus: Double, zoom: Double) -> Double {
        let visible = 1 / max(1, zoom)
        let span = 1 - visible
        guard span > 0.0001 else { return 0.5 }
        return min(1, max(0, (focus - visible / 2) / span))
    }

    static func viewportOrigin(travel: CGPoint, zoom: Double) -> CGPoint {
        let span = max(0, 1 - 1 / max(1, zoom))
        return CGPoint(x: min(1, max(0, travel.x)) * span,
                       y: min(1, max(0, travel.y)) * span)
    }

    // MARK: - Focus clusters

    static let clusterWidthFraction: Double = 0.5
    static let clusterHeightFraction: Double = 0.7

    struct FocusCluster: Equatable {
        var time: Double
        var center: CGPoint
    }

    static func focusClusters(_ points: [CGPoint],
                              frameRate: Int,
                              zoom: Double) -> [FocusCluster] {
        guard !points.isEmpty else { return [] }
        let step = 1.0 / Double(max(1, frameRate))
        let maxWidth = clusterWidthFraction / max(1, zoom)
        let maxHeight = clusterHeightFraction / max(1, zoom)

        var clusters: [FocusCluster] = []
        var box = CGRect(origin: points[0], size: .zero)
        var startedAt: Double = 0

        for index in points.indices {
            let point = points[index]
            let grown = box.union(CGRect(origin: point, size: .zero))
            if grown.width <= maxWidth, grown.height <= maxHeight {
                box = grown
                continue
            }
            clusters.append(FocusCluster(time: startedAt,
                                         center: CGPoint(x: box.midX, y: box.midY)))
            box = CGRect(origin: point, size: .zero)
            startedAt = Double(index) * step
        }
        clusters.append(FocusCluster(time: startedAt,
                                     center: CGPoint(x: box.midX, y: box.midY)))
        return clusters
    }

    static func focus(at time: Double, clusters: [FocusCluster]) -> CGPoint {
        var cursor = 0
        return focus(at: time, clusters: clusters, cursor: &cursor)
    }

    static func focus(at time: Double, clusters: [FocusCluster], cursor: inout Int) -> CGPoint {
        guard let first = clusters.first else { return CGPoint(x: 0.5, y: 0.5) }
        var current = cursor == 0 ? first.center : clusters[cursor - 1].center
        while cursor < clusters.count, clusters[cursor].time <= time {
            current = clusters[cursor].center
            cursor += 1
        }
        return current
    }

    // MARK: - Spring

    struct Spring: Equatable {
        var value: Double
        var velocity: Double = 0

        static let stiffness: Double = 200
        static let mass: Double = 2.25
        static let damping: Double = 40

        mutating func step(toward target: Double, dt: Double) {
            guard dt > 0 else { return }
            let acceleration = (Self.stiffness * (target - value) - Self.damping * velocity)
                / Self.mass
            velocity += acceleration * dt
            value += velocity * dt
        }
    }

    static func springed(_ targets: [Double], frameRate: Int) -> [Double] {
        guard targets.count > 1 else { return targets }
        let frameStep = 1.0 / Double(max(1, frameRate))
        let substep = 1.0 / 240.0
        var spring = Spring(value: targets[0])
        var result: [Double] = []
        result.reserveCapacity(targets.count)
        for target in targets {
            var elapsed: Double = 0
            while elapsed < frameStep {
                spring.step(toward: target, dt: min(substep, frameStep - elapsed))
                elapsed += substep
            }
            result.append(spring.value)
        }
        return result
    }

    // MARK: - Standing still

    static let idleDelay: Double = 2.5
    static let idleFadeOut: Double = 0.4
    static let idleFadeIn: Double = 0.25
    static let idleTravel: Double = 0.0006

    static func pointerOpacity(_ points: [CGPoint], frameRate: Int) -> [Double] {
        guard points.count > 1 else { return Array(repeating: 1, count: max(1, points.count)) }
        let step = 1.0 / Double(max(1, frameRate))

        var stillFor = [Double](repeating: 0, count: points.count)
        for index in 1..<points.count {
            let dx = Double(points[index].x - points[index - 1].x)
            let dy = Double(points[index].y - points[index - 1].y)
            let moved = (dx * dx + dy * dy).squareRoot() > idleTravel
            stillFor[index] = moved ? 0 : stillFor[index - 1] + step
        }
        var untilMoves = [Double](repeating: .greatestFiniteMagnitude, count: points.count)
        for index in stride(from: points.count - 2, through: 0, by: -1) {
            untilMoves[index] = stillFor[index + 1] == 0
                ? 0
                : untilMoves[index + 1] + step
        }

        return points.indices.map { index in
            let waking = untilMoves[index] <= idleFadeIn
                ? 1 - untilMoves[index] / idleFadeIn
                : 0
            let sleeping = stillFor[index] <= idleDelay
                ? 0
                : min(1, (stillFor[index] - idleDelay) / idleFadeOut)
            let hidden = max(0, sleeping - waking)
            return 1 - smoothstep(hidden)
        }
    }

    // MARK: - Click feedback

    static let pressPunchWindow: Double = 0.13
    static let pressPunchScale: Double = 0.8

    static func pressScale(at time: Double, clicks: [Click]) -> Double {
        var cursor = 0
        return pressScale(at: time, clicks: clicks, cursor: &cursor)
    }

    static func pressScale(at time: Double, clicks: [Click], cursor: inout Int) -> Double {
        let weight = anchorWeightForPunch(at: time, clicks: clicks, cursor: &cursor)
        return 1 - (1 - pressPunchScale) * weight
    }

    private static func anchorWeightForPunch(at time: Double,
                                             clicks: [Click],
                                             cursor: inout Int) -> Double {
        var weight: Double = 0
        var pressedAt: Double?
        var settled = cursor
        var index = cursor
        while index < clicks.count {
            let click = clicks[index]
            if pressedAt == nil, click.time > time + pressPunchWindow { break }
            index += 1
            if click.isDown {
                pressedAt = click.time
                if time >= click.time - pressPunchWindow, time <= click.time {
                    weight = max(weight, smoothstep((time - (click.time - pressPunchWindow))
                                                     / pressPunchWindow))
                }
            } else {
                if let down = pressedAt {
                    if time >= down, time <= click.time { weight = 1 }
                    if time > click.time, time <= click.time + pressPunchWindow {
                        weight = max(weight, smoothstep(1 - (time - click.time) / pressPunchWindow))
                    }
                    pressedAt = nil
                }
                if click.time + pressPunchWindow < time { settled = index }
            }
        }
        cursor = settled
        if let last = clicks.last, last.isDown, time >= last.time { weight = 1 }
        return min(1, weight)
    }

    static let ringDuration: Double = 0.4
    static let ringRadius: Double = 22

    static func ringProgress(at time: Double, clicks: [Click]) -> Double? {
        var cursor = 0
        return ringProgress(at: time, clicks: clicks, cursor: &cursor)
    }

    static func ringProgress(at time: Double, clicks: [Click], cursor: inout Int) -> Double? {
        var best: Double?
        var index = cursor
        while index < clicks.count {
            let click = clicks[index]
            let elapsed = time - click.time
            if elapsed < 0 { break }
            index += 1
            if elapsed > ringDuration { cursor = index; continue }
            guard click.isDown else { continue }
            let progress = elapsed / ringDuration
            best = min(best ?? progress, progress)
        }
        return best
    }
}
