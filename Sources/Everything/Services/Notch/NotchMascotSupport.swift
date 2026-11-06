// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum NotchMascotStyle: String, CaseIterable, Identifiable {
    case minimal, robot

    var id: String { rawValue }
}

enum NotchMascotShape: String, CaseIterable, Identifiable {
    case ball, egg, squircle, pill

    var id: String { rawValue }
}

struct NotchMascotColor: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    var alpha: CGFloat = 1

    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    static let ink = NotchMascotColor(red: 0.07, green: 0.07, blue: 0.08)
    static let visor = NotchMascotColor(red: 0.09, green: 0.09, blue: 0.11)
    static let shine = NotchMascotColor(red: 1, green: 1, blue: 1, alpha: 0.55)
}

enum NotchMascotPalette: String, CaseIterable, Identifiable {
    case pearl, lemon, peach, rose, lilac, sky, mint

    var id: String { rawValue }

    var light: NotchMascotColor {
        switch self {
        case .pearl: return NotchMascotColor(red: 0.99, green: 0.98, blue: 0.96)
        case .lemon: return NotchMascotColor(red: 1.00, green: 0.96, blue: 0.64)
        case .peach: return NotchMascotColor(red: 1.00, green: 0.86, blue: 0.74)
        case .rose: return NotchMascotColor(red: 1.00, green: 0.80, blue: 0.87)
        case .lilac: return NotchMascotColor(red: 0.88, green: 0.83, blue: 1.00)
        case .sky: return NotchMascotColor(red: 0.77, green: 0.90, blue: 1.00)
        case .mint: return NotchMascotColor(red: 0.72, green: 0.97, blue: 0.86)
        }
    }

    var shade: NotchMascotColor {
        switch self {
        case .pearl: return NotchMascotColor(red: 0.84, green: 0.85, blue: 0.90)
        case .lemon: return NotchMascotColor(red: 0.97, green: 0.83, blue: 0.30)
        case .peach: return NotchMascotColor(red: 0.98, green: 0.64, blue: 0.50)
        case .rose: return NotchMascotColor(red: 0.95, green: 0.54, blue: 0.68)
        case .lilac: return NotchMascotColor(red: 0.69, green: 0.59, blue: 0.96)
        case .sky: return NotchMascotColor(red: 0.43, green: 0.67, blue: 0.97)
        case .mint: return NotchMascotColor(red: 0.40, green: 0.83, blue: 0.66)
        }
    }
}

struct NotchMascotLook: Equatable {
    var style: NotchMascotStyle
    var shape: NotchMascotShape
    var palette: NotchMascotPalette

    static let standard = NotchMascotLook(style: .minimal, shape: .ball, palette: .pearl)
}

enum NotchMascotMood: String, CaseIterable, Identifiable {
    case idle, happy, wink, love, sleepy, determined, surprised, searching, thinking, confused
    case alert

    var id: String { rawValue }
}

enum NotchMascotSide: String, CaseIterable, Identifiable {
    case left, right

    var id: String { rawValue }
}

enum NotchMascotVisitFrequency: String, CaseIterable, Identifiable {
    case rare, normal, frequent

    var id: String { rawValue }

    var delay: ClosedRange<TimeInterval> {
        switch self {
        case .rare: return 600...1200
        case .normal: return 240...540
        case .frequent: return 90...180
        }
    }
}

enum NotchMascotReaction: String, CaseIterable {
    case celebrate
    case love
    case surprised
    case flash
    case confused
    case wakeUp
    case yawn
    case perk
    case bounce
    case hush
    case ready
    case groove

    var length: TimeInterval {
        switch self {
        case .celebrate: return 1.0
        case .love: return 1.4
        case .surprised: return 0.9
        case .flash: return 0.5
        case .confused: return 1.2
        case .wakeUp: return 1.6
        case .yawn: return 1.2
        case .perk: return 1.0
        case .bounce: return 1.0
        case .hush: return 1.0
        case .ready: return 1.0
        case .groove: return 1.6
        }
    }
}

enum NotchMascotMoment: String, CaseIterable, Identifiable {
    case visit, timerStarted, timeIsUp, music, agents, eventStarts, downloadFinished, downloadFailed, screenshot,
         micMuted, keepAwake, charging, lowBattery, unlocked

    var id: String { rawValue }

    var reaction: NotchMascotReaction? {
        switch self {
        case .visit: return nil
        case .timerStarted: return .ready
        case .timeIsUp: return .surprised
        case .music: return .groove
        case .agents: return .ready
        case .eventStarts: return .bounce
        case .downloadFinished: return .celebrate
        case .downloadFailed: return .confused
        case .screenshot: return .flash
        case .micMuted: return .hush
        case .keepAwake: return .perk
        case .charging: return .love
        case .lowBattery: return .yawn
        case .unlocked: return .wakeUp
        }
    }

    var followUp: NotchMascotReaction? {
        self == .agents ? .celebrate : nil
    }

    var symbol: String {
        switch self {
        case .visit: return "figure.walk"
        case .timerStarted: return "timer"
        case .timeIsUp: return "alarm"
        case .music: return "music.note"
        case .agents: return "sparkles"
        case .eventStarts: return "calendar"
        case .downloadFinished: return "arrow.down.circle"
        case .downloadFailed: return "exclamationmark.triangle"
        case .screenshot: return "camera.viewfinder"
        case .micMuted: return "mic.slash"
        case .keepAwake: return "cup.and.saucer"
        case .charging: return "bolt"
        case .lowBattery: return "battery.25percent"
        case .unlocked: return "lock.open"
        }
    }
}

struct NotchMascotReactionEvent: Equatable {
    let id: UUID
    let reaction: NotchMascotReaction
    let start: CFTimeInterval
}

struct NotchMascotReactionGate {
    static let spacing: TimeInterval = 2.5
    static let repeatInterval: TimeInterval = 30
    static let patience: TimeInterval = 8

    private(set) var last: (reaction: NotchMascotReaction, time: TimeInterval)?

    mutating func admits(_ reaction: NotchMascotReaction, at time: TimeInterval) -> Bool {
        if let last {
            if time - last.time < Self.spacing { return false }
            if last.reaction == reaction, time - last.time < Self.repeatInterval { return false }
        }
        last = (reaction, time)
        return true
    }
}

enum NotchCommandBarStyle: String, CaseIterable, Identifiable {
    case droplet
    case island

    var id: String { rawValue }
}

enum NotchMascotEye: Equatable {
    case open, closed, happy, heart, sleepy, wide, squint
    case determined

    var blinks: Bool { self == .open || self == .wide || self == .squint }
}

struct NotchMascotExpression: Equatable {
    var left: NotchMascotEye
    var right: NotchMascotEye
    var gaze: CGPoint = .zero
    var tilt: CGFloat = 0

    var blinks: Bool { left.blinks && right.blinks }
}

extension NotchMascotMood {
    var expression: NotchMascotExpression {
        switch self {
        case .idle: return NotchMascotExpression(left: .open, right: .open)
        case .happy: return NotchMascotExpression(left: .happy, right: .happy, gaze: CGPoint(x: 0, y: -0.02))
        case .wink: return NotchMascotExpression(left: .open, right: .happy, tilt: -0.08)
        case .love: return NotchMascotExpression(left: .heart, right: .heart)
        case .sleepy: return NotchMascotExpression(left: .sleepy, right: .sleepy, gaze: CGPoint(x: 0, y: 0.03), tilt: 0.05)
        case .determined: return NotchMascotExpression(left: .determined, right: .determined)
        case .surprised: return NotchMascotExpression(left: .wide, right: .wide, gaze: CGPoint(x: 0, y: -0.02))
        case .searching: return NotchMascotExpression(left: .open, right: .open, gaze: CGPoint(x: 0.05, y: 0))
        case .thinking: return NotchMascotExpression(left: .squint, right: .open, gaze: CGPoint(x: 0.06, y: -0.06), tilt: -0.1)
        case .confused: return NotchMascotExpression(left: .open, right: .squint, gaze: CGPoint(x: -0.03, y: 0.01), tilt: 0.14)
        case .alert: return NotchMascotExpression(left: .wide, right: .wide)
        }
    }
}

struct NotchMascotFaceLayout: Equatable {
    let leftEye: CGPoint
    let rightEye: CGPoint
    let eyeSize: CGSize
    let shineCenter: CGPoint
    let shineRadii: CGSize
    let shineAngle: CGFloat
}

extension NotchMascotLook {
    var face: NotchMascotFaceLayout {
        if style == .robot {
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.36, y: 0.63), rightEye: CGPoint(x: 0.64, y: 0.63),
                                         eyeSize: CGSize(width: 0.085, height: 0.16),
                                         shineCenter: CGPoint(x: 0.27, y: 0.34), shineRadii: CGSize(width: 0.07, height: 0.04),
                                         shineAngle: -0.3)
        }
        switch shape {
        case .ball:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.36, y: 0.50), rightEye: CGPoint(x: 0.64, y: 0.50),
                                         eyeSize: CGSize(width: 0.10, height: 0.20),
                                         shineCenter: CGPoint(x: 0.31, y: 0.29), shineRadii: CGSize(width: 0.085, height: 0.055),
                                         shineAngle: -0.5)
        case .egg:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.375, y: 0.55), rightEye: CGPoint(x: 0.625, y: 0.55),
                                         eyeSize: CGSize(width: 0.095, height: 0.19),
                                         shineCenter: CGPoint(x: 0.33, y: 0.31), shineRadii: CGSize(width: 0.075, height: 0.05),
                                         shineAngle: -0.6)
        case .squircle:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.35, y: 0.53), rightEye: CGPoint(x: 0.65, y: 0.53),
                                         eyeSize: CGSize(width: 0.10, height: 0.20),
                                         shineCenter: CGPoint(x: 0.24, y: 0.28), shineRadii: CGSize(width: 0.08, height: 0.05),
                                         shineAngle: -0.55)
        case .pill:
            return NotchMascotFaceLayout(leftEye: CGPoint(x: 0.37, y: 0.57), rightEye: CGPoint(x: 0.63, y: 0.57),
                                         eyeSize: CGSize(width: 0.09, height: 0.19),
                                         shineCenter: CGPoint(x: 0.20, y: 0.42), shineRadii: CGSize(width: 0.07, height: 0.045),
                                         shineAngle: -0.45)
        }
    }
}

enum NotchMascotGeometry {
    static let eyeCurveCount = 24

    static func body(_ shape: NotchMascotShape, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size, y: y * size) }
        switch shape {
        case .ball:
            path.addEllipse(in: CGRect(x: 0.08 * size, y: 0.12 * size, width: 0.84 * size, height: 0.84 * size))
        case .egg:
            path.move(to: point(0.5, 0.10))
            path.addCurve(to: point(0.86, 0.60), control1: point(0.71, 0.10), control2: point(0.86, 0.36))
            path.addCurve(to: point(0.5, 0.96), control1: point(0.86, 0.80), control2: point(0.70, 0.96))
            path.addCurve(to: point(0.14, 0.60), control1: point(0.30, 0.96), control2: point(0.14, 0.80))
            path.addCurve(to: point(0.5, 0.10), control1: point(0.14, 0.36), control2: point(0.29, 0.10))
            path.closeSubpath()
        case .squircle:
            let count = 72
            for index in 0..<count {
                let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
                let cosine = cos(angle), sine = sin(angle)
                let exponent: CGFloat = 2 / 3.4
                let x = 0.5 + 0.43 * (cosine < 0 ? -1 : 1) * pow(abs(cosine), exponent)
                let y = 0.55 + 0.40 * (sine < 0 ? -1 : 1) * pow(abs(sine), exponent)
                if index == 0 { path.move(to: point(x, y)) } else { path.addLine(to: point(x, y)) }
            }
            path.closeSubpath()
        case .pill:
            path.addRoundedRect(in: CGRect(x: 0.05 * size, y: 0.28 * size, width: 0.90 * size, height: 0.60 * size),
                                cornerWidth: 0.30 * size, cornerHeight: 0.30 * size)
        }
        return path
    }

    struct Robot {
        let head: CGPath
        let ears: CGPath
        let antenna: CGPath
        let bulb: CGPath
        let visor: CGPath
    }

    static func figureOffset(_ look: NotchMascotLook) -> CGFloat {
        let bounds: CGRect
        if look.style == .robot {
            let parts = robot(size: 1)
            bounds = [parts.ears, parts.antenna, parts.bulb]
                .reduce(parts.head.boundingBoxOfPath) { $0.union($1.boundingBoxOfPath) }
        } else {
            bounds = body(look.shape, size: 1).boundingBoxOfPath
        }
        return bounds.midY - 0.5
    }

    static func robot(size: CGFloat) -> Robot {
        func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: x * size, y: y * size, width: width * size, height: height * size)
        }
        func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
            CGPath(roundedRect: rect, cornerWidth: radius * size, cornerHeight: radius * size, transform: nil)
        }
        let ears = CGMutablePath()
        ears.addPath(rounded(rect(0.05, 0.50, 0.08, 0.20), 0.035))
        ears.addPath(rounded(rect(0.87, 0.50, 0.08, 0.20), 0.035))
        return Robot(head: rounded(rect(0.12, 0.26, 0.76, 0.68), 0.20),
                     ears: ears,
                     antenna: rounded(rect(0.475, 0.12, 0.05, 0.16), 0.025),
                     bulb: CGPath(ellipseIn: rect(0.43, 0.04, 0.14, 0.14), transform: nil),
                     visor: rounded(rect(0.20, 0.44, 0.60, 0.38), 0.15))
    }

    static func shine(_ face: NotchMascotFaceLayout, size: CGFloat) -> CGPath {
        var transform = CGAffineTransform(translationX: face.shineCenter.x * size, y: face.shineCenter.y * size)
            .rotated(by: face.shineAngle)
        let radii = CGSize(width: face.shineRadii.width * size, height: face.shineRadii.height * size)
        return CGPath(ellipseIn: CGRect(x: -radii.width, y: -radii.height, width: radii.width * 2, height: radii.height * 2),
                      transform: &transform)
    }

    static func eye(_ eye: NotchMascotEye, size: CGSize, center: CGPoint, right: Bool) -> CGPath {
        let points = eyePoints(eye, size: size, right: right).map {
            CGPoint(x: $0.x + center.x, y: $0.y + center.y)
        }
        return smoothClosedPath(points)
    }

    static func eyePoints(_ eye: NotchMascotEye, size: CGSize, right: Bool) -> [CGPoint] {
        let width = max(0.5, size.width), height = max(0.5, size.height)
        var outline: [CGPoint]
        switch eye {
        case .open:
            outline = stadium(width: width, height: height, center: .zero)
        case .closed:
            outline = stadium(width: width * 1.5, height: width * 0.45, center: CGPoint(x: 0, y: height * 0.12))
        case .squint:
            outline = stadium(width: width, height: height * 0.55, center: CGPoint(x: 0, y: height * 0.08))
        case .wide:
            outline = ellipse(radii: CGSize(width: width * 0.8, height: width * 0.8), center: CGPoint(x: 0, y: -height * 0.02))
        case .happy:
            outline = arch(span: width * 2.1, rise: height * 0.42, thickness: width * 0.55, top: -height * 0.18)
        case .heart:
            outline = heart(width: width * 2.0, height: width * 1.8, center: CGPoint(x: 0, y: -height * 0.02))
        case .sleepy:
            outline = lid(width: width * 1.25, top: height * 0.02, depth: height * 0.38)
        case .determined:
            outline = clipBelow(stadium(width: width, height: height, center: .zero),
                                from: CGPoint(x: -width / 2, y: -height * 0.30),
                                to: CGPoint(x: width / 2, y: height * 0.02))
        }
        if right { outline = outline.map { CGPoint(x: -$0.x, y: $0.y) } }
        return resample(outline, count: eyeCurveCount)
    }

    // MARK: Outlines

    private static let dense = 96

    private static func stadium(width: CGFloat, height: CGFloat, center: CGPoint) -> [CGPoint] {
        let radius = min(width, height) / 2
        let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        return roundedRect(rect, radius: radius)
    }

    private static func roundedRect(_ rect: CGRect, radius: CGFloat) -> [CGPoint] {
        let corners: [(CGPoint, CGFloat)] = [
            (CGPoint(x: rect.maxX - radius, y: rect.minY + radius), -.pi / 2),
            (CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), 0),
            (CGPoint(x: rect.minX + radius, y: rect.maxY - radius), .pi / 2),
            (CGPoint(x: rect.minX + radius, y: rect.minY + radius), .pi),
        ]
        var points: [CGPoint] = []
        let steps = dense / 4
        for (center, start) in corners {
            for step in 0...steps {
                let angle = start + CGFloat(step) / CGFloat(steps) * .pi / 2
                points.append(CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
            }
        }
        return points
    }

    private static func ellipse(radii: CGSize, center: CGPoint) -> [CGPoint] {
        (0..<dense).map { index in
            let angle = -CGFloat.pi / 2 + CGFloat(index) / CGFloat(dense) * 2 * .pi
            return CGPoint(x: center.x + radii.width * cos(angle), y: center.y + radii.height * sin(angle))
        }
    }

    private static func arch(span: CGFloat, rise: CGFloat, thickness: CGFloat, top: CGFloat) -> [CGPoint] {
        let half = max(0.1, span / 2 - thickness / 2)
        let lift = max(0.1, rise)
        let radius = (half * half + lift * lift) / (2 * lift)
        let apex = top + thickness / 2
        let center = CGPoint(x: 0, y: apex + radius)
        let reach = asin(min(1, half / radius))
        func onArc(_ angle: CGFloat, _ radius: CGFloat) -> CGPoint {
            CGPoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
        }
        let steps = dense / 3
        var points: [CGPoint] = []
        for step in 0...steps {
            points.append(onArc(-reach + CGFloat(step) / CGFloat(steps) * reach * 2, radius + thickness / 2))
        }
        let rightEnd = onArc(reach, radius)
        for step in 1..<12 {
            let angle = reach + CGFloat(step) / 12 * .pi
            points.append(CGPoint(x: rightEnd.x + thickness / 2 * sin(angle), y: rightEnd.y - thickness / 2 * cos(angle)))
        }
        for step in 0...steps {
            points.append(onArc(reach - CGFloat(step) / CGFloat(steps) * reach * 2, radius - thickness / 2))
        }
        let leftEnd = onArc(-reach, radius)
        for step in 1..<12 {
            let angle = -reach + .pi + CGFloat(step) / 12 * .pi
            points.append(CGPoint(x: leftEnd.x + thickness / 2 * sin(angle), y: leftEnd.y - thickness / 2 * cos(angle)))
        }
        return points
    }

    private static func heart(width: CGFloat, height: CGFloat, center: CGPoint) -> [CGPoint] {
        let raw: [CGPoint] = (0..<dense).map { index in
            let t = CGFloat(index) / CGFloat(dense) * 2 * .pi
            let x = 16 * pow(sin(t), 3)
            let y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
            return CGPoint(x: x, y: y)
        }
        let minY = raw.map(\.y).min() ?? 0, maxY = raw.map(\.y).max() ?? 1
        let middle = (minY + maxY) / 2
        return raw.map {
            CGPoint(x: center.x + $0.x / 32 * width,
                    y: center.y - ($0.y - middle) / (maxY - minY) * height)
        }
    }

    private static func lid(width: CGFloat, top: CGFloat, depth: CGFloat) -> [CGPoint] {
        let half = width / 2
        var points: [CGPoint] = []
        let flat = dense / 4
        for step in 0...flat {
            points.append(CGPoint(x: -half + CGFloat(step) / CGFloat(flat) * width, y: top))
        }
        let round = dense - flat
        for step in 1..<round {
            let angle = CGFloat(step) / CGFloat(round) * .pi
            points.append(CGPoint(x: half * cos(angle), y: top + depth * sin(angle)))
        }
        return points
    }

    private static func clipBelow(_ points: [CGPoint], from: CGPoint, to: CGPoint) -> [CGPoint] {
        func side(_ point: CGPoint) -> CGFloat {
            (to.x - from.x) * (point.y - from.y) - (to.y - from.y) * (point.x - from.x)
        }
        var clipped: [CGPoint] = []
        for index in points.indices {
            let current = points[index], next = points[(index + 1) % points.count]
            let a = side(current), b = side(next)
            if a >= 0 { clipped.append(current) }
            if (a >= 0) != (b >= 0) {
                let share = a / (a - b)
                clipped.append(CGPoint(x: current.x + (next.x - current.x) * share,
                                       y: current.y + (next.y - current.y) * share))
            }
        }
        return clipped.count >= 3 ? clipped : points
    }

    // MARK: Resampling

    static func resample(_ outline: [CGPoint], count: Int) -> [CGPoint] {
        guard outline.count >= 3, count >= 3 else { return outline }
        var points = outline
        var area: CGFloat = 0
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            area += a.x * b.y - b.x * a.y
        }
        if area < 0 { points.reverse() }
        var start: (index: Int, point: CGPoint)?
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            guard (a.x <= 0 && b.x > 0) || (a.x >= 0 && b.x < 0) || a.x == 0 else { continue }
            let share = b.x == a.x ? 0 : -a.x / (b.x - a.x)
            let crossing = CGPoint(x: 0, y: a.y + (b.y - a.y) * share)
            if start == nil || crossing.y < start!.point.y { start = (index, crossing) }
        }
        guard let start else { return Array(points.prefix(count)) }
        var walk = [start.point]
        for offset in 1...points.count {
            walk.append(points[(start.index + offset) % points.count])
        }
        walk.append(start.point)
        var lengths: [CGFloat] = [0]
        for index in 1..<walk.count {
            lengths.append(lengths[index - 1] + hypot(walk[index].x - walk[index - 1].x, walk[index].y - walk[index - 1].y))
        }
        let total = lengths.last ?? 0
        guard total > 0 else { return Array(repeating: start.point, count: count) }
        var result: [CGPoint] = []
        var segment = 1
        for step in 0..<count {
            let target = total * CGFloat(step) / CGFloat(count)
            while segment < lengths.count - 1, lengths[segment] < target { segment += 1 }
            let span = lengths[segment] - lengths[segment - 1]
            let share = span > 0 ? (target - lengths[segment - 1]) / span : 0
            let a = walk[segment - 1], b = walk[segment]
            result.append(CGPoint(x: a.x + (b.x - a.x) * share, y: a.y + (b.y - a.y) * share))
        }
        return result
    }

    static func smoothClosedPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        let count = points.count
        guard count >= 3 else { return path }
        path.move(to: points[0])
        for index in 0..<count {
            let previous = points[(index - 1 + count) % count]
            let current = points[index]
            let next = points[(index + 1) % count]
            let after = points[(index + 2) % count]
            let first = CGPoint(x: current.x + (next.x - previous.x) / 6, y: current.y + (next.y - previous.y) / 6)
            let second = CGPoint(x: next.x - (after.x - current.x) / 6, y: next.y - (after.y - current.y) / 6)
            path.addCurve(to: next, control1: first, control2: second)
        }
        path.closeSubpath()
        return path
    }
}

struct NotchMascotVisit: Equatable {
    enum Kind: Equatable {
        case lap
        case pass
        case home
        case cameo(NotchMascotReaction)
        case countdown(TimeInterval)
        case retreat
        case farewell
        case cross
        case arrive
        case linger(NotchMascotReaction)

        var endsOutOfSight: Bool {
            switch self {
            case .pass, .cameo, .countdown, .retreat, .farewell, .linger: return true
            case .lap, .home, .cross, .arrive: return false
            }
        }

        var watchesTimer: Bool {
            switch self {
            case .countdown, .retreat: return true
            default: return false
            }
        }

        var takesOnlyItsWing: Bool {
            switch self {
            case .countdown, .retreat, .cameo, .linger: return true
            default: return false
            }
        }

        var reaction: NotchMascotReaction? {
            switch self {
            case .cameo(let reaction), .linger(let reaction): return reaction
            default: return nil
            }
        }
    }

    let id: UUID
    let kind: Kind
    let greeting: NotchMascotMood
    let start: CFTimeInterval

    var duration: TimeInterval { NotchMascotMotion.duration(of: kind) }
}

struct NotchMascotTrack: Equatable {
    var width: CGFloat
    var height: CGFloat
    var size: CGFloat
    var rest: CGFloat
    var hidden: ClosedRange<CGFloat>?
    var baseline: CGFloat
    var ceiling: CGFloat = 0
    var mirrored = false
    var scale: CGFloat = 1

    func hop(_ share: CGFloat) -> CGFloat {
        min(size * share, max(scale, baseline - size / 2 - ceiling - (hidden == nil ? 1 : 2) * scale))
    }

    func behindCamera(_ hidden: ClosedRange<CGFloat>, margin: CGFloat) -> CGFloat {
        hidden.lowerBound + size / 2 + margin * scale
    }

    func scaled(by scale: CGFloat) -> NotchMascotTrack {
        NotchMascotTrack(width: width * scale, height: height * scale, size: size * scale, rest: rest * scale,
                         hidden: hidden.map { ($0.lowerBound * scale)...($0.upperBound * scale) },
                         baseline: baseline * scale, ceiling: ceiling * scale, mirrored: mirrored,
                         scale: self.scale * scale)
    }

    var leftSide: NotchMascotTrack {
        guard mirrored else { return self }
        var left = self
        left.mirrored = false
        left.rest = width - rest
        return left
    }

    var farSpot: CGFloat {
        guard let hidden else { return min(width - size * 0.8, rest + width * 0.22) }
        return hidden.upperBound + (hidden.lowerBound - rest)
    }
}

struct NotchMascotPath: Equatable {
    var keyTimes: [Double] = []
    var x: [CGFloat] = []
    var lift: [CGFloat] = []
    var squash: [CGFloat] = []
    var gaze: [CGFloat] = []
    var duration: TimeInterval = 0
    var greeting: ClosedRange<TimeInterval> = 0...0
}

enum NotchMascotMotion {
    static let lapDuration: TimeInterval = 3.6
    static let passDuration: TimeInterval = 3.4
    static let homeDuration: TimeInterval = 0.62
    static let cameoArrival: TimeInterval = 0.5
    static let cameoExit: TimeInterval = 0.32
    static let farewellDuration: TimeInterval = 0.78
    static let crossDuration: TimeInterval = 1.24
    static let restCrossfade: TimeInterval = 0.2

    static func duration(of kind: NotchMascotVisit.Kind) -> TimeInterval {
        switch kind {
        case .lap: return lapDuration
        case .pass: return passDuration
        case .home, .arrive: return homeDuration
        case .cameo(let reaction): return cameoArrival + cameoHold(reaction) + cameoExit
        case .linger(let reaction): return cameoHold(reaction) + cameoExit
        case .countdown(let total): return total + countdownLinger + cameoExit
        case .retreat: return cameoExit
        case .farewell: return farewellDuration
        case .cross: return crossDuration
        }
    }

    static let countdownLead: TimeInterval = 5
    static let countdownLinger: TimeInterval = 0.1

    static func cameoHold(_ reaction: NotchMascotReaction) -> TimeInterval { reaction.length + 0.3 }

    static func handBack(of kind: NotchMascotVisit.Kind, floats: Bool) -> TimeInterval? {
        guard let reaction = kind.reaction else { return nil }
        let arrival = kind == .linger(reaction) ? 0 : cameoArrival
        return arrival + cameoHold(reaction) + (floats ? cameoExit / 4 : 0)
    }

    static func path(for kind: NotchMascotVisit.Kind, on track: NotchMascotTrack) -> NotchMascotPath {
        switch kind {
        case .countdown(let total): return countdown(on: track.leftSide, total: total)
        case .retreat: return retreat(on: track.leftSide)
        default: break
        }
        guard track.mirrored else {
            switch kind {
            case .lap: return lap(on: track)
            case .pass: return pass(on: track)
            case .home: return home(on: track)
            case .cameo(let reaction): return cameo(on: track, hold: cameoHold(reaction))
            case .linger(let reaction): return linger(on: track, hold: cameoHold(reaction))
            case .farewell: return farewell(on: track)
            case .cross: return cross(on: track)
            case .arrive: return arrive(on: track)
            case .countdown, .retreat: return NotchMascotPath()
            }
        }
        var left = track
        left.mirrored = false
        left.rest = track.width - track.rest
        var path = self.path(for: kind, on: left)
        path.x = path.x.map { track.width - $0 }
        path.gaze = path.gaze.map { -$0 }
        return path
    }

    private enum Step {
        case stay(TimeInterval, bounces: Int = 0)
        case hop(to: CGFloat, TimeInterval, height: CGFloat)
        case walk(to: CGFloat, TimeInterval)
        case jump(to: CGFloat)
    }

    static func lap(on track: NotchMascotTrack) -> NotchMascotPath {
        let size = track.size
        let offstageRight = track.width + size
        let offstageLeft = -size
        var steps: [Step] = [.stay(0.18)]
        if let hidden = track.hidden {
            steps += [.hop(to: track.behindCamera(hidden, margin: 2), 0.34, height: track.hop(0.24)),
                      .walk(to: hidden.upperBound - size / 2 - 2 * track.scale, 0.50),
                      .hop(to: track.farSpot, 0.34, height: track.hop(0.24))]
        } else {
            steps += [.hop(to: track.farSpot, 0.60, height: track.hop(0.3)), .stay(0.58)]
        }
        steps += [.stay(0.94, bounces: 2),
                  .walk(to: offstageRight, 0.40),
                  .jump(to: offstageLeft),
                  .hop(to: track.rest, 0.52, height: track.hop(0.26))]
        var path = sample(steps, start: track.rest, track: track, duration: lapDuration)
        let greetStart: TimeInterval = track.hidden == nil ? 0.78 : 1.30
        path.greeting = greetStart...(greetStart + 1.0)
        return path
    }

    static func pass(on track: NotchMascotTrack) -> NotchMascotPath {
        let size = track.size
        var steps: [Step] = [.stay(0.20), .hop(to: track.rest, 0.42, height: track.hop(0.26)), .stay(0.88, bounces: 2)]
        if let hidden = track.hidden {
            steps += [.hop(to: track.behindCamera(hidden, margin: 2), 0.34, height: track.hop(0.24)),
                      .walk(to: hidden.upperBound - size / 2 - 2 * track.scale, 0.50),
                      .hop(to: track.farSpot, 0.34, height: track.hop(0.24)),
                      .stay(0.22)]
        } else {
            steps += [.hop(to: track.farSpot, 0.60, height: track.hop(0.3)), .stay(0.80)]
        }
        steps += [.walk(to: track.width + size, 0.40)]
        var path = sample(steps, start: -size, track: track, duration: passDuration)
        path.greeting = 0.55...1.55
        return path
    }

    static func home(on track: NotchMascotTrack) -> NotchMascotPath {
        guard let hidden = track.hidden else {
            var path = sample([.stay(0.08), .hop(to: track.rest, 0.36, height: track.hop(0.2))],
                              start: track.rest, track: track, duration: homeDuration)
            path.greeting = 0...0.4
            return path
        }
        var path = sample([.stay(0.06), .hop(to: track.rest, 0.42, height: track.hop(0.2))],
                          start: track.behindCamera(hidden, margin: 2), track: track, duration: homeDuration)
        path.greeting = 0...0.44
        return path
    }

    static func cameo(on track: NotchMascotTrack, hold: TimeInterval) -> NotchMascotPath {
        let size = track.size
        let duration = cameoArrival + hold + cameoExit
        guard let hidden = track.hidden else {
            return sample([.stay(0.06), .hop(to: track.rest, cameoArrival - 0.06, height: track.hop(0.3)), .stay(hold),
                           .walk(to: track.width + size, cameoExit)],
                          start: -size, track: track, duration: duration)
        }
        let behind = track.behindCamera(hidden, margin: 1)
        return sample([.stay(0.06), .hop(to: track.rest, cameoArrival - 0.06, height: track.hop(0.2)), .stay(hold),
                       .hop(to: behind, cameoExit, height: track.hop(0.16))],
                      start: behind, track: track, duration: duration)
    }

    static func linger(on track: NotchMascotTrack, hold: TimeInterval) -> NotchMascotPath {
        let duration = hold + cameoExit
        guard let hidden = track.hidden else {
            return sample([.stay(hold), .walk(to: track.width + track.size, cameoExit)],
                          start: track.rest, track: track, duration: duration)
        }
        return sample([.stay(hold), .hop(to: track.behindCamera(hidden, margin: 1), cameoExit, height: track.hop(0.16))],
                      start: track.rest, track: track, duration: duration)
    }

    static func countdown(on track: NotchMascotTrack, total: TimeInterval) -> NotchMascotPath {
        let size = track.size
        let duration = total + countdownLinger + cameoExit
        guard let hidden = track.hidden else {
            return sample([.stay(duration)], start: -size, track: track, duration: duration)
        }
        let behind = track.behindCamera(hidden, margin: 1)
        var steps: [Step] = [.stay(0.06), .hop(to: track.rest, cameoArrival - 0.06, height: track.hop(0.2))]
        var time = cameoArrival
        let ticks = stride(from: total.rounded(.up) - 1, through: 1, by: -1)
            .map { total - $0 }
            .filter { $0 - 0.15 > time + 0.1 }
        for tick in ticks {
            steps.append(.stay(tick - 0.15 - time))
            steps.append(.hop(to: track.rest, 0.3, height: track.hop(0.1)))
            time = tick + 0.15
        }
        steps.append(.stay(max(0, total + countdownLinger - time)))
        steps.append(.hop(to: behind, cameoExit, height: track.hop(0.16)))
        var path = sample(steps, start: behind, track: track, duration: duration)
        path.gaze = zip(path.keyTimes, path.gaze).map { keyTime, gaze in
            let time = keyTime * duration
            return time >= cameoArrival && time <= total + countdownLinger ? 0.07 : gaze
        }
        return path
    }

    static func arrive(on track: NotchMascotTrack) -> NotchMascotPath {
        guard track.hidden == nil else { return home(on: track) }
        var path = sample([.stay(0.06), .hop(to: track.rest, 0.46, height: track.hop(0.3))],
                          start: -track.size, track: track, duration: homeDuration)
        path.greeting = 0...0.52
        return path
    }

    static func cross(on track: NotchMascotTrack) -> NotchMascotPath {
        guard let hidden = track.hidden else { return home(on: track) }
        let size = track.size
        var path = sample([.stay(0.06),
                           .hop(to: hidden.upperBound - size / 2 - 2 * track.scale, 0.34, height: track.hop(0.24)),
                           .walk(to: track.behindCamera(hidden, margin: 2), 0.38),
                           .hop(to: track.rest, 0.36, height: track.hop(0.24)), .stay(0.1)],
                          start: track.farSpot, track: track, duration: crossDuration)
        path.greeting = 0.72...crossDuration
        return path
    }

    static func farewell(on track: NotchMascotTrack) -> NotchMascotPath {
        let size = track.size
        guard let hidden = track.hidden else {
            var path = sample([.stay(0.06), .hop(to: track.rest, 0.3, height: track.hop(0.22)), .stay(0.02),
                               .walk(to: track.width + size, 0.4)],
                              start: track.rest, track: track, duration: farewellDuration)
            path.greeting = 0...0.44
            return path
        }
        var path = sample([.stay(0.06), .hop(to: track.rest, 0.3, height: track.hop(0.22)), .stay(0.08),
                           .hop(to: track.behindCamera(hidden, margin: 1), cameoExit, height: track.hop(0.16))],
                          start: track.rest, track: track, duration: farewellDuration)
        path.greeting = 0...0.48
        return path
    }

    static func retreat(on track: NotchMascotTrack) -> NotchMascotPath {
        guard let hidden = track.hidden else {
            return sample([.stay(cameoExit)], start: -track.size, track: track, duration: cameoExit)
        }
        return sample([.hop(to: track.behindCamera(hidden, margin: 1), cameoExit, height: track.hop(0.16))],
                      start: track.rest, track: track, duration: cameoExit)
    }

    private static func sample(_ steps: [Step], start: CGFloat, track: NotchMascotTrack,
                               duration: TimeInterval) -> NotchMascotPath {
        let rate: Double = 60
        var path = NotchMascotPath()
        var time: TimeInterval = 0
        var position = start
        var landing: (squash: CGFloat, time: TimeInterval) = (0, 0)
        func add(_ x: CGFloat, lift: CGFloat, squash: CGFloat, gaze: CGFloat) {
            let recovery = landing.squash * CGFloat(max(0, 1 - (time - landing.time) / 0.14))
            path.keyTimes.append(min(1, time / duration))
            path.x.append(x)
            path.lift.append(lift)
            path.squash.append(squash != 0 ? squash : recovery)
            path.gaze.append(gaze)
        }
        add(position, lift: 0, squash: 0, gaze: 0)
        for step in steps {
            switch step {
            case .jump(let target):
                position = target
                add(position, lift: 0, squash: 0, gaze: 0.05)
            case .stay(let length, let bounces):
                let frames = max(1, Int((length * rate).rounded()))
                for frame in 1...frames {
                    let share = CGFloat(frame) / CGFloat(frames)
                    time += length / Double(frames)
                    let wave = bounces > 0 ? abs(sin(share * .pi * CGFloat(bounces))) : 0
                    add(position, lift: wave * track.hop(0.16), squash: 0, gaze: 0)
                }
            case .hop(let target, let length, let height):
                let from = position
                let frames = max(2, Int((length * rate).rounded()))
                let direction: CGFloat = target >= from ? 1 : -1
                for frame in 1...frames {
                    let share = CGFloat(frame) / CGFloat(frames)
                    time += length / Double(frames)
                    let eased = share * share * (3 - 2 * share)
                    let squash: CGFloat = share < 0.2 ? -0.12 * (1 - share / 0.2) : share > 0.88 ? 0.14 * (share - 0.88) / 0.12 : 0
                    add(from + (target - from) * eased, lift: height * 4 * share * (1 - share),
                        squash: squash, gaze: 0.05 * direction)
                }
                position = target
                landing = (0.14, time)
            case .walk(let target, let length):
                let from = position
                let frames = max(2, Int((length * rate).rounded()))
                let direction: CGFloat = target >= from ? 1 : -1
                for frame in 1...frames {
                    let share = CGFloat(frame) / CGFloat(frames)
                    time += length / Double(frames)
                    let bob = abs(sin(share * .pi * 3)) * track.hop(0.06)
                    add(from + (target - from) * share, lift: bob, squash: 0, gaze: 0.05 * direction)
                }
                position = target
            }
        }
        if time < duration {
            time = duration
            add(position, lift: 0, squash: 0, gaze: 0)
        } else if let last = path.keyTimes.indices.last {
            path.keyTimes[last] = 1
        }
        path.duration = duration
        return path
    }
}

enum NotchMascotSupport {
    static let welcomeDelay: TimeInterval = 1.5
    static let grooveInterval: TimeInterval = 600
    static let grooveDelay: TimeInterval = 1.2
    static let agentStartInterval: TimeInterval = 600

    static let hideDelay: TimeInterval = 30
    static let hideRetry: TimeInterval = 3
    static let hideAway = NotchMascotVisit.Kind.linger(.yawn)

    static func timerReaction(finishing phase: NotchTimerPhase) -> NotchMascotReaction {
        switch phase {
        case .focus: return .celebrate
        case .shortBreak, .longBreak: return .ready
        case .timer, .stopwatch: return .surprised
        }
    }

    static func powerReaction(pluggedIn: Bool, charged: Bool, low: Bool) -> NotchMascotReaction? {
        pluggedIn ? .love : charged ? .celebrate : low ? .yawn : nil
    }

    static func eventBegan(from before: NotchCalendarCountdown?, to after: NotchCalendarCountdown?,
                           at now: Date) -> Bool {
        guard let before, !before.ongoing else { return false }
        let since = now.timeIntervalSince(before.event.start)
        guard since >= -2, since < 60 else { return false }
        guard let after else { return true }
        return after.event.id != before.event.id || after.ongoing
    }
    static let greetings: [NotchMascotMood] = [.happy, .wink, .love]

    static func blinkInterval(lowPower: Bool) -> ClosedRange<TimeInterval> {
        lowPower ? 5.2...12.8 : 2.6...6.4
    }

    static let glanceChance = 0.25

    static func blinksBeforeSleep(hour: Int) -> Int {
        hour >= 22 || hour < 6 ? 12 : 36
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        AppFeature.notchMascot.isAvailable(in: defaults) && NotchSupport.isEnabled(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchMascotEnabled)
    }

    static func visits(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchMascotVisits)
    }

    static func reacts(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchMascotReactions)
    }

    static func hidesWhenIdle(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchMascotHidesWhenIdle)
    }

    static func visitFrequency(in defaults: UserDefaults = .standard) -> NotchMascotVisitFrequency {
        NotchMascotVisitFrequency(rawValue: defaults.string(forKey: DefaultsKey.notchMascotVisitFrequency) ?? "") ?? .normal
    }

    static func side(in defaults: UserDefaults = .standard) -> NotchMascotSide {
        NotchMascotSide(rawValue: defaults.string(forKey: DefaultsKey.notchMascotSide) ?? "") ?? .left
    }

    static func look(in defaults: UserDefaults = .standard) -> NotchMascotLook {
        NotchMascotLook(
            style: NotchMascotStyle(rawValue: defaults.string(forKey: DefaultsKey.notchMascotStyle) ?? "") ?? .minimal,
            shape: NotchMascotShape(rawValue: defaults.string(forKey: DefaultsKey.notchMascotShape) ?? "") ?? .ball,
            palette: NotchMascotPalette(rawValue: defaults.string(forKey: DefaultsKey.notchMascotPalette) ?? "") ?? .pearl)
    }

    static func commandBarStyle(in defaults: UserDefaults = .standard) -> NotchCommandBarStyle? {
        guard isEnabled(in: defaults), AppFeature.commandBar.isAvailable(in: defaults),
              defaults.bool(forKey: DefaultsKey.notchCommandBar) else { return nil }
        return NotchCommandBarStyle(rawValue: defaults.string(forKey: DefaultsKey.notchCommandBarStyle) ?? "") ?? .droplet
    }

    static func commandBarMood(query: String, hasResults: Bool, searching: Bool) -> NotchMascotMood {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .idle }
        if searching { return .thinking }
        return hasResults ? .idle : .confused
    }

    static func celebrates(from old: NotchMascotMood, to new: NotchMascotMood, query: String,
                           hasResults: Bool) -> Bool {
        (old == .thinking || old == .confused) && new == .idle && hasResults
            && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func readingGaze(for query: String) -> CGPoint? {
        guard !query.isEmpty else { return nil }
        return CGPoint(x: 0.07 + 0.04 * min(1, CGFloat(query.count) / 28), y: 0.01)
    }

    static func pointerGaze(from center: CGPoint, to pointer: CGPoint, size: CGFloat) -> CGPoint {
        guard size > 0 else { return .zero }
        let dx = (pointer.x - center.x) / (size * 3), dy = (pointer.y - center.y) / (size * 2)
        return CGPoint(x: max(-1, min(1, dx)) * 0.08, y: max(-1, min(1, dy)) * 0.05)
    }

    static func nextVisitDelay(_ frequency: NotchMascotVisitFrequency = visitFrequency(),
                               random: Double = Double.random(in: 0...1)) -> TimeInterval {
        let range = frequency.delay
        return range.lowerBound + (range.upperBound - range.lowerBound) * min(1, max(0, random))
    }

    static func greeting(random: Double = Double.random(in: 0..<1)) -> NotchMascotMood {
        greetings[min(greetings.count - 1, max(0, Int(random * Double(greetings.count))))]
    }

    static func size(stripHeight: CGFloat, floats: Bool) -> CGFloat {
        floats ? max(10, min(18, stripHeight - 6)) : max(12, min(20, stripHeight - 12))
    }

    static func track(stripWidth: CGFloat, stripHeight: CGFloat, wing: CGFloat,
                      cameraWidth: CGFloat, floats: Bool, bodyHeight: CGFloat,
                      side: NotchMascotSide = .left) -> NotchMascotTrack {
        if floats {
            let size = self.size(stripHeight: bodyHeight, floats: true)
            return NotchMascotTrack(width: stripWidth, height: stripHeight, size: size, rest: stripWidth / 2,
                                    hidden: nil, baseline: stripHeight / 2,
                                    ceiling: max(0, (stripHeight - bodyHeight) / 2))
        }
        let size = self.size(stripHeight: stripHeight, floats: false)
        let gap = max(4, min(8, wing - size - 6))
        let rest = max(size / 2, wing - gap - size / 2)
        return NotchMascotTrack(width: stripWidth, height: stripHeight, size: size,
                                rest: side == .right ? stripWidth - rest : rest,
                                hidden: wing...(wing + cameraWidth), baseline: stripHeight / 2 + 0.5,
                                mirrored: side == .right)
    }

    static let wingRoom: CGFloat = 10

    static let noticeSize: CGFloat = 18

    static func track(overActivity strip: NotchGeometry, size: CGSize,
                      side: NotchMascotSide = .left) -> NotchMascotTrack? {
        if strip.floats {
            return track(stripWidth: size.width, stripHeight: strip.stripHeight, wing: 0, cameraWidth: 0,
                         floats: true, bodyHeight: strip.stripBodyHeight)
        }
        guard !strip.compactActivityUsesFooter else { return nil }
        let wing = strip.compactActivityWingWidth
        guard wing >= self.size(stripHeight: strip.stripHeight, floats: false) + wingRoom else { return nil }
        return track(stripWidth: strip.compactActivitySize.width, stripHeight: strip.stripHeight, wing: wing,
                     cameraWidth: strip.compactActivityCameraGap, floats: false, bodyHeight: strip.stripBodyHeight,
                     side: side)
    }
}
