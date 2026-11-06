// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

final class MaxCapacityProbe {
    static let shared = MaxCapacityProbe()

    private let queue = DispatchQueue(label: "com.vorssaint.maxcapacity", qos: .utility)
    private let lock = NSLock()
    private var cached: Int?
    private var lastRefresh: TimeInterval = -.greatestFiniteMagnitude
    private var running = false
    private let interval: TimeInterval = 1800

    private init() {}

    var percent: Int? {
        lock.lock(); defer { lock.unlock() }
        return cached
    }

    func refreshIfStale() {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard !running, now - lastRefresh >= interval else {
            lock.unlock()
            return
        }
        running = true
        lastRefresh = now
        lock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            let value = Self.read()
            self.lock.lock()
            self.cached = value
            self.running = false
            self.lock.unlock()
        }
    }

    static func percent(fromSystemProfilerJSON data: Data) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return percent(in: root)
    }

    private static func read() -> Int? {
        let result = runSystemProfiler()
        guard result.status == 0,
              let data = result.output.data(using: .utf8)
        else { return nil }
        return percent(fromSystemProfilerJSON: data)
    }

    private static func runSystemProfiler() -> (status: Int32, output: String) {
        let result = BoundedProcessRunner.run(
            "/usr/sbin/system_profiler", ["SPPowerDataType", "-json"],
            timeout: 5, maxOutputBytes: 1024 * 1024)
        return (result.status, String(decoding: result.output, as: UTF8.self))
    }

    private static func percent(in value: Any) -> Int? {
        if let dict = value as? [String: Any] {
            if let raw = dict["sppower_battery_health_maximum_capacity"],
               let percent = percent(fromRawValue: raw) {
                return percent
            }
            for (key, raw) in dict {
                if normalizedMaximumCapacityKey(key),
                   let percent = percent(fromRawValue: raw) {
                    return percent
                }
            }
            for raw in dict.values {
                if let percent = percent(in: raw) {
                    return percent
                }
            }
        } else if let array = value as? [Any] {
            for raw in array {
                if let percent = percent(in: raw) {
                    return percent
                }
            }
        }
        return nil
    }

    private static func normalizedMaximumCapacityKey(_ key: String) -> Bool {
        let normalized = key.lowercased().filter(\.isLetter)
        return normalized.contains("maximumcapacity")
    }

    private static func percent(fromRawValue raw: Any) -> Int? {
        let value: Int?
        switch raw {
        case is Bool:
            value = nil
        case let raw as Int:
            value = raw
        case let raw as NSNumber:
            value = raw.intValue
        case let raw as String:
            guard let range = raw.range(of: #"[0-9]{1,3}"#, options: .regularExpression) else {
                value = nil
                break
            }
            value = Int(raw[range])
        default:
            value = nil
        }
        guard let value, value > 0, value <= 100 else { return nil }
        return value
    }
}
