// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AudioToolbox
import Combine
import CoreAudio
import Foundation

struct MixerInputDevice: Identifiable, Equatable {
    let id: String
    let uid: String
    let name: String
    let isDefault: Bool
    let priorityTier: MixerRoutingSupport.PriorityTier
    fileprivate let audioObjectID: AudioObjectID
}

final class AudioInputDeviceManager: ObservableObject {
    static let shared = AudioInputDeviceManager()

    @Published private(set) var inputDevices: [MixerInputDevice] = []
    @Published private(set) var preferredInputDeviceUID: String?
    @Published private(set) var currentInputDeviceUID: String?
    @Published private(set) var effectiveInputDeviceUID: String?
    @Published private(set) var inputVolume: Double?
    @Published private(set) var preferredUnavailable = false
    @Published private(set) var lastError: String?

    private var listenerInstalled = false
    private var globalListeners: [AudioObjectPropertySelector] = []
    private var volumeDeviceID: AudioObjectID?
    private var volumeListenerAddresses: [AudioObjectPropertyAddress] = []
    private var volumeRefreshGeneration = 0
    private let volumeWriteLock = NSLock()
    private var volumeWriteLifetime = UUID()
    private var applyingPreferred = false
    private var refreshPending = false
    private var lastListenerRefreshAt: CFAbsoluteTime = 0
    private var refresh = MixerRefreshCoordinator()
    private let halQueue = DispatchQueue(label: "com.vorssaint.utils.audioinput.hal", qos: .userInitiated)
    private var inputDeviceBeforeOverride: String?
    private var appliedInputDeviceUID: String?
    private(set) var inputPriorityIsActive = false

    private init() {}

    func syncWithPreferences() {
        inputPriorityIsActive = AppFeature.audioPriority.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.audioPriorityInputEnabled)
        if AppFeature.mixer.isAvailable || AppFeature.audioPriority.isAvailable {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard !listenerInstalled else {
            refreshAndApply()
            return
        }
        listenerInstalled = true
        installListener(selector: kAudioHardwarePropertyDevices)
        installListener(selector: kAudioHardwarePropertyDefaultInputDevice)
        refreshAndApply()
    }

    func stop() {
        removeVolumeListeners()
        if !inputPriorityIsActive {
            restoreOriginalInputDevice()
        } else {
            inputDeviceBeforeOverride = nil
            appliedInputDeviceUID = nil
        }
        guard listenerInstalled else { return }
        listenerInstalled = false
        refresh.discardInFlight()
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
        if !inputDevices.isEmpty { inputDevices = [] }
        if preferredUnavailable { preferredUnavailable = false }
        if lastError != nil { lastError = nil }
        if inputVolume != nil { inputVolume = nil }
        inputPriorityIsActive = false
    }

    func setInputPriorityActive(_ active: Bool) {
        guard inputPriorityIsActive != active else { return }
        inputPriorityIsActive = active
        refresh.discardInFlight()
        if listenerInstalled { refreshAndApply() }
    }

    func setPreferredInputDeviceUID(_ uid: String?) {
        volumeWriteLock.withLock { volumeWriteLifetime = UUID() }
        let sanitized = Defaults.sanitizedPreferredInputDeviceUID(uid)
        if inputPriorityIsActive {
            if let sanitized { setCurrentInputDeviceUID(sanitized) }
            return
        }
        if let sanitized {
            UserDefaults.standard.set(sanitized, forKey: DefaultsKey.preferredInputDevice)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.preferredInputDevice)
        }
        preferredInputDeviceUID = sanitized
        lastError = nil
        refresh.discardInFlight()
        refreshAndApply()
    }

    func setCurrentInputDeviceUID(_ uid: String) {
        volumeWriteLock.withLock { volumeWriteLifetime = UUID() }
        guard listenerInstalled,
              uid != currentInputDeviceUID,
              let device = inputDevices.first(where: { $0.uid == uid }) else { return }
        refresh.discardInFlight()
        halQueue.async { [weak self] in
            let status = Self.setDefaultInputDevice(device.audioObjectID)
            DispatchQueue.main.async {
                guard let self, self.listenerInstalled else { return }
                if status == noErr {
                    self.inputDeviceBeforeOverride = nil
                    self.appliedInputDeviceUID = nil
                    if self.lastError != nil { self.lastError = nil }
                } else {
                    let message = "OSStatus \(status)"
                    if self.lastError != message { self.lastError = message }
                }
                self.refreshAndApply()
            }
        }
    }

    func setInputVolume(_ volume: Double) {
        guard listenerInstalled, volume.isFinite,
              let muteLifetime = MicMuteService.shared.inputVolumeAdjustmentLifetime,
              let uid = effectiveInputDeviceUID,
              let device = inputDevices.first(where: { $0.uid == uid }),
              volumeDeviceID == device.audioObjectID, inputVolume != nil else { return }
        let clamped = min(max(volume, 0), 1)
        let lifetime = volumeWriteLock.withLock { volumeWriteLifetime }
        volumeRefreshGeneration &+= 1
        if inputVolume != clamped { inputVolume = clamped }
        halQueue.async { [weak self] in
            guard let self else { return }
            MicMuteService.shared.withUnmutedInput(lifetime: muteLifetime) {
                guard self.volumeWriteLock.withLock({ self.volumeWriteLifetime == lifetime }),
                      Self.defaultInputDeviceUID() == uid else { return }
                var deviceUID: CFString = "" as CFString
                guard Self.read(device.audioObjectID, kAudioDevicePropertyDeviceUID, &deviceUID),
                      deviceUID as String == uid,
                      self.volumeWriteLock.withLock({ self.volumeWriteLifetime == lifetime }) else { return }
                _ = Self.setInputVolume(Float32(clamped), for: device.audioObjectID)
            }
            DispatchQueue.main.async {
                guard self.volumeWriteLock.withLock({ self.volumeWriteLifetime == lifetime }) else { return }
                self.scheduleVolumeRefresh(for: device.audioObjectID)
            }
        }
    }

    private static let listenerCallback: AudioObjectPropertyListenerProc = { _, _, _, client in
        guard let client else { return noErr }
        let manager = Unmanaged<AudioInputDeviceManager>.fromOpaque(client).takeUnretainedValue()
        DispatchQueue.main.async { manager.scheduleListenerRefresh() }
        return noErr
    }

    private static let volumeListenerCallback: AudioObjectPropertyListenerProc = {
        device, _, _, client in
        guard let client else { return noErr }
        let manager = Unmanaged<AudioInputDeviceManager>.fromOpaque(client).takeUnretainedValue()
        DispatchQueue.main.async { manager.scheduleVolumeRefresh(for: device) }
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

    private func scheduleListenerRefresh() {
        guard !refreshPending else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastListenerRefreshAt
        if elapsed >= Self.listenerRefreshInterval {
            lastListenerRefreshAt = now
            refreshAndApply()
            return
        }
        refreshPending = true
        let delay = Self.listenerRefreshInterval - elapsed
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            self.lastListenerRefreshAt = CFAbsoluteTimeGetCurrent()
            self.refreshAndApply()
        }
    }

    private static let listenerRefreshInterval: CFAbsoluteTime = 0.2

    private struct RefreshRequest {
        let savedUID: String?
        let inputDeviceBeforeOverride: String?
        let mayApplyPreferred: Bool
        let priorityIsActive: Bool
        let preferredInputIsActive: Bool
        let volumeGeneration: Int
    }

    private struct RefreshSnapshot {
        let savedUID: String?
        let currentUID: String?
        let devices: [MixerInputDevice]
        let resolution: MixerInputRouteResolution
        let inputVolume: Double?
        let volumeGeneration: Int
        let applied: AppliedInput?
    }

    private struct AppliedInput {
        let device: MixerInputDevice
        let status: OSStatus
        let deviceBeforeOverride: String?
    }

    private func refreshAndApply() {
        guard listenerInstalled else { return }
        guard let generation = refresh.begin() else { return }
        let request = RefreshRequest(
            savedUID: Defaults.sanitizedPreferredInputDeviceUID(
                UserDefaults.standard.string(forKey: DefaultsKey.preferredInputDevice)),
            inputDeviceBeforeOverride: inputDeviceBeforeOverride,
            mayApplyPreferred: !applyingPreferred && !inputPriorityIsActive,
            priorityIsActive: inputPriorityIsActive,
            preferredInputIsActive: AppFeature.mixer.isAvailable,
            volumeGeneration: volumeRefreshGeneration)

        halQueue.async { [weak self] in
            let snapshot = Self.readSnapshot(request)
            DispatchQueue.main.async {
                self?.apply(snapshot, generation: generation)
            }
        }
    }

    private static func readSnapshot(_ request: RefreshRequest) -> RefreshSnapshot {
        let savedUID = request.savedUID
        let currentUID = defaultInputDeviceUID()
        let devices = inputDevices(defaultUID: currentUID)
        let availableUIDs = Set(devices.map(\.uid))
        let resolution = MixerRoutingSupport.resolveInputDevice(
            preferredUID: savedUID,
            availableUIDs: availableUIDs,
            currentUID: currentUID,
            priorityIsActive: request.priorityIsActive,
            preferredInputIsActive: request.preferredInputIsActive)

        guard resolution.shouldApplyPreferred,
              request.mayApplyPreferred,
              let savedUID,
              let device = devices.first(where: { $0.uid == savedUID }) else {
            let volume = resolution.effectiveUID
                .flatMap { uid in devices.first(where: { $0.uid == uid }) }
                .flatMap { inputVolume(for: $0.audioObjectID) }
            return RefreshSnapshot(savedUID: savedUID,
                                   currentUID: currentUID,
                                   devices: devices,
                                   resolution: resolution,
                                   inputVolume: volume.map(Double.init),
                                   volumeGeneration: request.volumeGeneration,
                                   applied: nil)
        }

        let before = request.inputDeviceBeforeOverride ?? currentUID
        let status = setDefaultInputDevice(device.audioObjectID)
        return RefreshSnapshot(savedUID: savedUID,
                               currentUID: currentUID,
                               devices: devices,
                               resolution: resolution,
                               inputVolume: inputVolume(for: device.audioObjectID).map(Double.init),
                               volumeGeneration: request.volumeGeneration,
                               applied: AppliedInput(device: device,
                                                     status: status,
                                                     deviceBeforeOverride: before))
    }

    private func apply(_ snapshot: RefreshSnapshot, generation: Int) {
        guard refresh.finish(generation) else {
            if let applied = snapshot.applied, applied.status == noErr {
                if inputDeviceBeforeOverride == nil {
                    inputDeviceBeforeOverride = applied.deviceBeforeOverride
                }
                appliedInputDeviceUID = applied.device.uid
            }
            return
        }
        let refreshAgain = refresh.takeRepeatRequest()
        guard listenerInstalled else { return }
        defer { if refreshAgain { refreshAndApply() } }

        if preferredInputDeviceUID != snapshot.savedUID {
            preferredInputDeviceUID = snapshot.savedUID
        }
        if currentInputDeviceUID != snapshot.currentUID {
            currentInputDeviceUID = snapshot.currentUID
        }
        let effectiveDeviceChanged = effectiveInputDeviceUID != snapshot.resolution.effectiveUID
        if effectiveDeviceChanged {
            effectiveInputDeviceUID = snapshot.resolution.effectiveUID
        }
        if preferredUnavailable != snapshot.resolution.selectedUnavailable {
            preferredUnavailable = snapshot.resolution.selectedUnavailable
        }
        if inputDevices != snapshot.devices {
            inputDevices = snapshot.devices
        }
        let effectiveDeviceID = snapshot.resolution.effectiveUID
            .flatMap { uid in snapshot.devices.first(where: { $0.uid == uid })?.audioObjectID }
        let sweepVolumeIsCurrent = volumeRefreshGeneration == snapshot.volumeGeneration
        let volumeDeviceChanged = volumeDeviceID != effectiveDeviceID
        updateVolumeListeners(for: effectiveDeviceID)
        if (sweepVolumeIsCurrent || effectiveDeviceChanged || volumeDeviceChanged), inputVolume != snapshot.inputVolume {
            inputVolume = snapshot.inputVolume
        }

        guard let applied = snapshot.applied else { return }
        applyPreferredInputDevice(applied)
    }

    private func applyPreferredInputDevice(_ applied: AppliedInput) {
        applyingPreferred = true
        defer { applyingPreferred = false }

        if inputDeviceBeforeOverride == nil {
            inputDeviceBeforeOverride = applied.deviceBeforeOverride
        }
        let device = applied.device
        guard applied.status == noErr else {
            let message = "OSStatus \(applied.status)"
            if lastError != message {
                lastError = message
            }
            return
        }

        if lastError != nil {
            lastError = nil
        }
        appliedInputDeviceUID = device.uid
        if currentInputDeviceUID != device.uid {
            currentInputDeviceUID = device.uid
        }
        if effectiveInputDeviceUID != device.uid {
            effectiveInputDeviceUID = device.uid
        }
        let updated = inputDevices.map {
            MixerInputDevice(id: $0.id,
                             uid: $0.uid,
                             name: $0.name,
                             isDefault: $0.uid == device.uid,
                             priorityTier: $0.priorityTier,
                             audioObjectID: $0.audioObjectID)
        }
        if inputDevices != updated {
            inputDevices = updated
        }
    }

    private func restoreOriginalInputDevice() {
        guard let originalUID = inputDeviceBeforeOverride,
              let appliedUID = appliedInputDeviceUID else { return }
        inputDeviceBeforeOverride = nil
        appliedInputDeviceUID = nil
        let devices = Self.inputDevices(defaultUID: nil)
        guard let restoredUID = MixerRoutingSupport.restorableInputDeviceUID(
            originalUID: originalUID,
            appliedUID: appliedUID,
            currentUID: Self.defaultInputDeviceUID(),
            availableUIDs: Set(devices.map(\.uid))),
            let device = devices.first(where: { $0.uid == restoredUID }) else { return }
        _ = Self.setDefaultInputDevice(device.audioObjectID)
    }

    private static func setDefaultInputDevice(_ deviceID: AudioObjectID) -> OSStatus {
        var nextDeviceID = deviceID
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                          &address,
                                          0,
                                          nil,
                                          UInt32(MemoryLayout<AudioObjectID>.size),
                                          &nextDeviceID)
    }

    private static let inputVolumeSelectors: [AudioObjectPropertySelector] = [
        kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        kAudioDevicePropertyVolumeScalar,
    ]

    private static func mainInputVolumeAddresses() -> [AudioObjectPropertyAddress] {
        inputVolumeSelectors.map { selector in
            AudioObjectPropertyAddress(mSelector: selector,
                                       mScope: kAudioDevicePropertyScopeInput,
                                       mElement: kAudioObjectPropertyElementMain)
        }
    }

    private static func channelInputVolumeAddresses(for deviceID: AudioObjectID) -> [AudioObjectPropertyAddress] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                mScope: kAudioDevicePropertyScopeInput,
                                                mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioBufferList>.size) else { return [] }
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, storage) == noErr else { return [] }
        let buffers = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
        let channelCount = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
        guard channelCount > 0 else { return [] }
        return (1...channelCount).map { channel in
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                       mScope: kAudioDevicePropertyScopeInput,
                                       mElement: AudioObjectPropertyElement(channel))
        }
    }

    private func updateVolumeListeners(for deviceID: AudioObjectID?) {
        guard volumeDeviceID != deviceID else { return }
        removeVolumeListeners()
        guard let deviceID else { return }

        volumeDeviceID = deviceID
        let addresses = Self.mainInputVolumeAddresses() + Self.channelInputVolumeAddresses(for: deviceID)
        for var address in addresses where Self.isSettable(deviceID, &address) {
            guard AudioObjectAddPropertyListener(deviceID,
                                                 &address,
                                                 Self.volumeListenerCallback,
                                                 listenerClient) == noErr else { continue }
            volumeListenerAddresses.append(address)
        }
    }

    private func removeVolumeListeners() {
        volumeWriteLock.withLock { volumeWriteLifetime = UUID() }
        volumeRefreshGeneration &+= 1
        guard let deviceID = volumeDeviceID else {
            volumeListenerAddresses.removeAll()
            return
        }
        for var address in volumeListenerAddresses {
            AudioObjectRemovePropertyListener(deviceID,
                                              &address,
                                              Self.volumeListenerCallback,
                                              listenerClient)
        }
        volumeListenerAddresses.removeAll()
        volumeDeviceID = nil
    }

    private func scheduleVolumeRefresh(for deviceID: AudioObjectID) {
        guard listenerInstalled, volumeDeviceID == deviceID else { return }
        volumeRefreshGeneration &+= 1
        let generation = volumeRefreshGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self,
                  self.listenerInstalled,
                  self.volumeDeviceID == deviceID,
                  self.volumeRefreshGeneration == generation else { return }
            self.halQueue.async { [weak self] in
                let volume = Self.inputVolume(for: deviceID).map(Double.init)
                DispatchQueue.main.async {
                    guard let self,
                          self.listenerInstalled,
                          self.volumeDeviceID == deviceID,
                          self.volumeRefreshGeneration == generation else { return }
                    if self.inputVolume != volume { self.inputVolume = volume }
                }
            }
        }
    }

    private static func isSettable(_ deviceID: AudioObjectID,
                                   _ address: inout AudioObjectPropertyAddress) -> Bool {
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr
            && settable.boolValue
    }

    private static func inputVolume(for deviceID: AudioObjectID) -> Float32? {
        for var address in mainInputVolumeAddresses() where isSettable(deviceID, &address) {
            var volume = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr {
                return volume.isFinite ? min(max(volume, 0), 1) : nil
            }
        }

        let channelVolumes = channelInputVolumeAddresses(for: deviceID).compactMap { address -> Float32? in
            var address = address
            guard isSettable(deviceID, &address) else { return nil }
            var volume = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr else {
                return nil
            }
            return volume
        }
        guard !channelVolumes.isEmpty, channelVolumes.allSatisfy(\.isFinite) else { return nil }
        return min(max(channelVolumes.reduce(0, +) / Float32(channelVolumes.count), 0), 1)
    }

    private static func setInputVolume(_ volume: Float32, for deviceID: AudioObjectID) -> Bool {
        let clamped = min(max(volume, 0), 1)
        for var address in mainInputVolumeAddresses() where isSettable(deviceID, &address) {
            var nextVolume = clamped
            if AudioObjectSetPropertyData(deviceID, &address, 0, nil,
                                          UInt32(MemoryLayout<Float32>.size),
                                          &nextVolume) == noErr {
                return true
            }
        }

        var applied = false
        for var address in channelInputVolumeAddresses(for: deviceID) where isSettable(deviceID, &address) {
            var nextVolume = clamped
            if AudioObjectSetPropertyData(deviceID, &address, 0, nil,
                                          UInt32(MemoryLayout<Float32>.size),
                                          &nextVolume) == noErr {
                applied = true
            }
        }
        return applied
    }

    private static func inputDevices(defaultUID: String?) -> [MixerInputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr else { return [] }
        var deviceIDs = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &deviceIDs) == noErr else { return [] }

        var devices: [MixerInputDevice] = []
        for deviceID in deviceIDs {
            guard hasInputStreams(deviceID) else { continue }

            var isAlive: UInt32 = 1
            if read(deviceID, kAudioDevicePropertyDeviceIsAlive, &isAlive), isAlive == 0 {
                continue
            }
            var isHidden: UInt32 = 0
            if read(deviceID, kAudioDevicePropertyIsHidden, &isHidden), isHidden != 0 {
                continue
            }
            var canBeDefault: UInt32 = 1
            if read(deviceID,
                    kAudioDevicePropertyDeviceCanBeDefaultDevice,
                    &canBeDefault,
                    scope: kAudioObjectPropertyScopeInput),
               canBeDefault == 0 {
                continue
            }

            var uidRef: CFString = "" as CFString
            guard read(deviceID, kAudioDevicePropertyDeviceUID, &uidRef) else { continue }
            let uid = uidRef as String
            guard !uid.isEmpty else { continue }

            var nameRef: CFString = "" as CFString
            let name = read(deviceID, kAudioObjectPropertyName, &nameRef)
                ? nameRef as String
                : uid
            guard !MicMuteSupport.isOwnDevice(name: name) else { continue }
            var transportType: UInt32 = 0
            _ = read(deviceID, kAudioDevicePropertyTransportType, &transportType)

            devices.append(MixerInputDevice(id: uid,
                                            uid: uid,
                                            name: name,
                                            isDefault: uid == defaultUID,
                                            priorityTier: MixerRoutingSupport.PriorityTier(
                                                transportType: transportType),
                                            audioObjectID: deviceID))
        }

        return devices.sorted { lhs, rhs in
            MixerRoutingSupport.deviceDisplayOrderedBefore(
                isDefault: lhs.isDefault, name: lhs.name, uid: lhs.uid,
                otherIsDefault: rhs.isDefault, otherName: rhs.name, otherUID: rhs.uid)
        }
    }

    private static func hasInputStreams(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr
            && size >= MemoryLayout<AudioObjectID>.size
    }

    private static func defaultInputDeviceUID() -> String? {
        var defaultDevice = AudioObjectID(0)
        guard read(AudioObjectID(kAudioObjectSystemObject),
                   kAudioHardwarePropertyDefaultInputDevice, &defaultDevice),
              defaultDevice != 0 else { return nil }
        var uidRef: CFString = "" as CFString
        guard read(defaultDevice, kAudioDevicePropertyDeviceUID, &uidRef) else { return nil }
        return uidRef as String
    }

    @discardableResult
    private static func read<T>(_ object: AudioObjectID,
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
