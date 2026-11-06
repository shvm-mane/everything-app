// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import EventKit

struct NotchCalendarColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    static let fallback = Self(red: 0.35, green: 0.65, blue: 1)
}

struct NotchCalendarEvent: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let calendar: String
    let start: Date
    let end: Date
    let allDay: Bool
    let location: String
    var color: NotchCalendarColor = .fallback
    var calendarItemIdentifier = ""
    var recurring = false
    var countdownKey = ""
}

struct NotchCalendarCountdown: Equatable, Sendable {
    let event: NotchCalendarEvent
    let ongoing: Bool

    var target: Date { ongoing ? event.end : event.start }

    func isShown(at now: Date, leadTime: TimeInterval) -> Bool {
        target > now && target.timeIntervalSince(now) <= (ongoing ? NotchCalendarSupport.timeLeftLeadTime : leadTime)
            && (!ongoing || event.start <= now)
    }
}

struct NotchCalendarChoice: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let sourceID: String
    let source: String
    var color: NotchCalendarColor = .fallback
}

enum NotchCalendarSupport {
    static let timeLeftLeadTime: TimeInterval = 60 * 60

    static let defaultCountdownLeadMinutes = 60
    static let countdownLeadPresets = [15, 30, 60, 120]
    static let countdownLeadRange = 5...240

    static func countdownLeadMinutes(_ minutes: Int) -> Int {
        min(countdownLeadRange.upperBound, max(countdownLeadRange.lowerBound, minutes))
    }

    static func countdownLeadTime(in defaults: UserDefaults = .standard) -> TimeInterval {
        let stored = defaults.object(forKey: DefaultsKey.notchCalendarCountdownLead) as? Int
        return TimeInterval(countdownLeadMinutes(stored ?? defaultCountdownLeadMinutes) * 60)
    }

    static func monthDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        let offset = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: month.start) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func weekDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: day) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    static func readInterval(month: Date?, now: Date, calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: today) ?? now
        if let month {
            let days = monthDays(containing: month, calendar: calendar)
            if let first = days.first, let last = days.last,
               let end = calendar.date(byAdding: .day, value: 1, to: last) {
                return DateInterval(start: first, end: calendar.isDate(month, equalTo: now, toGranularity: .month)
                                    ? max(end, weekEnd) : end)
            }
        }
        return DateInterval(start: today, end: weekEnd)
    }

    static func needsCurrentRead(visible: DateInterval, current: DateInterval,
                                 countdownEnabled: Bool) -> Bool {
        countdownEnabled && (visible.start > current.start || visible.end < current.end)
    }

    static func events(_ events: [NotchCalendarEvent], on day: Date,
                       calendar: Calendar = .current) -> [NotchCalendarEvent] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return events.filter { $0.start < interval.end && $0.end > interval.start }.sorted {
            if $0.allDay != $1.allDay { return $0.allDay }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id < $1.id
        }
    }

    static func requestFailed(status: EKAuthorizationStatus, hasError: Bool) -> Bool {
        hasError || ![.fullAccess, .denied, .restricted].contains(status)
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults)
            && AppFeature.notchCalendar.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchCalendarEnabled)
            && NotchSupport.modules(in: defaults).contains(.calendar)
    }

    static func showsCountdown(in defaults: UserDefaults = .standard) -> Bool {
        showsCountdown(chosen: false, in: defaults)
    }

    static func showsCountdown(chosen: Bool, in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && (chosen || defaults.bool(forKey: DefaultsKey.notchCalendarCountdown))
    }

    static func showsTimeLeft(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchCalendarTimeLeft)
    }

    static func weekNumber(of date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.weekOfYear, from: date)
    }

    static func weekNumberLabel(of date: Date, text: NotchCalendarStrings, calendar: Calendar = .current) -> String {
        String(format: text.weekNumber, weekNumber(of: date, calendar: calendar))
    }

    static func startsWeek(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.weekday, from: date) == calendar.firstWeekday
    }

    static func countdownKey(identifier: String, occurrence: Date?) -> String {
        guard let occurrence else { return identifier }
        return identifier + "@" + String(occurrence.timeIntervalSinceReferenceDate.rounded())
    }

    static func isChosen(_ event: NotchCalendarEvent, in chosen: Set<String>) -> Bool {
        !event.countdownKey.isEmpty && chosen.contains(event.countdownKey)
    }

    static func chosenCountdowns(in defaults: UserDefaults = .standard) -> [String: Date] {
        (defaults.dictionary(forKey: DefaultsKey.notchCalendarChosenCountdowns) ?? [:]).compactMapValues { $0 as? Date }
    }

    static func setCountdown(_ chosen: Bool, for event: NotchCalendarEvent, in defaults: UserDefaults = .standard) {
        guard !event.countdownKey.isEmpty else { return }
        var choices = chosenCountdowns(in: defaults)
        choices[event.countdownKey] = chosen ? event.end : nil
        storeChosenCountdowns(choices, in: defaults)
    }

    static func storeChosenCountdowns(_ choices: [String: Date], in defaults: UserDefaults = .standard) {
        if choices.isEmpty { defaults.removeObject(forKey: DefaultsKey.notchCalendarChosenCountdowns) }
        else { defaults.set(choices, forKey: DefaultsKey.notchCalendarChosenCountdowns) }
    }

    static func refreshedChoices(_ choices: [String: Date], events: [NotchCalendarEvent],
                                 now: Date) -> [String: Date]? {
        var refreshed = choices
        for event in events where refreshed[event.countdownKey] != nil { refreshed[event.countdownKey] = event.end }
        refreshed = refreshed.filter { $0.value > now }
        return refreshed == choices ? nil : refreshed
    }

    static func excludedCalendars(in defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: DefaultsKey.notchCalendarExcluded) ?? [])
    }

    static func setCalendar(_ identifier: String, shown: Bool, in defaults: UserDefaults = .standard) {
        var excluded = excludedCalendars(in: defaults)
        if shown { excluded.remove(identifier) } else { excluded.insert(identifier) }
        defaults.set(excluded.sorted(), forKey: DefaultsKey.notchCalendarExcluded)
    }

    static func calendarsToRead<C>(_ calendars: [C], excluded: Set<String>,
                                   identifier: (C) -> String) -> [C]? {
        guard calendars.contains(where: { excluded.contains(identifier($0)) }) else { return nil }
        return calendars.filter { !excluded.contains(identifier($0)) }
    }

    static func grouped(_ choices: [NotchCalendarChoice]) -> [[NotchCalendarChoice]] {
        Dictionary(grouping: choices, by: \.sourceID).values
            .map { $0.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
            .sorted {
                let order = $0[0].source.localizedStandardCompare($1[0].source)
                return order == .orderedSame ? $0[0].sourceID < $1[0].sourceID : order == .orderedAscending
            }
    }

    static func ordered(_ events: [NotchCalendarEvent]) -> [NotchCalendarEvent] {
        var seen = Set<String>()
        return events.filter {
            $0.start.timeIntervalSinceReferenceDate.isFinite
                && $0.end.timeIntervalSinceReferenceDate.isFinite
                && $0.end > $0.start && seen.insert($0.id).inserted
        }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.id < $1.id
        }
    }

    static func upcoming(_ events: [NotchCalendarEvent], now: Date) -> [NotchCalendarEvent] {
        ordered(events).filter { $0.end > now }
    }

    static func next(_ events: [NotchCalendarEvent], now: Date) -> NotchCalendarEvent? {
        upcoming(events, now: now).first { !$0.allDay }
    }

    static func countdown(_ events: [NotchCalendarEvent], now: Date, starts: Bool, ends: Bool,
                          chosen: Set<String> = [], leadTime: TimeInterval) -> NotchCalendarCountdown? {
        ordered(events).filter { !$0.allDay }
            .flatMap { event in
                followedMoments(event, starts: starts, ends: ends, chosen: chosen)
                    .map { NotchCalendarCountdown(event: event, ongoing: $0) }
            }
            .filter { $0.isShown(at: now, leadTime: leadTime) }
            .min { $0.target != $1.target ? $0.target < $1.target : $0.ongoing && !$1.ongoing }
    }

    private static func followedMoments(_ event: NotchCalendarEvent, starts: Bool, ends: Bool,
                                        chosen: Set<String>) -> [Bool] {
        (starts || isChosen(event, in: chosen) ? [false] : []) + (ends ? [true] : [])
    }

    static func tileEvent(_ events: [NotchCalendarEvent], now: Date,
                          calendar: Calendar = .current) -> NotchCalendarEvent? {
        let week = readInterval(month: nil, now: now, calendar: calendar)
        return ordered(events).first { !$0.allDay && $0.start > now && $0.start < week.end }
    }

    static func tileStartText(_ start: Date, now: Date, locale: Locale, calendar: Calendar = .current) -> String {
        var style = calendar.isDate(start, inSameDayAs: now)
            ? Date.FormatStyle.dateTime.hour().minute()
            : Date.FormatStyle.dateTime.weekday(.abbreviated).hour().minute()
        style.locale = locale
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return start.formatted(style)
    }

    static func countdownTransition(_ events: [NotchCalendarEvent], now: Date, starts: Bool, ends: Bool,
                                    chosen: Set<String> = [], leadTime: TimeInterval) -> Date? {
        ordered(events).filter { !$0.allDay }
            .flatMap { event in
                followedMoments(event, starts: starts, ends: ends, chosen: chosen).flatMap { ongoing in
                    ongoing ? [max(event.start, event.end.addingTimeInterval(-timeLeftLeadTime)), event.end]
                        : [event.start.addingTimeInterval(-leadTime), event.start]
                }
            }
            .filter { $0 > now }.min()
    }

    static let stripDotWidth: CGFloat = 6
    static let stripTitleSpacing: CGFloat = 5
    static let stripClockSpacing: CGFloat = 4

    static func countdownShape(leadTime: TimeInterval) -> String {
        let minutes = leadTime.isFinite
            ? min(Double(countdownLeadRange.upperBound), max(60, ceil(leadTime / 60))) : 60
        return String(repeating: "0", count: max(2, String(Int(minutes)).count)) + ":00"
    }

    static func timeText(_ countdown: NotchCalendarCountdown, locale: Locale) -> String {
        (countdown.ongoing ? "→\u{2009}" : "·\u{2009}")
            + countdown.target.formatted(.dateTime.hour().minute().locale(locale))
    }

    static func countdownText(until start: Date, now: Date) -> String {
        let seconds = max(0, Int(ceil(start.timeIntervalSince(now))))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func countdownAccessibilityText(until start: Date, now: Date, locale: Locale) -> String {
        let seconds = max(0, ceil(start.timeIntervalSince(now)))
        return Duration.seconds(seconds).formatted(.units(
            allowed: [.minutes, .seconds], width: .wide,
            fractionalPart: .hide(rounded: .down)).locale(locale))
    }

    static func eventURL(_ event: NotchCalendarEvent, calendar: Calendar = .current) -> URL? {
        guard !event.calendarItemIdentifier.isEmpty,
              let identifier = event.calendarItemIdentifier
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        var path = "ical://ekevent/"
        if event.recurring {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = event.allDay ? calendar.timeZone : TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            path += formatter.string(from: event.start) + "/"
        }
        return URL(string: path + identifier + "?method=show&options=more")
    }

    static func nextRefresh(_ events: [NotchCalendarEvent], now: Date,
                            calendar: Calendar = .current) -> Date {
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(900)
        return (upcoming(events, now: now).flatMap { [$0.start, $0.end] } + [midnight, now.addingTimeInterval(900)])
            .filter { $0 > now }.min() ?? now.addingTimeInterval(900)
    }
}
