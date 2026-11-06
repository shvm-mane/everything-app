// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NetworkCounters: Equatable {
    var received: UInt64 = 0
    var sent: UInt64 = 0
    var interfaces: Set<String> = []
}

struct NetworkCounterFallback {
    private(set) var isActive = false
    private var missingInboundSamples = 0

    mutating func observe(previous: NetworkCounters,
                          current: NetworkCounters) -> (sampleProcesses: Bool, useProcessDownload: Bool) {
        guard current.received >= previous.received,
              current.sent >= previous.sent else {
            reset()
            return (false, false)
        }

        if current.received > previous.received {
            reset()
            return (false, false)
        }

        let outgoingAdvanced = current.sent > previous.sent
        if isActive {
            return (true, true)
        }

        if outgoingAdvanced {
            missingInboundSamples += 1
        } else {
            missingInboundSamples = 0
        }
        if missingInboundSamples >= 2 {
            isActive = true
        }
        return (outgoingAdvanced, isActive)
    }

    mutating func reset() {
        isActive = false
        missingInboundSamples = 0
    }
}

struct DiskIOCounters: Equatable {
    var read: UInt64 = 0
    var written: UInt64 = 0
}

enum MetricFormat {
    static var locale: Locale = .current

    // MARK: Memory

    static func memoryUsed(totalBytes: UInt64,
                           appBytes: UInt64,
                           pageSize: UInt64,
                           wiredPages: UInt64,
                           compressorPages: UInt64,
                           tagStoragePages: UInt64) -> UInt64 {
        guard totalBytes > 0, pageSize > 0 else { return 0 }
        let wiredBytes = wiredPages.multipliedReportingOverflow(by: pageSize)
        guard !wiredBytes.overflow else { return 0 }
        let compressedBytes = compressorPages.multipliedReportingOverflow(by: pageSize)
        guard !compressedBytes.overflow else { return 0 }
        let tagStorageBytes = tagStoragePages.multipliedReportingOverflow(by: pageSize)
        guard !tagStorageBytes.overflow else { return 0 }
        let appAndWired = appBytes.addingReportingOverflow(wiredBytes.partialValue)
        guard !appAndWired.overflow else { return 0 }
        let withCompressed = appAndWired.partialValue.addingReportingOverflow(compressedBytes.partialValue)
        guard !withCompressed.overflow else { return 0 }
        let usedBytes = withCompressed.partialValue.addingReportingOverflow(tagStorageBytes.partialValue)
        guard !usedBytes.overflow else { return 0 }
        return min(usedBytes.partialValue, totalBytes)
    }

    static func appMemory(totalBytes: UInt64,
                          pageSize: UInt64,
                          internalPages: UInt64,
                          purgeablePages: UInt64) -> UInt64 {
        guard totalBytes > 0, pageSize > 0 else { return 0 }
        let activePages = internalPages.subtractingReportingOverflow(purgeablePages)
        guard !activePages.overflow else { return 0 }
        let activeBytes = activePages.partialValue.multipliedReportingOverflow(by: pageSize)
        guard !activeBytes.overflow else { return 0 }
        return min(activeBytes.partialValue, totalBytes)
    }

    static func compressedMemory(totalBytes: UInt64,
                                 pageSize: UInt64,
                                 compressorPages: UInt64) -> UInt64 {
        pageBytes(pageCount: compressorPages, pageSize: pageSize, totalBytes: totalBytes)
    }

    static func cachedFiles(totalBytes: UInt64,
                            pageSize: UInt64,
                            fileBackedPages: UInt64) -> UInt64 {
        pageBytes(pageCount: fileBackedPages, pageSize: pageSize, totalBytes: totalBytes)
    }

    private static func pageBytes(pageCount: UInt64, pageSize: UInt64, totalBytes: UInt64) -> UInt64 {
        guard totalBytes > 0, pageSize > 0 else { return 0 }
        let bytes = pageCount.multipliedReportingOverflow(by: pageSize)
        guard !bytes.overflow else { return 0 }
        return min(bytes.partialValue, totalBytes)
    }

    static func selectedMemory<Value>(used: Value, app: Value, metric: String) -> Value {
        metric == "app" ? app : used
    }

    static func menuBarMemoryPercent(used: UInt64?, total: UInt64?) -> String {
        guard let used, let total, total > 0 else { return "--%" }
        return percent(Double(used) / Double(total))
    }

    // MARK: Byte sizes

    static func scale(_ bytes: Double) -> (value: Double, unit: String) {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = max(0, bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        while index < units.count - 1, value.rounded() >= 1024, index == 0 || value >= 10 {
            value /= 1024
            index += 1
        }
        return (value, units[index])
    }

    private static func number(_ value: Double, unit: String) -> String {
        if unit == "B" { return String(format: "%.0f", locale: Self.locale, value) }
        return value < 10 ? String(format: "%.1f", locale: Self.locale, value) : String(format: "%.0f", locale: Self.locale, value)
    }

    static func bytes(_ bytes: UInt64) -> String {
        let (value, unit) = scale(Double(bytes))
        return "\(number(value, unit: unit)) \(unit)"
    }

    static func diskBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = max(0, Double(bytes))
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        if units[index] == "B" {
            return String(format: "%.0f B", locale: Self.locale, value)
        }
        return value < 10 ? String(format: "%.1f %@", locale: Self.locale, value, units[index])
            : String(format: "%.0f %@", locale: Self.locale, value, units[index])
    }

    static func diskBytesPrecise(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = max(0, Double(bytes))
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        let unit = units[index]
        if unit == "B" {
            return String(format: "%.0f B", locale: Self.locale, value)
        }
        if unit == "TB" || unit == "PB" {
            return String(format: "%.2f %@", locale: Self.locale, value, unit)
        }
        return value < 10 ? String(format: "%.1f %@", locale: Self.locale, value, unit)
            : String(format: "%.0f %@", locale: Self.locale, value, unit)
    }

    static func bytesPerSec(_ bytesPerSecond: Double) -> String {
        let (value, unit) = scale(bytesPerSecond)
        return "\(number(value, unit: unit)) \(unit)/s"
    }

    static func bytesPerSecCompact(_ bytesPerSecond: Double) -> String {
        let units = ["B", "K", "M", "G", "T", "P"]
        var value = bytesPerSecond.isFinite ? max(0, bytesPerSecond) : 0
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        while index < units.count - 1 {
            if index == 0 {
                guard value.rounded() >= 1024 else { break }
            } else if value >= 10 {
                guard value.rounded() >= 1024 else { break }
            } else {
                break
            }
            value /= 1024
            index += 1
        }
        if index == 0 {
            return "\(Int(value.rounded()))B"
        }
        if value < 10 {
            let rounded = (value * 10).rounded() / 10
            if rounded >= 10 {
                return "\(Int(rounded.rounded()))\(units[index])"
            }
            return String(format: "%.1f%@", locale: Self.locale, rounded, units[index])
        }
        return "\(Int(value.rounded()))\(units[index])"
    }

    static var networkSpeedInBits: Bool {
        UserDefaults.standard.string(forKey: DefaultsKey.networkSpeedUnit) == NetworkSpeedUnit.bits.rawValue
    }

    static func networkRate(_ bytesPerSecond: Double, inBits: Bool = networkSpeedInBits) -> String {
        inBits ? bitsPerSec(bytesPerSecond) : bytesPerSec(bytesPerSecond)
    }

    static func networkRateCompact(_ bytesPerSecond: Double, inBits: Bool = networkSpeedInBits) -> String {
        inBits ? bitsPerSecCompact(bytesPerSecond) : bytesPerSecCompact(bytesPerSecond)
    }

    static func bitsPerSec(_ bytesPerSecond: Double) -> String {
        let units = ["bps", "Kbps", "Mbps", "Gbps", "Tbps", "Pbps"]
        var value = bytesPerSecond.isFinite ? max(0, bytesPerSecond) * 8 : 0
        var index = 0
        while index < units.count - 1, value.rounded() >= 1000 {
            value /= 1000
            index += 1
        }
        if index == 0 {
            return String(format: "%.0f %@", locale: Self.locale, value, units[index])
        }
        return value < 10 ? String(format: "%.1f %@", locale: Self.locale, value, units[index])
            : String(format: "%.0f %@", locale: Self.locale, value, units[index])
    }

    static func bitsPerSecCompact(_ bytesPerSecond: Double) -> String {
        let units = ["b", "Kb", "Mb", "Gb", "Tb", "Pb"]
        var value = bytesPerSecond.isFinite ? max(0, bytesPerSecond) * 8 : 0
        var index = 0
        while index < units.count - 1 {
            let shown = value < 10 && index > 0 ? (value * 10).rounded() / 10 : value.rounded()
            guard shown >= 1000 else { break }
            value /= 1000
            index += 1
        }
        if index == 0 {
            return "\(Int(value.rounded()))b"
        }
        if value < 10 {
            let rounded = (value * 10).rounded() / 10
            if rounded >= 10 {
                return "\(Int(rounded.rounded()))\(units[index])"
            }
            return String(format: "%.1f%@", locale: Self.locale, rounded, units[index])
        }
        return "\(Int(value.rounded()))\(units[index])"
    }

    // MARK: Watts & percentages

    static func graphCeiling(_ peak: Double, unitStep: Double) -> Double {
        for power in 0..<6 {
            for step in [1.0, 2, 5, 10, 20, 50, 100, 200, 500] {
                let ceiling = step * pow(unitStep, Double(power))
                if ceiling >= peak { return ceiling }
            }
        }
        return peak
    }

    static func networkGraphCeiling(_ peakBytesPerSecond: Double,
                                    inBits: Bool = networkSpeedInBits) -> Double {
        guard inBits else { return graphCeiling(peakBytesPerSecond, unitStep: 1024) }
        return graphCeiling(peakBytesPerSecond * 8, unitStep: 1000) / 8
    }

    static func watts(_ value: Double) -> String {
        let magnitude = abs(value)
        return magnitude < 10 ? String(format: "%.1f W", locale: Self.locale, value) : String(format: "%.0f W", locale: Self.locale, value)
    }

    static func wattsCompact(_ value: Double) -> String {
        String(format: "%.0fW", locale: Self.locale, value.rounded())
    }

    static func systemPowerWatts(measured: Double?,
                                 batteryWatts: Double?,
                                 externalConnected: Bool) -> Double? {
        if let measured { return measured }
        guard !externalConnected, let batteryWatts, batteryWatts < 0 else { return nil }
        return -batteryWatts
    }

    static func adapterPowerWatts(measured: Double?,
                                  dcInRailWatts: Double?,
                                  hasInternalBattery: Bool,
                                  externalConnected: Bool) -> Double? {
        if let measured { return measured }
        guard !hasInternalBattery, externalConnected else { return nil }
        return dcInRailWatts
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((max(0, min(1, fraction)) * 100).rounded()))%"
    }

    static func boundedPercentage(_ percentage: Double) -> Double {
        guard percentage.isFinite else { return 0 }
        return max(0, min(100, percentage))
    }

    static func machTimeNanoseconds(_ ticks: UInt64,
                                    numerator: UInt32,
                                    denominator: UInt32) -> UInt64? {
        guard denominator > 0 else { return nil }
        let divisor = UInt64(denominator)
        let multiplier = UInt64(numerator)
        let whole = (ticks / divisor).multipliedReportingOverflow(by: multiplier)
        guard !whole.overflow else { return nil }
        let remainder = (ticks % divisor).multipliedReportingOverflow(by: multiplier)
        guard !remainder.overflow else { return nil }
        let nanoseconds = whole.partialValue.addingReportingOverflow(remainder.partialValue / divisor)
        return nanoseconds.overflow ? nil : nanoseconds.partialValue
    }

    static func processCPUPercentage(previousNanoseconds: UInt64,
                                     currentNanoseconds: UInt64,
                                     elapsed: TimeInterval,
                                     processorCount: Int) -> Double {
        guard currentNanoseconds >= previousNanoseconds,
              elapsed > 0, elapsed.isFinite else { return 0 }
        let capacityNanoseconds = elapsed * 1_000_000_000 * Double(max(1, processorCount))
        return boundedPercentage(Double(currentNanoseconds - previousNanoseconds) / capacityNanoseconds * 100)
    }

    static func processReconciliationScale(sampledTotal: Double,
                                           aggregatePercentage: Double?) -> Double {
        guard sampledTotal.isFinite, sampledTotal > 0,
              let aggregatePercentage, aggregatePercentage.isFinite else { return 1 }
        return min(1, boundedPercentage(aggregatePercentage) / sampledTotal)
    }

    static func stabilizedGPUUsage(previous: Double?, current: Double) -> Double {
        let value = current.isFinite ? max(0, min(1, current)) : 0
        guard let previous, previous.isFinite else { return value }
        let baseline = max(0, min(1, previous))
        if value > baseline {
            return min(value, baseline + 0.20)
        }
        return baseline * 0.35 + value * 0.65
    }

    static func temperature(_ celsius: Double, unit: TemperatureUnit) -> String {
        switch unit {
        case .celsius:
            return String(format: "%.0f °C", locale: Self.locale, celsius)
        case .fahrenheit:
            return String(format: "%.0f °F", locale: Self.locale, celsius * 9 / 5 + 32)
        }
    }

    static func temperatureCompact(_ celsius: Double, unit: TemperatureUnit) -> String {
        switch unit {
        case .celsius:
            return String(format: "%.0f°", locale: Self.locale, celsius)
        case .fahrenheit:
            return String(format: "%.0f°", locale: Self.locale, celsius * 9 / 5 + 32)
        }
    }

    static func temperatureUnitSuffix(_ unit: TemperatureUnit) -> String {
        switch unit {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    static func uptime(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)min" }
        return "\(minutes)min"
    }

    // MARK: Network speed & filtering

    static func netSpeed(previous: NetworkCounters,
                         current: NetworkCounters,
                         elapsed: Double) -> (down: Double, up: Double) {
        guard elapsed > 0 else { return (0, 0) }
        let down = current.received >= previous.received
            ? Double(current.received - previous.received) / elapsed : 0
        let up = current.sent >= previous.sent
            ? Double(current.sent - previous.sent) / elapsed : 0
        return (down, up)
    }

    static func diskSpeed(previous: DiskIOCounters,
                          current: DiskIOCounters,
                          elapsed: Double) -> (read: Double, write: Double) {
        guard elapsed > 0 else { return (0, 0) }
        let read = current.read >= previous.read
            ? Double(current.read - previous.read) / elapsed : 0
        let write = current.written >= previous.written
            ? Double(current.written - previous.written) / elapsed : 0
        return (read, write)
    }

    static func includeNetworkInterface(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let excluded = ["lo", "gif", "stf", "awdl", "llw", "nan", "utun", "bridge",
                        "ap", "anpi", "p2p", "XHC", "vmenet", "tap", "tun", "feth"]
        return !excluded.contains { name.hasPrefix($0) }
    }

    static func countedNetworkInterfaces(_ names: [String], primaries: [String]) -> Set<String> {
        let available = Set(names)
        let routed = primaries.filter { available.contains($0) }
        guard routed.contains(where: { $0.hasPrefix("bridge") }) else {
            return available.filter(includeNetworkInterface)
        }
        return Set(routed.filter { $0.hasPrefix("bridge") || includeNetworkInterface($0) })
    }
}

enum TemperatureUnit: String {
    case celsius
    case fahrenheit
}

enum NetworkSpeedUnit: String {
    case bytes
    case bits
}

struct MetricHistory {
    let capacity: Int
    private(set) var values: [Double] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    mutating func push(_ value: Double) {
        values.append(value)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
    }

    func publishedValues(whileVisible visible: Bool) -> [Double] {
        visible ? values : []
    }
}
