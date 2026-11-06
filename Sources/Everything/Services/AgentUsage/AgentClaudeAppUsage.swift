// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentClaudeAppUsage {
    static let bundleIdentifier = "com.anthropic.claudefordesktop"
    static let downloadURL = URL(string: "https://claude.ai/download")!
    static let freshness: TimeInterval = 30 * 60
    private static let maximumSize = 4 << 20

    static func historyURL(home: URL) -> URL {
        home.appending(path: "Library/Application Support/Claude/plan-usage-history.json", directoryHint: .notDirectory)
    }

    static func lastCheck(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Date? {
        (try? Data(contentsOf: historyURL(home: home))).flatMap(samples)?.last?.date
    }

    struct Sample: Equatable {
        let date: Date
        let organization: String?
        let used: [String: Double]
    }

    private static let windows: [(key: String, kind: AgentLimitWindow.Kind, minutes: Int, scope: String?)] = [
        ("fh", .session, 300, nil), ("sd", .weekly, 10_080, nil),
        ("so", .weekly, 10_080, "Opus"), ("sn", .weekly, 10_080, "Sonnet")]

    static func samples(from data: Data) -> [Sample]? {
        guard data.count <= maximumSize,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let version = (json["version"] as? NSNumber)?.intValue, version == 1 || version == 2,
              let entries = json["samples"] as? [[String: Any]] else { return nil }
        var result: [Sample] = []
        for entry in entries {
            guard let milliseconds = (entry["t"] as? NSNumber)?.doubleValue, milliseconds.isFinite,
                  milliseconds > 0 else { continue }
            let values = version == 1 ? entry : (entry["u"] as? [String: Any] ?? [:])
            var used: [String: Double] = [:]
            for window in windows {
                guard let number = values[window.key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite else { continue }
                used[window.key] = min(100, max(0, number.doubleValue))
            }
            result.append(Sample(date: Date(timeIntervalSince1970: milliseconds / 1_000),
                                 organization: entry["org"] as? String, used: used))
        }
        return result.sorted { $0.date < $1.date }
    }

    static func limits(from samples: [Sample], now: Date, sessionStart: Date? = nil,
                       organization: String? = nil) -> AgentLimits? {
        let samples = readings(samples, organization: organization)
        guard let latest = samples.last, latest.date <= now.addingTimeInterval(300),
              now.timeIntervalSince(latest.date) < 7 * 86_400 else { return nil }
        let history = samples.filter { $0.organization == latest.organization }
        var result: [AgentLimitWindow] = []
        for window in windows {
            guard let used = latest.used[window.key] else { continue }
            let length = TimeInterval(window.minutes) * 60
            if window.kind == .session, now.timeIntervalSince(latest.date) >= length { continue }
            let session = window.kind == .session
                ? sessionEnd(history, used: used, start: sessionStart, length: length) : nil
            let resets = window.kind == .session
                ? session?.latest
                : renewal(history, key: window.key, length: length, after: latest.date)
            if let resets, resets <= now { continue }
            if resets == nil, now.timeIntervalSince(latest.date) >= 86_400 { continue }
            result.append(AgentLimitWindow(id: "claude.\(window.key)", kind: window.kind, minutes: window.minutes,
                                           scope: window.scope, usedPercent: used, resetsAt: resets,
                                           estimatedResetsAt: session?.estimate))
        }
        guard !result.isEmpty else { return nil }
        return AgentLimits(provider: .claude, windows: result, observedAt: latest.date, source: .claudeApp)
    }

    static func sessionStart(_ records: [AgentUsageRecord], samples: [Sample], organization: String? = nil) -> Date? {
        guard let reading = readings(samples, organization: organization).last?.date else { return nil }
        let recent = records.filter {
            $0.provider == .claude && $0.date <= reading && reading.timeIntervalSince($0.date) < AgentUsageSummary.blockHistory
        }
        return AgentUsageSummary.currentBlock(recent, now: reading)?.start
    }

    private static func readings(_ samples: [Sample], organization: String?) -> [Sample] {
        organization.map { account in samples.filter { $0.organization == nil || $0.organization == account } } ?? samples
    }

    private static func sessionEnd(_ history: [Sample], used: Double, start: Date?, length: TimeInterval)
        -> (latest: Date, estimate: Date?)? {
        guard used > 0, var first = history.indices.last else { return nil }
        while first > 0, let before = history[first - 1].used["fh"], before > 0,
              before <= (history[first].used["fh"] ?? 0) + 1,
              history[first].date.timeIntervalSince(history[first - 1].date) < length {
            first -= 1
        }
        let latest = history[first].date
        let earliest = first > 0 ? history[first - 1].date : latest.addingTimeInterval(-length)
        if let start, start > earliest, start <= latest {
            return (start.addingTimeInterval(length), nil)
        }
        let estimate = unseenStart(earliest: earliest, latest: latest, bracketed: first > 0, length: length)
        return (latest.addingTimeInterval(length), estimate < latest ? estimate.addingTimeInterval(length) : nil)
    }

    private static func unseenStart(earliest: Date, latest: Date, bracketed: Bool, length: TimeInterval) -> Date {
        guard bracketed, latest.timeIntervalSince(earliest) > freshness else { return latest }
        let lower = max(earliest, latest.addingTimeInterval(-length))
        return lower.addingTimeInterval(latest.timeIntervalSince(lower) / 2)
    }

    private struct Drop {
        let earliest: Date, latest: Date

        var moment: Date {
            let next = hour(of: earliest).addingTimeInterval(3_600)
            return next <= latest ? next : latest
        }

        func overlap(_ other: Drop, shiftedBy shift: TimeInterval = 0) -> Drop? {
            let start = max(earliest, other.earliest.addingTimeInterval(shift))
            let end = min(latest, other.latest.addingTimeInterval(shift))
            return start < end ? Drop(earliest: start, latest: end) : nil
        }
    }

    private static func renewal(_ history: [Sample], key: String, length: TimeInterval, after reading: Date) -> Date? {
        let drops = history.indices.dropFirst().compactMap { index -> Drop? in
            guard let before = history[index - 1].used[key], let after = history[index].used[key],
                  after + 1 < before else { return nil }
            return Drop(earliest: history[index - 1].date, latest: history[index].date)
        }
        guard let last = drops.last else { return nil }
        var moment = last.moment
        for index in drops.indices.reversed() {
            let spans = drops.indices.filter { $0 != index }.compactMap {
                confirmation(of: drops[index], by: drops[$0], length: length)
            }
            guard let newest = spans.last else { continue }
            let agreed = spans.reduce(Optional(drops[index])) { $0?.overlap($1) }
            let confirmed = (agreed ?? newest).moment
            if !missed(confirmed, history: history, drops: drops, key: key, length: length, until: reading) {
                moment = confirmed
            }
            break
        }
        while moment <= reading { moment.addTimeInterval(length) }
        return moment
    }

    private static func missed(_ moment: Date, history: [Sample], drops: [Drop], key: String,
                               length: TimeInterval, until reading: Date) -> Bool {
        var next = moment.addingTimeInterval(length)
        while next <= reading {
            let start = next.addingTimeInterval(-3_600), end = next.addingTimeInterval(3_600)
            if let before = history.last(where: { $0.date >= start && $0.date < next && $0.used[key] != nil })?.used[key],
               let after = history.first(where: { $0.date > next && $0.date <= end && $0.used[key] != nil })?.used[key],
               before >= 10, after + 1 >= before,
               !drops.contains(where: { $0.latest >= start && $0.earliest <= end }) { return true }
            next.addTimeInterval(length)
        }
        return false
    }

    private static func confirmation(of drop: Drop, by other: Drop, length: TimeInterval) -> Drop? {
        guard drop.latest.timeIntervalSince(drop.earliest) < 86_400,
              other.latest.timeIntervalSince(other.earliest) < 86_400 else { return nil }
        let weeks = (drop.moment.timeIntervalSince(other.moment) / length).rounded()
        return weeks == 0 ? nil : drop.overlap(other, shiftedBy: weeks * length)
    }

    static func hour(of date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.dateInterval(of: .hour, for: date)?.start ?? date
    }
}
