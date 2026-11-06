import Foundation

@MainActor
enum Reminders {
    enum Reading: Equatable {
        case at(Date)
        case past
        case noTime
    }

    // MARK: Which lines count

    private static let marker = try! NSRegularExpression(
        pattern: #"^\s*(?:[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+|>\s+)?"#
    )

    static func body(ofLine line: String) -> String? {
        guard !Checkbox.isChecked(line) else { return nil }
        let text = sentence(ofLine: line)
        guard text.lowercased().hasPrefix("remind me") else { return nil }
        var rest = text.dropFirst("remind me".count)
        if rest.first == ":" || rest.first == "," {
            rest = rest.dropFirst()
        } else if !(rest.isEmpty || rest.first == " " || rest.first == "\t") {
            return nil
        }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    static func isReminder(_ line: String) -> Bool { false }

    nonisolated static func mightBeReminder(_ ns: NSString, _ line: NSRange) -> Bool {
        if true { return false }
        var start = line.location
        let end = NSMaxRange(line)
        while start < end, " \t-*+>[]xX0123456789.)".utf16.contains(ns.character(at: start)) { start += 1 }
        guard end - start >= 9 else { return false }
        return ns.compare("remind me", options: .caseInsensitive, range: NSRange(location: start, length: 9)) == .orderedSame
    }

    static func ticked(_ line: String) -> String {
        guard !Checkbox.isChecked(line) else { return line }
        let task = Checkbox.boxRange(in: line) == nil ? LineEditing.toggleTask(line: line) : line
        return Checkbox.toggling(task) ?? line
    }

    static func sentence(ofLine line: String) -> String {
        let ns = line as NSString
        let start = marker.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
            .map { NSMaxRange($0.range) } ?? 0
        return ns.substring(from: start).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Reading the time

    private static let defaultHour = 9
    private static let endOfDayHour = 17
    private static let longestSpan: Double = 100 * 366 * 86_400

    private enum PartOfDay {
        case morning, afternoon, evening, night

        init?(_ words: String) {
            let words = words.lowercased()
            if words.contains("morning") {
                self = .morning
            } else if words.contains("afternoon") {
                self = .afternoon
            } else if words.contains("evening") {
                self = .evening
            } else if words.contains("night") {
                self = .night
            } else {
                return nil
            }
        }

        var hour: Int {
            switch self {
            case .morning: 9
            case .afternoon: 15
            case .evening: 18
            case .night: 19
            }
        }
        var ends: Int { self == .morning ? 12 : self == .afternoon ? 18 : 24 }
    }

    private struct Clock {
        let range: NSRange
        var phrase: String
        let hour: Int
        let minute: Int
        var ambiguous = false
        var part: PartOfDay?
    }

    private struct Day {
        let range: NSRange
        let phrase: String
        let date: Date
        var time: Clock?
        var fallback: Date?
    }

    private struct Moment {
        let range: NSRange
        let phrase: String
        let date: Date?
    }

    static func read(_ line: String, now: Date = Date(), calendar: Calendar = .current) -> (reading: Reading, phrase: String)? {
        guard let body = body(ofLine: line) else { return nil }
        return readBody(body, now: now, calendar: calendar).map {
            ($0.reading, $0.phrase.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        }
    }

    private static func readBody(_ body: String, now: Date, calendar: Calendar) -> (reading: Reading, phrase: String)? {
        let whole = body as NSString
        let cut = whole.length > 600 ? whole.rangeOfComposedCharacterSequence(at: 600).location : whole.length
        let ns = whole.substring(to: cut) as NSString
        var claimed: [NSRange] = []
        var days: [Day] = []
        var moment: Moment?
        switch readSpan(ns, now: now, calendar: calendar, claimed: &claimed) {
        case .moment(let m): moment = m
        case .day(let d): days.append(d)
        case nil: break
        }
        days += readWeeks(ns, now: now, calendar: calendar, claimed: &claimed)
        days += readDays(ns, now: now, calendar: calendar, claimed: &claimed)
        claimed += notTimes.flatMap { $0.matches(in: ns as String, range: NSRange(location: 0, length: ns.length)).map(\.range) }
        var clocks = readClocks(ns, claimed: &claimed)
        let detected = detect(ns, hiding: claimed, now: now, calendar: calendar)
        days += detected.days
        clocks += detected.clocks
        let anchor = days.min { $0.range.location < $1.range.location }

        if let moment, moment.range.location < anchor?.range.location ?? .max {
            return moment.date.map { (.at($0), moment.phrase) } ?? (.noTime, moment.phrase)
        }
        let partClock = clocks.first { $0.part != nil }
        let part = partClock?.part ?? anchor?.time?.part
        var clock = clocks.filter { $0.part == nil }.min { $0.range.location < $1.range.location } ?? partClock
        if let chosen = clock, chosen.ambiguous, let partClock, partClock.range != chosen.range {
            clock?.phrase = "\(chosen.phrase) \(partClock.phrase)"
        }

        if let anchor {
            let time = clock ?? anchor.time
            let phrase = clock.map { "\(anchor.phrase) \($0.phrase)" } ?? anchor.phrase
            for day in [anchor.date] + [anchor.fallback].compactMap({ $0 }) {
                let date = time.map { at(hour(of: $0, part: part), $0.minute, on: day, calendar: calendar) }
                    ?? at(defaultHour, 0, on: day, calendar: calendar)
                if date > now { return (.at(date), phrase) }
                if calendar.isDate(day, inSameDayAs: now), time == nil || time?.part != nil,
                   let next = nextWholeHour(after: now, before: time?.part?.ends ?? 24, calendar: calendar) {
                    return (.at(next), phrase)
                }
            }
            return (.past, phrase)
        }

        guard let clock else { return (.noTime, "") }
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        if clock.ambiguous, part == nil {
            let options = [clock.hour % 12, clock.hour % 12 + 12].filter { $0 >= 7 }
            for hour in options {
                let date = at(hour, clock.minute, on: today, calendar: calendar)
                if date > now { return (.at(date), clock.phrase) }
            }
            return (.at(at(options[0], clock.minute, on: tomorrow, calendar: calendar)), clock.phrase)
        }
        let settled = hour(of: clock, part: part)
        let date = at(settled, clock.minute, on: today, calendar: calendar)
        if date > now { return (.at(date), clock.phrase) }
        return (.at(at(settled, clock.minute, on: tomorrow, calendar: calendar)), clock.phrase)
    }

    private static func hour(of clock: Clock, part: PartOfDay?) -> Int {
        guard clock.ambiguous else { return clock.hour }
        if let part { return part == .morning ? clock.hour % 12 : clock.hour == 12 ? 24 : clock.hour + 12 }
        return clock.hour == 12 ? 12 : clock.hour < 7 ? clock.hour + 12 : clock.hour
    }

    private static func at(_ hour: Int, _ minute: Int, on day: Date, calendar: Calendar) -> Date {
        let day = hour >= 24 ? calendar.date(byAdding: .day, value: 1, to: day) ?? day : day
        return calendar.date(bySettingHour: hour % 24, minute: minute, second: 0, of: day) ?? day
    }

    private static func nextWholeHour(after now: Date, before ends: Int, calendar: Calendar) -> Date? {
        guard let hourStart = calendar.dateInterval(of: .hour, for: now)?.start,
              let next = calendar.date(byAdding: .hour, value: 1, to: hourStart),
              calendar.isDate(next, inSameDayAs: now), calendar.component(.hour, from: next) < ends else { return nil }
        return next
    }

    // MARK: Spans

    private static let amount = #"(?:half\s+an|a\s+couple\s+of|\d+(?:\.\d+)?|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty|forty-five|forty|fifty|sixty|ninety)"#
    private static let unit = #"(?:seconds?|secs?|minutes?|mins?|hours?|hrs?|days?|weeks?|wks?|months?)"#
    private static let shortUnit = #"(\d+(?:\.\d+)?)([mh])"#
    private static let spanPattern = try! NSRegularExpression(
        pattern: #"\bin\s+(?:("# + amount + #")\s*("# + unit + #")|"# + shortUnit + #")\b"#, options: .caseInsensitive
    )
    private static let spanMorePattern = try! NSRegularExpression(
        pattern: #"\s*,?\s*(?:and\s+)?(?:(a\s+half)|("# + amount + #")\s*("# + unit + #")|"# + shortUnit + #")\b"#,
        options: .caseInsensitive
    )
    private static let numberWords: [String: Double] = [
        "a": 1, "an": 1, "a couple of": 2, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20,
        "thirty": 30, "forty": 40, "forty-five": 45, "fifty": 50, "sixty": 60, "ninety": 90,
    ]

    private static func unitRank(_ unit: String) -> Int {
        let unit = unit.lowercased()
        return unit.hasPrefix("mo") ? 5 : unit.hasPrefix("w") ? 4 : unit.hasPrefix("d") ? 3
            : unit.hasPrefix("h") ? 2 : unit.hasPrefix("m") ? 1 : 0
    }

    private enum SpanReading {
        case moment(Moment)
        case day(Day)
    }

    private static func readSpan(_ ns: NSString, now: Date, calendar: Calendar, claimed: inout [NSRange]) -> SpanReading? {
        let body = ns as String
        guard let first = spanPattern.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            m.range(at: i).location != NSNotFound ? ns.substring(with: m.range(at: i)) : nil
        }
        var parts = [(amount: group(first, 1) ?? group(first, 3) ?? "", unit: group(first, 2) ?? group(first, 4) ?? "")]
        var end = NSMaxRange(first.range)
        while let more = spanMorePattern.firstMatch(
            in: body, options: .anchored, range: NSRange(location: end, length: ns.length - end)
        ), more.range.length > 0 {
            let next = group(more, 1) != nil
                ? (amount: "half", unit: parts[parts.count - 1].unit)
                : (amount: group(more, 2) ?? group(more, 4) ?? "", unit: group(more, 3) ?? group(more, 5) ?? "")
            guard group(more, 1) != nil || unitRank(next.unit) < unitRank(parts[parts.count - 1].unit) else { break }
            parts.append(next)
            end = NSMaxRange(more.range)
        }
        let range = NSRange(location: first.range.location, length: end - first.range.location)
        let phrase = ns.substring(with: range)
        claimed.append(range)

        var months = 0.0, days = 0.0, seconds = 0.0
        for part in parts {
            let key = part.amount.lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let value = key.hasPrefix("half") ? 0.5 : Double(key) ?? numberWords[key] ?? 0
            let unit = part.unit.lowercased()
            if unit.hasPrefix("mo") {
                months += value
            } else if unit.hasPrefix("w") {
                days += value * 7
            } else if unit.hasPrefix("d") {
                days += value
            } else {
                seconds += value * (unit.hasPrefix("h") ? 3600 : unit.hasPrefix("m") ? 60 : 1)
            }
        }
        let total = months * 31 * 86_400 + days * 86_400 + seconds
        guard total.isFinite, total > 0, total <= longestSpan else {
            return .moment(Moment(range: range, phrase: phrase, date: nil))
        }
        let byMonths = calendar.date(byAdding: .month, value: Int(months), to: now) ?? now
        if seconds == 0, months == months.rounded(), days == days.rounded() {
            let day = calendar.date(byAdding: .day, value: Int(days), to: byMonths) ?? byMonths
            return .day(Day(range: range, phrase: phrase, date: calendar.startOfDay(for: day)))
        }
        let rest = (months - months.rounded(.down)) * 30 * 86_400 + days * 86_400 + seconds
        return .moment(Moment(range: range, phrase: phrase, date: byMonths.addingTimeInterval(rest)))
    }

    // MARK: Weeks and weekends

    private static let weekday = #"(monday|mon|tuesday|tues|tue|wednesday|weds|wed|thursday|thurs|thur|thu|friday|fri|saturday|sat|sunday|sun)"#
    private static let nextWeekPattern = try! NSRegularExpression(
        pattern: #"\b(?:"# + weekday + #"\s+next\s+week|next\s+week(?:\s+on)?\s+"# + weekday + #"|next\s+week)\b(?!['’]s)"#,
        options: .caseInsensitive
    )
    private static let weekendPattern = try! NSRegularExpression(
        pattern: #"\b(?:(next)|this|the|on\s+the|at\s+the|over\s+the)\s+weekend\b(?!['’]s)"#, options: .caseInsensitive
    )

    private static func readWeeks(_ ns: NSString, now: Date, calendar: Calendar, claimed: inout [NSRange]) -> [Day] {
        let body = ns as String
        let all = NSRange(location: 0, length: ns.length)
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        var days: [Day] = []
        if let m = nextWeekPattern.firstMatch(in: body, range: all), !overlaps(m.range, claimed) {
            let toMonday = (9 - weekday) % 7 == 0 ? 7 : (9 - weekday) % 7
            let named = [m.range(at: 1), m.range(at: 2)].first { $0.location != NSNotFound }
            let offset = named.map { weekdayIndex(ns.substring(with: $0)) } ?? 0
            if let day = calendar.date(byAdding: .day, value: toMonday + offset, to: today) {
                days.append(Day(range: m.range, phrase: ns.substring(with: m.range), date: day))
                claimed.append(m.range)
            }
        }
        if let m = weekendPattern.firstMatch(in: body, range: all), !overlaps(m.range, claimed) {
            let toSaturday = weekday == 1 ? 0 : 7 - weekday
            let next = m.range(at: 1).location != NSNotFound
            let offset = next ? (weekday == 1 ? 6 : toSaturday + 7) : toSaturday
            if let day = calendar.date(byAdding: .day, value: offset, to: today) {
                let sunday = calendar.component(.weekday, from: day) == 7 ? calendar.date(byAdding: .day, value: 1, to: day) : nil
                days.append(Day(range: m.range, phrase: ns.substring(with: m.range), date: day, fallback: sunday))
                claimed.append(m.range)
            }
        }
        return days
    }

    private static let shortWeekday = #"(mon|tue|tues|wed|weds|thu|thur|thurs|fri|sat|sun)"#
    private static let dayPart = #"(?-i:\s+(morning|afternoon|evening|night))?"#
    private static let weekdayPattern = try! NSRegularExpression(
        pattern: #"(?<!\bnext\s)(?<!\blast\s)(?<!\bevery\s)(?<!\buntil\s)(?<!\btill\s)(?<!\bbefore\s)(?<!\bafter\s)"#
            + #"\b(?:(?:on|this)\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b(?!['’]s)"# + dayPart
            + #"|\b(?:on|this)\s+"# + shortWeekday + #"\b"# + dayPart
            + #"|(?<!\bnext\s)(?<!\blast\s)\b(?-i:([Mm]on|[Tt]ues?|[Ww]eds?|[Tt]hu(?:rs?)?|[Ff]ri|[Ss]at|[Ss]un))\b"#
            + #"(?=\s+(?:at\b|@|\d{1,2}(?::\d{2})?\s*[ap]\.?m\b|\d{1,2}:\d{2}|morning|afternoon|evening|night))"# + dayPart
            + #"|(?<!\bnext\s)(?<!\blast\s)\b(?-i:(Mon|Tues?|Weds?|Thu(?:rs?)?|Fri|Sat|Sun))\b(?=\s+\d)"# + dayPart,
        options: .caseInsensitive
    )
    private static let ordinalPattern = try! NSRegularExpression(
        pattern: #"\b(?:on\s+the\s+(\d{1,2})(?:st|nd|rd|th)\b(?!\s+of\b)|the\s+(\d{1,2})(?:st|nd|rd|th)(?=\s+(?:at\b|@)))"#,
        options: .caseInsensitive
    )

    private static func readDays(_ ns: NSString, now: Date, calendar: Calendar, claimed: inout [NSRange]) -> [Day] {
        let body = ns as String
        let all = NSRange(location: 0, length: ns.length)
        let today = calendar.startOfDay(for: now)
        var days: [Day] = []
        for m in weekdayPattern.matches(in: body, range: all) where !overlaps(m.range, claimed) {
            func group(_ i: Int) -> String? {
                m.range(at: i).location != NSNotFound ? ns.substring(with: m.range(at: i)) : nil
            }
            guard let name = group(1) ?? group(3) ?? group(5) ?? group(7) else { continue }
            let wanted = (weekdayIndex(name) + 1) % 7 + 1
            let ahead = (wanted - calendar.component(.weekday, from: today) + 7) % 7
            if let day = calendar.date(byAdding: .day, value: ahead == 0 ? 7 : ahead, to: today) {
                let part = (group(2) ?? group(4) ?? group(6) ?? group(8)).flatMap(PartOfDay.init)
                let time = part.map { Clock(range: m.range, phrase: "", hour: $0.hour, minute: 0, part: $0) }
                days.append(Day(range: m.range, phrase: ns.substring(with: m.range), date: day, time: time))
                claimed.append(m.range)
            }
            break
        }
        if let m = ordinalPattern.firstMatch(in: body, range: all), !overlaps(m.range, claimed),
           let number = [m.range(at: 1), m.range(at: 2)].first(where: { $0.location != NSNotFound }),
           let wanted = Int(ns.substring(with: number)), (1...31).contains(wanted) {
            var month = calendar.dateComponents([.year, .month], from: today)
            for _ in 0..<12 {
                month.day = wanted
                if let day = calendar.date(from: month), calendar.component(.day, from: day) == wanted, day >= today {
                    days.append(Day(range: m.range, phrase: ns.substring(with: m.range), date: day))
                    claimed.append(m.range)
                    break
                }
                month.day = 1
                if let first = calendar.date(from: month), let following = calendar.date(byAdding: .month, value: 1, to: first) {
                    month = calendar.dateComponents([.year, .month], from: following)
                }
            }
        }
        return days
    }

    private static let notTimes = [
        #"\bat\s+\d{1,4}\.(?!00\b|15\b|30\b|45\b)\d{2}\b"#,
        #"(?<![\d\-–/.])(?<!\bat\s)\b\d{1,3}\s*[-–]\s*\d{1,3}\b(?![-–/.]\d)"#,
        #"\b(?:mon|tues|wednes|thurs|fri|satur|sun)day['’]s\b"#,
    ].map { try! NSRegularExpression(pattern: $0, options: .caseInsensitive) }

    private static func weekdayIndex(_ name: String) -> Int {
        ["mon", "tue", "wed", "thu", "fri", "sat", "sun"].firstIndex(of: String(name.lowercased().prefix(3))) ?? 0
    }

    // MARK: Clock times

    private enum ClockForm { case meridiem, digits, named, part, endOfDay }

    private static let atWord = #"(?:\bat\s*|@\s*)"#
    private static let clockPatterns: [(NSRegularExpression, ClockForm)] = ([
        (#"(?:"# + atWord + #")?\b(\d{1,2})(?:[:.](\d{2}))?\s*([ap])\.?\s?m\b\.?"#, .meridiem),
        (atWord + #"(\d{1,2})(?:[:.](\d{2}))?([ap])\b"#, .meridiem),
        (#"(?:"# + atWord + #")?\b(\d{1,2}):(\d{2})\b"#, .digits),
        (atWord + #"(\d{1,2})\.(00|15|30|45)\b"#, .digits),
        (atWord + #"(\d{1,2})(?:\s*o['’]?clock)?\b(?![:.]\d|\s*[ap]\.?m\b|[ap]\b|%|/)"#, .digits),
        (#"\b(\d{1,2})\s*o['’]?clock\b"#, .digits),
        (#"(?-i:\b(noon|midday|midnight|NOON|MIDDAY|MIDNIGHT)\b(?!['’]s))|\b(?:at|by)\s+(noon|midday|midnight|lunch|dinner)\b|\b(lunchtime|dinnertime)\b"#, .named),
        (#"\bin\s+the\s+(?:morning|afternoon|evening)\b"#, .part),
        (#"\b(?:(?:by\s+)?(?:the\s+)?end\s+of\s+(?:the\s+)?day|eod)\b"#, .endOfDay),
    ] as [(String, ClockForm)]).map { (try! NSRegularExpression(pattern: $0.0, options: .caseInsensitive), $0.1) }

    private static func readClocks(_ ns: NSString, claimed: inout [NSRange]) -> [Clock] {
        let body = ns as String
        let all = NSRange(location: 0, length: ns.length)
        var found: [Clock] = []
        for (pattern, form) in clockPatterns {
            for m in pattern.matches(in: body, range: all) {
                if let clock = clock(m, form: form, in: ns) { found.append(clock) }
            }
        }
        found.sort {
            $0.range.location != $1.range.location ? $0.range.location < $1.range.location : $0.range.length > $1.range.length
        }
        var kept: [Clock] = []
        for clock in found where !overlaps(clock.range, claimed) {
            kept.append(clock)
            claimed.append(clock.range)
        }
        return kept
    }

    private static func clock(_ m: NSTextCheckingResult, form: ClockForm, in ns: NSString) -> Clock? {
        func group(_ i: Int) -> String? {
            m.numberOfRanges > i && m.range(at: i).location != NSNotFound ? ns.substring(with: m.range(at: i)) : nil
        }
        let phrase = ns.substring(with: m.range).trimmingCharacters(in: .whitespaces)
        switch form {
        case .meridiem:
            guard let hour = group(1).flatMap(Int.init), (1...12).contains(hour) else { return nil }
            let minute = group(2).flatMap(Int.init) ?? 0
            guard minute < 60 else { return nil }
            let pm = group(3)?.lowercased() == "p"
            return Clock(range: m.range, phrase: phrase, hour: hour % 12 + (pm ? 12 : 0), minute: minute)
        case .digits:
            guard let written = group(1), let hour = Int(written), hour < 24 else { return nil }
            let minute = group(2).flatMap(Int.init) ?? 0
            guard minute < 60 else { return nil }
            let ambiguous = (1...12).contains(hour) && !written.hasPrefix("0")
            return Clock(range: m.range, phrase: phrase, hour: hour, minute: minute, ambiguous: ambiguous)
        case .named:
            let word = (group(1) ?? group(2) ?? group(3) ?? "").lowercased()
            let hour = word == "midnight" ? 24 : word.hasPrefix("dinner") ? 19 : 12
            return Clock(range: m.range, phrase: phrase, hour: hour, minute: 0)
        case .part:
            guard let part = PartOfDay(phrase) else { return nil }
            return Clock(range: m.range, phrase: phrase, hour: part.hour, minute: 0, part: part)
        case .endOfDay:
            return Clock(range: m.range, phrase: phrase, hour: endOfDayHour, minute: 0)
        }
    }

    private static func overlaps(_ range: NSRange, _ others: [NSRange]) -> Bool {
        others.contains { NSIntersectionRange($0, range).length > 0 }
    }

    // MARK: macOS's reader

    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    private static let clockOnly = try! NSRegularExpression(
        pattern: #"^(?:at\s*|@\s*)?\d{1,4}(?:[:.h]\d{2})?\s*(?:[ap]\.?m?\.?)?(?:\s*o['’]?clock)?$"#, options: .caseInsensitive
    )

    private static func detect(
        _ ns: NSString, hiding claimed: [NSRange], now: Date, calendar: Calendar
    ) -> (days: [Day], clocks: [Clock]) {
        let masked = NSMutableString(string: ns)
        for range in claimed {
            masked.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }
        var days: [Day] = []
        var clocks: [Clock] = []
        for m in detector.matches(in: masked as String, range: NSRange(location: 0, length: masked.length)) {
            guard let date = m.date else { continue }
            if m.duration > 0 { continue }
            let phrase = masked.substring(with: m.range).trimmingCharacters(in: .whitespaces)
            let t = calendar.dateComponents([.hour, .minute, .second], from: date)
            let time = t.hour == 12 && t.minute == 0 && t.second == 0 ? nil
                : Clock(range: m.range, phrase: phrase, hour: t.hour ?? defaultHour, minute: t.minute ?? 0, part: PartOfDay(phrase))
            if clockOnly.firstMatch(in: phrase, range: NSRange(location: 0, length: (phrase as NSString).length)) != nil {
                if let time { clocks.append(time) }
            } else {
                days.append(Day(range: m.range, phrase: phrase, date: calendar.startOfDay(for: date), time: time))
            }
        }
        return (days, clocks)
    }

    // MARK: Showing a time

    enum Label: Equatable {
        case due(Date)
        case set(Date)
        case sent(Date)
        case past
        case noTime
        case notificationsOff
        case needsPermission
        case notSent
        case outsideApplications
        case notOnThisMac

        @MainActor
        func text(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
            switch self {
            case .due(let date): return "\u{2192} " + Reminders.describe(date, now: now, calendar: calendar, locale: locale)
            case .set(let date): return Reminders.describe(date, now: now, calendar: calendar, locale: locale)
            case .sent(let date): return "sent " + Reminders.describe(date, now: now, calendar: calendar, locale: locale)
            case .past: return "time has passed"
            case .noTime: return "no time found"
            case .notificationsOff: return "notifications are off"
            case .needsPermission: return "allow notifications to get this"
            case .notSent: return "not sent"
            case .outsideApplications: return "move Wisp to Applications to get reminders"
            case .notOnThisMac: return "not set on this Mac"
            }
        }

        @MainActor
        func shortText(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
            switch self {
            case .due(let date): return "\u{2192} " + Reminders.clock(date, calendar: calendar, locale: locale)
            case .set(let date): return Reminders.clock(date, calendar: calendar, locale: locale)
            case .sent: return "sent"
            case .past: return "passed"
            case .noTime: return "no time"
            case .notificationsOff: return "notifications off"
            case .needsPermission: return "needs permission"
            case .notSent: return "not sent"
            case .outsideApplications: return "move to Applications"
            case .notOnThisMac: return "not set here"
            }
        }

        var symbol: String? {
            switch self {
            case .set: return "bell"
            case .sent: return "checkmark.circle"
            default: return nil
            }
        }

        var ticksLine: Bool {
            if case .sent = self { return true }
            return false
        }
    }

    static func clock(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        formatter(nil, calendar: calendar, locale: locale).string(from: date)
    }

    static func describe(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let clock = clock(date, calendar: calendar, locale: locale)
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        if days == 0 { return clock }
        if abs(days) == 1, let real = calendar.date(byAdding: .day, value: days, to: Date()) {
            return "\(relativeFormatter(calendar: calendar, locale: locale).string(from: real)) \(clock)"
        }
        let year = [.japanese, .republicOfChina].contains(calendar.identifier) ? "dMMMyG" : "dMMMy"
        let template = days > 1 && days < 7 ? "EEE"
            : calendar.component(.year, from: date) == calendar.component(.year, from: now) ? "dMMM" : year
        return "\(formatter(template, calendar: calendar, locale: locale).string(from: date)) \(clock)"
    }

    private static var formatters: [String: DateFormatter] = [:]

    private static func relativeFormatter(calendar: Calendar, locale: Locale) -> DateFormatter {
        let key = "\(locale.identifier)|\(calendar.identifier)|\(calendar.timeZone.identifier)|relative"
        if let cached = formatters[key] { return cached }
        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.doesRelativeDateFormatting = true
        f.dateStyle = .medium
        f.timeStyle = .none
        f.formattingContext = .beginningOfSentence
        formatters[key] = f
        return f
    }

    private static func formatter(_ template: String?, calendar: Calendar, locale: Locale) -> DateFormatter {
        let key = "\(locale.identifier)|\(calendar.identifier)|\(calendar.timeZone.identifier)|\(template ?? "time")"
        if let cached = formatters[key] { return cached }
        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        if let template {
            f.setLocalizedDateFormatFromTemplate(template)
        } else {
            f.dateStyle = .none
            f.timeStyle = .short
        }
        formatters[key] = f
        return f
    }
}
