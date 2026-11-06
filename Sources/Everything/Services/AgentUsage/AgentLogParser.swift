// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum AgentLogEntry: Equatable {
    case usage(key: String, record: AgentUsageRecord, billable: AgentBillable)
    case usageModel(key: String, model: String)
    case limits(AgentLimits)
    case plan(String, observedAt: Date)
    case turnBegan(Date)
    case turnContext(model: String, project: String)
    case turnActive(Date?)
    case turnSettled(Date)
    case turnEnded(Date?, completed: Bool, duration: TimeInterval?)
    case reset(Date)
}

struct AgentLogState: Equatable {
    var session = ""
    var project = ""
    var model = ""
    var turnOpen = false
    var sawUsageRecords = false
    var lastTotal: AgentTokens?
    var fast = false
    var codexSubagent = false
    var codexHeaderRead = false
    var codexRoot = ""
    var codexTotalsSession = ""
    var copilotTotals: [String: AgentTokens] = [:]
    var copilotRequests: [String: Int] = [:]
    var copilotRequestModels: [String: String] = [:]
    var copilotReportedRequests: [String: Int] = [:]
    var copilotTurnID: String?
    var copilotFinalResponse = false
    var parentSession = ""
    var openCodeSessions: [String: OpenCodeSessionState] = [:]
    var runningCommands: Set<String> = []
}

struct OpenCodeSessionState: Equatable {
    var project = ""
    var model = ""
    var turnOpen = false
    var turnStarted: Date?
    var activeUserMessageID = ""
    var lastActivity: Date?
    var settledAt: Date?
    var writingReplyID = ""
    var activePromptDate: Date?
    var seenUserMessageIDs: Set<String> = []
    var completedAssistantMessageIDs: Set<String> = []
    var completedUserMessageIDs: Set<String> = []
}

enum AgentLogParser {
    // MARK: Byte tests

    static func contains(_ line: Data, _ needle: StaticString) -> Bool {
        line.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress, bytes.count >= needle.utf8CodeUnitCount else { return false }
            return memmem(base, bytes.count, needle.utf8Start, needle.utf8CodeUnitCount) != nil
        }
    }

    static func firstType(_ line: Data, from start: Int = 0) -> (name: String, end: Int)? {
        let key: StaticString = #""type":""#
        return line.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress, start < bytes.count,
                  let found = memmem(base + start, bytes.count - start, key.utf8Start, key.utf8CodeUnitCount)
            else { return nil }
            let value = base.distance(to: found) + key.utf8CodeUnitCount
            let limit = min(bytes.count, value + 64)
            guard value < limit, let quote = memchr(base + value, 0x22, limit - value) else { return nil }
            let end = base.distance(to: UnsafeRawPointer(quote))
            return (String(decoding: UnsafeRawBufferPointer(rebasing: bytes[value..<end]), as: UTF8.self), end + 1)
        }
    }

    static let codexEvents: Set<String> = [
        "token_count", "task_started", "task_complete", "turn_aborted", "thread_settings_applied",
    ]

    static func object(_ line: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }

    // MARK: Claude Code

    static func parseClaude(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        ClaudeReader().parse(line, state: &state, now: now)
    }

    // MARK: Codex

    static func parseCodex(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        CodexReader().parse(line, state: &state, now: now)
    }

    static func codexTokens(_ usage: [String: Any]) -> AgentTokens {
        let input = int(usage["input_tokens"])
        let cached = min(input, int(usage["cached_input_tokens"]))
        let written = min(input - cached, int(usage["cache_write_input_tokens"]))
        return AgentTokens(input: input - cached - written, cacheWrite: written, cacheRead: cached,
                           output: int(usage["output_tokens"]), reasoning: int(usage["reasoning_output_tokens"]))
    }

    static func fastTier(_ tier: String) -> Bool {
        ["fast", "priority"].contains(tier.lowercased())
    }

    // MARK: OpenCode

    static let openCodeSettle: TimeInterval = 30

    static func parseOpenCode(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        OpenCodeReader().parse(line, state: &state, now: now)
    }

    // MARK: GitHub Copilot

    static func parseCopilot(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        CopilotReader().parse(line, state: &state, now: now)
    }

    static func copilotEvent(_ type: String) -> Bool {
        ["user.message", "assistant.turn_start", "assistant.message", "assistant.turn_end",
         "session.start", "session.context_changed", "session.model_change", "session.shutdown", "abort"].contains(type)
    }

    static func isMainBucket(_ limits: [String: Any]) -> Bool {
        let id = (limits["limit_id"] as? String ?? "").lowercased()
        return id.isEmpty || id == "codex"
    }

    typealias WindowKeys = (used: String, minutes: String, resets: String, individual: String, remaining: String)
    static let logWindowKeys: WindowKeys = ("used_percent", "window_minutes", "resets_at",
                                            "individual_limit", "remaining_percent")

    static func codexWindows(_ limits: [String: Any], observed: Date,
                             keys: WindowKeys = logWindowKeys) -> [AgentLimitWindow]? {
        var windows: [AgentLimitWindow] = []
        for slot in ["primary", "secondary"] {
            guard let window = limits[slot] as? [String: Any],
                  let used = (window[keys.used] as? NSNumber)?.doubleValue, used.isFinite else { continue }
            let minutes = (window[keys.minutes] as? NSNumber)?.intValue
            var resets = seconds(window[keys.resets])
            if resets == nil, let delay = (window["resets_in_seconds"] as? NSNumber)?.doubleValue, delay.isFinite {
                resets = observed.addingTimeInterval(max(0, delay))
            }
            windows.append(AgentLimitWindow(id: "codex.\(minutes.map(String.init) ?? slot)",
                                            kind: kind(minutes: minutes), minutes: minutes, scope: nil,
                                            usedPercent: min(100, max(0, used)), resetsAt: resets))
        }
        if windows.isEmpty, let individual = limits[keys.individual] as? [String: Any],
           let remaining = (individual[keys.remaining] as? NSNumber)?.doubleValue, remaining.isFinite {
            windows.append(AgentLimitWindow(id: "codex.individual", kind: .other, minutes: nil, scope: nil,
                                            usedPercent: min(100, max(0, 100 - remaining)),
                                            resetsAt: seconds(individual[keys.resets])))
        }
        return windows.sorted { ($0.minutes ?? .max) < ($1.minutes ?? .max) }
    }

    static func kind(minutes: Int?) -> AgentLimitWindow.Kind {
        guard let minutes, minutes > 0 else { return .other }
        if minutes <= 12 * 60 { return .session }
        if (6 * 1440...8 * 1440).contains(minutes) { return .weekly }
        return .other
    }

    // MARK: Shared values

    static func projectName(_ path: String) -> String {
        var path = path
        if let range = path.range(of: "/.claude/worktrees/") { path = String(path[..<range.lowerBound]) }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return native((path as NSString).lastPathComponent)
    }

    static func native(_ text: String) -> String {
        String(decoding: text.utf8, as: UTF8.self)
    }

    static func int(_ value: Any?) -> Int {
        guard let number = value as? NSNumber else { return 0 }
        let double = number.doubleValue
        guard double.isFinite, double > 0 else { return 0 }
        return Int(min(double, 1e12))
    }

    static func seconds(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber else { return nil }
        let raw = number.doubleValue
        guard raw.isFinite, raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw > 100_000_000_000 ? raw / 1000 : raw)
    }

    static func timestamp(_ value: Any?) -> Date? {
        guard let text = value as? String else { return seconds(value) }
        return AgentTimestamp.parse(text)
    }
}

enum AgentTimestamp {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let whole = ISO8601DateFormatter()
    private static let lock = NSLock()

    static func parse(_ text: String) -> Date? {
        if let date = fast(Array(text.utf8)) { return date }
        return lock.withLock { fractional.date(from: text) ?? whole.date(from: text) }
    }

    private static func fast(_ b: [UInt8]) -> Date? {
        guard b.count >= 20, b[4] == 0x2D, b[7] == 0x2D, b[10] == 0x54, b[13] == 0x3A, b[16] == 0x3A else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                let digit = Int(b[index]) - 0x30
                guard (0...9).contains(digit) else { return nil }
                value = value * 10 + digit
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19),
              (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 61 else { return nil }
        var index = 19
        var fraction = 0.0
        if b[index] == 0x2E {
            var scale = 0.1
            index += 1
            while index < b.count, (0x30...0x39).contains(b[index]) {
                fraction += Double(b[index] - 0x30) * scale
                scale /= 10
                index += 1
            }
        }
        guard index < b.count else { return nil }
        var offset = 0
        if b[index] == 0x5A {
            guard index == b.count - 1 else { return nil }
        } else if b[index] == 0x2B || b[index] == 0x2D, b.count == index + 6, b[index + 3] == 0x3A,
                  let hours = number(index + 1..<index + 3), let minutes = number(index + 4..<index + 6) {
            offset = (hours * 3600 + minutes * 60) * (b[index] == 0x2B ? 1 : -1)
        } else {
            return nil
        }
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146_097 + doe - 719_468
        let seconds = Double(days * 86_400 + hour * 3600 + minute * 60 + second - offset) + fraction
        return Date(timeIntervalSince1970: seconds)
    }
}
