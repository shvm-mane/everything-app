// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchAudioLevelSupport {
    static let bandCount = 7
    static let bandEdgesHz: [Double] = [50, 120, 250, 500, 1000, 2000, 4500, 12_000]
    static let floorDecibels = 60.0
    static let updatesPerSecond = 30.0
    static let silenceGrace = 8.0

    static let processSettle = 0.25

    static func fallsBack(heard: Bool, elapsed: TimeInterval) -> Bool {
        !heard && elapsed >= silenceGrace
    }

    enum TapChange: Equatable {
        case none
        case rebuild
        case restart
    }

    static func tapChange<Process: Hashable>(tapped: Set<Process>, current: Set<Process>) -> TapChange {
        if current == tapped { return .none }
        if !tapped.isSubset(of: current) { return .restart }
        return .rebuild
    }

    struct SilenceMemory: Equatable {
        private var givenUp: NotchMusicIdentity?

        func reads(_ identity: NotchMusicIdentity) -> Bool { identity != givenUp }
        mutating func giveUp(on identity: NotchMusicIdentity) { givenUp = identity }
        mutating func rearm() { givenUp = nil }
    }

    static var isSupported: Bool {
        if #available(macOS 14.4, *) { return true }
        return false
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.notchLiveEqualizer)
    }

    static func bandRanges(sampleRate: Double, size: Int) -> [Range<Int>] {
        let usable = max(2, size / 2)
        let binWidth = sampleRate > 0 && size > 0 ? sampleRate / Double(size) : 1
        var ranges: [Range<Int>] = []
        for band in 0..<bandCount {
            var lower = Int((bandEdgesHz[band] / binWidth).rounded(.down))
            var upper = Int((bandEdgesHz[band + 1] / binWidth).rounded(.down))
            lower = min(max(lower, 1), usable - 1)
            upper = min(max(upper, lower + 1), usable)
            ranges.append(lower..<upper)
        }
        return ranges
    }

    static func bandLevels(magnitudes: [Float], bands: [Range<Int>]) -> [Double] {
        bands.map { band in
            let clipped = band.clamped(to: 0..<magnitudes.count)
            guard !clipped.isEmpty else { return 0 }
            var sum: Float = 0
            for bin in clipped { sum += magnitudes[bin] }
            let mean = Double(sum) / Double(clipped.count)
            guard mean > 0 else { return 0 }
            let decibels = 20 * log10(mean)
            return min(1, max(0, (decibels + floorDecibels) / floorDecibels))
        }
    }

    static func barIndex(_ bar: Int, of bars: Int, bands: Int) -> Int {
        guard bars > 0, bands > 0 else { return 0 }
        let position = (Double(bar) + 0.5) / Double(bars) * Double(bands)
        return min(bands - 1, max(0, Int(position.rounded(.down))))
    }

    struct Smoother {
        static let attack = 0.55
        static let decay = 0.12
        static let ceilingDecay = 0.995
        static let peakTarget = 0.92
        private var levels: [Double] = []
        private var ceiling = 0.05

        init() {}

        mutating func next(_ raw: [Double]) -> [Double] {
            if levels.count != raw.count { levels = Array(repeating: 0, count: raw.count) }
            ceiling = max(raw.max() ?? 0, ceiling * Self.ceilingDecay, 0.05)
            let gain = Self.peakTarget / ceiling
            for index in raw.indices {
                let target = min(1, max(0, raw[index] * gain))
                let rate = target > levels[index] ? Self.attack : Self.decay
                levels[index] += (target - levels[index]) * rate
            }
            return levels
        }
    }
}
