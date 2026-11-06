// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

struct BoostLimiter {
    static let ceiling: Float = 0.944

    static let releaseMilliseconds: Double = 160

    static func release(sampleRate: Double) -> Float {
        let rate = sampleRate.isFinite && sampleRate >= 8000 ? sampleRate : 48000
        return Float(exp(-1000.0 / (rate * releaseMilliseconds)))
    }

    private var envelope: Float = 0

    mutating func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, channels: Int,
                          release: Float) {
        guard frames > 0, channels > 0 else { return }
        var envelope = self.envelope
        let ceiling = Self.ceiling
        var base = 0
        for _ in 0..<frames {
            var peak: Float = 0
            for channel in 0..<channels {
                let magnitude = abs(samples[base + channel])
                if magnitude > peak { peak = magnitude }
            }
            envelope = peak > envelope ? peak : peak + (envelope - peak) * release
            if envelope > ceiling {
                let gain = ceiling / envelope
                for channel in 0..<channels {
                    samples[base + channel] *= gain
                }
            }
            base += channels
        }
        self.envelope = envelope
    }
}

final class BoostLookaheadLimiter {
    static let lookaheadFrames = 256

    private let channelCapacity: Int
    private var delay: ContiguousArray<Float>
    private var position = 0
    private var filledFrames = 0
    private var activeChannels = 0
    private var gain: Float = 1
    private var targetGain: Float = 1
    private var attackFrames = 0
    private var attackStep: Float = 0
    private var holdFrames = 0

    init(channels: Int) {
        channelCapacity = max(channels, 1)
        delay = ContiguousArray(
            repeating: 0,
            count: Self.lookaheadFrames * channelCapacity)
    }

    @discardableResult
    func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, channels: Int,
                 release: Float) -> Bool {
        guard frames > 0, channels > 0, channels <= channelCapacity else { return false }
        if channels != activeChannels {
            delay.withUnsafeMutableBufferPointer { buffer in
                buffer.initialize(repeating: 0)
            }
            position = 0
            filledFrames = 0
            gain = 1
            targetGain = 1
            attackFrames = 0
            attackStep = 0
            holdFrames = 0
            activeChannels = channels
        }
        let ceiling = BoostLimiter.ceiling
        var inputBase = 0
        for _ in 0..<frames {
            var peak: Float = 0
            for channel in 0..<channels {
                let magnitude = abs(samples[inputBase + channel])
                if magnitude > peak { peak = magnitude }
            }
            let requiredGain = peak > ceiling ? ceiling / peak : 1
            let isOverCeiling = requiredGain < 1
            if requiredGain < targetGain {
                targetGain = requiredGain
                let nextStep = (targetGain - gain) / Float(Self.lookaheadFrames)
                attackStep = attackFrames > 0 ? min(attackStep, nextStep) : nextStep
                attackFrames = Self.lookaheadFrames
            }
            if isOverCeiling { holdFrames = Self.lookaheadFrames }

            if attackFrames > 0 {
                gain += attackStep
                attackFrames -= 1
                if gain <= targetGain {
                    gain = targetGain
                    attackFrames = 0
                }
            } else if isOverCeiling {
            } else if holdFrames > 0 {
                holdFrames -= 1
            } else {
                gain = 1 + (gain - 1) * release
                targetGain = gain
            }

            let delayedBase = position * channelCapacity
            for channel in 0..<channels {
                let delayed = filledFrames >= Self.lookaheadFrames
                    ? delay[delayedBase + channel]
                    : 0
                delay[delayedBase + channel] = samples[inputBase + channel]
                samples[inputBase + channel] = delayed * gain
            }
            position += 1
            if position == Self.lookaheadFrames { position = 0 }
            if filledFrames < Self.lookaheadFrames { filledFrames += 1 }
            inputBase += channels
        }
        return true
    }
}

final class BoostLookaheadBufferListLimiter {
    private let channelCapacity: Int
    private var delay: ContiguousArray<Float>
    private var position = 0
    private var filledFrames = 0
    private var activeChannels = 0
    private var gain: Float = 1
    private var targetGain: Float = 1
    private var attackFrames = 0
    private var attackStep: Float = 0
    private var holdFrames = 0

    init(channelCapacity: Int) {
        self.channelCapacity = max(1, channelCapacity)
        delay = ContiguousArray(repeating: 0,
                                count: BoostLookaheadLimiter.lookaheadFrames
                                    * self.channelCapacity)
    }

    func reset() {
        activeChannels = 0
    }

    @discardableResult
    func process(_ buffers: UnsafeMutableAudioBufferListPointer,
                 frames: Int,
                 release: Float) -> Bool {
        let channels = buffers.reduce(0) { partial, buffer in
            partial + (buffer.mData == nil ? 0 : Int(buffer.mNumberChannels))
        }
        guard frames > 0, channels > 0, channels <= channelCapacity else { return false }
        if channels != activeChannels {
            delay.withUnsafeMutableBufferPointer {
                $0.baseAddress?.update(repeating: 0, count: $0.count)
            }
            position = 0
            filledFrames = 0
            gain = 1
            targetGain = 1
            attackFrames = 0
            attackStep = 0
            holdFrames = 0
            activeChannels = channels
        }

        let ceiling = BoostLimiter.ceiling
        for frame in 0..<frames {
            var peak: Float = 0
            for buffer in buffers {
                let count = Int(buffer.mNumberChannels)
                guard count > 0,
                      let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let base = frame * count
                for channel in 0..<count {
                    peak = max(peak, abs(samples[base + channel]))
                }
            }

            let requiredGain = peak > ceiling ? ceiling / peak : 1
            let isOverCeiling = requiredGain < 1
            if requiredGain < targetGain {
                targetGain = requiredGain
                let nextStep = (targetGain - gain)
                    / Float(BoostLookaheadLimiter.lookaheadFrames)
                attackStep = attackFrames > 0 ? min(attackStep, nextStep) : nextStep
                attackFrames = BoostLookaheadLimiter.lookaheadFrames
            }
            if isOverCeiling { holdFrames = BoostLookaheadLimiter.lookaheadFrames }

            if attackFrames > 0 {
                gain += attackStep
                attackFrames -= 1
                if gain <= targetGain {
                    gain = targetGain
                    attackFrames = 0
                }
            } else if !isOverCeiling, holdFrames > 0 {
                holdFrames -= 1
            } else if !isOverCeiling {
                gain = 1 + (gain - 1) * release
                targetGain = gain
            }

            let delayedBase = position * channelCapacity
            var channelIndex = 0
            for buffer in buffers {
                let count = Int(buffer.mNumberChannels)
                guard count > 0,
                      let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let base = frame * count
                for channel in 0..<count {
                    let delayed = filledFrames >= BoostLookaheadLimiter.lookaheadFrames
                        ? delay[delayedBase + channelIndex] : 0
                    delay[delayedBase + channelIndex] = samples[base + channel]
                    samples[base + channel] = delayed * gain
                    channelIndex += 1
                }
            }
            position += 1
            if position == BoostLookaheadLimiter.lookaheadFrames { position = 0 }
            if filledFrames < BoostLookaheadLimiter.lookaheadFrames { filledFrames += 1 }
        }
        return true
    }
}

struct BoostBufferListLimiter {
    private var envelope: Float = 0

    mutating func process(_ buffers: UnsafeMutableAudioBufferListPointer,
                          frames: Int,
                          release: Float) {
        guard frames > 0 else { return }
        for frame in 0..<frames {
            var peak: Float = 0
            for buffer in buffers {
                let channels = Int(buffer.mNumberChannels)
                guard channels > 0,
                      let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let base = frame * channels
                for channel in 0..<channels { peak = max(peak, abs(samples[base + channel])) }
            }
            envelope = peak > envelope ? peak : peak + (envelope - peak) * release
            guard envelope > BoostLimiter.ceiling else { continue }
            let gain = BoostLimiter.ceiling / envelope
            for buffer in buffers {
                let channels = Int(buffer.mNumberChannels)
                guard channels > 0,
                      let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let base = frame * channels
                for channel in 0..<channels { samples[base + channel] *= gain }
            }
        }
    }
}
