// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchCalendarStrings {
    let title: String
    let description: String
    let permission: String
    let allow: String
    let denied: String
    let settings: String
    let empty: String
    let next: String
    let ongoing: String
    let allDay: String
    let untitled: String
    let openCalendar: String
    let week: String
    let today: String
    let requestFailed: String
    let previousMonth: String
    let nextMonth: String
    let previousWeek: String
    let nextWeek: String
    let month: String
    let emptyDay: String
    let hasEvents: String
    let countdown: String
    let countdownHint: String
    let countdownLead: String
    let addCountdown: String
    let removeCountdown: String
    let timeLeft: String
    let timeLeftHint: String
    let weekNumbers: String
    let weekNumber: String
    let calendars: String
}

extension FeatureStrings {
    static func notchCalendar(_ language: AppLanguage) -> NotchCalendarStrings {
        switch language {
        case .enUS: return NotchCalendarStrings(
            title: "Calendar",
            description: "Browse the month and your upcoming appointments in the Dynamic Island.",
            permission: "Read your calendars to show upcoming appointments. Events stay on this Mac.",
            allow: "Allow Calendar Access",
            denied: "Allow calendar access in System Settings to see your appointments.",
            settings: "Open System Settings",
            empty: "No upcoming appointments",
            next: "Up next",
            ongoing: "Happening now",
            allDay: "All day",
            untitled: "Untitled event",
            openCalendar: "Open Calendar",
            week: "Next 7 days",
            today: "Today",
            requestFailed: "Could not request calendar access. Please try again.",
            previousMonth: "Previous month",
            nextMonth: "Next month",
            previousWeek: "Previous week",
            nextWeek: "Next week",
            month: "Month",
            emptyDay: "No appointments on this day",
            hasEvents: "Has appointments",
            countdown: "Event countdown",
            countdownHint: "Show every timed event in the closed island before it starts. To count down to only some, turn this off and right-click them on the island’s Calendar page. Titles may appear in screen captures.",
            countdownLead: "Time before event",
            addCountdown: "Add Countdown",
            removeCountdown: "Remove Countdown",
            timeLeft: "Time left in current event",
            timeLeftHint: "Show a timed event in progress in the closed island during the hour before it ends. Its title may appear in screen captures.",
            weekNumbers: "Week numbers",
            weekNumber: "Week %d",
            calendars: "Calendars shown")
        }
    }
}
