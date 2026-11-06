// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Accelerate
import CoreAudio
import Darwin

struct MixerTapFormat: Equatable {
    let sampleRate: Double
    let channels: Int
    let flags: AudioFormatFlags

    init?(_ format: AudioStreamBasicDescription, allowNonInterleaved: Bool = false) {
        let channels = Int(format.mChannelsPerFrame)
        let planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mFormatFlags & kAudioFormatFlagIsPacked != 0,
              allowNonInterleaved || !planar,
              format.mFormatFlags & kAudioFormatFlagIsBigEndian == kAudioFormatFlagsNativeEndian,
              format.mBitsPerChannel == 32, channels > 0,
              UInt64(format.mBytesPerFrame) == UInt64(planar ? 1 : channels) * 4,
              format.mFramesPerPacket == 1,
              format.mBytesPerPacket == format.mBytesPerFrame,
              format.mSampleRate.isFinite, format.mSampleRate > 0 else { return nil }
        sampleRate = format.mSampleRate
        self.channels = channels
        flags = format.mFormatFlags
    }

    static func usesDeviceStream(processDevices: [[AudioObjectID]], outputDevice: AudioObjectID,
                                 streamCount: Int, startingChannel: UInt32,
                                 format: MixerTapFormat?) -> Bool {
        guard outputDevice != 0, streamCount == 1, startingChannel == 1,
              let format, format.channels > 2 else { return false }
        let devices = Set(processDevices.flatMap { $0 })
        return devices == [outputDevice]
    }
}

enum MixerRender {
    static func frames(bytes: UInt32, channels: UInt32) -> Int {
        guard channels > 0 else { return 0 }
        return Int(bytes) / (MemoryLayout<Float>.size * Int(channels))
    }

    static func tapBufferIndex(in buffers: UnsafeMutableAudioBufferListPointer,
                               tapChannels: Int) -> Int? {
        var lone: Int?
        for index in stride(from: buffers.count - 1, through: 0, by: -1)
        where buffers[index].mNumberChannels > 0 {
            if Int(buffers[index].mNumberChannels) == tapChannels {
                return buffers[index].mData == nil ? nil : index
            }
            if buffers.count == 1, buffers[index].mData != nil { lone = index }
        }
        return lone
    }

    static func sourceChannel(for outputChannel: Int, sourceChannels: Int) -> Int? {
        if outputChannel < sourceChannels { return outputChannel }
        if sourceChannels == 1, outputChannel == 1 { return 0 }
        return nil
    }

    static func silence(_ output: UnsafeMutableAudioBufferListPointer, from frame: Int = 0) {
        for buffer in output {
            if frame == 0 {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
                continue
            }
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0,
                  let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let unwritten = frames(bytes: buffer.mDataByteSize,
                                   channels: buffer.mNumberChannels) - frame
            guard unwritten > 0 else { continue }
            vDSP_vclr(destination + frame * channels, 1, vDSP_Length(unwritten * channels))
        }
    }

    @discardableResult
    static func render(source: AudioBuffer,
                       into output: UnsafeMutableAudioBufferListPointer,
                       gain: Float) -> Int {
        var written = 0
        defer { silence(output, from: written) }
        let sourceChannels = Int(source.mNumberChannels)
        guard sourceChannels > 0,
              let samples = source.mData?.assumingMemoryBound(to: Float.self) else { return 0 }

        var frames = self.frames(bytes: source.mDataByteSize, channels: source.mNumberChannels)
        var outputChannels = 0
        var hasWritableOutput = false
        for buffer in output where buffer.mNumberChannels > 0 {
            outputChannels += Int(buffer.mNumberChannels)
            guard buffer.mData != nil else { continue }
            hasWritableOutput = true
            frames = min(frames, self.frames(bytes: buffer.mDataByteSize,
                                             channels: buffer.mNumberChannels))
        }
        guard frames > 0, outputChannels > 0, hasWritableOutput else { return 0 }
        var gain = gain

        if output.count == 1, Int(output[0].mNumberChannels) == sourceChannels,
           let destination = output[0].mData?.assumingMemoryBound(to: Float.self) {
            vDSP_vsmul(samples, 1, &gain, destination, 1, vDSP_Length(frames * sourceChannels))
            written = frames
            return written
        }

        if outputChannels == 1, sourceChannels > 1 {
            guard let buffer = output.first(where: { $0.mNumberChannels == 1 && $0.mData != nil }),
                  let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { return 0 }
            var scale = gain / Float(sourceChannels)
            vDSP_vsmul(samples, vDSP_Stride(sourceChannels), &scale,
                       destination, 1, vDSP_Length(frames))
            for channel in 1..<sourceChannels {
                vDSP_vsma(samples + channel, vDSP_Stride(sourceChannels), &scale,
                          destination, 1, destination, 1, vDSP_Length(frames))
            }
            written = frames
            return written
        }

        var firstOutputChannel = 0
        var didWriteSourceChannel = false
        for buffer in output {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0 else { continue }
            defer { firstOutputChannel += channels }
            guard let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for channel in 0..<channels {
                guard let sourceChannel = sourceChannel(for: firstOutputChannel + channel,
                                                        sourceChannels: sourceChannels) else {
                    vDSP_vclr(destination + channel, vDSP_Stride(channels), vDSP_Length(frames))
                    continue
                }
                didWriteSourceChannel = true
                vDSP_vsmul(samples + sourceChannel, vDSP_Stride(sourceChannels), &gain,
                           destination + channel, vDSP_Stride(channels), vDSP_Length(frames))
            }
        }
        written = didWriteSourceChannel ? frames : 0
        return written
    }
}
