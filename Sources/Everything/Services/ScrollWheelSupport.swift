// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

enum ScrollHorizontalModifier: String, CaseIterable {
    case shift, option, control, command

    init(storageValue: String?) {
        self = storageValue.flatMap(Self.init(rawValue:)) ?? .shift
    }

    var flag: CGEventFlags {
        switch self {
        case .shift: return .maskShift
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .command: return .maskCommand
        }
    }
}

enum ScrollZoomModifier: String, CaseIterable {
    case none, option, control, command

    init(storageValue: String?) {
        self = storageValue.flatMap(Self.init(rawValue:)) ?? .none
    }

    var modifier: ScrollHorizontalModifier? {
        ScrollHorizontalModifier(rawValue: rawValue)
    }
}

enum ScrollWheelAxis {
    case vertical, horizontal
}

struct ScrollZoomAction {
    let axis: ScrollWheelAxis
    let modifier: ScrollHorizontalModifier
    let delta: Double
}

struct ScrollZoomPreferences: Equatable {
    let pinchZoom: ScrollHorizontalModifier?

    var isEnabled: Bool {
        pinchZoom != nil
    }

    init(isAvailable: Bool, boolFor: (String) -> Bool, stringFor: (String) -> String?) {
        func modifier(_ enabled: String, _ key: String) -> ScrollHorizontalModifier? {
            isAvailable && boolFor(enabled) ? ScrollZoomModifier(storageValue: stringFor(key)).modifier : nil
        }
        pinchZoom = modifier(DefaultsKey.pinchZoomEnabled, DefaultsKey.pinchZoomModifier)
    }

    func action(for event: CGEvent) -> ScrollZoomAction? {
        guard let modifier = pinchZoom else { return nil }
        for axis in [ScrollWheelAxis.vertical, .horizontal] {
            if let delta = ScrollWheelSupport.zoomDelta(event, modifier: modifier, axis: axis) {
                return ScrollZoomAction(axis: axis, modifier: modifier, delta: delta)
            }
        }
        return nil
    }
}

struct ScrollZoomGestureState {
    private(set) var preferences: ScrollZoomPreferences?
    private(set) var pinchModifier: ScrollHorizontalModifier?
    private(set) var pinchLocation: CGPoint?
    private var acceptsEvents = false

    mutating func update(_ preferences: ScrollZoomPreferences) -> Bool {
        guard self.preferences != preferences else { return false }
        self.preferences = preferences
        acceptsEvents = false
        return endPinch()
    }

    mutating func start() { acceptsEvents = preferences?.isEnabled == true }

    mutating func stop() -> Bool {
        acceptsEvents = false
        preferences = nil
        return endPinch()
    }

    func accepts(_ preferences: ScrollZoomPreferences) -> Bool {
        acceptsEvents && self.preferences == preferences
    }

    mutating func beginPinch(_ modifier: ScrollHorizontalModifier, at point: CGPoint) -> (endPrevious: Bool, begin: Bool) {
        let changed = pinchModifier != modifier || pinchLocation != point
        let endPrevious = changed && pinchModifier != nil
        pinchModifier = modifier
        pinchLocation = point
        return (endPrevious, changed)
    }

    mutating func endPinch() -> Bool {
        guard pinchModifier != nil else { return false }
        pinchModifier = nil
        pinchLocation = nil
        return true
    }
}

struct ScrollDirectionPreferences {
    let invertVertical: Bool
    let invertHorizontal: Bool
    let horizontalModifier: ScrollHorizontalModifier?
    let zoom: ScrollZoomPreferences

    var isEnabled: Bool {
        invertVertical || invertHorizontal || horizontalModifier != nil || zoom.isEnabled
    }

    init(isAvailable: (AppFeature) -> Bool,
         boolFor: (String) -> Bool,
         stringFor: (String) -> String?) {
        invertVertical = isAvailable(.scrollInverter) && boolFor(DefaultsKey.scrollInverterEnabled)
        invertHorizontal = isAvailable(.scrollInverter) && boolFor(DefaultsKey.scrollInverterHorizontalEnabled)
        horizontalModifier = isAvailable(.scrollHorizontal) && boolFor(DefaultsKey.scrollHorizontalEnabled)
            ? ScrollHorizontalModifier(storageValue: stringFor(DefaultsKey.scrollHorizontalModifier)) : nil
        zoom = ScrollZoomPreferences(isAvailable: isAvailable(.scrollZoom),
                                     boolFor: boolFor, stringFor: stringFor)
    }

    init(defaults: UserDefaults = .standard) {
        self.init(isAvailable: { defaults.bool(forKey: $0.availabilityKey) },
                  boolFor: { defaults.bool(forKey: $0) },
                  stringFor: { defaults.string(forKey: $0) })
    }
}

struct ScrollWheelEventTraits: Equatable {
    let isContinuous: Bool
    let momentumPhase: Int64
    let scrollPhase: Int64
    let scrollCount: Int64
}

struct ScrollWheelInversionPlan: Equatable {
    let vertical: Bool
    let horizontal: Bool
}

struct ScrollWheelAxisDelta: Equatable {
    var line: Int64
    var point: Int64
    var fixedPoint: Double

    var hasMovement: Bool { line != 0 || point != 0 || fixedPoint != 0 }
}

enum ScrollWheelSupport {
    static let tapLocation: CGEventTapLocation = .cgAnnotatedSessionEventTap

    static let touchGestureGraceSeconds: TimeInterval = 1.0

    static let syntheticTag: Int64 = 0x564F5253
    static let horizontalRedirectTag: Int64 = 0x564F5248

    static let pointsPerLine: Double = 10

    @discardableResult
    static func redirectVerticalScroll(_ event: CGEvent, modifier: ScrollHorizontalModifier,
                                       targetsOwnWindow: @autoclosure () -> Bool = false) -> Bool {
        let shortcutFlags: CGEventFlags = [.maskShift, .maskAlternate, .maskControl, .maskCommand]
        guard event.flags.intersection(shortcutFlags) == modifier.flag else { return false }

        guard isVerticalOnly(event) else { return false }
        guard !targetsOwnWindow() else { return false }

        moveVerticalToHorizontal(event)
        event.flags.remove(modifier.flag)
        event.setIntegerValueField(.eventSourceUserData, value: horizontalRedirectTag)
        return true
    }

    static func isVerticalOnly(_ event: CGEvent) -> Bool {
        (event.getIntegerValueField(.scrollWheelEventDeltaAxis1) != 0
            || event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) != 0
            || event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) != 0)
            && event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 0
            && event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == 0
            && event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) == 0
    }

    static func zoomDelta(_ event: CGEvent, modifier: ScrollHorizontalModifier,
                          axis: ScrollWheelAxis) -> Double? {
        let shortcutFlags: CGEventFlags = [.maskShift, .maskAlternate, .maskControl, .maskCommand]
        guard event.flags.intersection(shortcutFlags) == modifier.flag else { return nil }
        let fields: (CGEventField, CGEventField, CGEventField) = axis == .vertical
            ? (.scrollWheelEventDeltaAxis1, .scrollWheelEventPointDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1)
            : (.scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2)
        let line = event.getIntegerValueField(fields.0)
        let point = event.getDoubleValueField(fields.1)
        let fixed = event.getDoubleValueField(fields.2)
        return zoomDelta(point: point, fixed: fixed, line: line)
    }

    static func zoomDelta(point: Double, fixed: Double, line: Int64) -> Double? {
        if point != 0 { return point }
        if fixed != 0 { return fixed }
        return line == 0 ? nil : Double(line)
    }

    static func zoomDelta(_ delta: Double, axis: ScrollWheelAxis,
                          invertVertical: Bool, invertHorizontal: Bool) -> Double {
        switch axis {
        case .vertical: return invertVertical ? -delta : delta
        case .horizontal: return invertHorizontal ? -delta : delta
        }
    }

    static func moveVerticalToHorizontal(_ event: CGEvent) {
        let line = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let point = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let fixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: line)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixed)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: point)
    }

    static func wheelMovesStripSideways(stripScrollsHorizontally: Bool, stripScrollsVertically: Bool,
                                        enclosingScrollsVertically: Bool) -> Bool {
        stripScrollsHorizontally && !stripScrollsVertically && !enclosingScrollsVertically
    }

    static func applyDirection(to event: CGEvent, isContinuous: Bool,
                               invertVertical: Bool, invertHorizontal: Bool,
                               horizontalModifier: ScrollHorizontalModifier?,
                               targetsOwnWindow: @autoclosure () -> Bool = false) {
        let redirected = event.getIntegerValueField(.eventSourceUserData) == horizontalRedirectTag
            || (horizontalModifier.map {
                redirectVerticalScroll(event, modifier: $0, targetsOwnWindow: targetsOwnWindow())
            } ?? false)
        let verticalLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let verticalPoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let verticalFixedPoint = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let horizontalLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let horizontalPoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let horizontalFixedPoint = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        let hasVerticalMovement = verticalLine != 0 || verticalPoint != 0 || verticalFixedPoint != 0
        let hasHorizontalMovement = horizontalLine != 0
            || horizontalPoint != 0
            || horizontalFixedPoint != 0
        let plan = ScrollWheelSupport.inversionPlan(
            hasVerticalMovement: hasVerticalMovement,
            hasHorizontalMovement: hasHorizontalMovement,
            shiftRedirectsVertical: !isContinuous && event.flags.contains(.maskShift),
            invertVertical: invertVertical,
            invertHorizontal: invertHorizontal
        )
        if plan.vertical {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -verticalLine)
            if isContinuous || redirected || verticalLine == 0 {
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -verticalPoint)
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -verticalFixedPoint)
            }
        }
        if plan.horizontal {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -horizontalLine)
            if isContinuous || redirected || horizontalLine == 0 {
                event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -horizontalPoint)
                event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -horizontalFixedPoint)
            }
        }
    }

    static func targetsOwnWindow(in windows: [[String: Any]], at point: CGPoint,
                                 ownProcessID: Int32,
                                 clickThroughWindowIDs: Set<CGWindowID>) -> Bool {
        ScrollWheelTargetCache.windows(in: windows, ownProcessID: ownProcessID,
            clickThroughWindowIDs: clickThroughWindowIDs).first { $0.frame.contains(point) }?.isOwn ?? false
    }

    static func isMouseWheel(_ traits: ScrollWheelEventTraits,
                             secondsSinceLastGesturePhase: TimeInterval?) -> Bool {
        if !traits.isContinuous {
            return true
        }
        guard traits.momentumPhase == 0, traits.scrollPhase == 0 else {
            return false
        }
        if traits.scrollCount != 0,
           let elapsed = secondsSinceLastGesturePhase,
           elapsed <= touchGestureGraceSeconds {
            return false
        }
        return true
    }

    static func inversionPlan(hasVerticalMovement: Bool,
                              hasHorizontalMovement: Bool,
                              shiftRedirectsVertical: Bool,
                              invertVertical: Bool,
                              invertHorizontal: Bool) -> ScrollWheelInversionPlan {
        let shiftRedirectsVertically = shiftRedirectsVertical
            && hasVerticalMovement
            && !hasHorizontalMovement
        return ScrollWheelInversionPlan(
            vertical: hasVerticalMovement
                && (shiftRedirectsVertically ? invertHorizontal : invertVertical),
            horizontal: hasHorizontalMovement && invertHorizontal
        )
    }
}

// MARK: - Linear scrolling

extension ScrollWheelSupport {
    static let linesPerNotchRange = 1...10
    static let defaultLinesPerNotch = 3

    static func linearLinesPerNotch(defaults: UserDefaults, isAvailable: Bool,
                                    isExcepted: () -> Bool) -> Int? {
        guard isAvailable, defaults.bool(forKey: DefaultsKey.linearScrollEnabled), !isExcepted() else {
            return nil
        }
        return sanitizedLinesPerNotch(defaults.integer(forKey: DefaultsKey.linearScrollLines))
    }

    static func sanitizedLinesPerNotch(_ value: Int) -> Int {
        guard value != 0 else { return defaultLinesPerNotch }
        return min(max(value, linesPerNotchRange.lowerBound), linesPerNotchRange.upperBound)
    }

    static func discreteTicks(line: Int64, fixedPoint: Double, point: Int64) -> Double {
        if line != 0 { return line > 0 ? 1 : -1 }
        if fixedPoint.isFinite, fixedPoint != 0 { return fixedPoint }
        return Double(point) / pointsPerLine
    }

    static func continuousTicks(fixedPointDelta: Double, pointDelta: Double) -> Double {
        guard fixedPointDelta.isFinite, pointDelta.isFinite else { return 0 }
        return pointDelta != 0 ? pointDelta / pointsPerLine : fixedPointDelta
    }

    static func linearLines(ticks: Double, linesPerNotch: Int) -> Double {
        guard ticks.isFinite, ticks != 0 else { return 0 }
        let lines = min(abs(ticks), 1) * Double(sanitizedLinesPerNotch(linesPerNotch))
        return ticks < 0 ? -lines : lines
    }

    static func linearDelta(_ delta: ScrollWheelAxisDelta,
                            isContinuous: Bool,
                            linesPerNotch: Int,
                            carry: Double) -> (delta: ScrollWheelAxisDelta, carry: Double) {
        let ticks = isContinuous
            ? continuousTicks(fixedPointDelta: delta.fixedPoint, pointDelta: Double(delta.point))
            : discreteTicks(line: delta.line, fixedPoint: delta.fixedPoint, point: delta.point)
        let lines = linearLines(ticks: ticks, linesPerNotch: linesPerNotch)
        let kept = SmoothScrollSupport.carry(carry, continuing: lines)
        if isContinuous {
            let points = SmoothScrollSupport.wholePixels(lines * pointsPerLine,
                                                         carry: kept * pointsPerLine)
            let wholeLines = points.pixels / pointsPerLine
            return (ScrollWheelAxisDelta(line: Int64(wholeLines.rounded(.towardZero)),
                                         point: Int64(points.pixels),
                                         fixedPoint: wholeLines),
                    points.carry / pointsPerLine)
        }
        let wholeLines = SmoothScrollSupport.wholePixels(lines, carry: kept)
        return (ScrollWheelAxisDelta(line: Int64(wholeLines.pixels), point: 0, fixedPoint: 0),
                wholeLines.carry)
    }

    static func writeLinear(vertical: ScrollWheelAxisDelta?, horizontal: ScrollWheelAxisDelta?,
                            to event: CGEvent, isContinuous: Bool) {
        if let vertical { event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: vertical.line) }
        if let horizontal { event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: horizontal.line) }
        guard isContinuous else { return }
        if let vertical {
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: vertical.point)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: vertical.fixedPoint)
        }
        if let horizontal {
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: horizontal.point)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: horizontal.fixedPoint)
        }
    }
}

// MARK: - HID stage

struct ScrollWheelHIDStageLedger {
    static let capacity = 256
    static let tolerance: UInt64 = 1_000

    var isWatching = false
    private var timestamps = [UInt64](repeating: 0, count: capacity)
    private var next = 0

    mutating func note(_ raw: UInt64, nowTicks: UInt64 = mach_absolute_time(),
                       timebase: EventTimestamp.Timebase = EventTimestamp.machTimebase) {
        timestamps[next] = EventTimestamp.nanoseconds(raw: raw, nowTicks: nowTicks, timebase: timebase)
        next = (next + 1) % Self.capacity
    }

    func passed(_ raw: UInt64, sourceProcessID: Int64, nowTicks: UInt64 = mach_absolute_time(),
                timebase: EventTimestamp.Timebase = EventTimestamp.machTimebase) -> Bool {
        guard isWatching else { return true }
        guard sourceProcessID != 0 else { return true }
        guard raw != 0 else { return false }
        let nanoseconds = EventTimestamp.nanoseconds(raw: raw, nowTicks: nowTicks, timebase: timebase)
        return timestamps.contains { noted in
            noted != 0 && (noted >= nanoseconds ? noted - nanoseconds : nanoseconds - noted) <= Self.tolerance
        }
    }

    mutating func reset() {
        isWatching = false
        timestamps = [UInt64](repeating: 0, count: Self.capacity)
        next = 0
    }
}

final class ScrollWheelTargetCache {
    private static let resolveLifetime: TimeInterval = 0.5

    struct OwnWindow: Equatable {
        let id: CGWindowID
        var frame: CGRect
        var visible: Bool
        var alpha: Double
        var ignoresMouseEvents: Bool
        var level: Int
    }

    struct Window {
        let frame: CGRect
        let isOwn: Bool
    }

    private struct Snapshot {
        let windows: [Window]
        let target: Int?
        let point: CGPoint
        let resolvedAt: TimeInterval

        func holds(_ point: CGPoint, now: TimeInterval) -> Bool {
            guard now >= resolvedAt, now - resolvedAt < ScrollWheelTargetCache.resolveLifetime else { return false }
            if point == self.point { return true }
            guard target != nil else { return false }
            return windows.firstIndex { $0.frame.contains(point) } == target
        }

        var isOwn: Bool { target.map { windows[$0].isOwn } ?? false }
    }

    private let lock = NSLock()
    private let ownProcessID: Int32
    private let now: () -> TimeInterval
    private let lookup: () -> [[String: Any]]
    private var enabled = false
    private var generation: UInt64 = 0
    private var ownWindows: [OwnWindow] = []
    private var orderedWindowIDs: [CGWindowID] = []
    private var snapshot: Snapshot?

    var clickThroughWindowIDs: Set<CGWindowID> {
        lock.withLock { Set(ownWindows.filter(\.ignoresMouseEvents).map(\.id)) }
    }

    init(ownProcessID: Int32, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         lookup: @escaping () -> [[String: Any]] = WindowServerSupport.onScreenWindowInfo) {
        self.ownProcessID = ownProcessID
        self.now = now
        self.lookup = lookup
    }

    func setEnabled(_ enabled: Bool) {
        lock.withLock {
            guard self.enabled != enabled else { return }
            self.enabled = enabled
            generation &+= 1
            snapshot = nil
            if !enabled {
                ownWindows = []
                orderedWindowIDs = []
            }
        }
    }

    func update(ownWindows: [OwnWindow], orderedWindowIDs: [CGWindowID]) {
        lock.withLock {
            guard enabled, self.ownWindows != ownWindows || self.orderedWindowIDs != orderedWindowIDs else { return }
            self.ownWindows = ownWindows
            self.orderedWindowIDs = orderedWindowIDs
            generation &+= 1
            snapshot = nil
        }
    }

    func contains(_ point: CGPoint) -> Bool {
        for _ in 0..<2 {
            let time = now()
            let state = lock.withLock { () -> (answer: Bool?, generation: UInt64, clickThrough: Set<CGWindowID>) in
                guard enabled else { return (false, generation, []) }
                if let snapshot, snapshot.holds(point, now: time) { return (snapshot.isOwn, generation, []) }
                return (nil, generation, Set(ownWindows.filter(\.ignoresMouseEvents).map(\.id)))
            }
            if let answer = state.answer { return answer }
            let windows = Self.windows(in: lookup(), ownProcessID: ownProcessID,
                                       clickThroughWindowIDs: state.clickThrough)
            let resolved = Snapshot(windows: windows, target: windows.firstIndex { $0.frame.contains(point) },
                                    point: point, resolvedAt: time)
            let answer = lock.withLock { () -> Bool? in
                guard enabled else { return false }
                guard generation == state.generation else { return nil }
                snapshot = resolved
                return resolved.isOwn
            }
            if let answer { return answer }
        }
        return true
    }

    static func windows(in windows: [[String: Any]], ownProcessID: Int32,
                        clickThroughWindowIDs: Set<CGWindowID>) -> [Window] {
        windows.compactMap { window in
            guard let frame = WindowServerSupport.bounds(from: window),
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0 else { return nil }
            let isOwn = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == ownProcessID
            if isOwn, let number = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
               clickThroughWindowIDs.contains(number) { return nil }
            return Window(frame: frame, isOwn: isOwn)
        }
    }
}
