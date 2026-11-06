// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Accelerate
import AVFoundation
import CoreAudio
import Darwin

final class RecorderAudioFlag {
    private var bits: Int32 = 0

    var value: Bool { OSAtomicAdd32Barrier(0, &bits) != 0 }

    func raise() {
        OSAtomicCompareAndSwap32Barrier(0, 1, &bits)
    }
}

final class RecorderAudioHostTime {
    private var bits: Int64 = 0

    var value: UInt64 {
        get { UInt64(bitPattern: OSAtomicAdd64Barrier(0, &bits)) }
        set {
            let replacement = Int64(bitPattern: newValue)
            while true {
                let current = OSAtomicAdd64Barrier(0, &bits)
                if OSAtomicCompareAndSwap64Barrier(current, replacement, &bits) { return }
            }
        }
    }
}

enum RecorderAudioProbe {
    static func containsSound(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              stream.mFormatID == kAudioFormatLinearPCM,
              stream.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              stream.mBitsPerChannel == 32
        else { return false }
        let heard = try? sampleBuffer.withAudioBufferList(blockBufferMemoryAllocator: nil,
                                                          flags: []) { list, _ in
            list.contains { containsSound($0) }
        }
        return heard ?? false
    }

    static func containsSound(_ buffer: AudioBuffer) -> Bool {
        guard let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { return false }
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        guard count > 0 else { return false }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(count))
        return peak > 0
    }
}

final class RecorderSystemAudioTap: @unchecked Sendable {
    var onSample: ((CMSampleBuffer) -> Void)?

    var onReaderLost: (() -> Void)?

    var heardSound: Bool { heard.value }

    var hearsOneApp: Bool { pid != nil }

    var pipelineStart: UInt64 { pipelineStarted.value }

    var ranPipeline: Bool { ran.value }

    private let queue: DispatchQueue
    private let heard = RecorderAudioFlag()
    private let pipelineStarted = RecorderAudioHostTime()
    private let ran = RecorderAudioFlag()
    private let ownProcess: AudioObjectID
    private let pid: pid_t?
    private var tapID = AudioObjectID(0)
    private var tapUID = ""
    private var tapChannels = 2
    private var tapped: [AudioObjectID] = []
    private var awaitingApp = false
    private var clock: CMClock?
    private var aggregateID = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?
    private var hostDeviceUID: String?
    private var sampleRate: Double = 0
    private var deviceListenerClient: UnsafeMutableRawPointer?
    private var rateListenerClient: UnsafeMutableRawPointer?
    private var processListenerClient: UnsafeMutableRawPointer?
    private var stopped = false
    private let levelCompensation = AtomicFloatBox(1)
    private var levelWatch: LevelCompensationWatch?

    private static let teardownQueue = DispatchQueue(label: "com.vorssaint.recorder.systemaudio.teardown",
                                                     qos: .utility)
    private static let listenerQueue = DispatchQueue(label: "com.vorssaint.recorder.systemaudio.listeners",
                                                     qos: .utility)

    static func make(hearing pid: pid_t?) async -> RecorderSystemAudioTap? {
        guard #available(macOS 14.4, *) else { return nil }
        let queue = DispatchQueue(label: "com.vorssaint.recorder.systemaudio",
                                  qos: .userInitiated)
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: RecorderSystemAudioTap(queue: queue, pid: pid))
            }
        }
    }

    @available(macOS 14.4, *)
    private init?(queue: DispatchQueue, pid: pid_t?) {
        self.queue = queue
        self.pid = pid
        guard let ownProcess = Self.processObject(for: ProcessInfo.processInfo.processIdentifier)
        else { return nil }
        self.ownProcess = ownProcess
        let gathered = pid.map { Self.processObjects(for: $0, excluding: ownProcess) }
        if gathered?.isEmpty == true {
            awaitingApp = true
            return
        }
        guard buildTap(around: gathered) else { return nil }
    }

    @available(macOS 14.4, *)
    private func buildTap(around gathered: [AudioObjectID]? = nil) -> Bool {
        let description: CATapDescription
        if let pid {
            let objects = gathered ?? Self.processObjects(for: pid, excluding: ownProcess)
            guard !objects.isEmpty else { return false }
            tapped = objects
            description = CATapDescription(stereoMixdownOfProcesses: objects)
        } else {
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcess])
        }
        description.name = "EVERYTHING Recorder"
        description.isPrivate = true
        var tapID = AudioObjectID(0)
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != 0 else {
            return false
        }
        self.tapID = tapID
        tapUID = description.uuid.uuidString
        var format = AudioStreamBasicDescription()
        tapChannels = Self.read(tapID, kAudioTapPropertyFormat, &format) && format.mChannelsPerFrame > 0
            ? Int(format.mChannelsPerFrame)
            : 2
        return true
    }

    deinit {
        let tapID = stopped ? 0 : self.tapID
        let aggregateID = self.aggregateID
        let ioProc = self.ioProc
        levelWatch?.stop()
        Self.removeListener(deviceListenerClient, from: AudioObjectID(kAudioObjectSystemObject),
                            kAudioHardwarePropertyDefaultOutputDevice)
        Self.removeListener(processListenerClient, from: AudioObjectID(kAudioObjectSystemObject),
                            kAudioHardwarePropertyProcessObjectList)
        Self.removeListener(rateListenerClient, from: aggregateID, kAudioDevicePropertyNominalSampleRate)
        Self.destroy(aggregateID: aggregateID, ioProc: ioProc, tapID: tapID)
    }

    // MARK: - Lifecycle

    @discardableResult
    func start(synchronizingTo clock: CMClock) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                self.clock = clock
                if !stopped {
                    if !awaitingApp {
                        followProcesses()
                        buildPipeline()
                    }
                    watchDefaultOutputDevice()
                    watchProcessList()
                }
                continuation.resume(returning: aggregateID != 0 || awaitingApp)
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard !stopped else { continuation.resume(); return }
                stopped = true
                Self.removeListener(deviceListenerClient, from: AudioObjectID(kAudioObjectSystemObject),
                                    kAudioHardwarePropertyDefaultOutputDevice)
                deviceListenerClient = nil
                Self.removeListener(processListenerClient, from: AudioObjectID(kAudioObjectSystemObject),
                                    kAudioHardwarePropertyProcessObjectList)
                processListenerClient = nil
                levelWatch?.stop()
                levelWatch = nil
                teardownPipeline()
                Self.destroy(aggregateID: 0, ioProc: nil, tapID: tapID)
                continuation.resume()
            }
        }
    }

    // MARK: - Pipeline

    private func buildPipeline() {
        guard aggregateID == 0, let clock,
              let hostUID = Self.hostDeviceUID() else { return }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "EVERYTHING Recorder",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: hostUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: hostUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapDriftCompensationKey: true,
            ]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
        var aggregateID = AudioObjectID(0)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr,
              aggregateID != 0 else { return }
        let sampleRate = Self.nominalSampleRate(of: aggregateID)
        guard let format = Self.format(sampleRate: sampleRate, channels: tapChannels) else {
            Self.destroy(aggregateID: aggregateID, ioProc: nil, tapID: 0)
            return
        }

        let channels = tapChannels
        let heard = self.heard
        let onSample = self.onSample
        let compensation = levelCompensation
        let ramp = TapLevelRamp()
        let limiter = LimiterState(release: BoostLimiter.release(sampleRate: sampleRate))
        let timescale = CMTimeScale(sampleRate.rounded())
        let hostClock = CMClockGetHostTimeClock()
        var ioProc: AudioDeviceIOProcID?
        let created = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil) {
            now, input, inputTime, output, _ in
            MixerRender.silence(UnsafeMutableAudioBufferListPointer(output))
            let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let index = MixerRender.tapBufferIndex(in: inputBuffers, tapChannels: channels)
            else { return }
            let buffer = inputBuffers[index]
            if !heard.value, RecorderAudioProbe.containsSound(buffer) { heard.raise() }
            guard let onSample else { return }
            let hostTime = inputTime.pointee.mFlags.contains(.hostTimeValid)
                ? CMClockMakeHostTimeFromSystemUnits(inputTime.pointee.mHostTime)
                : CMClockGetTime(hostClock)
            let time = CMSyncConvertTime(hostTime, from: hostClock, to: clock)
            guard time.isValid,
                  let sample = Self.sampleBuffer(from: buffer, format: format,
                                                 timescale: timescale, time: time)
            else { return }
            let gain = ramp.next(toward: compensation.value, hostTime: now.pointee.mHostTime)
            if gain > 1 {
                Self.withSamples(of: sample) { samples, count in
                    RecorderSupport.restoreTapLevel(samples, count: count, channels: channels,
                                                    gain: gain, limiter: &limiter.limiter,
                                                    release: limiter.release)
                }
            } else {
                limiter.limiter = BoostLimiter()
            }
            onSample(sample)
        }
        guard created == noErr, let ioProc,
              AudioDeviceStart(aggregateID, ioProc) == noErr else {
            Self.destroy(aggregateID: aggregateID, ioProc: ioProc, tapID: 0)
            return
        }
        self.aggregateID = aggregateID
        self.ioProc = ioProc
        hostDeviceUID = hostUID
        self.sampleRate = sampleRate
        pipelineStarted.value = mach_absolute_time()
        ran.raise()
        watchSampleRate(of: aggregateID)
    }

    private func teardownPipeline() {
        let aggregateID = self.aggregateID
        let ioProc = self.ioProc
        let rateListenerClient = self.rateListenerClient
        self.aggregateID = 0
        self.ioProc = nil
        self.rateListenerClient = nil
        hostDeviceUID = nil
        pipelineStarted.value = 0
        guard aggregateID != 0 else { return }
        if let ioProc {
            AudioDeviceStop(aggregateID, ioProc)
        }
        Self.removeListener(rateListenerClient, from: aggregateID, kAudioDevicePropertyNominalSampleRate)
        Self.destroy(aggregateID: aggregateID, ioProc: ioProc, tapID: 0)
    }

    private func rebuildPipelineIfChanged() {
        guard !stopped, aggregateID != 0 else { return }
        let hostChanged = Self.hostDeviceUID() != hostDeviceUID
        let rateChanged = Self.nominalSampleRate(of: aggregateID) != sampleRate
        guard hostChanged || rateChanged else { return }
        teardownPipeline()
        buildPipeline()
        if aggregateID == 0 { onReaderLost?() }
    }

    private func rebuildTapIfProcessesChanged() {
        guard !stopped, let pid, #available(macOS 14.4, *) else { return }
        let current = Self.processObjects(for: pid, excluding: ownProcess)
        if awaitingApp {
            guard !current.isEmpty, clock != nil else { return }
            awaitingApp = false
            if buildTap(around: current) {
                followProcesses()
                buildPipeline()
            }
            if aggregateID == 0 { onReaderLost?() }
            return
        }
        guard aggregateID != 0,
              RecorderSupport.rebuildsAppTap(tapped: Set(tapped), current: Set(current)) else { return }
        teardownPipeline()
        Self.destroy(aggregateID: 0, ioProc: nil, tapID: tapID)
        tapID = 0
        levelWatch?.stop()
        levelWatch = nil
        if buildTap(around: current) {
            followProcesses()
            buildPipeline()
        }
        if aggregateID == 0 { onReaderLost?() }
    }

    private func watchProcessList() {
        guard pid != nil, processListenerClient == nil else { return }
        processListenerClient = listen(to: AudioObjectID(kAudioObjectSystemObject),
                                       kAudioHardwarePropertyProcessObjectList)
        rebuildTapIfProcessesChanged()
    }

    private func watchDefaultOutputDevice() {
        guard deviceListenerClient == nil else { return }
        deviceListenerClient = listen(to: AudioObjectID(kAudioObjectSystemObject),
                                      kAudioHardwarePropertyDefaultOutputDevice)
    }

    private func watchSampleRate(of aggregateID: AudioObjectID) {
        rateListenerClient = listen(to: aggregateID, kAudioDevicePropertyNominalSampleRate)
    }

    private func listen(to object: AudioObjectID,
                        _ selector: AudioObjectPropertySelector) -> UnsafeMutableRawPointer? {
        let client = AudioListenerClients.reserve(for: self)
        var address = Self.address(selector)
        guard AudioObjectAddPropertyListener(object, &address, Self.pipelineDeviceChanged,
                                             client) == noErr else {
            AudioListenerClients.forget(client)
            return nil
        }
        return client
    }

    private static let pipelineDeviceChanged: AudioObjectPropertyListenerProc = { _, _, _, client in
        guard let tap = AudioListenerClients.owner(of: client) as? RecorderSystemAudioTap else {
            return noErr
        }
        tap.queue.async { [weak tap] in
            tap?.rebuildPipelineIfChanged()
            tap?.rebuildTapIfProcessesChanged()
        }
        return noErr
    }

    private static func removeListener(_ client: UnsafeMutableRawPointer?, from object: AudioObjectID,
                                       _ selector: AudioObjectPropertySelector) {
        guard let client else { return }
        AudioListenerClients.forget(client)
        let removalQueue = object == AudioObjectID(kAudioObjectSystemObject)
            ? listenerQueue
            : teardownQueue
        removalQueue.async {
            var address = Self.address(selector)
            AudioObjectRemovePropertyListener(object, &address, Self.pipelineDeviceChanged, client)
        }
    }

    // MARK: - Level

    private func followProcesses() {
        guard !stopped, levelWatch == nil else { return }
        let compensation = levelCompensation
        let store: (Float) -> Void = { compensation.value = $0 }
        let watch = pid == nil
            ? LevelCompensationWatch.started(everyProcessExcept: [ownProcess], store: store)
            : LevelCompensationWatch.started(objects: tapped, store: store)
        watch.waitForFirstRead()
        levelWatch = watch
    }

    private static func destroy(aggregateID: AudioObjectID,
                                ioProc: AudioDeviceIOProcID?,
                                tapID: AudioObjectID) {
        guard aggregateID != 0 || tapID != 0 else { return }
        teardownQueue.async {
            if aggregateID != 0 {
                if let ioProc {
                    AudioDeviceDestroyIOProcID(aggregateID, ioProc)
                }
                AudioHardwareDestroyAggregateDevice(aggregateID)
            }
            if tapID != 0, #available(macOS 14.4, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
        }
    }

    // MARK: - Samples

    private final class LimiterState {
        var limiter = BoostLimiter()
        let release: Float

        init(release: Float) {
            self.release = release
        }
    }

    private static func withSamples(of sampleBuffer: CMSampleBuffer,
                                    _ body: (UnsafeMutablePointer<Float>, Int) -> Void) {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var length = 0
        var data: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: &length,
                                          totalLengthOut: nil,
                                          dataPointerOut: &data) == kCMBlockBufferNoErr,
              let data else { return }
        let count = length / MemoryLayout<Float>.size
        data.withMemoryRebound(to: Float.self, capacity: count) { body($0, count) }
    }

    private static func format(sampleRate: Double, channels: Int) -> CMAudioFormatDescription? {
        guard sampleRate > 0, channels > 0 else { return nil }
        let bytesPerFrame = UInt32(channels * MemoryLayout<Float>.size)
        var stream = AudioStreamBasicDescription(mSampleRate: sampleRate,
                                                 mFormatID: kAudioFormatLinearPCM,
                                                 mFormatFlags: kAudioFormatFlagIsFloat
                                                     | kAudioFormatFlagIsPacked,
                                                 mBytesPerPacket: bytesPerFrame,
                                                 mFramesPerPacket: 1,
                                                 mBytesPerFrame: bytesPerFrame,
                                                 mChannelsPerFrame: UInt32(channels),
                                                 mBitsPerChannel: 32,
                                                 mReserved: 0)
        var description: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                             asbd: &stream,
                                             layoutSize: 0,
                                             layout: nil,
                                             magicCookieSize: 0,
                                             magicCookie: nil,
                                             extensions: nil,
                                             formatDescriptionOut: &description) == noErr
        else { return nil }
        return description
    }

    private static func sampleBuffer(from buffer: AudioBuffer,
                                     format: CMAudioFormatDescription,
                                     timescale: CMTimeScale,
                                     time: CMTime) -> CMSampleBuffer? {
        let frames = MixerRender.frames(bytes: buffer.mDataByteSize, channels: buffer.mNumberChannels)
        guard frames > 0 else { return nil }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: timescale),
                                        presentationTimeStamp: time,
                                        decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreate(allocator: kCFAllocatorDefault,
                                   dataBuffer: nil,
                                   dataReady: false,
                                   makeDataReadyCallback: nil,
                                   refcon: nil,
                                   formatDescription: format,
                                   sampleCount: frames,
                                   sampleTimingEntryCount: 1,
                                   sampleTimingArray: &timing,
                                   sampleSizeEntryCount: 0,
                                   sampleSizeArray: nil,
                                   sampleBufferOut: &sampleBuffer) == noErr,
              let sampleBuffer
        else { return nil }
        var list = AudioBufferList(mNumberBuffers: 1, mBuffers: buffer)
        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: &list) == noErr
        else { return nil }
        return sampleBuffer
    }

    // MARK: - Audio system

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func read<T>(_ object: AudioObjectID,
                                _ selector: AudioObjectPropertySelector,
                                _ value: inout T,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Bool {
        var address = address(selector, scope: scope)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size,
                                       UnsafeMutableRawPointer(pointer)) == noErr
        }
    }

    @available(macOS 14.4, *)
    private static func processObjects(for pid: pid_t, excluding own: AudioObjectID) -> [AudioObjectID] {
        var objects: [AudioObjectID] = []
        for object in AppVolumeMixer.audioProcessObjects() where object != own {
            var owner: pid_t = -1
            guard read(object, kAudioProcessPropertyPID, &owner), owner > 0,
                  owner == pid || ResponsibleProcess.regularAppOwner(of: owner)?.processIdentifier == pid
            else { continue }
            objects.append(object)
        }
        return objects
    }

    private static func processObject(for pid: pid_t) -> AudioObjectID? {
        var pid = pid
        var object = AudioObjectID(0)
        var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &pid) { pidPointer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<pid_t>.size), pidPointer,
                                       &size, &object)
        }
        guard status == noErr, object != 0 else { return nil }
        return object
    }

    private static func nominalSampleRate(of deviceID: AudioObjectID) -> Double {
        var sampleRate: Float64 = 0
        guard read(deviceID, kAudioDevicePropertyNominalSampleRate, &sampleRate), sampleRate > 0
        else { return 48_000 }
        return sampleRate
    }

    private static func hostDeviceUID() -> String? {
        var defaultDevice = AudioObjectID(0)
        guard read(AudioObjectID(kAudioObjectSystemObject),
                   kAudioHardwarePropertyDefaultOutputDevice, &defaultDevice),
              defaultDevice != 0 else { return nil }
        var uid: CFString = "" as CFString
        guard read(defaultDevice, kAudioDevicePropertyDeviceUID, &uid) else { return nil }
        return uid as String
    }
}
