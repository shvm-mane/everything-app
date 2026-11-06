// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

enum NotchTimerMode: String, CaseIterable { case timer, pomodoro, stopwatch }
enum NotchTimerPhase: String { case timer, focus, shortBreak, longBreak, stopwatch }

enum NotchTimerRulerScale {
    static let spacing = 14.0

    static func moving(_ value: Double, by points: Double) -> Double {
        guard value.isFinite, points.isFinite else { return 1 }
        return min(180, max(1, value - points / spacing))
    }

    static func minute(_ value: Double) -> Int {
        Int(moving(value, by: 0).rounded())
    }

    static func offset(of minute: Int, selected: Int) -> Double {
        (Double(minute) - Double(selected)) * spacing
    }

    static func selectionX(selected: Int, width: Double) -> Double {
        guard width.isFinite, width > 0 else { return 0 }
        let inset = min(24, width / 2)
        let selected = min(180, max(1, selected))
        let leading = Double(selected - 1) * spacing
        let trailing = Double(180 - selected) * spacing
        if leading + trailing <= width - 2 * inset {
            return (width - leading - trailing) / 2 + leading
        }
        return min(inset + leading, max(width / 2, width - inset - trailing))
    }

    static func label(for minute: Int) -> String {
        minute >= 60 ? NotchTimerSupport.hoursText(hours: minute / 60, minutes: minute % 60) : String(minute)
    }
}

struct NotchPomodoroConfiguration: Equatable {
    static let focusRange = 1...180
    static let breakRange = 1...60
    static let sessionRange = 1...24
    let focusMinutes: Int
    let shortBreakMinutes: Int
    let longBreakMinutes: Int
    let longBreakInterval: Int
    let totalSessions: Int

    init(focusMinutes: Int = 25, shortBreakMinutes: Int = 5, longBreakMinutes: Int = 15,
         longBreakInterval: Int = 4, totalSessions: Int = 4) {
        self.focusMinutes = min(Self.focusRange.upperBound, max(Self.focusRange.lowerBound, focusMinutes))
        self.shortBreakMinutes = min(Self.breakRange.upperBound, max(Self.breakRange.lowerBound, shortBreakMinutes))
        self.longBreakMinutes = min(Self.breakRange.upperBound, max(Self.breakRange.lowerBound, longBreakMinutes))
        self.longBreakInterval = min(Self.sessionRange.upperBound, max(Self.sessionRange.lowerBound, longBreakInterval))
        self.totalSessions = min(Self.sessionRange.upperBound, max(Self.sessionRange.lowerBound, totalSessions))
    }

    static func load(in defaults: UserDefaults = .standard) -> Self {
        Self(focusMinutes: defaults.object(forKey: DefaultsKey.notchPomodoroFocusMinutes) as? Int ?? 25,
             shortBreakMinutes: defaults.object(forKey: DefaultsKey.notchPomodoroShortBreakMinutes) as? Int ?? 5,
             longBreakMinutes: defaults.object(forKey: DefaultsKey.notchPomodoroLongBreakMinutes) as? Int ?? 15,
             longBreakInterval: defaults.object(forKey: DefaultsKey.notchPomodoroLongBreakInterval) as? Int ?? 4,
             totalSessions: defaults.object(forKey: DefaultsKey.notchPomodoroTotalSessions) as? Int ?? 4)
    }
}

struct NotchTimerSession: Equatable {
    private(set) var mode: NotchTimerMode = .timer
    private(set) var phase: NotchTimerPhase = .timer
    private(set) var duration: TimeInterval = 300
    private(set) var anchor: TimeInterval?
    private(set) var pausedReading: TimeInterval?
    private(set) var completed = false
    private(set) var completedFocuses = 0
    private(set) var configuration = NotchPomodoroConfiguration()

    var countsUp: Bool { mode == .stopwatch }
    var isRunning: Bool { anchor != nil }
    var isPaused: Bool { pausedReading != nil }
    var hasSession: Bool { isRunning || isPaused || completed }
    var deadline: TimeInterval? { countsUp ? nil : anchor }
    var cycleFinished: Bool { mode == .pomodoro && completed && completedFocuses >= configuration.totalSessions }
    var canStartNext: Bool { mode == .pomodoro && completed && !cycleFinished }
    var sessionNumber: Int {
        min(configuration.totalSessions, completedFocuses + (phase == .focus && !completed ? 1 : 0))
    }

    func reading(at now: TimeInterval) -> TimeInterval {
        if let anchor { return max(0, countsUp ? now - anchor : anchor - now) }
        return pausedReading ?? (completed || countsUp ? 0 : duration)
    }

    mutating func start(mode: NotchTimerMode, minutes: Int, now: TimeInterval,
                        configuration: NotchPomodoroConfiguration = NotchPomodoroConfiguration()) {
        guard !hasSession, now.isFinite else { return }
        self.mode = mode
        self.configuration = configuration
        completedFocuses = 0
        switch mode {
        case .timer:
            phase = .timer
            duration = Double(NotchTimerSupport.timerMinutes(minutes)) * 60
            anchor = now + duration
        case .pomodoro:
            phase = .focus
            duration = Double(configuration.focusMinutes) * 60
            anchor = now + duration
        case .stopwatch:
            phase = .stopwatch
            duration = 0
            anchor = now
        }
    }

    @discardableResult mutating func finishIfDue(at now: TimeInterval) -> Bool {
        guard let deadline, now.isFinite, now >= deadline else { return false }
        anchor = nil
        pausedReading = nil
        completed = true
        if phase == .focus { completedFocuses += 1 }
        return true
    }

    mutating func pause(at now: TimeInterval) {
        guard isRunning, now.isFinite else { return }
        if finishIfDue(at: now) { return }
        pausedReading = reading(at: now)
        anchor = nil
    }

    mutating func resume(at now: TimeInterval) {
        guard let reading = pausedReading, now.isFinite else { return }
        pausedReading = nil
        anchor = countsUp ? now - reading : now + reading
    }

    var nextPhase: NotchTimerPhase {
        phase == .focus ? (completedFocuses.isMultiple(of: configuration.longBreakInterval) ? .longBreak : .shortBreak) : .focus
    }

    mutating func startNext(at now: TimeInterval) {
        guard canStartNext, now.isFinite else { return }
        phase = nextPhase
        duration = Double(phase == .focus ? configuration.focusMinutes
            : phase == .longBreak ? configuration.longBreakMinutes : configuration.shortBreakMinutes) * 60
        completed = false
        anchor = now + duration
    }

    mutating func cancel() { self = Self() }
}

enum NotchTimerSupport {
    static func showsActivity(_ session: NotchTimerSession, in defaults: UserDefaults = .standard) -> Bool {
        session.hasSession && isEnabled(in: defaults)
            && (session.completed || !defaults.bool(forKey: DefaultsKey.notchHideTimerCountdown))
    }

    static func isSoundEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchTimerSoundEnabled) as? Bool ?? true
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.notchTimer.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchTimerEnabled)
            && NotchSupport.modules(in: defaults).contains(.timer)
    }

    enum ModePicker {
        static let height: CGFloat = 24
        static let spacing: CGFloat = 14
        static let labelSize: CGFloat = 12
        static let labelPadding: CGFloat = 4
        static let menuSpacing: CGFloat = 3
        static let menuMinimumScale: CGFloat = 0.7

        static func menuNamesFit(_ names: [String], in room: CGFloat) -> Bool {
            let font = NSFont.systemFont(ofSize: labelSize, weight: .medium)
            let widest = names.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
            let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))?.size.width ?? 8
            return widest * menuMinimumScale * 1.05 + menuSpacing + chevron + labelPadding * 2 <= room
        }

        static func symbol(for mode: NotchTimerMode) -> String { mode == .stopwatch ? "stopwatch" : "timer" }
    }

    enum StartButton {
        static let labelSize: CGFloat = 12
        static let padding: CGFloat = 10
    }

    static let timerLimit: TimeInterval = 180 * 60
    static let stopwatchLimit: TimeInterval = 100 * 3600 - 1

    static func timerMinutes(_ value: Int) -> Int { min(180, max(1, value)) }

    static func savedMode(in defaults: UserDefaults = .standard) -> NotchTimerMode {
        NotchTimerMode(rawValue: defaults.string(forKey: DefaultsKey.notchTimerMode) ?? "") ?? .timer
    }

    private static func wholeSeconds(_ value: TimeInterval, limit: TimeInterval,
                                     rounded rule: FloatingPointRoundingRule) -> Int {
        value.isFinite ? Int(min(limit, max(0, value)).rounded(rule)) : 0
    }

    private static func clockText(seconds: Int) -> String {
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    static func clockText(_ remaining: TimeInterval) -> String {
        clockText(seconds: wholeSeconds(remaining, limit: timerLimit, rounded: .up))
    }

    static func stopwatchText(_ elapsed: TimeInterval) -> String {
        clockText(seconds: wholeSeconds(elapsed, limit: stopwatchLimit, rounded: .down))
    }

    static func hoursText(hours: Int, minutes: Int) -> String {
        String(format: "%dh%02d", hours, minutes)
    }

    static func compactHoursText(_ remaining: TimeInterval) -> String {
        let seconds = wholeSeconds(remaining, limit: timerLimit, rounded: .down)
        return hoursText(hours: seconds / 3600, minutes: seconds / 60 % 60)
    }

    static func compactStopwatchText(_ elapsed: TimeInterval) -> String {
        let seconds = wholeSeconds(elapsed, limit: stopwatchLimit, rounded: .down)
        return seconds >= 3600 ? hoursText(hours: seconds / 3600, minutes: seconds / 60 % 60) : clockText(seconds: seconds)
    }

    static func clockText(for session: NotchTimerSession, at now: TimeInterval) -> String {
        session.countsUp ? stopwatchText(session.reading(at: now)) : clockText(session.reading(at: now))
    }

    static func rollingValue(_ value: String, everySecond: Bool) -> String {
        guard !everySecond, let colon = value.lastIndex(of: ":") else { return value }
        return String(value[..<colon])
    }

    static func compactText(for session: NotchTimerSession, at now: TimeInterval, locale: Locale) -> String {
        let reading = session.reading(at: now)
        if session.countsUp { return compactStopwatchText(reading) }
        return reading >= 3600 ? compactHoursText(reading) : compactText(reading, locale: locale)
    }

    static func secondBoundaryOffset(for session: NotchTimerSession, at now: TimeInterval) -> TimeInterval {
        let reading = session.reading(at: now)
        guard reading.isFinite else { return 0 }
        let fraction = reading.truncatingRemainder(dividingBy: 1)
        let offset = session.countsUp ? 1 - fraction : fraction
        return offset > 0 ? offset : 1
    }

    static func tickScheduleOffset(for session: NotchTimerSession, at now: TimeInterval) -> TimeInterval {
        secondBoundaryOffset(for: session, at: now) - 1
    }

    static func compactText(_ remaining: TimeInterval, locale: Locale) -> String {
        let seconds = remaining.isFinite ? ceil(min(timerLimit, max(0, remaining))) : 0
        let units: Set<Duration.UnitsFormatStyle.Unit> = seconds >= 3600
            ? [.hours, .minutes] : [seconds >= 60 ? .minutes : .seconds]
        return Duration.seconds(seconds).formatted(.units(
            allowed: units, width: .narrow,
            fractionalPart: .hide(rounded: .down)).locale(locale))
    }

    // MARK: Strip

    static let stripWingRange: ClosedRange<CGFloat> = 44...64
    static let stripCameraGap: CGFloat = 6

    static func stripTextSize(height: CGFloat) -> CGFloat { min(16, height - 6) }

    static let barMinimumWidth: CGFloat = 40

    static func readingInset(_ geometry: NotchGeometry) -> CGFloat {
        guard !geometry.compactActivityUsesFooter else { return 0 }
        let height = geometry.compactActivityContentHeight
        let text = geometry.compactActivityEdgeInset(boxHeight: stripTextSize(height: height) * 0.72, radius: 0)
        let icon = stripIconSize(height: height)
        return max(text, geometry.compactActivityEdgeInset(boxHeight: icon, radius: icon / 2)) + 4
    }
    static func stripIconSize(height: CGFloat) -> CGFloat { min(20, height - NotchLayout.compactEdgeGap * 2) }
    static func stripAgentMarkSize(height: CGFloat, working: Int) -> CGFloat {
        min(working > 1 ? 11 : 14, max(8, height - NotchLayout.compactEdgeGap * 2 - 4))
    }
}
