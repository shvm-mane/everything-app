// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchActivityStrings {
    let timer: String
    let timerDescription: String
    let pomodoro: String
    let stopwatch: String
    let focus: String
    let shortBreak: String
    let longBreak: String
    let pomodoroHint: String
    let totalSessions: String
    let longBreakInterval: String
    let sessionProgress: String
    let pomodoroFinished: String
    let minutes: String
    let start: String
    let resume: String
    let finished: String
    let soundEnabled: String
    let hideTimerCountdown: String
    let camera: String
    let cameraUnavailable: String
    let cameraHint: String
    let startCamera: String
    let stopCamera: String
    let accessories: String
    let accessoryDescription: String
    let connected: String
    let lowBattery: String
    let keepAwakeActivity: String
    let keepAwakeActivityHint: String

    func phase(_ phase: NotchTimerPhase) -> String {
        switch phase {
        case .timer: return timer
        case .stopwatch: return stopwatch
        case .focus: return focus
        case .shortBreak: return shortBreak
        case .longBreak: return longBreak
        }
    }
}

extension FeatureStrings {
    static func notchActivities(_ language: AppLanguage) -> NotchActivityStrings {
        switch language {
        case .enUS: return NotchActivityStrings(
            timer: "Timer",
            timerDescription: "Timers, a stopwatch and focused work sessions in the Dynamic Island.",
            pomodoro: "Pomodoro",
            stopwatch: "Stopwatch",
            focus: "Focus",
            shortBreak: "Short break",
            longBreak: "Long break",
            pomodoroHint: "Start each phase when you are ready. The cycle ends after the last focus session.",
            totalSessions: "Total sessions",
            longBreakInterval: "Sessions between long breaks",
            sessionProgress: "Session %d of %d",
            pomodoroFinished: "Pomodoro complete",
            minutes: "Minutes",
            start: "Start",
            resume: "Resume",
            finished: "Time is up",
            soundEnabled: "Play sound when time is up",
            hideTimerCountdown: "Hide timer countdown",
            camera: "Camera mirror",
            cameraUnavailable: "The camera could not start. Try opening it again.",
            cameraHint: "Open a live mirror here. The camera stops when you leave this view.",
            startCamera: "Open camera",
            stopCamera: "Stop camera",
            accessories: "Accessory alerts",
            accessoryDescription: "Show connected accessories and warn once when their battery falls to 20%.",
            connected: "Connected",
            lowBattery: "Low battery",
            keepAwakeActivity: "Show “Keep awake” in the closed island",
            keepAwakeActivityHint: "A running session appears beside the camera with the time it has left, or ∞ when it has no end.")
        }
    }
}
