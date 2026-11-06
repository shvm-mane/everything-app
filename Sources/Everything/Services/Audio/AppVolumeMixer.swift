// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Accelerate
import AppKit
import AudioToolbox
import Combine
import CoreAudio
import Darwin

struct MixerOutputDevice: Identifiable, Equatable {
    let id: String
    let uid: String
    let name: String
    let isDefault: Bool
    let isHeadphones: Bool
    let canBeDefaultOutput: Bool
    let canBeDefaultSystemOutput: Bool
    let priorityTier: MixerRoutingSupport.PriorityTier
    fileprivate let audioObjectID: AudioObjectID
}

struct MixerApp: Identifiable, Equatable {
    let id: String
    let persistenceID: String?
    let ownerPid: pid_t
    let name: String
    let audioObjects: [AudioObjectID]
    let isPlaying: Bool
    var isBypassed: Bool = false
    var supportsVolumeOverride: Bool = false
    var universalOutputRouteUID: String? = nil
    var selectedOutputDeviceUID: String?
    var effectiveOutputDeviceUID: String?
    var outputDeviceUnavailable: Bool
    var volume: Double

    var identity: MixerRowIdentity {
        MixerRowIdentity(rowID: id, persistenceID: persistenceID)
    }
}

struct MixerHiddenApp: Identifiable, Equatable {
    let id: String
    let name: String
}

final class AppVolumeMixer: ObservableObject {
    static let shared = AppVolumeMixer()

    static var isSupported: Bool {
        if #available(macOS 14.4, *) { return true }
        return false
    }

    static let maxVolume: Double = 1.0

    @Published private(set) var apps: [MixerApp] = []
    @Published private(set) var outputDevices: [MixerOutputDevice] = []
    @Published private(set) var currentOutputDeviceUID: String?
    @Published private(set) var currentSystemSoundOutputDeviceUID: String?
    @Published private(set) var systemOutputVolume: Double?
    @Published private(set) var systemOutputMuted: Bool?
    @Published private(set) var outputSwitchError: String?
    @Published private(set) var needsPermission = false
    @Published private(set) var hiddenApps: [MixerHiddenApp] = []

    private var engines: [String: any GainEngine] = [:]
    private var builds = MixerEngineBuilds()
    private var engineChangeAt: [String: Double] = [:]
    private var objectsLostAt: [String: Double] = [:]
    private var engineRenderProgress: [String: MixerRoutingSupport.EngineRenderObservation] = [:]
    private var engineRecovery = MixerEngineRecovery()
    private var configurationRepairs: [String: CFAbsoluteTime] = [:]
    private var engineReconcilePending = false
    private var sessionVolumes: [String: Double] = [:]
    private var sessionRoutes: [String: String] = [:]
    private var universalOutputDeviceUID: String? {
        nil
    }
    private var lastAudibleVolume: [String: Double] = [:]
    private var listenerInstalled = false
    private var processMonitoringEnabled = false
    private var airPlayActive = false
    private var globalListeners: [AudioObjectPropertySelector] = []
    private var runningListeners: [AudioObjectID: Set<AudioObjectPropertySelector>] = [:]
    private var outputControlListenerDevice: AudioObjectID?
    private var outputControlListenerAddresses: [AudioObjectPropertyAddress] = []
    private var outputControlRefreshGeneration = 0
    private var stopped = false
    private var wakeObserver: NSObjectProtocol?
    private var lastAutomaticLoweredOutputUID: String?
    private var loweredOutput: LoweredOutput?
    private var refreshPending = false
    private var lastListenerRefreshAt: CFAbsoluteTime = 0
    private var refresh = MixerRefreshCoordinator()
    private let buildQueue = DispatchQueue(label: "com.vorssaint.utils.mixer", qos: .userInitiated)
    enum OutputKeyResult: Equatable {
        case applied, superseded, unconfirmed, fallback
        var handled: Bool { self != .fallback }
    }

    private struct OutputAdjustment {
        let device: AudioObjectID
        let lifetime: UUID
        let keyGeneration: Int
        var volume: Double?
        var muted: Bool?
        var step: OutputStep?
        var completion: (OutputKeyResult) -> Void
    }
    private var pendingOutputAdjustment: OutputAdjustment?
    private var outputWriteInFlight: OutputAdjustment?
    private struct OutputStep {
        let level: ((Double) -> Double)?
        let completion: (OutputKeyResult) -> Void
    }
    private struct OutputKeyWrite {
        let adjustment: OutputAdjustment
        let expectedVolume: Double?
        var volumeTolerance: Double = 0.0001
        let muted: Bool?
        let volumeWritten: Bool
        var muteWritten = false
    }
    private var queuedOutputSteps: [OutputStep] = []
    private var outputStepReadInFlight = false
    private var outputStepReadGeneration = 0
    private let outputControlLock = NSLock()
    private var outputControlLifetime = UUID()
    private var outputKeyGeneration = 0
    private var nativeOutputKeyLifetime: UUID?
    private let halQueue = DispatchQueue(label: "com.vorssaint.utils.mixer.hal", qos: .userInitiated)

    private init() {}

    // MARK: - Lifecycle

    func syncWithPreferences() {
        let needs = MixerRoutingSupport.observationNeeds(isAvailable: { $0.isAvailable })
        guard needs.devices else {
            stop()
            return
        }

        if listenerInstalled, processMonitoringEnabled {
            stop()
        }
        start()
    }

    func start() {
        stopped = false
        processMonitoringEnabled = false
        if processMonitoringEnabled {
            publishHiddenApps()
            AirPlayRouteManager.shared.activate { [weak self] in
                self?.refreshApps()
            }
            airPlayActive = true
        }
        guard !listenerInstalled else {
            refreshApps()
            return
        }
        listenerInstalled = true
        installListener(selector: kAudioHardwarePropertyDevices)
        installListener(selector: kAudioHardwarePropertyDefaultOutputDevice)
        installListener(selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
        if processMonitoringEnabled, Self.isSupported {
            installListener(selector: kAudioHardwarePropertyProcessObjectList)
        }
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.engineRenderProgress.removeAll()
                self.engineRecovery.clearAll()
                self.removeOutputControlListeners()
                self.refreshApps()
                self.reconcileEngines(with: self.apps)
                self.scheduleEngineReconcile(after: 2)
            }
        }
        refreshApps()
    }

    func stopAll() {
        stopped = true
        builds.invalidateAll()
        for engine in engines.values { engine.stop() }
        engines.removeAll()
        configurationRepairs.removeAll()
        engineChangeAt.removeAll()
        objectsLostAt.removeAll()
        engineRenderProgress.removeAll()
        engineRecovery.clearAll()
        restoreLoweredOutputVolume()
    }

    func stop() {
        stopAll()
        sessionVolumes.removeAll()
        sessionRoutes.removeAll()
        refresh.discardInFlight()
        pruneRunningListeners(keeping: [])
        removeGlobalListeners()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if airPlayActive {
            AirPlayRouteManager.shared.deactivate()
            airPlayActive = false
        }
        if !apps.isEmpty { apps = [] }
        if !hiddenApps.isEmpty { hiddenApps = [] }
        if !outputDevices.isEmpty { outputDevices = [] }
        if currentOutputDeviceUID != nil { currentOutputDeviceUID = nil }
        if currentSystemSoundOutputDeviceUID != nil { currentSystemSoundOutputDeviceUID = nil }
        if systemOutputVolume != nil { systemOutputVolume = nil }
        if systemOutputMuted != nil { systemOutputMuted = nil }
        if outputSwitchError != nil { outputSwitchError = nil }
        if needsPermission { needsPermission = false }
        processMonitoringEnabled = false
    }

    private static let listenerCallback: AudioObjectPropertyListenerProc = { _, _, _, client in
        guard let client else { return noErr }
        let mixer = Unmanaged<AppVolumeMixer>.fromOpaque(client).takeUnretainedValue()
        DispatchQueue.main.async { mixer.scheduleListenerRefresh() }
        return noErr
    }

    private static let outputControlListenerCallback: AudioObjectPropertyListenerProc = {
        device, _, _, client in
        guard let client else { return noErr }
        let mixer = Unmanaged<AppVolumeMixer>.fromOpaque(client).takeUnretainedValue()
        DispatchQueue.main.async { mixer.scheduleOutputControlRefresh(for: device) }
        return noErr
    }

    private var listenerClient: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    private func installListener(selector: AudioObjectPropertySelector) {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject),
                                             &address,
                                             Self.listenerCallback,
                                             listenerClient) == noErr else { return }
        globalListeners.append(selector)
    }

    private func removeGlobalListeners() {
        guard listenerInstalled else { return }
        listenerInstalled = false
        removeOutputControlListeners()
        for selector in globalListeners {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject),
                                              &address,
                                              Self.listenerCallback,
                                              listenerClient)
        }
        globalListeners.removeAll()
    }

    private func subscribeToOutputControls(of device: AudioObjectID?) {
        guard outputControlListenerDevice != device else { return }
        removeOutputControlListeners()
        guard let device else { return }

        let selectors = Self.outputVolumeSelectors + [kAudioDevicePropertyMute]
        for selector in selectors {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                                                     mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectHasProperty(device, &address) else { continue }
            if AudioObjectAddPropertyListener(device, &address,
                                              Self.outputControlListenerCallback,
                                              listenerClient) == noErr {
                outputControlListenerAddresses.append(address)
            }
        }
        if !outputControlListenerAddresses.isEmpty {
            outputControlListenerDevice = device
        }
    }

    private func removeOutputControlListeners() {
        if let device = outputControlListenerDevice {
            for var address in outputControlListenerAddresses {
                AudioObjectRemovePropertyListener(device, &address,
                                                  Self.outputControlListenerCallback,
                                                  listenerClient)
            }
        }
        outputControlListenerDevice = nil
        outputControlListenerAddresses.removeAll()
        outputControlRefreshGeneration &+= 1
        outputControlLock.withLock { outputControlLifetime = UUID() }
        let pending = pendingOutputAdjustment
        pendingOutputAdjustment = nil
        pending?.completion(.superseded)
        outputStepReadInFlight = false
        settleQueuedOutputSteps(result: .superseded)
    }

    private func scheduleOutputControlRefresh(for device: AudioObjectID) {
        guard listenerInstalled, outputControlListenerDevice == device else { return }
        outputControlRefreshGeneration &+= 1
        let generation = outputControlRefreshGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self,
                  self.listenerInstalled,
                  self.outputControlListenerDevice == device,
                  self.outputControlRefreshGeneration == generation else { return }
            self.halQueue.async { [weak self] in
                let volume = Self.hasSettableOutputVolume(for: device)
                    ? Self.outputVolume(for: device).map(Double.init)
                    : nil
                let muted = Self.outputMuted(for: device)
                DispatchQueue.main.async {
                    guard let self,
                          self.listenerInstalled,
                          self.outputControlListenerDevice == device,
                          self.outputControlRefreshGeneration == generation else { return }
                    self.applyOutputControls(volume: volume, muted: muted)
                }
            }
        }
    }

    private func subscribeToRunningChanges(of object: AudioObjectID) {
        for selector in Self.runningListenerSelectors
        where runningListeners[object]?.contains(selector) != true {
            var address = Self.runningAddress(selector)
            if AudioObjectAddPropertyListener(object, &address,
                                              Self.listenerCallback, listenerClient) == noErr {
                runningListeners[object, default: []].insert(selector)
            }
        }
    }

    private func pruneRunningListeners(keeping current: Set<AudioObjectID>) {
        for object in runningListeners.keys.filter({ !current.contains($0) }) {
            guard let selectors = runningListeners.removeValue(forKey: object) else { continue }
            for selector in selectors {
                var address = Self.runningAddress(selector)
                AudioObjectRemovePropertyListener(object, &address,
                                                  Self.listenerCallback, listenerClient)
            }
        }
    }

    private static let runningListenerSelectors: [AudioObjectPropertySelector] = [
        kAudioProcessPropertyIsRunningOutput, kAudioProcessPropertyIsRunning,
        kAudioProcessPropertyDevices,
    ]

    private static func runningAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: selector == kAudioProcessPropertyDevices
                                       ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private func scheduleListenerRefresh() {
        guard !refreshPending else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastListenerRefreshAt
        if elapsed >= Self.listenerRefreshInterval {
            lastListenerRefreshAt = now
            refreshApps()
            return
        }
        refreshPending = true
        let delay = Self.listenerRefreshInterval - elapsed
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            self.lastListenerRefreshAt = CFAbsoluteTimeGetCurrent()
            self.refreshApps()
        }
    }

    private static let listenerRefreshInterval: CFAbsoluteTime = 0.2

    // MARK: - Volume API (panel)

    func requestOutputAdjustment(volume: Double? = nil, muted: Bool? = nil,
                                 completion: @escaping (Bool) -> Void = { _ in }) {
        enqueueOutputAdjustment(volume: volume, muted: muted) { completion($0.handled) }
    }

    private func enqueueOutputAdjustment(volume: Double? = nil, muted: Bool? = nil,
                                         step: OutputStep? = nil,
                                         completion: @escaping (OutputKeyResult) -> Void) {
        guard let device = outputControlListenerDevice,
              volume?.isFinite != false,
              volume == nil || systemOutputVolume != nil,
              muted == nil || systemOutputMuted != nil else { completion(.fallback); return }
        if step == nil {
            outputStepReadGeneration &+= 1
            outputControlLock.withLock { outputKeyGeneration &+= 1 }
            settleQueuedOutputSteps(result: .superseded)
        }
        outputControlRefreshGeneration &+= 1
        let previous = pendingOutputAdjustment
        var adjustment = previous ?? OutputAdjustment(device: device,
            lifetime: outputControlLock.withLock { outputControlLifetime },
            keyGeneration: outputControlLock.withLock { outputKeyGeneration }, completion: completion)
        adjustment.completion = completion
        adjustment.step = step
        if let volume {
            let value = min(1, max(0, volume))
            adjustment.volume = value
            if step == nil { systemOutputVolume = value }
            if systemOutputMuted != nil, muted == nil {
                let mutes = MixerRoutingSupport.mutesOutput(atVolume: value)
                adjustment.muted = mutes
                if step == nil { systemOutputMuted = mutes }
            }
        }
        if let muted {
            adjustment.muted = muted
            if step == nil { systemOutputMuted = muted }
        }
        pendingOutputAdjustment = adjustment
        previous?.completion(.superseded)
        drainOutputAdjustment()
    }

    func requestOutputStep(level: @escaping (Double) -> Double,
                           completion: @escaping (OutputKeyResult) -> Void = { _ in }) {
        enqueueOutputKey(OutputStep(level: level, completion: completion),
                         isAvailable: systemOutputVolume != nil)
    }

    func requestOutputMuteToggle(completion: @escaping (OutputKeyResult) -> Void = { _ in }) {
        enqueueOutputKey(OutputStep(level: nil, completion: completion),
                         isAvailable: systemOutputMuted != nil)
    }

    private func enqueueOutputKey(_ step: OutputStep, isAvailable: Bool) {
        guard outputControlListenerDevice != nil, isAvailable else {
            step.completion(.fallback)
            return
        }
        queuedOutputSteps.append(step)
        readOutputForQueuedKeys()
    }

    private func readOutputForQueuedKeys() {
        guard let device = outputControlListenerDevice, !queuedOutputSteps.isEmpty,
              !outputStepReadInFlight else { return }
        guard !hasCurrentOutputAdjustment else { return }
        outputStepReadInFlight = true
        let readGeneration = outputStepReadGeneration
        let lifetime = outputControlLock.withLock { outputControlLifetime }
        halQueue.async { [weak self] in
            let isDefault = Self.defaultOutputDeviceID() == device
            let volume = isDefault && Self.hasSettableOutputVolume(for: device)
                ? Self.outputVolume(for: device).map(Double.init)
                : nil
            let muted = isDefault ? Self.outputMuted(for: device) : nil
            DispatchQueue.main.async {
                guard let self else { return }
                let current = self.outputControlListenerDevice == device
                    && self.outputControlLock.withLock { self.outputControlLifetime == lifetime }
                guard current else { return }
                self.outputStepReadInFlight = false
                guard isDefault else {
                    self.settleQueuedOutputSteps(result: .superseded)
                    if current { self.scheduleListenerRefresh() }
                    return
                }
                let superseded = self.outputStepReadGeneration != readGeneration
                let fresh = !superseded && !self.hasCurrentOutputAdjustment
                if fresh {
                    if self.systemOutputVolume != volume { self.systemOutputVolume = volume }
                    if self.systemOutputMuted != muted { self.systemOutputMuted = muted }
                }
                self.applyQueuedOutputSteps()
            }
        }
    }

    private func settleQueuedOutputSteps(result: OutputKeyResult) {
        let steps = queuedOutputSteps
        queuedOutputSteps.removeAll()
        for step in steps { step.completion(result) }
    }

    private func applyQueuedOutputSteps() {
        guard !hasCurrentOutputAdjustment, !queuedOutputSteps.isEmpty else { return }
        let step = queuedOutputSteps.removeFirst()
        if let level = step.level, let volume = systemOutputVolume {
            let target = level(systemOutputMuted == true ? 0 : volume)
            guard target.isFinite else {
                step.completion(.fallback)
                applyQueuedOutputSteps()
                return
            }
            enqueueOutputAdjustment(volume: target, step: step, completion: step.completion)
        } else if step.level == nil, let muted = systemOutputMuted {
            enqueueOutputAdjustment(muted: !muted, step: step, completion: step.completion)
        } else {
            step.completion(.fallback)
            applyQueuedOutputSteps()
        }
    }

    private func isCurrentOutputAdjustment(_ adjustment: OutputAdjustment) -> Bool {
        outputControlLock.withLock { outputControlLifetime == adjustment.lifetime }
    }

    private var hasCurrentOutputAdjustment: Bool {
        pendingOutputAdjustment != nil || outputWriteInFlight.map(isCurrentOutputAdjustment) == true
    }

    private func applyOutputControls(volume: Double?, muted: Bool?) {
        guard !hasCurrentOutputAdjustment else { return }
        if systemOutputVolume != volume { systemOutputVolume = volume }
        if systemOutputMuted != muted { systemOutputMuted = muted }
    }

    private func isCurrentOutputKey(_ adjustment: OutputAdjustment) -> Bool {
        outputControlLock.withLock {
            outputControlLifetime == adjustment.lifetime && outputKeyGeneration == adjustment.keyGeneration
        }
    }

    private func drainOutputAdjustment() {
        guard outputWriteInFlight == nil, let adjustment = pendingOutputAdjustment else { return }
        pendingOutputAdjustment = nil
        guard isCurrentOutputAdjustment(adjustment), outputControlListenerDevice == adjustment.device else {
            adjustment.completion(.superseded)
            return
        }
        outputWriteInFlight = adjustment
        halQueue.async { [weak self] in
            guard let self else { return }
            if adjustment.step != nil {
                self.beginOutputKeyAdjustment(adjustment)
                return
            }
            let device = adjustment.device
            guard self.isCurrentOutputAdjustment(adjustment), Self.defaultOutputDeviceID() == device else {
                self.finishOutputAdjustment(adjustment, result: .superseded)
                return
            }
            var confirmation = adjustment
            if let volume = adjustment.volume, Self.requiresQuantizedOutputKeys(for: device),
               let current = Self.outputVolume(for: device).map(Double.init),
               Self.hasSettableScalarOutput(for: device, matching: current),
               let converted = Self.quantizedOutputVolume(volume, for: device),
               converted.isFinite, (0...1).contains(converted) {
                confirmation.volume = converted
            }
            var success = self.isCurrentOutputAdjustment(adjustment) && Self.defaultOutputDeviceID() == device
            if success, let volume = adjustment.volume { success = Self.setOutputVolume(Float(volume), for: device) }
            let volumeWritten = success && adjustment.volume != nil
            if success, let muted = adjustment.muted, self.isCurrentOutputAdjustment(adjustment),
               Self.defaultOutputDeviceID() == device {
                success = Self.setOutputMuted(muted, for: device)
            }
            if success || volumeWritten { self.confirmDirectOutputAdjustment(confirmation) }
            else { self.finishOutputAdjustment(adjustment, result: .fallback) }
        }
    }

    private static func outputAdjustmentIsConfirmed(_ adjustment: OutputAdjustment,
                                                    volume: Double?, muted: Bool?) -> Bool {
        if let expected = adjustment.volume,
           volume.map({ $0.isFinite && abs($0 - expected) < 0.005 }) != true { return false }
        if let expected = adjustment.muted, muted != expected { return false }
        return true
    }

    private func confirmDirectOutputAdjustment(_ adjustment: OutputAdjustment, remainingReads: Int = 3) {
        guard isCurrentOutputAdjustment(adjustment), Self.defaultOutputDeviceID() == adjustment.device else {
            finishOutputAdjustment(adjustment, result: .superseded)
            return
        }
        let volume = Self.outputVolume(for: adjustment.device).map(Double.init)
        let muted = Self.outputMuted(for: adjustment.device)
        if Self.outputAdjustmentIsConfirmed(adjustment, volume: volume, muted: muted) {
            finishOutputAdjustment(adjustment, result: .applied)
        } else if remainingReads > 0 {
            halQueue.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.confirmDirectOutputAdjustment(adjustment, remainingReads: remainingReads - 1)
            }
        } else {
            finishOutputAdjustment(adjustment, result: .unconfirmed)
        }
    }

    private func finishOutputAdjustment(_ adjustment: OutputAdjustment, result: OutputKeyResult,
                                        volume: Double? = nil, muted: Bool? = nil) {
        let result = Self.defaultOutputDeviceID() == adjustment.device ? result : .superseded
        let current = adjustment.step == nil ? isCurrentOutputAdjustment(adjustment)
            : isCurrentOutputKey(adjustment)
        _ = current
        DispatchQueue.main.async {
            self.outputWriteInFlight = nil
            let current = adjustment.step == nil ? self.isCurrentOutputAdjustment(adjustment)
                : self.isCurrentOutputKey(adjustment)
            let result = current ? result : .superseded
            if adjustment.step == nil, result == .unconfirmed, self.pendingOutputAdjustment == nil {
                self.settleQueuedOutputSteps(result: .unconfirmed)
            }
            if result == .applied, adjustment.step != nil, self.pendingOutputAdjustment == nil {
                self.applyOutputControls(volume: volume, muted: muted)
            }
            adjustment.completion(result)
            if self.pendingOutputAdjustment != nil {
                self.drainOutputAdjustment()
            } else if current, result != .superseded {
                self.readOutputForQueuedKeys()
                self.scheduleOutputControlRefresh(for: adjustment.device)
            } else {
                if current { self.settleQueuedOutputSteps(result: .superseded) }
                self.scheduleListenerRefresh()
            }
        }
    }

    private func beginOutputKeyAdjustment(_ adjustment: OutputAdjustment) {
        let device = adjustment.device
        guard isCurrentOutputKey(adjustment), Self.defaultOutputDeviceID() == device else {
            finishOutputAdjustment(adjustment, result: .superseded)
            return
        }
        if nativeOutputKeyLifetime == adjustment.lifetime {
            finishOutputAdjustment(adjustment, result: .fallback)
            return
        }
        let muted = Self.outputMuted(for: device)
        let volume = Self.outputVolume(for: device).map(Double.init)
        guard let step = adjustment.step else { return }
        if let level = step.level {
            guard let volume, volume.isFinite else {
                finishOutputAdjustment(adjustment, result: .fallback)
                return
            }
            if muted == true, level(0) == 0 {
                finishOutputAdjustment(adjustment, result: .applied, volume: volume, muted: muted)
                return
            }
            let plain: (volume: Double, muted: Bool?, usesScalar: Bool) = {
                let first = min(1, max(0, level(muted == true ? 0 : volume)))
                return (first, muted == nil ? nil : MixerRoutingSupport.mutesOutput(atVolume: first), false)
            }()
            let target = Self.outputKeyVolumeTarget(for: device, from: volume, muted: muted, level: level) ?? plain
            guard isCurrentOutputKey(adjustment), Self.defaultOutputDeviceID() == device else {
                finishOutputAdjustment(adjustment, result: .superseded)
                return
            }
            let changesVolume = abs(target.volume - volume) >= 0.0001
            if changesVolume {
                let success = target.usesScalar ? Self.setOutputScalarVolume(target.volume, for: device)
                    : Self.setOutputVolume(Float(target.volume), for: device, permitsFallback: false)
                guard success else {
                    finishOutputAdjustment(adjustment, result: .fallback)
                    return
                }
            }
            confirmOutputKeyAdjustment(OutputKeyWrite(adjustment: adjustment, expectedVolume: target.volume,
                                                       volumeTolerance: target.usesScalar ? 0.0001 : 0.04,
                                                       muted: target.muted, volumeWritten: changesVolume))
        } else if let muted {
            confirmOutputKeyAdjustment(OutputKeyWrite(adjustment: adjustment, expectedVolume: nil,
                                                       muted: !muted, volumeWritten: false))
        } else {
            finishOutputAdjustment(adjustment, result: .fallback)
        }
    }

    private func confirmOutputKeyAdjustment(_ pending: OutputKeyWrite, remainingReads: Int = 3) {
        var write = pending
        let adjustment = write.adjustment
        let device = adjustment.device
        guard isCurrentOutputKey(adjustment), Self.defaultOutputDeviceID() == device else {
            finishOutputAdjustment(adjustment, result: .superseded)
            return
        }
        let actual = Self.outputVolume(for: device).map(Double.init)
        if let expected = write.expectedVolume, write.muted != true,
           actual.map({ $0.isFinite && abs($0 - expected) < write.volumeTolerance
               && (write.muted != false || !MixerRoutingSupport.mutesOutput(atVolume: $0)) }) != true {
            scheduleOutputKeyConfirmation(write, remainingReads: remainingReads)
            return
        }
        var actualMuted = Self.outputMuted(for: device)
        if let muted = write.muted, actualMuted != muted {
            if !write.muteWritten {
                guard isCurrentOutputKey(adjustment), Self.defaultOutputDeviceID() == device else {
                    finishOutputAdjustment(adjustment, result: .superseded)
                    return
                }
                guard Self.setOutputMuted(muted, for: device) else {
                    finishOutputAdjustment(adjustment, result: write.volumeWritten ? .unconfirmed : .fallback)
                    return
                }
                write.muteWritten = true
                actualMuted = Self.outputMuted(for: device)
            }
            guard actualMuted == muted else {
                scheduleOutputKeyConfirmation(write, remainingReads: remainingReads)
                return
            }
        }
        guard isCurrentOutputKey(adjustment), Self.defaultOutputDeviceID() == device else {
            finishOutputAdjustment(adjustment, result: .superseded)
            return
        }
        finishOutputAdjustment(adjustment, result: .applied, volume: actual, muted: actualMuted)
    }

    private func scheduleOutputKeyConfirmation(_ write: OutputKeyWrite, remainingReads: Int) {
        guard remainingReads > 0 else {
            finishOutputAdjustment(write.adjustment, result: .unconfirmed)
            return
        }
        halQueue.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.confirmOutputKeyAdjustment(write, remainingReads: remainingReads - 1)
        }
    }

    private static func outputKeyVolumeTarget(for device: AudioObjectID, from volume: Double,
                                              muted: Bool?, level: (Double) -> Double)
        -> (volume: Double, muted: Bool?, usesScalar: Bool)? {
        guard volume.isFinite, (0...1).contains(volume) else { return nil }
        let from = muted == true ? 0 : volume
        let requested = level(from)
        guard requested.isFinite else { return nil }
        let first = min(1, max(0, requested))
        if first == from {
            return (volume, muted == nil ? nil : MixerRoutingSupport.mutesOutput(atVolume: first), false)
        }
        guard requiresQuantizedOutputKeys(for: device) else {
            return (first, muted == nil ? nil : MixerRoutingSupport.mutesOutput(atVolume: first), false)
        }
        guard hasSettableScalarOutput(for: device, matching: volume) else { return nil }
        let direction = first > from ? 1.0 : -1.0
        var targets = [first]
        while targets.count < 64, let last = targets.last, last > 0, last < 1 {
            let next = level(last)
            guard next.isFinite else { return nil }
            let clamped = min(1, max(0, next))
            guard (clamped - last) * direction > 0 else { return nil }
            targets.append(clamped)
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.05
        var queries = 0
        func converted(_ target: Double) -> Double? {
            guard queries < 11, ProcessInfo.processInfo.systemUptime <= deadline else { return nil }
            queries += 1
            guard let value = quantizedOutputVolume(target, for: device), value.isFinite,
                  (0...1).contains(value), ProcessInfo.processInfo.systemUptime <= deadline else { return nil }
            return value
        }
        guard let baseline = converted(volume), abs(baseline - volume) < 0.0001 else { return nil }
        let probe = volume >= 1.0 / 1024 ? volume - 1.0 / 1024 : volume + 1.0 / 1024
        guard let nearby = converted(probe), abs(nearby - baseline) < 0.0001,
              let initial = converted(first), (initial - from) * direction >= -0.0001 else { return nil }
        func advances(_ value: Double, at index: Int) -> Bool {
            if muted != nil, MixerRoutingSupport.mutesOutput(atVolume: targets[index]) { return true }
            return (value - from) * direction >= 0.0001
                && (direction < 0 || !MixerRoutingSupport.mutesOutput(atVolume: value))
        }
        var chosen = initial
        var index = 0
        if !advances(initial, at: 0) {
            var low = 0
            var high = targets.count - 1
            guard high > low, let end = converted(targets[high]), advances(end, at: high),
                  (end - initial) * direction >= 0 else { return nil }
            var lowValue = initial
            var highValue = end
            while high - low > 1 {
                let middle = (low + high) / 2
                guard let value = converted(targets[middle]),
                      (value - lowValue) * direction >= -0.0001,
                      (highValue - value) * direction >= -0.0001 else { return nil }
                if advances(value, at: middle) { high = middle; highValue = value }
                else { low = middle; lowValue = value }
            }
            index = high
            chosen = highValue
        }
        guard let canonical = converted(chosen), abs(canonical - chosen) < 0.0001 else { return nil }
        let mutes = MixerRoutingSupport.mutesOutput(atVolume: targets[index])
            || MixerRoutingSupport.mutesOutput(atVolume: chosen)
        return (chosen, muted == nil ? nil : mutes, true)
    }

    private static func requiresQuantizedOutputKeys(for device: AudioObjectID) -> Bool {
        var transport: UInt32 = 0
        guard read(device, kAudioDevicePropertyTransportType, &transport) else { return true }
        return transport == kAudioDeviceTransportTypeUSB
    }

    private static func hasSettableScalarOutput(for device: AudioObjectID, matching volume: Double) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                 mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var settable = DarwinBoolean(false)
        var actual: Float32 = 0
        return AudioObjectHasProperty(device, &address)
            && AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
            && read(device, kAudioDevicePropertyVolumeScalar, &actual, scope: kAudioObjectPropertyScopeOutput)
            && actual.isFinite && abs(Double(actual) - volume) < 0.0001
    }

    private static func quantizedOutputVolume(_ volume: Double, for device: AudioObjectID) -> Double? {
        var value = Float32(volume)
        for selector in [kAudioDevicePropertyVolumeScalarToDecibels, kAudioDevicePropertyVolumeDecibelsToScalar] {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                                                     mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectHasProperty(device, &address),
                  AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
                  size == UInt32(MemoryLayout<Float32>.size), value.isFinite else { return nil }
        }
        return Double(value)
    }

    private static func setOutputScalarVolume(_ volume: Double, for device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                 mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value = Float32(volume)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    private func isUnity(_ volume: Double) -> Bool { MixerRoutingSupport.isUnity(volume) }

    func setVolume(_ volume: Double, for app: MixerApp) {
        guard !app.isBypassed else { return }
        engineRecovery.clear(app.id)
        let clamped = Defaults.sanitizedAppVolume(volume)
        persistVolume(clamped, for: app)
        if clamped > 0.001 { lastAudibleVolume[app.id] = clamped }
        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            apps[index].volume = clamped
            let updated = apps[index]
            applyRouting(for: updated)
        } else {
            applyRouting(for: app)
        }
        reconcileEngines(with: apps)
    }

    func setOutputDeviceUID(_ uid: String?, for app: MixerApp) {
        guard !app.isBypassed else { return }
        if uid == MixerRoutingSupport.airPlaySpeakerChoiceID {
            chooseAirPlaySpeaker(for: app)
            return
        }
        engineRecovery.clear(app.id)
        let sanitized = Defaults.sanitizedAppOutputDeviceUID(uid)
        persistOutputDeviceUID(sanitized, for: app)
        refresh.discardInFlight()
        if let sanitized, MixerRoutingSupport.isAirPlaySentinel(sanitized), !AirPlayRouteManager.shared.isConnected {
            DispatchQueue.main.async { AirPlayRouteManager.shared.presentPicker() }
        }
        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            apps[index].selectedOutputDeviceUID = sanitized
            applyOutputRoute(to: &apps[index],
                             savedOutputs: savedOutputDeviceUIDs(),
                             availableUIDs: MixerRoutingSupport.routableOutputUIDs(
                                outputDevices.map(\.uid),
                                airPlayConnected: AirPlayRouteManager.isSpeakerConnected),
                             defaultUID: currentOutputDeviceUID)
            applyRouting(for: apps[index])
        }
        refreshApps()
    }

    private func chooseAirPlaySpeaker(for app: MixerApp) {
        let routed = app.selectedOutputDeviceUID.map(MixerRoutingSupport.isAirPlaySentinel) == true
        let connected = AirPlayRouteManager.shared.isConnected
        if !routed { setOutputDeviceUID(AirPlayRouteManager.airPlaySentinelUID, for: app) }
        if routed || connected {
            DispatchQueue.main.async { AirPlayRouteManager.shared.presentPicker() }
        }
    }

    @discardableResult
    func setUniversalOutputDeviceUID(_ uid: String) -> Bool {
        setDefaultOutputDeviceUID(uid)
    }

    func setPriorityOutputDeviceUID(_ uid: String) {
        guard let sanitized = Defaults.sanitizedAppOutputDeviceUID(uid),
              let device = outputDevices.first(where: {
                  $0.uid == sanitized && $0.canBeDefaultOutput
              }) else {
            outputSwitchError = L10n.shared.s.mixerOutputUnavailable
            refreshApps()
            return
        }

        halQueue.async { [weak self] in
            let status = Self.setDefaultDevice(
                device.audioObjectID,
                selector: kAudioHardwarePropertyDefaultOutputDevice)
            DispatchQueue.main.async {
                guard let self, self.listenerInstalled else { return }
                if status == noErr {
                    if self.outputSwitchError != nil { self.outputSwitchError = nil }
                } else {
                    let message = "OSStatus \(status)"
                    if self.outputSwitchError != message { self.outputSwitchError = message }
                }
                self.refresh.discardInFlight()
                self.refreshApps()
            }
        }
    }

    @discardableResult
    private func setDefaultOutputDeviceUID(_ uid: String) -> Bool {
        guard let sanitized = Defaults.sanitizedAppOutputDeviceUID(uid),
              let device = outputDevices.first(where: { $0.uid == sanitized && $0.canBeDefaultOutput }) else {
            outputSwitchError = L10n.shared.s.mixerOutputUnavailable
            refreshApps()
            return false
        }

        let status = Self.setDefaultDevice(device.audioObjectID,
                                           selector: kAudioHardwarePropertyDefaultOutputDevice)
        guard status == noErr else {
            outputSwitchError = "OSStatus \(status)"
            refreshApps()
            return false
        }

        outputSwitchError = nil
        refresh.discardInFlight()
        let savedOutputUIDs = savedOutputDeviceUIDs()
        let preferences = MixerRoutingSupport.preferencesAfterUniversalOutputSwitch(
            outputDeviceUIDs: savedOutputUIDs,
            volumes: savedVolumes(),
            switchSucceeded: true)
        persistOutputDeviceUIDs(preferences.outputDeviceUIDs)
        sessionRoutes.removeAll()
        currentOutputDeviceUID = device.uid

        builds.invalidateAll()

        refreshApps()
        return true
    }

    @discardableResult
    func setSystemSoundOutputDeviceUID(_ uid: String) -> Bool {
        guard let sanitized = Defaults.sanitizedAppOutputDeviceUID(uid),
              let device = outputDevices.first(where: {
                  $0.uid == sanitized && $0.canBeDefaultSystemOutput
              }) else {
            outputSwitchError = L10n.shared.s.mixerOutputUnavailable
            refreshApps()
            return false
        }

        let status = Self.setDefaultDevice(
            device.audioObjectID,
            selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
        guard status == noErr else {
            outputSwitchError = "OSStatus \(status)"
            refreshApps()
            return false
        }

        outputSwitchError = nil
        refresh.discardInFlight()
        currentSystemSoundOutputDeviceUID = device.uid
        refreshApps()
        return true
    }

    @discardableResult
    func switchToNextSoundOutput(in selectedUIDs: [String]) -> Bool {
        let availableUIDs = Set(outputDevices.filter(\.canBeDefaultOutput).map(\.uid))
        guard let nextUID = MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: currentOutputDeviceUID,
            selectedUIDs: selectedUIDs,
            availableUIDs: availableUIDs) else {
            return selectedUIDs.contains { rawUID in
                MixerRoutingSupport.sanitizedDeviceUID(rawUID).map { availableUIDs.contains($0) } ?? false
            }
        }
        return setUniversalOutputDeviceUID(nextUID)
    }

    func toggleMute(_ app: MixerApp) {
        if app.volume > 0.001 {
            lastAudibleVolume[app.id] = app.volume
            setVolume(0, for: app)
        } else {
            setVolume(lastAudibleVolume[app.id] ?? 1, for: app)
        }
    }

    private func applyRouting(for app: MixerApp) {
        guard !stopped else { return }
        guard !app.isBypassed else {
            discardEngine(for: app.id)
            return
        }
        guard let targetOutputDeviceUID = app.effectiveOutputDeviceUID,
              appNeedsEngine(app) else {
            discardEngine(for: app.id)
            clearPermissionIfNoActiveAdjustments()
            return
        }
        if let engine = engines[app.id],
           engine.tappedObjects == app.audioObjects,
           engine.outputDeviceUID == targetOutputDeviceUID,
           !engine.requiresRebuild {
            engine.gain = MixerRoutingSupport.gain(forVolume: app.volume)
            return
        }
        if let delay = configurationRepairDelay(for: app.id) {
            scheduleEngineReconcile(after: delay)
            return
        }
        guard rowMayBeTapped(app) else {
            discardEngine(for: app.id)
            clearPermissionIfNoActiveAdjustments()
            return
        }
        let configuration = MixerEngineRecovery.Configuration(
            objects: app.audioObjects,
            outputDeviceUID: targetOutputDeviceUID)
        guard engineRecovery.allowsBuild(app.id, configuration: configuration) else { return }
        guard #available(macOS 14.4, *), let token = builds.begin(app.id) else { return }

        if MixerRoutingSupport.isAirPlaySentinel(targetOutputDeviceUID) {
            guard let clockUID = clockDeviceUIDForAirPlayTap() else {
                builds.finish(app.id, token: token)
                return
            }
            buildQueue.async { [weak self] in
                guard AirPlayRouteManager.shared.prepareToStream() else {
                    DispatchQueue.main.async {
                        self?.finishUnavailableAirPlayBuild(for: app.id, token: token)
                    }
                    return
                }
                let engine = AirPlayGainEngine(appID: app.id,
                                               objects: app.audioObjects,
                                               gain: MixerRoutingSupport.gain(forVolume: app.volume),
                                               clockDeviceUID: clockUID)
                if engine == nil {
                    AirPlayRouteManager.shared.stopIfIdle()
                }
                DispatchQueue.main.async {
                    guard let self else {
                        engine?.stop()
                        return
                    }
                    self.install(engine, for: app.id, token: token)
                }
            }
            return
        }

        buildQueue.async { [weak self] in
            let engine = TapGainEngine(objects: app.audioObjects,
                                       gain: MixerRoutingSupport.gain(forVolume: app.volume),
                                       outputDeviceUID: targetOutputDeviceUID)
            DispatchQueue.main.async {
                guard let self else {
                    engine?.stop()
                    return
                }
                self.install(engine, for: app.id, token: token)
            }
        }
    }

    private func finishUnavailableAirPlayBuild(for id: String, token: Int) {
        builds.finish(id, token: token)
        AirPlayRouteManager.shared.reportStreamingFailure()
    }

    private func clockDeviceUIDForAirPlayTap() -> String? {
        let hardware = outputDevices.map(\.uid).filter { !MixerRoutingSupport.isAirPlaySentinel($0) }
        if let current = currentOutputDeviceUID, hardware.contains(current) { return current }
        return hardware.first
    }

    private func install(_ engine: (any GainEngine)?, for id: String, token: Int) {
        let isCurrentBuild = builds.isCurrent(id, token: token)
        builds.finish(id, token: token)
        guard isCurrentBuild, !stopped else {
            engine?.stop()
            return
        }
        guard let engine else {
            if retryInvalidatedEngine(for: id) { return }
            if let running = engines[id],
               !MixerRoutingSupport.engineOutputIsPresent(running.outputDeviceUID,
                                                          clockUID: running.clockDeviceUID,
                                                          listedUIDs: outputDevices.map(\.uid),
                                                          airPlayConnected: AirPlayRouteManager.isSpeakerConnected) {
                discardEngine(for: id)
            }
            if engines[id] == nil, !needsPermission {
                needsPermission = true
            }
            engines[id]?.refreshLevelCompensation(immediately: true)
            return
        }
        if needsPermission {
            needsPermission = false
        }
        guard let latestApp = apps.first(where: { $0.id == id }) else {
            engine.stop()
            return
        }
        guard latestApp.audioObjects == engine.tappedObjects,
              latestApp.effectiveOutputDeviceUID == engine.outputDeviceUID,
              appNeedsEngine(latestApp) else {
            engine.stop()
            applyRouting(for: latestApp)
            return
        }
        engine.gain = MixerRoutingSupport.gain(forVolume: latestApp.volume)
        configurationRepairs.removeValue(forKey: id)
        let previous = engines.updateValue(engine, forKey: id)
        engineChangeAt[id] = CFAbsoluteTimeGetCurrent()
        engineRenderProgress.removeValue(forKey: id)
        previous?.stop()
        reconcileEngines(with: apps)
    }

    private func discardEngine(for id: String) {
        engines.removeValue(forKey: id)?.stop()
        configurationRepairs.removeValue(forKey: id)
        engineChangeAt.removeValue(forKey: id)
        objectsLostAt.removeValue(forKey: id)
        engineRenderProgress.removeValue(forKey: id)
        engineRecovery.clear(id)
    }

    private func retryInvalidatedEngine(for id: String) -> Bool {
        guard configurationRepairs[id] != nil || engines[id]?.requiresRebuild == true else { return false }
        engines.removeValue(forKey: id)?.stop()
        engineRenderProgress.removeValue(forKey: id)
        guard let app = apps.first(where: { $0.id == id }), appNeedsEngine(app),
              let outputDeviceUID = app.effectiveOutputDeviceUID else {
            configurationRepairs.removeValue(forKey: id)
            return true
        }
        let configuration = MixerEngineRecovery.Configuration(objects: app.audioObjects,
                                                              outputDeviceUID: outputDeviceUID)
        if engineRecovery.recordFailure(id, configuration: configuration) {
            configurationRepairs[id] = CFAbsoluteTimeGetCurrent() + 0.5
            scheduleEngineReconcile(after: 0.5)
        } else {
            configurationRepairs.removeValue(forKey: id)
        }
        return true
    }

    private func configurationRepairDelay(for id: String, now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) -> Double? {
        guard let deadline = configurationRepairs[id], deadline > now else { return nil }
        return deadline - now
    }

    private func rowMayBeTapped(_ app: MixerApp) -> Bool {
        guard !app.isBypassed else { return false }
        return MixerRoutingSupport.rowMayBeTapped(
            savedVolume: storedVolume(for: app.identity, saved: savedVolumes()),
            savedRouteUID: storedRoute(for: app.identity, saved: savedOutputDeviceUIDs()),
            defaultOutputDeviceUID: app.effectiveOutputDeviceUID,
            universalOutputRouteUID: app.universalOutputRouteUID)
    }

    private func appNeedsEngine(_ app: MixerApp) -> Bool {
        guard !app.isBypassed else { return false }
        return MixerRoutingSupport.requiresEngine(hasAudioObjects: !app.audioObjects.isEmpty,
                                           volume: app.volume,
                                           selectedOutputDeviceUID: app.selectedOutputDeviceUID,
                                           targetOutputDeviceUID: app.effectiveOutputDeviceUID,
                                           defaultOutputDeviceUID: app.effectiveOutputDeviceUID,
                                           universalOutputRouteUID: app.universalOutputRouteUID)
    }

    private func applyOutputRoute(to app: inout MixerApp,
                                  savedOutputs: [String: String],
                                  availableUIDs: Set<String>,
                                  defaultUID: String?) {
        let selectedUID = storedRoute(for: app.identity, saved: savedOutputs)
        app.selectedOutputDeviceUID = selectedUID
        app.effectiveOutputDeviceUID = MixerRoutingSupport.effectiveDeviceUID(
            selectedUID: selectedUID,
            availableUIDs: availableUIDs,
            defaultUID: defaultUID)
        app.outputDeviceUnavailable = MixerRoutingSupport.selectedDeviceUnavailable(
            selectedUID: selectedUID,
            availableUIDs: availableUIDs)
    }

    // MARK: - Process discovery

    private struct RefreshRequest {
        let includeApps: Bool
        let previousDefaultUID: String?
        let previousOutputDevices: [MixerOutputDevice]
        let lowered: LoweredOutputState
        let lowerOnHeadphonesDisconnect: Bool
        let lowerToPercent: Int
        let savedVolumes: [String: Double]
        let savedOutputs: [String: String]
        let callAppVolumeEnabled: Set<String>
        let sessionVolumes: [String: Double]
        let sessionRoutes: [String: String]
        let universalOutputDeviceUID: String?
        let previouslyRoutedObjects: [String: [AudioObjectID]]
        let showFinder: Bool
        let hiddenRowIDs: Set<String>
        let ownPid: pid_t
    }

    private struct RefreshSnapshot {
        let defaultUID: String?
        let systemSoundUID: String?
        let outputDevices: [MixerOutputDevice]
        let defaultDeviceID: AudioObjectID?
        let systemOutputVolume: Double?
        let systemOutputMuted: Bool?
        let apps: [MixerApp]?
        let processObjects: [AudioObjectID]
        let lowered: LoweredOutputState
    }

    func refreshApps() {
        guard listenerInstalled else { return }
        guard let generation = refresh.begin() else { return }
        let universalUID = universalOutputDeviceUID
        let request = RefreshRequest(
            includeApps: processMonitoringEnabled,
            previousDefaultUID: currentOutputDeviceUID,
            previousOutputDevices: outputDevices,
            lowered: LoweredOutputState(lastAutomaticLoweredOutputUID: lastAutomaticLoweredOutputUID,
                                        loweredOutput: loweredOutput),
            lowerOnHeadphonesDisconnect: AppFeature.mixer.isAvailable
                && UserDefaults.standard.bool(forKey: DefaultsKey.mixerLowerVolumeOnHeadphonesDisconnect),
            lowerToPercent: Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent(
                UserDefaults.standard.integer(forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent)),
            savedVolumes: savedVolumes(),
            savedOutputs: savedOutputDeviceUIDs(),
            callAppVolumeEnabled: savedCallAppVolumeEnabled(),
            sessionVolumes: sessionVolumes,
            sessionRoutes: sessionRoutes,
            universalOutputDeviceUID: universalUID,
            previouslyRoutedObjects: Dictionary(uniqueKeysWithValues: apps.compactMap { app in
                guard universalUID != nil,
                      app.universalOutputRouteUID == universalUID
                        || engines[app.id]?.tappedObjects == app.audioObjects else { return nil }
                return (app.id, app.audioObjects)
            }),
            showFinder: UserDefaults.standard.bool(forKey: DefaultsKey.mixerShowFinder),
            hiddenRowIDs: MixerRoutingSupport.hiddenRowIDs(
                hiddenApps: savedHiddenApps(),
                showFinder: UserDefaults.standard.bool(forKey: DefaultsKey.mixerShowFinder)),
            ownPid: ProcessInfo.processInfo.processIdentifier)

        halQueue.async { [weak self] in
            let snapshot = Self.readSnapshot(request)
            DispatchQueue.main.async {
                self?.apply(snapshot, generation: generation)
            }
        }
    }

    private func apply(_ snapshot: RefreshSnapshot, generation: Int) {
        guard refresh.finish(generation) else {
            if snapshot.lowered.loweredOutput != nil {
                lastAutomaticLoweredOutputUID = snapshot.lowered.lastAutomaticLoweredOutputUID
                loweredOutput = snapshot.lowered.loweredOutput
            }
            return
        }
        let refreshAgain = refresh.takeRepeatRequest()
        guard listenerInstalled else { return }
        defer { if refreshAgain { refreshApps() } }

        lastAutomaticLoweredOutputUID = snapshot.lowered.lastAutomaticLoweredOutputUID
        loweredOutput = snapshot.lowered.loweredOutput

        if (snapshot.defaultUID != currentOutputDeviceUID
            || snapshot.systemSoundUID != currentSystemSoundOutputDeviceUID),
           outputSwitchError != nil {
            outputSwitchError = nil
        }
        let audioEnvironmentChanged = currentOutputDeviceUID != nil
            && (snapshot.defaultUID != currentOutputDeviceUID || snapshot.outputDevices != outputDevices)
        if audioEnvironmentChanged {
            builds.invalidateAll()
            var targets: [String: String] = [:]
            for app in snapshot.apps ?? [] {
                if let target = app.effectiveOutputDeviceUID { targets[app.id] = target }
            }
            for id in MixerRoutingSupport.enginesKeepingTheirOutput(
                engineOutputs: engines.mapValues(\.outputDeviceUID), targets: targets) {
                engines[id]?.refreshLevelCompensation(immediately: true)
            }
        }
        if currentOutputDeviceUID != snapshot.defaultUID {
            currentOutputDeviceUID = snapshot.defaultUID
        }
        if currentSystemSoundOutputDeviceUID != snapshot.systemSoundUID {
            currentSystemSoundOutputDeviceUID = snapshot.systemSoundUID
        }
        if snapshot.outputDevices != outputDevices {
            outputDevices = snapshot.outputDevices
        }
        if let defaultUID = snapshot.defaultUID, defaultUID != snapshot.systemSoundUID,
           let device = snapshot.outputDevices.first(where: { $0.uid == defaultUID && $0.canBeDefaultSystemOutput }) {
            let deviceID = device.audioObjectID
            halQueue.async {
                _ = Self.setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
            }
        }
        subscribeToOutputControls(of: snapshot.defaultDeviceID)
        applyOutputControls(volume: snapshot.systemOutputVolume, muted: snapshot.systemOutputMuted)

        guard let readApps = snapshot.apps else {
            if !apps.isEmpty {
                apps = []
            }
            return
        }

        pruneRunningListeners(keeping: Set(snapshot.processObjects))
        for object in snapshot.processObjects {
            subscribeToRunningChanges(of: object)
        }

        let next = applyingCurrentVolumes(to: readApps)
        guard audioEnvironmentChanged || next != apps else { return }
        if apps != next {
            apps = next
        }
        reconcileEngines(with: next)
        clearPermissionIfNoActiveAdjustments()
    }

    private static func readSnapshot(_ request: RefreshRequest) -> RefreshSnapshot {
        let defaultUID = defaultOutputDeviceUID(selector: kAudioHardwarePropertyDefaultOutputDevice)
        let systemSoundUID = defaultOutputDeviceUID(
            selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
        let nextOutputDevices = outputDevices(defaultUID: defaultUID)
        let defaultDevice = nextOutputDevices.first { $0.uid == defaultUID }
        let availableUIDs = MixerRoutingSupport.routableOutputUIDs(
            nextOutputDevices.map(\.uid),
            airPlayConnected: AirPlayRouteManager.isSpeakerConnected)
        let lowered = loweringOutputVolumeIfHeadphonesDisconnected(
            state: request.lowered,
            previousDefaultUID: request.previousDefaultUID,
            previousOutputDevices: request.previousOutputDevices,
            nextDefaultUID: defaultUID,
            nextOutputDevices: nextOutputDevices,
            lowerOnDisconnect: request.lowerOnHeadphonesDisconnect,
            lowerToPercent: request.lowerToPercent)
        let systemOutputVolume = defaultDevice.flatMap { device in
            hasSettableOutputVolume(for: device.audioObjectID)
                ? outputVolume(for: device.audioObjectID).map(Double.init)
                : nil
        }
        let systemOutputMuted = defaultDevice.flatMap { outputMuted(for: $0.audioObjectID) }

        guard request.includeApps, isSupported else {
            return RefreshSnapshot(defaultUID: defaultUID,
                                   systemSoundUID: systemSoundUID,
                                   outputDevices: nextOutputDevices,
                                   defaultDeviceID: defaultDevice?.audioObjectID,
                                   systemOutputVolume: systemOutputVolume,
                                   systemOutputMuted: systemOutputMuted,
                                   apps: nil,
                                   processObjects: [],
                                   lowered: lowered)
        }

        let ownPid = request.ownPid
        let saved = request.savedVolumes
        let savedOutputs = request.savedOutputs
        let showFinder = request.showFinder
        let followsUniversalOutput = request.universalOutputDeviceUID != nil
            && request.universalOutputDeviceUID == defaultUID
        let defaultDevices = followsUniversalOutput ? defaultDevice.map {
            MixerRoutingSupport.outputDevices(of: $0.audioObjectID,
                                               subDeviceUIDs: subDeviceUIDs(of:),
                                               deviceForUID: deviceID(forUID:))
        } ?? [] : Set<AudioObjectID>()
        var groups: [pid_t: [AudioObjectID]] = [:]
        var playing: Set<pid_t> = []
        var bypassed: Set<pid_t> = []
        var bundleHints: [pid_t: String] = [:]
        let processObjects = audioProcessObjects()
        for object in processObjects {
            var pid: pid_t = -1
            guard Self.read(object, kAudioProcessPropertyPID, &pid), pid > 0, pid != ownPid else { continue }

            guard let app = ResponsibleProcess.regularAppOwner(of: pid) else { continue }
            let owner = app.processIdentifier
            let name = ResponsibleProcess.displayName(pid: owner, fallback: app.localizedName ?? "pid \(owner)")
            if MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: app.bundleIdentifier,
                                                      name: name,
                                                      allowCallAppVolume: request.callAppVolumeEnabled.contains(
                                                        app.bundleIdentifier?.lowercased() ?? "")) {
                bypassed.insert(owner)
            }

            var running: UInt32 = 0
            _ = Self.read(object, kAudioProcessPropertyIsRunningOutput, &running)
            if running != 0 { playing.insert(owner) }

            groups[owner, default: []].append(object)
            if bundleHints[owner] == nil {
                bundleHints[owner] = app.bundleIdentifier
                    ?? (pid == owner ? Self.processBundleIdentifier(of: object) : nil)
            }
        }

        var next: [MixerApp] = []
        for (owner, objects) in groups {
            let fallbackName = "pid \(owner)"
            let name = ResponsibleProcess.displayName(pid: owner, fallback: fallbackName)
            let identity = MixerRoutingSupport.rowIdentity(bundleIdentifier: bundleHints[owner],
                                                           ownerPid: owner,
                                                           displayName: name == fallbackName ? nil : name)
            if MixerRoutingSupport.isHiddenFromMixer(persistenceID: identity.persistenceID,
                                                     hiddenIDs: request.hiddenRowIDs) { continue }
            let isBypassed = bypassed.contains(owner)
            let route = isBypassed ? nil : storedRoute(for: identity,
                                                       saved: savedOutputs,
                                                       session: request.sessionRoutes)
            next.append(MixerApp(id: identity.rowID,
                                 persistenceID: identity.persistenceID,
                                 ownerPid: owner,
                                 name: name,
                                 audioObjects: objects.sorted(),
                                 isPlaying: playing.contains(owner),
                                 isBypassed: isBypassed,
                                 supportsVolumeOverride: MixerRoutingSupport.needsScreenSharingProtection(
                                    bundleIdentifier: bundleHints[owner]),
                                 selectedOutputDeviceUID: route,
                                 effectiveOutputDeviceUID: isBypassed ? nil : MixerRoutingSupport.effectiveDeviceUID(
                                    selectedUID: route,
                                    availableUIDs: availableUIDs,
                                    defaultUID: defaultUID),
                                 outputDeviceUnavailable: isBypassed ? false : MixerRoutingSupport.selectedDeviceUnavailable(
                                    selectedUID: route,
                                    availableUIDs: availableUIDs),
                                 volume: isBypassed ? 1 : (storedVolume(for: identity,
                                                                       saved: saved,
                                                                       session: request.sessionVolumes) ?? 1)))
        }
        if MixerRoutingSupport.needsPersistentFinderRow(
            showFinder: showFinder,
            hasFinderRow: next.contains { $0.id == MixerRoutingSupport.finderBundleIdentifier }
        ), let finder = NSRunningApplication.runningApplications(
            withBundleIdentifier: MixerRoutingSupport.finderBundleIdentifier
        ).first {
            let id = MixerRoutingSupport.finderBundleIdentifier
            next.append(MixerApp(id: id,
                                 persistenceID: id,
                                 ownerPid: finder.processIdentifier,
                                 name: finder.localizedName ?? "Finder",
                                 audioObjects: [],
                                 isPlaying: false,
                                 selectedOutputDeviceUID: savedOutputs[id],
                                 effectiveOutputDeviceUID: MixerRoutingSupport.effectiveDeviceUID(
                                    selectedUID: savedOutputs[id],
                                    availableUIDs: availableUIDs,
                                    defaultUID: defaultUID),
                                 outputDeviceUnavailable: MixerRoutingSupport.selectedDeviceUnavailable(
                                    selectedUID: savedOutputs[id],
                                    availableUIDs: availableUIDs),
                                 volume: saved[id] ?? 1))
        }
        next.sort {
            MixerRoutingSupport.displayOrderedBefore(name: $0.name, id: $0.id,
                                                     otherName: $1.name, otherID: $1.id)
        }
        next = coalescingAppsWithDuplicateIDs(next)
        next = applyingUniversalOutputRoute(to: next,
                                            requestedUID: request.universalOutputDeviceUID,
                                            defaultUID: defaultUID,
                                            defaultDevices: defaultDevices,
                                            previouslyRoutedObjects: request.previouslyRoutedObjects)

        return RefreshSnapshot(defaultUID: defaultUID,
                               systemSoundUID: systemSoundUID,
                               outputDevices: nextOutputDevices,
                               defaultDeviceID: defaultDevice?.audioObjectID,
                               systemOutputVolume: systemOutputVolume,
                               systemOutputMuted: systemOutputMuted,
                               apps: next,
                               processObjects: processObjects,
                               lowered: lowered)
    }

    private static func applyingUniversalOutputRoute(to apps: [MixerApp],
                                                      requestedUID: String?,
                                                      defaultUID: String?,
                                                      defaultDevices: Set<AudioObjectID>,
                                                      previouslyRoutedObjects: [String: [AudioObjectID]]) -> [MixerApp] {
        apps.map { current in
            var app = current
            app.universalOutputRouteUID = nil
            guard let requestedUID, requestedUID == defaultUID,
                  !app.isBypassed, app.selectedOutputDeviceUID == nil else { return app }
            let devices = app.audioObjects.reduce(into: Set<AudioObjectID>()) { devices, object in
                devices.formUnion(objectList(object, kAudioProcessPropertyDevices,
                                             scope: kAudioObjectPropertyScopeOutput))
            }
            if MixerRoutingSupport.requiresUniversalOutputRouting(
                requestedUID: requestedUID,
                defaultUID: defaultUID,
                selectedUID: app.selectedOutputDeviceUID,
                audioObjects: app.audioObjects,
                previouslyRoutedObjects: previouslyRoutedObjects[app.id],
                processDevices: devices,
                defaultDevices: defaultDevices) {
                app.universalOutputRouteUID = defaultUID
            }
            return app
        }
    }

    private static func coalescingAppsWithDuplicateIDs(_ apps: [MixerApp]) -> [MixerApp] {
        var merged: [MixerApp] = []
        var indexesByID: [String: Int] = [:]

        for app in apps {
            guard let index = indexesByID[app.id] else {
                indexesByID[app.id] = merged.count
                merged.append(app)
                continue
            }

            let existing = merged[index]
            let audioObjects = Array(Set(existing.audioObjects).union(app.audioObjects)).sorted()
            merged[index] = MixerApp(id: existing.id,
                                     persistenceID: existing.persistenceID,
                                     ownerPid: existing.ownerPid,
                                     name: existing.name,
                                     audioObjects: audioObjects,
                                     isPlaying: existing.isPlaying || app.isPlaying,
                                     isBypassed: existing.isBypassed || app.isBypassed,
                                     supportsVolumeOverride: existing.supportsVolumeOverride || app.supportsVolumeOverride,
                                     universalOutputRouteUID: existing.universalOutputRouteUID ?? app.universalOutputRouteUID,
                                     selectedOutputDeviceUID: existing.selectedOutputDeviceUID,
                                     effectiveOutputDeviceUID: existing.effectiveOutputDeviceUID,
                                     outputDeviceUnavailable: existing.outputDeviceUnavailable,
                                     volume: existing.volume)
        }

        return merged
    }

    private struct LoweredOutput {
        let uid: String
        let previousVolume: Float32
        let appliedVolume: Float32
        var mutedByLowering = false
    }

    private struct LoweredOutputState {
        var lastAutomaticLoweredOutputUID: String?
        var loweredOutput: LoweredOutput?
    }

    private static func loweringOutputVolumeIfHeadphonesDisconnected(
        state: LoweredOutputState,
        previousDefaultUID: String?,
        previousOutputDevices: [MixerOutputDevice],
        nextDefaultUID: String?,
        nextOutputDevices: [MixerOutputDevice],
        lowerOnDisconnect: Bool,
        lowerToPercent: Int) -> LoweredOutputState {
        var state = state
        if let nextDefaultUID,
           nextOutputDevices.first(where: { $0.uid == nextDefaultUID })?.isHeadphones == true {
            state.lastAutomaticLoweredOutputUID = nil
            state.loweredOutput = restoringLoweredOutputVolume(state.loweredOutput,
                                                               in: nextOutputDevices)
            return state
        }

        guard lowerOnDisconnect,
              let previousDefaultUID,
              let previousDefault = previousOutputDevices.first(where: { $0.uid == previousDefaultUID }),
              previousDefault.isHeadphones,
              !nextOutputDevices.contains(where: { $0.uid == previousDefaultUID && $0.isHeadphones }),
              let nextDefaultUID,
              let nextDefault = nextOutputDevices.first(where: { $0.uid == nextDefaultUID }),
              !nextDefault.isHeadphones,
              state.lastAutomaticLoweredOutputUID != nextDefaultUID else {
            return state
        }

        let volume = Float32(Double(lowerToPercent) / 100)
        let previousVolume = outputVolume(for: nextDefault.audioObjectID)
        if setOutputVolume(volume, for: nextDefault.audioObjectID) {
            state.lastAutomaticLoweredOutputUID = nextDefaultUID
            let muted = MixerRoutingSupport.shouldMuteOutputLoweredForDisconnect(
                lowerToPercent: lowerToPercent,
                currentlyMuted: outputMuted(for: nextDefault.audioObjectID))
                && setOutputMuted(true, for: nextDefault.audioObjectID)
            if let previousVolume, previousVolume > volume || muted {
                state.loweredOutput = LoweredOutput(uid: nextDefaultUID,
                                                    previousVolume: previousVolume,
                                                    appliedVolume: volume,
                                                    mutedByLowering: muted)
            }
        }
        return state
    }

    private static func restoringLoweredOutputVolume(_ lowered: LoweredOutput?,
                                                     in devices: [MixerOutputDevice]) -> LoweredOutput? {
        guard let lowered else { return nil }
        guard let device = devices.first(where: { $0.uid == lowered.uid }) else {
            return lowered
        }
        guard MixerRoutingSupport.shouldRestoreOutputVolume(
            appliedVolume: Double(lowered.appliedVolume),
            currentVolume: outputVolume(for: device.audioObjectID).map(Double.init)) else { return nil }
        _ = setOutputVolume(lowered.previousVolume, for: device.audioObjectID)
        if lowered.mutedByLowering, outputMuted(for: device.audioObjectID) == true {
            setOutputMuted(false, for: device.audioObjectID)
        }
        return nil
    }

    private func restoreLoweredOutputVolume() {
        loweredOutput = Self.restoringLoweredOutputVolume(loweredOutput, in: outputDevices)
    }

    private func reconcileEngines(with apps: [MixerApp]) {
        let apps = Self.coalescingAppsWithDuplicateIDs(apps)
        if AirPlayRouteManager.isListed {
            AirPlayRouteManager.shared.routedAudioChanged(active: apps.contains { app in
                MixerRoutingSupport.playsOnAirPlay(isPlaying: app.isPlaying,
                                                   effectiveOutputDeviceUID: app.effectiveOutputDeviceUID)
            })
        }
        var byId: [String: MixerApp] = [:]
        for app in apps {
            byId[app.id] = app
        }

        let now = CFAbsoluteTimeGetCurrent()
        var nextPassDelay: Double?

        for (id, engine) in Array(engines) {
            let app = byId[id]
            let hasAudioObjects = !(app?.audioObjects.isEmpty ?? true)

            guard hasAudioObjects, let app else {
                let lostAt = objectsLostAt[id]
                if let delay = MixerRoutingSupport.engineTeardownDelay(
                    hasAudioObjects: false,
                    lastChangeAt: lostAt,
                    now: now) {
                    if lostAt == nil { objectsLostAt[id] = now }
                    nextPassDelay = min(nextPassDelay ?? delay, delay)
                } else {
                    discardEngine(for: id)
                }
                continue
            }
            objectsLostAt.removeValue(forKey: id)

            if engine.requiresRebuild {
                engineRenderProgress.removeValue(forKey: id)
                engineChangeAt[id] = now
                applyRouting(for: app)
                continue
            }

            switch MixerRoutingSupport.engineRenderVerdict(previous: engineRenderProgress[id],
                                                           cycles: engine.renderCycles,
                                                           isPlaying: app.isPlaying,
                                                           now: now) {
            case .note(let observation, let recheckAfter):
                if let previous = engineRenderProgress[id],
                   observation.cycles != previous.cycles {
                    engineRecovery.clear(id)
                }
                engineRenderProgress[id] = observation
                nextPassDelay = min(nextPassDelay ?? recheckAfter, recheckAfter)
            case .stalled(let recheckAfter):
                nextPassDelay = min(nextPassDelay ?? recheckAfter, recheckAfter)
            case .wedged:
                engines.removeValue(forKey: id)?.stop()
                engineRenderProgress.removeValue(forKey: id)
                engineChangeAt[id] = now
                let configuration = MixerEngineRecovery.Configuration(
                    objects: engine.tappedObjects,
                    outputDeviceUID: engine.outputDeviceUID)
                let shouldRetry = engineRecovery.recordFailure(id, configuration: configuration)
                if shouldRetry {
                    applyRouting(for: app)
                }
                continue
            case nil:
                engineRenderProgress.removeValue(forKey: id)
            }

            engine.refreshLevelCompensation(immediately: false)

            let listedUIDs = outputDevices.map(\.uid)
            let clockIsGone = engine.clockDeviceUID.map { !listedUIDs.contains($0) } == true
            guard engine.tappedObjects != app.audioObjects
                || engine.outputDeviceUID != app.effectiveOutputDeviceUID
                || !appNeedsEngine(app)
                || clockIsGone else { continue }

            engineChangeAt[id] = now
            guard appNeedsEngine(app) else {
                discardEngine(for: id)
                continue
            }
            if !MixerRoutingSupport.engineOutputIsPresent(engine.outputDeviceUID,
                                                          clockUID: engine.clockDeviceUID,
                                                          listedUIDs: listedUIDs,
                                                          airPlayConnected: AirPlayRouteManager.isSpeakerConnected) {
                engines.removeValue(forKey: id)?.stop()
                engineRenderProgress.removeValue(forKey: id)
            }
            applyRouting(for: app)
        }

        for app in apps where appNeedsEngine(app) && engines[app.id] == nil {
            applyRouting(for: app)
        }
        forgetEngineStateOfMissingRows(byId)
        if let nextPassDelay {
            scheduleEngineReconcile(after: nextPassDelay)
        }
    }

    fileprivate func reconcileAudioConfigurationChanges() {
        guard listenerInstalled, !stopped else { return }
        reconcileEngines(with: apps)
    }

    private func scheduleEngineReconcile(after delay: Double) {
        guard !engineReconcilePending else { return }
        engineReconcilePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + max(delay, 0.01)) { [weak self] in
            guard let self else { return }
            self.engineReconcilePending = false
            guard !self.stopped, self.listenerInstalled else { return }
            self.reconcileEngines(with: self.apps)
        }
    }

    private func forgetEngineStateOfMissingRows(_ byId: [String: MixerApp]) {
        for id in engineChangeAt.keys where byId[id] == nil && engines[id] == nil {
            engineChangeAt.removeValue(forKey: id)
            configurationRepairs.removeValue(forKey: id)
            objectsLostAt.removeValue(forKey: id)
            engineRecovery.clear(id)
        }
    }

    // MARK: - Persistence

    private func savedVolumes() -> [String: Double] {
        let raw = UserDefaults.standard.dictionary(forKey: DefaultsKey.appVolumes) ?? [:]
        var sanitized: [String: Double] = [:]
        for (id, value) in raw {
            let number: Double?
            if let value = value as? Double {
                number = value
            } else if let value = value as? NSNumber {
                number = value.doubleValue
            } else {
                number = nil
            }
            guard let number, number.isFinite else { continue }
            sanitized[id] = Defaults.sanitizedAppVolume(number)
        }
        return sanitized
    }

    private func savedOutputDeviceUIDs() -> [String: String] {
        let raw = UserDefaults.standard.dictionary(forKey: DefaultsKey.appOutputDevices) ?? [:]
        return Defaults.sanitizedAppOutputDevices(raw)
    }

    // MARK: - Call audio compatibility

    private func savedCallAppVolumeEnabled() -> Set<String> {
        MixerRoutingSupport.sanitizedCallAppVolumeIDs(
            UserDefaults.standard.stringArray(forKey: DefaultsKey.mixerCallAppVolumeEnabled) ?? [])
    }

    func setCallAppVolumeControl(_ enabled: Bool, for app: MixerApp) {
        guard let index = apps.firstIndex(where: { $0.id == app.id }),
              apps[index].supportsVolumeOverride,
              let id = apps[index].persistenceID else { return }
        var allowed = savedCallAppVolumeEnabled()
        if enabled { allowed.insert(id.lowercased()) }
        else { allowed.remove(id.lowercased()) }
        UserDefaults.standard.set(allowed.sorted(), forKey: DefaultsKey.mixerCallAppVolumeEnabled)

        refresh.discardInFlight()
        builds.invalidate(app.id)
        apps[index].isBypassed = !enabled
        apps[index].universalOutputRouteUID = nil
        if enabled {
            apps[index].volume = storedVolume(for: apps[index].identity, saved: savedVolumes()) ?? 1
            applyOutputRoute(to: &apps[index], savedOutputs: savedOutputDeviceUIDs(),
                             availableUIDs: MixerRoutingSupport.routableOutputUIDs(
                                outputDevices.map(\.uid), airPlayConnected: AirPlayRouteManager.isSpeakerConnected),
                             defaultUID: currentOutputDeviceUID)
        } else {
            apps[index].volume = 1
            apps[index].selectedOutputDeviceUID = nil
            apps[index].effectiveOutputDeviceUID = nil
            apps[index].outputDeviceUnavailable = false
        }
        applyRouting(for: apps[index])
        clearPermissionIfNoActiveAdjustments()
        refreshApps()
    }

    // MARK: - List visibility (issue #300)

    func hideFromList(_ app: MixerApp) {
        guard let id = app.persistenceID else { return }
        if id == MixerRoutingSupport.finderBundleIdentifier {
            UserDefaults.standard.set(false, forKey: DefaultsKey.mixerShowFinder)
        } else {
            var hidden = savedHiddenApps()
            hidden[id] = app.name
            persistHiddenApps(hidden)
        }
        publishHiddenApps()
        refreshApps()
    }

    func showInList(id: String) {
        if id == MixerRoutingSupport.finderBundleIdentifier {
            UserDefaults.standard.set(true, forKey: DefaultsKey.mixerShowFinder)
        } else {
            var hidden = savedHiddenApps()
            hidden.removeValue(forKey: id)
            persistHiddenApps(hidden)
        }
        publishHiddenApps()
        refreshApps()
    }

    private func savedHiddenApps() -> [String: String] {
        MixerRoutingSupport.sanitizedHiddenApps(
            UserDefaults.standard.dictionary(forKey: DefaultsKey.mixerHiddenApps) ?? [:])
    }

    private func persistHiddenApps(_ hidden: [String: String]) {
        if hidden.isEmpty {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.mixerHiddenApps)
        } else {
            UserDefaults.standard.set(hidden, forKey: DefaultsKey.mixerHiddenApps)
        }
    }

    private func publishHiddenApps() {
        var entries = savedHiddenApps().map { MixerHiddenApp(id: $0.key, name: $0.value) }
        if !UserDefaults.standard.bool(forKey: DefaultsKey.mixerShowFinder) {
            let finderID = MixerRoutingSupport.finderBundleIdentifier
            let name = NSRunningApplication.runningApplications(withBundleIdentifier: finderID)
                .first?.localizedName ?? "Finder"
            entries.append(MixerHiddenApp(id: finderID, name: name))
        }
        entries.sort {
            MixerRoutingSupport.displayOrderedBefore(name: $0.name, id: $0.id,
                                                     otherName: $1.name, otherID: $1.id)
        }
        if hiddenApps != entries { hiddenApps = entries }
    }

    private static func storedVolume(for identity: MixerRowIdentity,
                                     saved: [String: Double],
                                     session: [String: Double]) -> Double? {
        guard let key = identity.persistenceID else { return session[identity.rowID] }
        return saved[key]
    }

    private static func storedRoute(for identity: MixerRowIdentity,
                                    saved: [String: String],
                                    session: [String: String]) -> String? {
        guard let key = identity.persistenceID else { return session[identity.rowID] }
        return saved[key]
    }

    private func storedVolume(for identity: MixerRowIdentity, saved: [String: Double]) -> Double? {
        Self.storedVolume(for: identity, saved: saved, session: sessionVolumes)
    }

    private func storedRoute(for identity: MixerRowIdentity, saved: [String: String]) -> String? {
        Self.storedRoute(for: identity, saved: saved, session: sessionRoutes)
    }

    private func applyingCurrentVolumes(to rows: [MixerApp]) -> [MixerApp] {
        let saved = savedVolumes()
        return rows.map { row in
            var row = row
            row.volume = row.isBypassed ? 1 : (storedVolume(for: row.identity, saved: saved) ?? 1)
            return row
        }
    }

    private func persistVolume(_ volume: Double, for app: MixerApp) {
        guard let id = app.persistenceID else {
            if isUnity(volume) {
                sessionVolumes.removeValue(forKey: app.id)
            } else {
                sessionVolumes[app.id] = volume
            }
            return
        }
        var volumes = savedVolumes()
        if isUnity(volume) {
            volumes.removeValue(forKey: id)
        } else {
            volumes[id] = volume
        }
        UserDefaults.standard.set(volumes, forKey: DefaultsKey.appVolumes)
    }

    private func persistOutputDeviceUID(_ uid: String?, for app: MixerApp) {
        guard let id = app.persistenceID else {
            if let uid {
                sessionRoutes[app.id] = uid
            } else {
                sessionRoutes.removeValue(forKey: app.id)
            }
            return
        }
        var routes = savedOutputDeviceUIDs()
        if let uid {
            routes[id] = uid
        } else {
            routes.removeValue(forKey: id)
        }
        UserDefaults.standard.set(routes, forKey: DefaultsKey.appOutputDevices)
    }

    private func persistOutputDeviceUIDs(_ routes: [String: String]) {
        if routes.isEmpty {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.appOutputDevices)
        } else {
            UserDefaults.standard.set(routes, forKey: DefaultsKey.appOutputDevices)
        }
    }

    private func clearPermissionIfNoActiveAdjustments() {
        guard needsPermission,
              !apps.contains(where: appNeedsEngine),
              engines.isEmpty,
              builds.isEmpty else { return }
        needsPermission = false
    }

    // MARK: - CoreAudio plumbing

    static func audioProcessObjects() -> [AudioObjectID] {
        objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
    }

    private static func processBundleIdentifier(of object: AudioObjectID) -> String? {
        guard #available(macOS 14.4, *) else { return nil }
        var bundleRef: CFString = "" as CFString
        guard read(object, kAudioProcessPropertyBundleID, &bundleRef) else { return nil }
        let bundleID = bundleRef as String
        return bundleID.isEmpty ? nil : bundleID
    }

    private static let outputVolumeSelectors: [AudioObjectPropertySelector] = [
        kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        kAudioDevicePropertyVolumeScalar,
    ]

    private static func outputVolume(for deviceID: AudioObjectID) -> Float32? {
        for selector in outputVolumeSelectors {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                                                     mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            var volume: Float32 = 0
            if read(deviceID, selector, &volume, scope: kAudioObjectPropertyScopeOutput) {
                return volume
            }
        }
        return nil
    }

    private static func hasSettableOutputVolume(for deviceID: AudioObjectID) -> Bool {
        for selector in outputVolumeSelectors {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                                                     mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            var isSettable = DarwinBoolean(false)
            if AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
               isSettable.boolValue {
                return true
            }
        }
        return false
    }

    private static func outputDevices(defaultUID: String?) -> [MixerOutputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr else { return [] }
        var deviceIDs = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &deviceIDs) == noErr else { return [] }

        var devices: [MixerOutputDevice] = []
        for deviceID in deviceIDs {
            let streams = outputStreams(deviceID)
            guard !streams.isEmpty else { continue }

            var isAlive: UInt32 = 1
            if read(deviceID, kAudioDevicePropertyDeviceIsAlive, &isAlive), isAlive == 0 {
                continue
            }
            var isHidden: UInt32 = 0
            if read(deviceID, kAudioDevicePropertyIsHidden, &isHidden), isHidden != 0 {
                continue
            }
            let canBeDefaultOutput = canBeDefault(deviceID,
                                                  selector: kAudioDevicePropertyDeviceCanBeDefaultDevice)
            let canBeDefaultSystemOutput = canBeDefault(
                deviceID,
                selector: kAudioDevicePropertyDeviceCanBeDefaultSystemDevice)

            var uidRef: CFString = "" as CFString
            guard read(deviceID, kAudioDevicePropertyDeviceUID, &uidRef) else { continue }
            let uid = uidRef as String
            guard !uid.isEmpty else { continue }

            var nameRef: CFString = "" as CFString
            let name = read(deviceID, kAudioObjectPropertyName, &nameRef)
                ? nameRef as String
                : uid
            guard !MicMuteSupport.isOwnDevice(name: name) else { continue }
            let dataSourceName = outputDataSourceName(for: deviceID)
            let terminalTypes: [UInt32] = streams.compactMap { stream in
                var terminal: UInt32 = kAudioStreamTerminalTypeUnknown
                return read(stream, kAudioStreamPropertyTerminalType, &terminal) ? terminal : nil
            }
            var transportType: UInt32 = 0
            _ = read(deviceID, kAudioDevicePropertyTransportType, &transportType)

            devices.append(MixerOutputDevice(id: uid,
                                             uid: uid,
                                             name: name,
                                             isDefault: uid == defaultUID,
                                             isHeadphones: MixerRoutingSupport.outputLooksLikeHeadphones(
                                                name: name,
                                                uid: uid,
                                                dataSourceName: dataSourceName,
                                                terminalTypes: terminalTypes),
                                             canBeDefaultOutput: canBeDefaultOutput,
                                             canBeDefaultSystemOutput: canBeDefaultSystemOutput,
                                             priorityTier: MixerRoutingSupport.PriorityTier(
                                                transportType: transportType),
                                             audioObjectID: deviceID))
        }

        if AirPlayRouteManager.isListed {
            let airPlayName: String
            if let active = AirPlayRouteManager.currentSpeakerName, !active.isEmpty {
                airPlayName = "\(active) (AirPlay)"
            } else {
                airPlayName = "AirPlay"
            }
            devices.append(MixerOutputDevice(id: AirPlayRouteManager.airPlaySentinelUID,
                                             uid: AirPlayRouteManager.airPlaySentinelUID,
                                             name: airPlayName,
                                             isDefault: false,
                                             isHeadphones: false,
                                             canBeDefaultOutput: false,
                                             canBeDefaultSystemOutput: false,
                                             priorityTier: .hardware,
                                             audioObjectID: 0))
        }

        return devices.sorted { lhs, rhs in
            MixerRoutingSupport.deviceDisplayOrderedBefore(
                isDefault: lhs.isDefault, name: lhs.name, uid: lhs.uid,
                otherIsDefault: rhs.isDefault, otherName: rhs.name, otherUID: rhs.uid)
        }
    }

    private static func outputDataSourceName(for deviceID: AudioObjectID) -> String? {
        var dataSourceID: UInt32 = 0
        guard read(deviceID,
                   kAudioDevicePropertyDataSource,
                   &dataSourceID,
                   scope: kAudioObjectPropertyScopeOutput) else { return nil }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSourceNameForIDCFString,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var nameRef: CFString = "" as CFString
        let status = withUnsafeMutablePointer(to: &dataSourceID) { dataSourcePointer in
            withUnsafeMutablePointer(to: &nameRef) { namePointer in
                var translation = AudioValueTranslation(
                    mInputData: UnsafeMutableRawPointer(dataSourcePointer),
                    mInputDataSize: UInt32(MemoryLayout<UInt32>.size),
                    mOutputData: UnsafeMutableRawPointer(namePointer),
                    mOutputDataSize: UInt32(MemoryLayout<CFString>.size))
                var size = UInt32(MemoryLayout<AudioValueTranslation>.size)
                return AudioObjectGetPropertyData(
                    deviceID,
                    &address,
                    0,
                    nil,
                    &size,
                    &translation)
            }
        }
        guard status == noErr else { return nil }
        return nameRef as String
    }

    fileprivate static func outputStreamChannels(of deviceID: AudioObjectID) -> [Int] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioBufferList>.size) else { return [] }
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, storage) == noErr else {
            return []
        }
        return UnsafeMutableAudioBufferListPointer(
            storage.assumingMemoryBound(to: AudioBufferList.self)).map { Int($0.mNumberChannels) }
    }

    fileprivate static func outputStreams(_ deviceID: AudioObjectID) -> [AudioStreamID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioStreamID>.size else { return [] }
        var streams = [AudioStreamID](repeating: 0, count: Int(size) / MemoryLayout<AudioStreamID>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &streams) == noErr else { return [] }
        return Array(streams.prefix(Int(size) / MemoryLayout<AudioStreamID>.size))
    }

    private static func canBeDefault(_ deviceID: AudioObjectID,
                                     selector: AudioObjectPropertySelector) -> Bool {
        var value: UInt32 = 0
        return read(deviceID, selector, &value, scope: kAudioObjectPropertyScopeOutput) && value != 0
    }

    private static func defaultOutputDeviceUID(
        selector: AudioObjectPropertySelector = kAudioHardwarePropertyDefaultOutputDevice
    ) -> String? {
        var defaultDevice = AudioObjectID(0)
        guard read(AudioObjectID(kAudioObjectSystemObject),
                   selector, &defaultDevice),
              defaultDevice != 0 else { return nil }
        var uidRef: CFString = "" as CFString
        guard read(defaultDevice, kAudioDevicePropertyDeviceUID, &uidRef) else { return nil }
        return uidRef as String
    }

    private static func setDefaultDevice(_ deviceID: AudioObjectID,
                                         selector: AudioObjectPropertySelector) -> OSStatus {
        var nextDeviceID = deviceID
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                          &address,
                                          0,
                                          nil,
                                          UInt32(MemoryLayout<AudioObjectID>.size),
                                          &nextDeviceID)
    }

    private static func setOutputVolume(_ volume: Float32, for deviceID: AudioObjectID,
                                        permitsFallback: Bool = true) -> Bool {
        let clamped = min(max(volume, 0), 1)
        for selector in outputVolumeSelectors {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                                                     mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectHasProperty(deviceID, &address) else { continue }

            var isSettable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr,
                  isSettable.boolValue else { continue }

            var nextVolume = clamped
            let status = AudioObjectSetPropertyData(deviceID,
                                                    &address,
                                                    0,
                                                    nil,
                                                    UInt32(MemoryLayout<Float32>.size),
                                                    &nextVolume)
            if status == noErr { return true }
            if !permitsFallback { return false }
        }
        return false
    }

    @discardableResult
    static func setSystemOutputVolume(_ volume: Double) -> Bool {
        guard let device = defaultOutputDeviceID() else { return false }
        let level = min(max(volume, 0), 1)
        let applied = setOutputVolume(Float32(level), for: device)
        setOutputMuted(MixerRoutingSupport.mutesOutput(atVolume: level), for: device)
        return applied
    }

    static func systemOutputIsMuted() -> Bool? {
        guard let device = defaultOutputDeviceID() else { return nil }
        return outputMuted(for: device)
    }

    @discardableResult
    static func setSystemOutputMuted(_ muted: Bool) -> Bool {
        guard let device = defaultOutputDeviceID() else { return false }
        return setOutputMuted(muted, for: device)
    }

    fileprivate static func defaultOutputDeviceID() -> AudioObjectID? {
        var device = AudioObjectID(0)
        guard read(AudioObjectID(kAudioObjectSystemObject),
                   kAudioHardwarePropertyDefaultOutputDevice, &device),
              device != 0 else { return nil }
        return device
    }

    private static func muteElements(for deviceID: AudioObjectID) -> [AudioObjectPropertyElement] {
        [kAudioObjectPropertyElementMain, 1, 2]
    }

    private static func outputMuted(for deviceID: AudioObjectID) -> Bool? {
        for element in muteElements(for: deviceID) {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                     mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: element)
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr
            else { continue }
            return value != 0
        }
        return nil
    }

    @discardableResult
    private static func setOutputMuted(_ muted: Bool, for deviceID: AudioObjectID) -> Bool {
        var changed = false
        for element in muteElements(for: deviceID) {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                     mScope: kAudioObjectPropertyScopeOutput,
                                                     mElement: element)
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr,
                  settable.boolValue else { continue }
            var value: UInt32 = muted ? 1 : 0
            if AudioObjectSetPropertyData(deviceID, &address, 0, nil,
                                          UInt32(MemoryLayout<UInt32>.size), &value) == noErr {
                changed = true
            }
        }
        return changed
    }

    fileprivate static func objectList(_ object: AudioObjectID,
                                       _ selector: AudioObjectPropertySelector,
                                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioObjectID>.size) else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &objects) == noErr else {
            return []
        }
        return objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size).filter { $0 != 0 }
    }

    fileprivate static func subDeviceUIDs(of device: AudioObjectID) -> [String] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioAggregateDevicePropertyFullSubDeviceList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var list: Unmanaged<CFArray>?
        var size = UInt32(MemoryLayout<Unmanaged<CFArray>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &list) == noErr,
              size == UInt32(MemoryLayout<Unmanaged<CFArray>?>.size),
              let list else { return [] }
        return (list.takeRetainedValue() as? [String]) ?? []
    }

    fileprivate static func deviceID(forUID uid: String) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var qualifier = uid as CFString
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &qualifier) { pointer in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<CFString>.size), pointer, &size, &device)
        }
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    @discardableResult
    fileprivate static func read<T>(_ object: AudioObjectID,
                                    _ selector: AudioObjectPropertySelector,
                                    _ value: inout T,
                                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size,
                                       UnsafeMutableRawPointer(pointer)) == noErr
        }
    }
}

// MARK: - Tap engine

private protocol GainEngine: AnyObject {
    var gain: Float { get set }
    var tappedObjects: [AudioObjectID] { get }
    var outputDeviceUID: String { get }
    var clockDeviceUID: String? { get }
    var renderCycles: UInt64 { get }
    var requiresRebuild: Bool { get }
    func refreshLevelCompensation(immediately: Bool)
    func stop()
}

private extension GainEngine {
    var requiresRebuild: Bool { false }
}

final class LevelCompensationWatch {
    private var objects: [AudioObjectID]
    private let excluded: Set<AudioObjectID>?
    private let store: (Float) -> Void
    private let listenLock = NSLock()
    private var listenedObjects: [AudioObjectID] = []
    private var listensToProcessList = false
    private var client: UnsafeMutableRawPointer?
    private let pendingLock = NSLock()
    private var refreshPending = false
    private var immediatePending = false
    private let queue = DispatchQueue(label: "com.vorssaint.utils.mixer.level",
                                      qos: .userInitiated)
    private var lastDevices = Set<AudioObjectID>()
    private var lastReadAt: CFAbsoluteTime = 0

    private static let firstReadWait = DispatchTimeInterval.milliseconds(50)
    private let firstRead = DispatchSemaphore(value: 0)

    private init(objects: [AudioObjectID], excluded: Set<AudioObjectID>? = nil,
                 store: @escaping (Float) -> Void) {
        self.objects = objects
        self.excluded = excluded
        self.store = store
    }

    static func started(objects: [AudioObjectID],
                        store: @escaping (Float) -> Void) -> LevelCompensationWatch {
        let watch = LevelCompensationWatch(objects: objects, store: store)
        let client = Unmanaged.passRetained(watch).toOpaque()
        for object in objects {
            var address = Self.address
            if AudioObjectAddPropertyListener(object, &address, Self.listener, client) == noErr {
                watch.listenedObjects.append(object)
            }
        }
        if watch.listenedObjects.isEmpty {
            Unmanaged<LevelCompensationWatch>.fromOpaque(client).release()
        } else {
            watch.client = client
        }
        watch.queue.async {
            watch.read()
            watch.firstRead.signal()
        }
        return watch
    }

    static func started(everyProcessExcept excluded: [AudioObjectID],
                        store: @escaping (Float) -> Void) -> LevelCompensationWatch {
        let watch = LevelCompensationWatch(objects: [], excluded: Set(excluded), store: store)
        let client = Unmanaged.passRetained(watch).toOpaque()
        watch.client = client
        var address = Self.processListAddress
        watch.listensToProcessList = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject), &address, Self.listener, client) == noErr
        watch.queue.async {
            _ = watch.followProcessList()
            watch.read()
            watch.firstRead.signal()
        }
        return watch
    }

    func waitForFirstRead() {
        _ = firstRead.wait(timeout: .now() + Self.firstReadWait)
    }

    func refresh(immediately: Bool) {
        let queued = pendingLock.withLock {
            immediatePending = immediatePending || immediately
            guard !refreshPending else { return false }
            refreshPending = true
            return true
        }
        guard queued else { return }
        queue.async { [self] in
            let immediately = pendingLock.withLock {
                defer {
                    refreshPending = false
                    immediatePending = false
                }
                return immediatePending
            }
            guard MixerRoutingSupport.tapLevelReadIsDue(
                immediately: immediately,
                sinceLastRead: CFAbsoluteTimeGetCurrent() - lastReadAt) else { return }
            read()
        }
    }

    func stop() {
        guard #available(macOS 14.4, *) else { return }
        TapGainEngine.teardownQueue.addOperation { [weak self] in self?.stopListening() }
    }

    private func stopListening() {
        let (client, listened, processList) = listenLock.withLock {
            defer {
                self.client = nil
                listenedObjects.removeAll()
                listensToProcessList = false
            }
            return (self.client, listenedObjects, listensToProcessList)
        }
        guard let client else { return }
        var removedAll = true
        for object in listened {
            var address = Self.address
            let status = AudioObjectRemovePropertyListener(object, &address, Self.listener, client)
            if status != noErr && status != kAudioHardwareBadObjectError {
                removedAll = false
            }
        }
        if processList {
            var address = Self.processListAddress
            if AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject), &address,
                                                 Self.listener, client) != noErr {
                removedAll = false
            }
        }
        if removedAll { Unmanaged<LevelCompensationWatch>.fromOpaque(client).release() }
    }

    private func followProcessList() -> Bool {
        guard let excluded else { return false }
        let current = AppVolumeMixer.audioProcessObjects().filter { $0 != 0 && !excluded.contains($0) }
        guard Set(current) != Set(objects) else { return false }
        objects = current
        listenLock.withLock {
            guard let client else { return }
            let changes = MixerRoutingSupport.listenerChanges(listened: Set(listenedObjects),
                                                              wanted: Set(current))
            listenedObjects.removeAll { object in
                guard changes.remove.contains(object) else { return false }
                var address = Self.address
                let status = AudioObjectRemovePropertyListener(object, &address, Self.listener, client)
                return status == noErr || status == kAudioHardwareBadObjectError
            }
            for object in changes.add {
                var address = Self.address
                if AudioObjectAddPropertyListener(object, &address, Self.listener, client) == noErr {
                    listenedObjects.append(object)
                }
            }
        }
        return true
    }

    private func read() {
        lastReadAt = CFAbsoluteTimeGetCurrent()
        var devices = Set<AudioObjectID>()
        for object in objects { devices.formUnion(Self.processOutputDevices(of: object)) }
        if let first = MixerRoutingSupport.tapLevelBeforeReading(
            devices: devices,
            lastDevices: lastDevices,
            defaultOutputDevices: devices.isEmpty ? Self.defaultOutputDevices() : []) {
            store(Float(first))
        }
        guard !devices.isEmpty else { return }
        lastDevices = devices
        store(Float(MixerRoutingSupport.tapLevelCompensation(
            streamChannels: devices.map { Self.stereoStreamChannels(of: $0) })))
    }

    private static func processOutputDevices(of process: AudioObjectID) -> [AudioObjectID] {
        AppVolumeMixer.objectList(process, address.mSelector, scope: address.mScope)
    }

    private static func defaultOutputDevices() -> Set<AudioObjectID> {
        guard let output = AppVolumeMixer.defaultOutputDeviceID() else { return [] }
        return MixerRoutingSupport.outputDevices(of: output,
                                                 subDeviceUIDs: AppVolumeMixer.subDeviceUIDs(of:),
                                                 deviceForUID: AppVolumeMixer.deviceID(forUID:))
    }

    private static func stereoStreamChannels(of deviceID: AudioObjectID) -> Int? {
        let streams = AppVolumeMixer.outputStreamChannels(of: deviceID)
        guard !streams.isEmpty else { return nil }
        var stereoPair: (UInt32, UInt32) = (1, 2)
        _ = AppVolumeMixer.read(deviceID, kAudioDevicePropertyPreferredChannelsForStereo, &stereoPair,
                                scope: kAudioObjectPropertyScopeOutput)
        return MixerRoutingSupport.stereoStreamChannels(streamChannels: streams,
                                                        preferredLeftChannel: Int(stereoPair.0))
    }

    private static let address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyDevices,
                                                            mScope: kAudioObjectPropertyScopeOutput,
                                                            mElement: kAudioObjectPropertyElementMain)

    private static let processListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private static let listener: AudioObjectPropertyListenerProc = { object, _, _, client in
        guard let client else { return noErr }
        let watch = Unmanaged<LevelCompensationWatch>.fromOpaque(client).takeUnretainedValue()
        if object == AudioObjectID(kAudioObjectSystemObject) {
            watch.queue.async {
                if watch.followProcessList() { watch.refresh(immediately: true) }
            }
        } else {
            watch.refresh(immediately: true)
        }
        return noErr
    }
}

final class AtomicFloatBox {
    private var bits: Int32

    init(_ value: Float) {
        bits = Int32(bitPattern: value.bitPattern)
    }

    var value: Float {
        get {
            Float(bitPattern: UInt32(bitPattern: OSAtomicAdd32Barrier(0, &bits)))
        }
        set {
            let replacement = Int32(bitPattern: newValue.bitPattern)
            while true {
                let current = OSAtomicAdd32Barrier(0, &bits)
                if OSAtomicCompareAndSwap32Barrier(current, replacement, &bits) { return }
            }
        }
    }
}

@available(macOS 14.4, *)
private final class MixerTapConfiguration {
    struct Source {
        let device: AudioObjectID
        let stream: AudioObjectID
        let format: MixerTapFormat
    }

    private let tap: AudioObjectID
    private let aggregate: AudioObjectID
    private let objects: [AudioObjectID]
    private let source: Source?
    private let format: MixerTapFormat
    private let sampleRate: Double
    private let outputChannels: [Int]
    private let outputFormats: [AudioObjectID: MixerTapFormat]
    private let onInvalidated: () -> Void
    private let rendering = AtomicFloatBox(1)
    private let invalidated = AtomicFloatBox(0)
    var canRender: Bool { rendering.value != 0 }
    var requiresRebuild: Bool { invalidated.value != 0 }

    private let queue = DispatchQueue(label: "com.vorssaint.utils.mixer.format", qos: .userInitiated)
    private let lock = NSLock()
    private var pending = false
    private var immediatePending = false
    private var stopped = false
    private var lastReadAt: CFAbsoluteTime = 0
    private var registrations: [(AudioObjectID, AudioObjectPropertyAddress)] = []
    private var client: UnsafeMutableRawPointer?

    init(tap: AudioObjectID, aggregate: AudioObjectID, objects: [AudioObjectID],
         source: Source?, format: MixerTapFormat, sampleRate: Double, outputChannels: [Int],
         outputFormats: [AudioObjectID: MixerTapFormat],
         onInvalidated: @escaping () -> Void) {
        self.tap = tap
        self.aggregate = aggregate
        self.objects = objects
        self.source = source
        self.format = format
        self.sampleRate = sampleRate
        self.outputChannels = outputChannels
        self.outputFormats = outputFormats
        self.onInvalidated = onInvalidated
    }

    @discardableResult
    func start() -> Bool {
        let client = Unmanaged.passRetained(self).toOpaque()
        self.client = client
        var properties: [(AudioObjectID, AudioObjectPropertySelector, AudioObjectPropertyScope)] = [
            (tap, kAudioTapPropertyFormat, kAudioObjectPropertyScopeGlobal),
            (aggregate, kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal),
            (aggregate, kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeOutput),
            (aggregate, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput),
        ]
        properties += outputFormats.keys.map {
            ($0, kAudioStreamPropertyVirtualFormat, kAudioObjectPropertyScopeGlobal)
        }
        if let source {
            if outputFormats[source.stream] == nil {
                properties.append((source.stream, kAudioStreamPropertyVirtualFormat, kAudioObjectPropertyScopeGlobal))
            }
            properties += objects.map { ($0, kAudioProcessPropertyDevices, kAudioObjectPropertyScopeOutput) }
        }
        for (object, selector, scope) in properties {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                     mElement: kAudioObjectPropertyElementMain)
            if AudioObjectAddPropertyListener(object, &address, Self.listener, client) == noErr {
                registrations.append((object, address))
            }
        }
        if registrations.isEmpty {
            self.client = nil
            Unmanaged<MixerTapConfiguration>.fromOpaque(client).release()
        }
        guard registrations.count == properties.count else {
            stop()
            return false
        }
        refresh(immediately: true, suspend: true)
        return true
    }

    func refresh(immediately: Bool, suspend: Bool = false) {
        let enqueue = lock.withLock {
            guard !stopped, !requiresRebuild else { return false }
            if suspend { rendering.value = 0 }
            immediatePending = immediatePending || immediately
            guard !pending else { return false }
            pending = true
            return true
        }
        guard enqueue else { return }
        queue.async { [self] in
            let shouldRead = lock.withLock {
                let immediately = immediatePending
                pending = false
                immediatePending = false
                return !stopped && MixerRoutingSupport.tapLevelReadIsDue(
                    immediately: immediately, sinceLastRead: CFAbsoluteTimeGetCurrent() - lastReadAt)
            }
            guard shouldRead else { return }
            lastReadAt = CFAbsoluteTimeGetCurrent()
            let unchanged = isCurrent()
            let notify = lock.withLock {
                let notify = !stopped && !requiresRebuild && !unchanged
                if !unchanged {
                    rendering.value = 0
                    invalidated.value = 1
                } else if !stopped, !pending, !requiresRebuild {
                    rendering.value = 1
                }
                return notify
            }
            if notify { onInvalidated() }
        }
    }

    private func isCurrent() -> Bool {
        var currentFormat = AudioStreamBasicDescription()
        var currentRate: Float64 = 0
        guard AppVolumeMixer.read(tap, kAudioTapPropertyFormat, &currentFormat),
              MixerTapFormat(currentFormat) == format,
              AppVolumeMixer.read(aggregate, kAudioDevicePropertyNominalSampleRate, &currentRate),
              currentRate == sampleRate,
              AppVolumeMixer.outputStreamChannels(of: aggregate) == outputChannels,
              Set(AppVolumeMixer.outputStreams(aggregate)) == Set(outputFormats.keys) else { return false }
        for (stream, expected) in outputFormats {
            guard AppVolumeMixer.read(stream, kAudioStreamPropertyVirtualFormat, &currentFormat),
                  MixerTapFormat(currentFormat, allowNonInterleaved: true) == expected else { return false }
        }
        if let source {
            guard AppVolumeMixer.read(source.stream, kAudioStreamPropertyVirtualFormat, &currentFormat),
                  MixerTapFormat(currentFormat) == source.format else { return false }
            let devices = Set(objects.flatMap {
                AppVolumeMixer.objectList($0, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput)
            })
            guard devices.isEmpty || devices == [source.device] else { return false }
        }
        return true
    }

    func stop() {
        let client = lock.withLock {
            stopped = true
            rendering.value = 0
            defer { self.client = nil }
            return self.client
        }
        guard let client else { return }
        let registrations = self.registrations
        TapGainEngine.teardownQueue.addOperation {
            var removedAll = true
            for (object, storedAddress) in registrations {
                var address = storedAddress
                let status = AudioObjectRemovePropertyListener(object, &address, Self.listener, client)
                if status != noErr && status != kAudioHardwareBadObjectError { removedAll = false }
            }
            if removedAll { Unmanaged<MixerTapConfiguration>.fromOpaque(client).release() }
        }
    }

    private static let listener: AudioObjectPropertyListenerProc = { _, _, _, client in
        guard let client else { return noErr }
        let watch = Unmanaged<MixerTapConfiguration>.fromOpaque(client).takeUnretainedValue()
        watch.refresh(immediately: true, suspend: true)
        return noErr
    }
}

@available(macOS 14.4, *)
private final class TapGainEngine: GainEngine {
    let tappedObjects: [AudioObjectID]
    let outputDeviceUID: String
    var clockDeviceUID: String? { nil }
    var gain: Float {
        get { gainBox.value }
        set { gainBox.value = min(max(newValue, 0), Float(AppVolumeMixer.maxVolume)) }
    }

    private final class AtomicCycleBox {
        private var bits: Int64 = 0
        var value: UInt64 { UInt64(bitPattern: OSAtomicAdd64Barrier(0, &bits)) }
        func increment() { _ = OSAtomicIncrement64Barrier(&bits) }
    }

    private final class LimiterBox {
        let lookahead: BoostLookaheadBufferListLimiter
        var fallback = BoostBufferListLimiter()
        init(channelCapacity: Int) {
            lookahead = BoostLookaheadBufferListLimiter(channelCapacity: channelCapacity)
        }

        func reset() {
            lookahead.reset()
            fallback = BoostBufferListLimiter()
        }

        func process(_ output: UnsafeMutableAudioBufferListPointer, release: Float) {
            var frames = Int.max
            for buffer in output where buffer.mData != nil && buffer.mNumberChannels > 0 {
                frames = min(frames, MixerRender.frames(bytes: buffer.mDataByteSize,
                                                        channels: buffer.mNumberChannels))
            }
            guard frames > 0, frames < Int.max else { return }
            if !lookahead.process(output, frames: frames, release: release) {
                fallback.process(output, frames: frames, release: release)
            }
        }
    }

    private let gainBox = AtomicFloatBox(1)
    private let compensationBox = AtomicFloatBox(1)
    private let cycleBox = AtomicCycleBox()
    private let releaseBox = AtomicFloatBox(BoostLimiter.release(sampleRate: 48000))
    var renderCycles: UInt64 { cycleBox.value }
    var requiresRebuild: Bool { configuration?.requiresRebuild ?? false }
    private var tapID = AudioObjectID(0)
    private var aggregateID = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?
    private var configuration: MixerTapConfiguration?
    private var levelWatch: LevelCompensationWatch?

    init?(objects: [AudioObjectID], gain: Float, outputDeviceUID: String) {
        tappedObjects = objects
        gainBox.value = min(max(gain, 0), Float(AppVolumeMixer.maxVolume))
        self.outputDeviceUID = outputDeviceUID

        guard let capture = Self.createTap(objects: objects, outputDeviceUID: outputDeviceUID) else { return nil }
        tapID = capture.id
        let description = capture.description
        let compensation = compensationBox
        if capture.source == nil {
            levelWatch = LevelCompensationWatch.started(objects: objects) { compensation.value = $0 }
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "EVERYTHING Mixer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr,
              aggregateID != 0 else {
            aggregateID = 0
            stop()
            return nil
        }

        let box = gainBox
        guard let sampleRate = Self.nominalSampleRate(of: aggregateID) else {
            stop()
            return nil
        }
        let outputChannels = AppVolumeMixer.outputStreamChannels(of: aggregateID)
        guard !outputChannels.isEmpty,
              capture.source == nil || outputChannels.reduce(0, +) == capture.format.channels,
              let outputFormats = Self.outputFormats(of: aggregateID) else {
            stop()
            return nil
        }
        let configuration = MixerTapConfiguration(tap: tapID, aggregate: aggregateID, objects: objects,
                                                   source: capture.source, format: capture.format,
                                                   sampleRate: sampleRate, outputChannels: outputChannels,
                                                   outputFormats: outputFormats) {
            DispatchQueue.main.async { AppVolumeMixer.shared.reconcileAudioConfigurationChanges() }
        }
        self.configuration = configuration
        let ramp = TapLevelRamp()
        let limiterBox = LimiterBox(
            channelCapacity: max(2, outputChannels.reduce(0, +)))
        releaseBox.value = BoostLimiter.release(sampleRate: sampleRate)
        let release = releaseBox
        let cycles = cycleBox
        let tapChannels = capture.format.channels
        guard AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil, { now, input, _, output, _ in
            let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let outputBuffers = UnsafeMutableAudioBufferListPointer(output)
            guard configuration.canRender else {
                MixerRender.silence(outputBuffers)
                limiterBox.reset()
                return
            }
            defer { limiterBox.process(outputBuffers, release: release.value) }
            guard let tapIndex = MixerRender.tapBufferIndex(in: inputBuffers,
                                                            tapChannels: tapChannels) else {
                MixerRender.silence(outputBuffers)
                return
            }
            let gain = box.value * ramp.next(toward: compensation.value, hostTime: now.pointee.mHostTime)
            let frames = MixerRender.render(source: inputBuffers[tapIndex],
                                            into: outputBuffers,
                                            gain: gain)
            guard frames > 0 else { return }
            cycles.increment()
        }) == noErr else {
            ioProc = nil
            stop()
            return nil
        }

        guard configuration.start() else {
            stop()
            return nil
        }
        levelWatch?.waitForFirstRead()

        guard AudioDeviceStart(aggregateID, ioProc) == noErr else {
            stop()
            return nil
        }
    }

    func refreshLevelCompensation(immediately: Bool) {
        levelWatch?.refresh(immediately: immediately)
        configuration?.refresh(immediately: immediately)
    }

    fileprivate static let rateQueue = DispatchQueue(label: "com.vorssaint.utils.mixer.rate",
                                                 qos: .userInitiated)
    private static let maximumConcurrentTeardowns = 4
    fileprivate static let teardownQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.vorssaint.utils.mixer.teardown"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = maximumConcurrentTeardowns
        return queue
    }()

    fileprivate static func nominalSampleRateAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                   mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private struct Capture {
        let id: AudioObjectID
        let description: CATapDescription
        let format: MixerTapFormat
        let source: MixerTapConfiguration.Source?
    }

    private static func createTap(objects: [AudioObjectID], outputDeviceUID: String) -> Capture? {
        let source = deviceStreamSource(objects: objects, outputDeviceUID: outputDeviceUID)
        if let source,
           let capture = createTap(CATapDescription(processes: objects, deviceUID: outputDeviceUID, stream: 0),
                                   source: source) {
            return capture
        }
        return createTap(CATapDescription(stereoMixdownOfProcesses: objects), source: nil)
    }

    private static func createTap(_ description: CATapDescription,
                                  source: MixerTapConfiguration.Source?) -> Capture? {
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        var tap = AudioObjectID(0)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr, tap != 0 else { return nil }
        var asbd = AudioStreamBasicDescription()
        guard AppVolumeMixer.read(tap, kAudioTapPropertyFormat, &asbd),
              let format = MixerTapFormat(asbd),
              source == nil || format == source?.format else {
            AudioHardwareDestroyProcessTap(tap)
            return nil
        }
        return Capture(id: tap, description: description, format: format, source: source)
    }

    private static func deviceStreamSource(objects: [AudioObjectID], outputDeviceUID: String)
        -> MixerTapConfiguration.Source? {
        guard let device = AppVolumeMixer.deviceID(forUID: outputDeviceUID) else { return nil }
        let streams = AppVolumeMixer.outputStreams(device)
        guard streams.count == 1, let stream = streams.first else { return nil }
        var asbd = AudioStreamBasicDescription()
        var startingChannel: UInt32 = 0
        guard AppVolumeMixer.read(stream, kAudioStreamPropertyVirtualFormat, &asbd),
              AppVolumeMixer.read(stream, kAudioStreamPropertyStartingChannel, &startingChannel),
              let format = MixerTapFormat(asbd) else { return nil }
        let devices = objects.map {
            AppVolumeMixer.objectList($0, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput)
        }
        guard MixerTapFormat.usesDeviceStream(processDevices: devices, outputDevice: device,
                                              streamCount: streams.count, startingChannel: startingChannel,
                                              format: format) else { return nil }
        return MixerTapConfiguration.Source(device: device, stream: stream, format: format)
    }

    private static func nominalSampleRate(of deviceID: AudioObjectID) -> Double? {
        var sampleRate: Float64 = 0
        guard AppVolumeMixer.read(deviceID, kAudioDevicePropertyNominalSampleRate, &sampleRate),
              sampleRate.isFinite, sampleRate > 0 else { return nil }
        return sampleRate
    }

    private static func outputFormats(of deviceID: AudioObjectID) -> [AudioObjectID: MixerTapFormat]? {
        let streams = AppVolumeMixer.outputStreams(deviceID)
        guard !streams.isEmpty else { return nil }
        var formats: [AudioObjectID: MixerTapFormat] = [:]
        for stream in streams {
            var asbd = AudioStreamBasicDescription()
            guard AppVolumeMixer.read(stream, kAudioStreamPropertyVirtualFormat, &asbd),
                  let format = MixerTapFormat(asbd, allowNonInterleaved: true) else { return nil }
            formats[stream] = format
        }
        return formats
    }

    func stop() {
        let tapID = self.tapID
        let aggregateID = self.aggregateID
        let ioProc = self.ioProc
        guard tapID != 0 || aggregateID != 0 || ioProc != nil else {
            return
        }

        self.tapID = 0
        self.aggregateID = 0
        self.ioProc = nil
        configuration?.stop()
        configuration = nil
        levelWatch?.stop()
        levelWatch = nil

        if let ioProc, aggregateID != 0 {
            AudioDeviceStop(aggregateID, ioProc)
        }

        Self.teardownQueue.addOperation {
            if let ioProc, aggregateID != 0 {
                AudioDeviceDestroyIOProcID(aggregateID, ioProc)
            }
            if aggregateID != 0 {
                AudioHardwareDestroyAggregateDevice(aggregateID)
            }
            if tapID != 0 {
                AudioHardwareDestroyProcessTap(tapID)
            }
        }
    }

    deinit { stop() }
}

@available(macOS 14.4, *)
private final class AirPlayGainEngine: GainEngine {
    let tappedObjects: [AudioObjectID]
    let outputDeviceUID: String
    let clockDeviceUID: String?
    private let appID: String

    private final class AtomicCycleBox {
        private var bits: Int64 = 0
        var value: UInt64 { UInt64(bitPattern: OSAtomicAdd64Barrier(0, &bits)) }
        func increment() { _ = OSAtomicIncrement64Barrier(&bits) }
    }

    private let gainBox: AtomicFloatBox
    private let compensationBox: AtomicFloatBox
    private let cycleBox = AtomicCycleBox()
    var renderCycles: UInt64 { cycleBox.value }
    private var levelWatch: LevelCompensationWatch?

    var gain: Float {
        get { gainBox.value }
        set { gainBox.value = min(max(newValue, 0), Float(AppVolumeMixer.maxVolume)) }
    }

    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private let ringBuffer: AudioRingBuffer
    private var registration: AirPlayStreamRegistration?
    private var rateListenerClient: UnsafeMutableRawPointer?

    init?(appID: String, objects: [AudioObjectID], gain: Float, clockDeviceUID: String) {
        self.appID = appID
        self.tappedObjects = objects
        self.outputDeviceUID = AirPlayRouteManager.airPlaySentinelUID
        self.clockDeviceUID = clockDeviceUID
        self.gainBox = AtomicFloatBox(gain)
        self.compensationBox = AtomicFloatBox(1)

        let description = CATapDescription(stereoMixdownOfProcesses: objects)
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != 0 else {
            return nil
        }
        let compensation = compensationBox
        levelWatch = LevelCompensationWatch.started(objects: objects) { compensation.value = $0 }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "EVERYTHING AirPlay",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: clockDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: clockDeviceUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr,
              aggregateID != 0 else {
            levelWatch?.stop()
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }

        let tapChannels = Self.tapChannels(of: tapID)
        let sampleRate = Self.nominalSampleRate(of: aggregateID)
        self.ringBuffer = AudioRingBuffer(sampleRate: sampleRate)
        let ring = self.ringBuffer
        let box = self.gainBox
        let ramp = TapLevelRamp()
        let cycles = self.cycleBox

        guard AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregateID, nil, { now, input, _, output, _ in
            let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let outputBuffers = UnsafeMutableAudioBufferListPointer(output)

            MixerRender.silence(outputBuffers)

            guard let tapIndex = MixerRender.tapBufferIndex(in: inputBuffers, tapChannels: tapChannels),
                  let data = inputBuffers[tapIndex].mData?.assumingMemoryBound(to: Float.self) else {
                return
            }

            let channels = Int(inputBuffers[tapIndex].mNumberChannels)
            let frames = MixerRender.frames(bytes: inputBuffers[tapIndex].mDataByteSize,
                                            channels: inputBuffers[tapIndex].mNumberChannels)
            guard frames > 0 else { return }
            cycles.increment()

            let currentGain = box.value * ramp.next(toward: compensation.value, hostTime: now.pointee.mHostTime)
            if currentGain > 0.0001 {
                ring.write(frames: data, frameCount: frames, channels: channels, gain: currentGain)
            }
        }) == noErr else {
            ioProc = nil
            stop()
            return nil
        }

        startWatchingSampleRate()
        levelWatch?.waitForFirstRead()

        guard AudioDeviceStart(aggregateID, ioProc) == noErr,
              let registration = AirPlayRouteManager.shared.addAudioStream(appID: appID, buffer: ringBuffer) else {
            stop()
            return nil
        }
        self.registration = registration
    }

    func refreshLevelCompensation(immediately: Bool) { levelWatch?.refresh(immediately: immediately) }

    private func startWatchingSampleRate() {
        var address = TapGainEngine.nominalSampleRateAddress()
        let client = Unmanaged.passRetained(ringBuffer).toOpaque()
        guard AudioObjectAddPropertyListener(aggregateID, &address,
                                             Self.sampleRateListener, client) == noErr else {
            Unmanaged<AudioRingBuffer>.fromOpaque(client).release()
            return
        }
        rateListenerClient = client
    }

    private static let sampleRateListener: AudioObjectPropertyListenerProc = { deviceID, _, _, client in
        guard let client else { return noErr }
        let ring = Unmanaged<AudioRingBuffer>.fromOpaque(client).takeUnretainedValue()
        TapGainEngine.rateQueue.async {
            ring.sampleRate = nominalSampleRate(of: deviceID)
        }
        return noErr
    }

    func stop() {
        registration?.end()
        registration = nil
        let aggregate = aggregateID
        let tap = tapID
        let proc = ioProc
        let listenerClient = rateListenerClient
        self.aggregateID = 0
        self.tapID = 0
        self.ioProc = nil
        rateListenerClient = nil
        levelWatch?.stop()
        levelWatch = nil

        if let proc, aggregate != 0 {
            AudioDeviceStop(aggregate, proc)
        }

        TapGainEngine.teardownQueue.addOperation {
            if let listenerClient {
                var mayRelease = aggregate == 0
                if aggregate != 0 {
                    var address = TapGainEngine.nominalSampleRateAddress()
                    mayRelease = AudioObjectRemovePropertyListener(
                        aggregate, &address, Self.sampleRateListener, listenerClient) == noErr
                }
                if mayRelease {
                    Unmanaged<AudioRingBuffer>.fromOpaque(listenerClient).release()
                }
            }
            if let proc, aggregate != 0 {
                AudioDeviceDestroyIOProcID(aggregate, proc)
            }
            if aggregate != 0 {
                AudioHardwareDestroyAggregateDevice(aggregate)
            }
            if tap != 0 {
                AudioHardwareDestroyProcessTap(tap)
            }
        }
    }

    deinit { stop() }

    private static func tapChannels(of tapID: AudioObjectID) -> Int {
        var format = AudioStreamBasicDescription()
        guard AppVolumeMixer.read(tapID, kAudioTapPropertyFormat, &format),
              format.mChannelsPerFrame > 0 else { return 2 }
        return Int(format.mChannelsPerFrame)
    }

    private static func nominalSampleRate(of deviceID: AudioObjectID) -> Double {
        var rate: Double = 44_100
        _ = AppVolumeMixer.read(deviceID, kAudioDevicePropertyNominalSampleRate, &rate)
        return rate > 0 ? rate : 44_100
    }
}
