// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Accelerate
import AppKit
import Combine
import CoreAudio
import Foundation

final class NotchAudioLevelService: ObservableObject {
    static let shared = NotchAudioLevelService()

    @Published private(set) var levels: [Double]?

    private var enabled = false
    private var subscription: AnyCancellable?
    private var reader: NotchAudioLevelReader?
    private var readerPID: pid_t = 0
    private var readerID: UUID?
    private var silence = NotchAudioLevelSupport.SilenceMemory()
    private var stopWork: DispatchWorkItem?

    private init() {}

    func syncWithPreferences() {
        enabled = AppFeature.notchLiveEqualizer.isAvailable && NotchSupport.isEnabled()
            && NotchAudioLevelSupport.isSupported && NotchAudioLevelSupport.isEnabled()
            && !PerformanceMode.reduceMotion
        if enabled {
            if subscription == nil {
                silence.rearm()
                subscription = NotchMusicService.shared.$playback
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] playback in self?.playbackChanged(playback) }
            }
        } else {
            subscription = nil
            stop()
        }
    }

    func stop() {
        stopWork?.cancel(); stopWork = nil
        reader?.stop()
        reader = nil
        readerPID = 0
        readerID = nil
        if levels != nil { levels = nil }
    }

    private func playbackChanged(_ playback: NotchPlayback?) {
        guard enabled, let playback, playback.isPlaying,
              let pid = playback.track.appPID, pid > 0 else {
            silence.rearm()
            scheduleStop()
            return
        }
        let resumeBeforeSound = stopWork != nil && levels == nil
        stopWork?.cancel(); stopWork = nil
        guard readerPID != pid || resumeBeforeSound else { return }
        stop()
        let identity = NotchMusicIdentity(playback)
        guard silence.reads(identity) else { return }
        readerPID = pid
        read(pid, on: identity)
    }

    private func read(_ pid: pid_t, on identity: NotchMusicIdentity) {
        let id = UUID()
        readerID = id
        let created = NotchAudioLevelReader(pid: pid, onLevels: { [weak self] next in
            DispatchQueue.main.async {
                guard let self, self.readerID == id else { return }
                self.receive(next, from: pid)
            }
        }, onSilence: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.readerID == id else { return }
                self.giveUp(pid, on: identity)
            }
        }, onUnavailable: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.readerID == id else { return }
                self.release(pid)
            }
        }, onProcessesLeft: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.readerID == id else { return }
                self.restart(pid, on: identity)
            }
        })
        reader = created
        created.start()
    }

    private func restart(_ pid: pid_t, on identity: NotchMusicIdentity) {
        guard enabled, readerPID == pid else { return }
        let pausing = stopWork != nil
        stop()
        guard !pausing else { return }
        readerPID = pid
        read(pid, on: identity)
    }

    private func giveUp(_ pid: pid_t, on identity: NotchMusicIdentity) {
        guard readerPID == pid else { return }
        if stopWork == nil { silence.giveUp(on: identity) }
        stop()
    }

    private func release(_ pid: pid_t) {
        guard readerPID == pid else { return }
        stop()
    }

    private func scheduleStop() {
        guard reader != nil || levels != nil, stopWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.stopWork = nil
            self?.stop()
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func receive(_ next: [Double], from pid: pid_t) {
        guard reader != nil, readerPID == pid, levels != next else { return }
        levels = next
    }
}

private enum NotchAudioLevelListeners {
    private static let lock = NSLock()
    private static var readers: [UInt: NotchAudioLevelReader] = [:]
    private static var counter: UInt = 0

    static func reserve() -> UnsafeMutableRawPointer {
        lock.lock()
        defer { lock.unlock() }
        counter &+= 1
        if counter == 0 { counter = 1 }
        return UnsafeMutableRawPointer(bitPattern: counter).unsafelyUnwrapped
    }

    static func attach(_ reader: NotchAudioLevelReader, to client: UnsafeMutableRawPointer) {
        lock.lock()
        defer { lock.unlock() }
        readers[UInt(bitPattern: client)] = reader
    }

    static func forget(_ client: UnsafeMutableRawPointer) {
        lock.lock()
        defer { lock.unlock() }
        readers[UInt(bitPattern: client)] = nil
    }

    static func reader(for client: UnsafeMutableRawPointer?) -> NotchAudioLevelReader? {
        guard let client else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return readers[UInt(bitPattern: client)]
    }
}

private final class NotchAudioLevelReader {
    private let queue = DispatchQueue(label: "com.vorssaint.notch-audio-levels", qos: .utility)
    private static let teardownQueue = DispatchQueue(label: "com.vorssaint.notch-audio-levels.teardown", qos: .utility)
    private let pid: pid_t
    private let onLevels: ([Double]) -> Void
    private let onSilence: () -> Void
    private let onUnavailable: () -> Void
    private let onProcessesLeft: () -> Void
    private let ring = NotchAudioRing(capacity: 8192)
    private var startedAt: TimeInterval = 0
    private var tapID = AudioObjectID(0)
    private var tapUID = ""
    private var tapChannels = 2
    private var aggregateID = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?
    private var timer: DispatchSourceTimer?
    private var analyzer: NotchAudioAnalyzer?
    private var smoother = NotchAudioLevelSupport.Smoother()
    private var samples: [Float] = []
    private var hostDeviceUID: String?
    private var sampleRate: Double = 0
    private var tapped: [AudioObjectID] = []
    private var levelCompensation: Float = 1
    private var levelWatch: LevelCompensationWatch?
    private let listenerClient = NotchAudioLevelListeners.reserve()
    private var deviceListening = false
    private var processListening = false
    private var rateListenerDevice = AudioObjectID(0)
    private var processCheck: DispatchWorkItem?
    private var stopped = false

    init(pid: pid_t, onLevels: @escaping ([Double]) -> Void,
         onSilence: @escaping () -> Void, onUnavailable: @escaping () -> Void,
         onProcessesLeft: @escaping () -> Void) {
        self.pid = pid
        self.onLevels = onLevels
        self.onSilence = onSilence
        self.onUnavailable = onUnavailable
        self.onProcessesLeft = onProcessesLeft
    }

    deinit {
        Self.destroy(aggregateID: aggregateID, ioProc: ioProc, tapID: tapID)
    }

    func start() {
        queue.async { [self] in
            guard !stopped else { return }
            NotchAudioLevelListeners.attach(self, to: listenerClient)
            guard buildTap(), buildPipeline() else {
                release(reporting: onUnavailable)
                return
            }
            watchDefaultOutputDevice()
            watchProcessList()
            startAnalysis()
        }
    }

    func stop() {
        queue.async { [self] in
            guard !stopped else { return }
            release(reporting: nil)
        }
    }

    // MARK: - Pipeline

    private func buildTap() -> Bool {
        guard #available(macOS 14.4, *), tapID == 0 else { return false }
        let objects = Self.processObjects(for: pid)
        guard !objects.isEmpty else { return false }
        tapped = objects
        let description = CATapDescription(stereoMixdownOfProcesses: objects)
        description.name = "EVERYTHING Island Levels"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tapID = AudioObjectID(0)
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != 0 else { return false }
        self.tapID = tapID
        tapUID = description.uuid.uuidString
        var format = AudioStreamBasicDescription()
        if Self.read(tapID, kAudioTapPropertyFormat, &format), format.mChannelsPerFrame > 0 {
            tapChannels = Int(format.mChannelsPerFrame)
        }
        followLevel(of: objects)
        return true
    }

    private func followLevel(of objects: [AudioObjectID]) {
        let watch = LevelCompensationWatch.started(objects: objects) { [weak self] value in
            self?.queue.async { [weak self] in
                guard let self, !self.stopped, self.tapped == objects else { return }
                self.levelCompensation = value
            }
        }
        stopFollowingLevel()
        levelWatch = watch
    }

    private func stopFollowingLevel() {
        levelWatch?.stop()
        levelWatch = nil
    }

    private func buildPipeline() -> Bool {
        buildPipeline(includingOutput: false) || buildPipeline(includingOutput: true)
    }

    private func buildPipeline(includingOutput: Bool) -> Bool {
        guard aggregateID == 0, tapID != 0, let hostUID = Self.hostDeviceUID() else { return false }
        var aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "EVERYTHING Island Levels",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tapUID,
                kAudioSubTapDriftCompensationKey: includingOutput,
            ]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
        if includingOutput {
            aggregate[kAudioAggregateDeviceMainSubDeviceKey] = hostUID
            aggregate[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: hostUID]]
        }
        var aggregateID = AudioObjectID(0)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr,
              aggregateID != 0 else { return false }
        var frames: UInt32 = 1024
        var bufferAddress = Self.address(kAudioDevicePropertyBufferFrameSize)
        _ = AudioObjectSetPropertyData(aggregateID, &bufferAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &frames)
        let sampleRate = Self.nominalSampleRate(of: aggregateID)
        guard let analyzer = NotchAudioAnalyzer(sampleRate: sampleRate) else {
            Self.destroy(aggregateID: aggregateID, ioProc: nil, tapID: 0)
            return false
        }
        let ring = self.ring
        let channels = tapChannels
        var ioProc: AudioDeviceIOProcID?
        let created = AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil) { _, input, _, output, _ in
            if includingOutput { MixerRender.silence(UnsafeMutableAudioBufferListPointer(output)) }
            let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let index = MixerRender.tapBufferIndex(in: inputBuffers, tapChannels: channels) else { return }
            ring.write(inputBuffers[index])
        }
        guard created == noErr, let ioProc, AudioDeviceStart(aggregateID, ioProc) == noErr else {
            Self.destroy(aggregateID: aggregateID, ioProc: ioProc, tapID: 0)
            return false
        }
        self.aggregateID = aggregateID
        self.ioProc = ioProc
        self.analyzer = analyzer
        self.hostDeviceUID = hostUID
        self.sampleRate = sampleRate
        samples = [Float](repeating: 0, count: analyzer.size)
        watchSampleRate(of: aggregateID)
        return true
    }

    private func teardownPipeline() {
        let aggregateID = self.aggregateID
        let ioProc = self.ioProc
        let rateDevice = rateListenerDevice
        self.aggregateID = 0
        self.ioProc = nil
        rateListenerDevice = 0
        analyzer = nil
        hostDeviceUID = nil
        if rateDevice != 0 {
            var address = Self.address(kAudioDevicePropertyNominalSampleRate)
            AudioObjectRemovePropertyListener(rateDevice, &address, Self.deviceCallback, listenerClient)
        }
        guard aggregateID != 0 else { return }
        if let ioProc { AudioDeviceStop(aggregateID, ioProc) }
        Self.destroy(aggregateID: aggregateID, ioProc: ioProc, tapID: 0)
    }

    private func release(reporting callback: (() -> Void)?) {
        stopped = true
        stopAnalysis()
        processCheck?.cancel()
        processCheck = nil
        if deviceListening {
            var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &address,
                                              Self.deviceCallback, listenerClient)
            deviceListening = false
        }
        if processListening {
            var address = Self.address(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &address,
                                              Self.processCallback, listenerClient)
            processListening = false
        }
        stopFollowingLevel()
        tapped = []
        teardownPipeline()
        let tapID = self.tapID
        self.tapID = 0
        Self.destroy(aggregateID: 0, ioProc: nil, tapID: tapID)
        NotchAudioLevelListeners.forget(listenerClient)
        callback?()
    }

    private func rebuildIfDeviceChanged() {
        guard !stopped, aggregateID != 0 else { return }
        guard Self.hostDeviceUID() != hostDeviceUID
                || Self.nominalSampleRate(of: aggregateID) != sampleRate else { return }
        teardownPipeline()
        if !buildPipeline() { release(reporting: onUnavailable) }
    }

    private func watchDefaultOutputDevice() {
        guard !deviceListening else { return }
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        deviceListening = AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &address,
                                                         Self.deviceCallback, listenerClient) == noErr
    }

    private func watchProcessList() {
        guard !processListening else { return }
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        processListening = AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &address,
                                                          Self.processCallback, listenerClient) == noErr
    }

    private func watchSampleRate(of aggregateID: AudioObjectID) {
        var address = Self.address(kAudioDevicePropertyNominalSampleRate)
        if AudioObjectAddPropertyListener(aggregateID, &address,
                                          Self.deviceCallback, listenerClient) == noErr {
            rateListenerDevice = aggregateID
        }
    }

    private func tappedProcessesChanged() {
        processCheck = nil
        guard !stopped, !tapped.isEmpty else { return }
        guard #available(macOS 14.4, *) else { return }
        switch NotchAudioLevelSupport.tapChange(tapped: Set(tapped),
                                                current: Set(Self.processObjects(for: pid))) {
        case .none: return
        case .restart: release(reporting: onProcessesLeft)
        case .rebuild: rebuildTap()
        }
    }

    private func rebuildTap() {
        teardownPipeline()
        let previous = tapID
        tapID = 0
        tapped = []
        Self.destroy(aggregateID: 0, ioProc: nil, tapID: previous)
        if !buildTap() || !buildPipeline() { release(reporting: onProcessesLeft) }
    }

    private func scheduleProcessCheck() {
        guard !stopped, !tapped.isEmpty else { return }
        processCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.tappedProcessesChanged() }
        processCheck = work
        queue.asyncAfter(deadline: .now() + NotchAudioLevelSupport.processSettle, execute: work)
    }

    // MARK: - Listeners

    private static let deviceCallback: AudioObjectPropertyListenerProc = { _, _, _, client in
        NotchAudioLevelListeners.reader(for: client)?.deviceChanged()
        return noErr
    }

    private static let processCallback: AudioObjectPropertyListenerProc = { _, _, _, client in
        NotchAudioLevelListeners.reader(for: client)?.processListChanged()
        return noErr
    }

    fileprivate func deviceChanged() {
        queue.async { [self] in rebuildIfDeviceChanged() }
    }

    fileprivate func processListChanged() {
        queue.async { [self] in scheduleProcessCheck() }
    }

    // MARK: - Analysis

    private func startAnalysis() {
        startedAt = ProcessInfo.processInfo.systemUptime
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.1, repeating: 1 / NotchAudioLevelSupport.updatesPerSecond, leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.analyse() }
        self.timer = timer
        timer.resume()
    }

    private func stopAnalysis() {
        timer?.cancel()
        timer = nil
    }

    private func analyse() {
        guard !stopped, let analyzer else { return }
        guard ring.hasHeard(gain: levelCompensation) else {
            if NotchAudioLevelSupport.fallsBack(heard: false, elapsed: ProcessInfo.processInfo.systemUptime - startedAt) {
                release(reporting: onSilence)
            }
            return
        }
        guard ring.latest(into: &samples) else { return }
        if levelCompensation > 1 {
            var gain = levelCompensation
            samples.withUnsafeMutableBufferPointer { buffer in
                vDSP_vsmul(buffer.baseAddress!, 1, &gain, buffer.baseAddress!, 1, vDSP_Length(buffer.count))
            }
        }
        let magnitudes = analyzer.magnitudes(of: samples)
        let raw = NotchAudioLevelSupport.bandLevels(magnitudes: magnitudes, bands: analyzer.bands)
        onLevels(smoother.next(raw))
    }

    // MARK: - Core Audio

    private static func destroy(aggregateID: AudioObjectID, ioProc: AudioDeviceIOProcID?, tapID: AudioObjectID) {
        guard aggregateID != 0 || tapID != 0 else { return }
        teardownQueue.async {
            if aggregateID != 0 {
                if let ioProc { AudioDeviceDestroyIOProcID(aggregateID, ioProc) }
                AudioHardwareDestroyAggregateDevice(aggregateID)
            }
            if tapID != 0, #available(macOS 14.4, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout T) -> Bool {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, UnsafeMutableRawPointer(pointer)) == noErr
        }
    }

    @available(macOS 14.4, *)
    private static func processObjects(for pid: pid_t) -> [AudioObjectID] {
        var objects: [AudioObjectID] = []
        for object in AppVolumeMixer.audioProcessObjects() {
            var owner: pid_t = -1
            guard read(object, kAudioProcessPropertyPID, &owner), owner > 0,
                  owner == pid || ResponsibleProcess.regularAppOwner(of: owner)?.processIdentifier == pid
            else { continue }
            objects.append(object)
        }
        if objects.isEmpty, let direct = processObject(for: pid) { objects.append(direct) }
        return objects
    }

    private static func processObject(for pid: pid_t) -> AudioObjectID? {
        var pid = pid
        var object = AudioObjectID(0)
        var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &pid) { pidPointer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<pid_t>.size), pidPointer, &size, &object)
        }
        guard status == noErr, object != 0 else { return nil }
        return object
    }

    private static func nominalSampleRate(of deviceID: AudioObjectID) -> Double {
        var sampleRate: Float64 = 0
        guard read(deviceID, kAudioDevicePropertyNominalSampleRate, &sampleRate), sampleRate > 0 else { return 48_000 }
        return sampleRate
    }

    private static func hostDeviceUID() -> String? {
        var defaultDevice = AudioObjectID(0)
        guard read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, &defaultDevice),
              defaultDevice != 0 else { return nil }
        var uid: CFString = "" as CFString
        guard read(defaultDevice, kAudioDevicePropertyDeviceUID, &uid) else { return nil }
        return uid as String
    }
}

private final class NotchAudioRing {
    private let lock = NSLock()
    private var samples: [Float]
    private var head = 0
    private var filled = 0
    private var peak: Float = 0
    private var heard = false
    private let capacity: Int

    func hasHeard(gain: Float) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if peak * gain > 0.001 { heard = true }
        return heard
    }

    init(capacity: Int) {
        self.capacity = capacity
        samples = [Float](repeating: 0, count: capacity)
    }

    func write(_ buffer: AudioBuffer) {
        guard lock.try() else { return }
        defer { lock.unlock() }
        let channels = Int(buffer.mNumberChannels)
        guard channels > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return }
        let frames = MixerRender.frames(bytes: buffer.mDataByteSize, channels: buffer.mNumberChannels)
        let scale = 1 / Float(channels)
        var loudest: Float = 0
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channels { sum += data[frame * channels + channel] }
            let mono = sum * scale
            samples[head] = mono
            head = (head + 1) % capacity
            loudest = max(loudest, abs(mono))
        }
        filled = min(capacity, filled + frames)
        peak = max(peak, loudest)
    }

    func latest(into output: inout [Float]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let count = output.count
        guard count > 0, count <= capacity, filled >= count else { return false }
        var index = (head - count + capacity) % capacity
        for position in 0..<count {
            output[position] = samples[index]
            index = (index + 1) % capacity
        }
        return true
    }
}

private final class NotchAudioAnalyzer {
    let size = 1024
    let bands: [Range<Int>]
    private let setup: vDSP_DFT_Setup
    private var window: [Float]
    private var windowed: [Float]
    private var imaginary: [Float]
    private var outReal: [Float]
    private var outImaginary: [Float]
    private var magnitudes: [Float]

    init?(sampleRate: Double) {
        guard let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(size), .FORWARD) else { return nil }
        self.setup = setup
        window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        windowed = [Float](repeating: 0, count: size)
        imaginary = [Float](repeating: 0, count: size)
        outReal = [Float](repeating: 0, count: size)
        outImaginary = [Float](repeating: 0, count: size)
        magnitudes = [Float](repeating: 0, count: size / 2)
        bands = NotchAudioLevelSupport.bandRanges(sampleRate: sampleRate, size: size)
    }

    deinit { vDSP_DFT_DestroySetup(setup) }

    func magnitudes(of samples: [Float]) -> [Float] {
        guard samples.count == size else { return magnitudes }
        let length = vDSP_Length(size)
        let half = vDSP_Length(size / 2)
        samples.withUnsafeBufferPointer { input in
            window.withUnsafeBufferPointer { taper in
                windowed.withUnsafeMutableBufferPointer { output in
                    vDSP_vmul(input.baseAddress!, 1, taper.baseAddress!, 1, output.baseAddress!, 1, length)
                }
            }
        }
        windowed.withUnsafeBufferPointer { real in
            imaginary.withUnsafeBufferPointer { imaginaryInput in
                outReal.withUnsafeMutableBufferPointer { realOutput in
                    outImaginary.withUnsafeMutableBufferPointer { imaginaryOutput in
                        vDSP_DFT_Execute(setup, real.baseAddress!, imaginaryInput.baseAddress!,
                                         realOutput.baseAddress!, imaginaryOutput.baseAddress!)
                    }
                }
            }
        }
        var scale = 1 / Float(size)
        outReal.withUnsafeMutableBufferPointer { real in
            outImaginary.withUnsafeMutableBufferPointer { imaginaryOutput in
                magnitudes.withUnsafeMutableBufferPointer { output in
                    var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imaginaryOutput.baseAddress!)
                    vDSP_zvabs(&split, 1, output.baseAddress!, 1, half)
                    vDSP_vsmul(output.baseAddress!, 1, &scale, output.baseAddress!, 1, half)
                }
            }
        }
        return magnitudes
    }
}
