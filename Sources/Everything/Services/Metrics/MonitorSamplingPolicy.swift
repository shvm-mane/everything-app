// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MonitorSamplingKind: String {
    case cpu
    case memory
    case network
    case disk
    case power
    case powerDraw
    case peripheralBattery
    case gpuUsage
    case gpuUsageMenuBar
    case temperature
    case temperatureMenuBar
    case fanSpeed
    case fanSpeedMenuBar
    case connectedDevices
}

enum MonitorSamplingPolicy {
    static func shouldSample(_ kind: MonitorSamplingKind,
                             tick: Int,
                             intervalSeconds: Int,
                             foreground: Bool,
                             forced: Set<MonitorSamplingKind> = []) -> Bool {
        if forced.contains(kind) { return true }
        let stride = sampleStride(for: kind,
                                  intervalSeconds: intervalSeconds,
                                  foreground: foreground)
        return tick % stride == 0
    }

    static func sampleStride(for kind: MonitorSamplingKind,
                             intervalSeconds: Int,
                             foreground: Bool) -> Int {
        let interval = max(1, intervalSeconds)
        let targetSeconds = targetIntervalSeconds(for: kind, foreground: foreground)
        return max(1, Int(ceil(targetSeconds / Double(interval))))
    }

    static func wakeTicks(for kinds: [MonitorSamplingKind],
                          intervalSeconds: Int,
                          foreground: Bool) -> Int {
        let cadence = kinds.reduce(0) { partial, kind in
            gcd(partial, sampleStride(for: kind, intervalSeconds: intervalSeconds, foreground: foreground))
        }
        return max(1, cadence)
    }

    static func alignedTick(_ tick: Int, wakeTicks: Int) -> Int {
        guard wakeTicks > 1 else { return tick }
        let remainder = tick % wakeTicks
        return remainder == 0 ? tick : tick + (wakeTicks - remainder)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = a
        var b = b
        while b != 0 {
            (a, b) = (b, a % b)
        }
        return a
    }

    private static func targetIntervalSeconds(for kind: MonitorSamplingKind,
                                              foreground: Bool) -> Double {
        if foreground {
            switch kind {
            case .peripheralBattery:
                return 15
            case .connectedDevices:
                return 2
            case .cpu, .memory, .network, .disk, .power, .powerDraw, .gpuUsage, .gpuUsageMenuBar,
                 .temperature, .temperatureMenuBar, .fanSpeed, .fanSpeedMenuBar:
                return 1
            }
        }

        switch kind {
        case .cpu, .memory, .network, .powerDraw, .gpuUsageMenuBar, .temperatureMenuBar, .fanSpeedMenuBar:
            return 1
        case .gpuUsage:
            return 10
        case .fanSpeed:
            return 5
        case .connectedDevices:
            return 10
        case .power, .temperature:
            return 15
        case .disk:
            return 10
        case .peripheralBattery:
            return 60
        }
    }
}
