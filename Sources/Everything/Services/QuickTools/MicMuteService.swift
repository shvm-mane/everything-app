// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreAudio
import Foundation

final class MicMuteService: ObservableObject {
    static let shared = MicMuteService()

    @Published private(set) var isMuted = false
    @Published private(set) var shortcutRegistrationFailed = false

    private let hotkey = QuickToolHotkey(id: 12)
    private var installedListeners: [AudioObjectPropertySelector] = []
    private let halQueue = DispatchQueue(label: "com.vorssaint.utils.micmute.hal", qos: .userInitiated)
    private var applyGeneration = 0
    private var wantsMute = UserDefaults.standard.bool(forKey: DefaultsKey.micMuteActive)
    private let inputVolumeLock = NSLock()
    private var inputVolumeBlocked = false
    private var inputVolumeLifetime = UUID()

    private init() {
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    private static let listenerCallback: AudioObjectPropertyListenerProc = { _, _, _, client in
        guard let client else { return noErr }
        let service = Unmanaged<MicMuteService>.fromOpaque(client).takeUnretainedValue()
        DispatchQueue.main.async { service.reapplyIfNeeded() }
        return noErr
    }

    private var listenerClient: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    func syncWithPreferences() {
        let available = AppFeature.micMute.isAvailable
        let enabled = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.micMuteShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.micMuteShortcut,
                                            fallback: .micMuteDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut,
                                                  storageKey: DefaultsKey.micMuteShortcut)

        if available {
            if wantsMute {
                apply(muted: true, announce: false)
            } else if hasOutstandingClaims {
                apply(muted: false, announce: false)
            }
            isMuted = wantsMute
        } else {
            if wantsMute || hasOutstandingClaims {
                apply(muted: false, announce: false)
                UserDefaults.standard.set(false, forKey: DefaultsKey.micMuteActive)
            }
            isMuted = false
        }
        syncListeners()
    }

    private func syncListeners() {
        if isMuted || (AppFeature.micMute.isAvailable && hasOutstandingClaims) {
            installListeners()
        } else {
            removeListeners()
        }
    }

    private var hasOutstandingClaims: Bool {
        !(UserDefaults.standard.stringArray(forKey: DefaultsKey.micMuteMutedDevices) ?? []).isEmpty
    }

    func suspend() {
        hotkey.unregister()
    }

    func toggle() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        apply(muted: muted, announce: true)
    }

    var inputVolumeAdjustmentLifetime: UUID? {
        guard !UserDefaults.standard.bool(forKey: DefaultsKey.micMuteActive) else { return nil }
        return inputVolumeLock.withLock { inputVolumeBlocked ? nil : inputVolumeLifetime }
    }

    func withUnmutedInput(lifetime: UUID, _ adjustment: () -> Void) {
        halQueue.sync {
            guard inputVolumeAdjustmentLifetime == lifetime else { return }
            adjustment()
        }
    }

    func unmuteForTeardown() {
        let defaults = UserDefaults.standard
        guard wantsMute || defaults.bool(forKey: DefaultsKey.micMuteActive) || hasOutstandingClaims else { return }
        applyGeneration += 1
        wantsMute = false
        _ = halQueue.sync { Self.sweep(muted: false) }
        defaults.set(false, forKey: DefaultsKey.micMuteActive)
        isMuted = false
        inputVolumeLock.withLock {
            inputVolumeBlocked = false
            inputVolumeLifetime = UUID()
        }
        removeListeners()
    }

    private func reapplyIfNeeded() {
        if wantsMute {
            apply(muted: true, announce: false)
        } else if hasOutstandingClaims {
            apply(muted: false, announce: false)
        }
    }

    // MARK: - Applying

    private func apply(muted: Bool, announce: Bool) {
        wantsMute = muted
        inputVolumeLock.withLock {
            inputVolumeBlocked = muted
            inputVolumeLifetime = UUID()
        }
        applyGeneration += 1
        let generation = applyGeneration
        halQueue.async { [weak self] in
            let outcome = Self.sweep(muted: muted)
            DispatchQueue.main.async {
                self?.finish(outcome, muted: muted, announce: announce, generation: generation)
            }
        }
    }

    private static func sweep(muted: Bool) -> MuteOutcome {
        let defaults = UserDefaults.standard
        let outcome = applyToDevices(
            muted: muted,
            savedVolumes: defaults.dictionary(forKey: DefaultsKey.micMuteSavedVolumes) as? [String: Double] ?? [:],
            savedChannelVolumes: defaults.dictionary(forKey: DefaultsKey.micMuteSavedChannelVolumes)
                as? [String: [String: Double]] ?? [:],
            mutedDevices: defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices),
            legacyVolume: defaults.double(forKey: DefaultsKey.micMuteSavedVolume))
        if outcome.applied {
            defaults.set(outcome.savedVolumes, forKey: DefaultsKey.micMuteSavedVolumes)
            defaults.set(outcome.savedChannelVolumes, forKey: DefaultsKey.micMuteSavedChannelVolumes)
            defaults.set(outcome.mutedDevices, forKey: DefaultsKey.micMuteMutedDevices)
        }
        return outcome
    }

    private func finish(_ outcome: MuteOutcome, muted: Bool, announce: Bool, generation: Int) {
        guard generation == applyGeneration else { return }
        if outcome.applied {
            if isMuted != muted { isMuted = muted }
            UserDefaults.standard.set(muted, forKey: DefaultsKey.micMuteActive)
            syncListeners()
        } else {
            wantsMute = isMuted
            inputVolumeLock.withLock { inputVolumeBlocked = isMuted }
        }
        guard announce else { return }
        if outcome.failed {
            NotchService.shared.retractMicrophoneNotice()
            QuickToolHUD.show(icon: "exclamationmark.triangle",
                              message: muted ? L10n.shared.s.micMutePartialHUD : L10n.shared.s.micUnmutePartialHUD)
            return
        }
        guard outcome.applied else { return }
        let shownInIsland = NotchService.shared.showMicrophone(muted: muted)
        NotchService.shared.reactMascot(muted ? .hush : .perk)
        guard !shownInIsland else { return }
        QuickToolHUD.show(icon: muted ? "mic.slash.fill" : "mic.fill",
                          message: muted ? L10n.shared.s.micMutedHUD : L10n.shared.s.micUnmutedHUD)
    }

    // MARK: - CoreAudio

    private struct InputDevice {
        let id: AudioDeviceID
        let uid: String
    }

    private struct MuteOutcome {
        var applied: Bool
        var savedVolumes: [String: Double]
        var savedChannelVolumes: [String: [String: Double]]
        var mutedDevices: [String]
        var failed = false
    }

    private static func applyToDevices(muted: Bool,
                                       savedVolumes: [String: Double],
                                       savedChannelVolumes: [String: [String: Double]],
                                       mutedDevices: [String]?,
                                       legacyVolume: Double) -> MuteOutcome {
        let devices = inputDevices()
        guard !devices.isEmpty else {
            return MuteOutcome(applied: !muted, savedVolumes: savedVolumes,
                               savedChannelVolumes: savedChannelVolumes, mutedDevices: mutedDevices ?? [])
        }
        return muted
            ? mute(devices, savedVolumes: savedVolumes, savedChannelVolumes: savedChannelVolumes,
                   mutedDevices: mutedDevices)
            : unmute(devices, savedVolumes: savedVolumes, savedChannelVolumes: savedChannelVolumes,
                     mutedDevices: mutedDevices, legacyVolume: legacyVolume)
    }

    private static func mute(_ devices: [InputDevice],
                             savedVolumes: [String: Double],
                             savedChannelVolumes: [String: [String: Double]],
                             mutedDevices: [String]?) -> MuteOutcome {
        var outcome = MuteOutcome(applied: false,
                                  savedVolumes: savedVolumes,
                                  savedChannelVolumes: savedChannelVolumes,
                                  mutedDevices: MicMuteSupport.absentClaims(recorded: mutedDevices,
                                                                            present: devices.map(\.uid)))
        let owned = Set(mutedDevices ?? [])
        for device in devices {
            if isSilenced(device.id) {
                outcome.applied = true
                if owned.contains(device.uid) { outcome.mutedDevices.append(device.uid) }
                continue
            }
            if setMuteSwitch(true, of: device.id) {
                outcome.applied = true
                outcome.mutedDevices.append(device.uid)
                continue
            }
            let volume = inputVolume(of: device.id)
            if MicMuteSupport.shouldSaveVolume(volume), let volume {
                outcome.savedVolumes[device.uid] = Double(volume)
            }
            let channels = channelVolumes(of: device.id)
            if !channels.isEmpty { outcome.savedChannelVolumes[device.uid] = channels }
            if setInputVolume(0, of: device.id), isSilenced(device.id) {
                outcome.applied = true
                outcome.mutedDevices.append(device.uid)
            } else {
                outcome.savedVolumes.removeValue(forKey: device.uid)
                outcome.savedChannelVolumes.removeValue(forKey: device.uid)
                var transport: UInt32 = 0
                var running: UInt32 = 0
                read(device.id, kAudioDevicePropertyTransportType, &transport)
                read(device.id, kAudioDevicePropertyDeviceIsRunningSomewhere, &running)
                if transport != kAudioDeviceTransportTypeAggregate, running != 0 { outcome.failed = true }
            }
        }
        return outcome
    }

    private static func unmute(_ devices: [InputDevice],
                               savedVolumes: [String: Double],
                               savedChannelVolumes: [String: [String: Double]],
                               mutedDevices: [String]?,
                               legacyVolume: Double) -> MuteOutcome {
        let present = devices.map(\.uid)
        var outcome = MuteOutcome(applied: false,
                                  savedVolumes: savedVolumes,
                                  savedChannelVolumes: savedChannelVolumes,
                                  mutedDevices: MicMuteSupport.absentClaims(recorded: mutedDevices,
                                                                            present: present))
        let targets = Set(MicMuteSupport.restoreTargets(recorded: mutedDevices, present: present))
        var attempted = false
        for device in devices where targets.contains(device.uid) {
            if muteSwitchValue(of: device.id) == 1 {
                attempted = true
                if setMuteSwitch(false, of: device.id) {
                    outcome.applied = true
                    outcome.savedVolumes.removeValue(forKey: device.uid)
                    outcome.savedChannelVolumes.removeValue(forKey: device.uid)
                } else {
                    outcome.mutedDevices.append(device.uid)
                    outcome.failed = true
                }
                continue
            }
            guard let volume = inputVolume(of: device.id) else {
                outcome.mutedDevices.append(device.uid)
                continue
            }
            guard volume <= 0.01 else {
                outcome.savedVolumes.removeValue(forKey: device.uid)
                outcome.savedChannelVolumes.removeValue(forKey: device.uid)
                continue
            }
            attempted = true
            let restore = MicMuteSupport.volumeToRestore(uid: device.uid,
                                                         saved: savedVolumes,
                                                         legacy: legacyVolume)
            if setInputVolume(restore, of: device.id, channels: savedChannelVolumes[device.uid] ?? [:]) {
                outcome.applied = true
                outcome.savedVolumes.removeValue(forKey: device.uid)
                outcome.savedChannelVolumes.removeValue(forKey: device.uid)
            } else {
                outcome.mutedDevices.append(device.uid)
                outcome.failed = true
            }
        }
        if !attempted { outcome.applied = true }
        return outcome
    }

    private static func isSilenced(_ device: AudioDeviceID) -> Bool {
        if muteSwitchValue(of: device) == 1 { return true }
        guard let volume = inputVolume(of: device) else { return false }
        return volume <= 0.01
    }

    private static func inputDevices() -> [InputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var deviceIDs = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &deviceIDs) == noErr else { return [] }

        var devices: [InputDevice] = []
        for deviceID in deviceIDs {
            guard hasInputStreams(deviceID) else { continue }

            var isAlive: UInt32 = 1
            if read(deviceID, kAudioDevicePropertyDeviceIsAlive, &isAlive), isAlive == 0 { continue }

            var uidRef: CFString = "" as CFString
            guard read(deviceID, kAudioDevicePropertyDeviceUID, &uidRef) else { continue }
            let uid = uidRef as String
            guard !uid.isEmpty else { continue }

            var nameRef: CFString = "" as CFString
            let name = read(deviceID, kAudioObjectPropertyName, &nameRef) ? nameRef as String : uid
            guard !MicMuteSupport.isOwnDevice(name: name) else { continue }

            devices.append(InputDevice(id: deviceID, uid: uid))
        }
        return devices
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr
            && size >= MemoryLayout<AudioObjectID>.size
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                   mScope: kAudioDevicePropertyScopeInput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func muteSwitchValue(of device: AudioDeviceID) -> UInt32? {
        var address = muteAddress()
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func setMuteSwitch(_ muted: Bool, of device: AudioDeviceID) -> Bool {
        var address = muteAddress()
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
              settable.boolValue else { return false }
        var value: UInt32 = muted ? 1 : 0
        guard AudioObjectSetPropertyData(device, &address, 0, nil,
                                         UInt32(MemoryLayout<UInt32>.size), &value) == noErr else { return false }
        guard let readBack = muteSwitchValue(of: device) else { return true }
        return readBack == value
    }

    private static func volumeAddresses() -> [AudioObjectPropertyAddress] {
        [kAudioObjectPropertyElementMain, 1, 2].map { element in
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                       mScope: kAudioDevicePropertyScopeInput,
                                       mElement: element)
        }
    }

    private static func inputVolume(of device: AudioDeviceID) -> Float? {
        for var address in volumeAddresses() where AudioObjectHasProperty(device, &address) {
            var volume = Float(0)
            var size = UInt32(MemoryLayout<Float>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr {
                return volume
            }
        }
        return nil
    }

    private static func channelVolumes(of device: AudioDeviceID) -> [String: Double] {
        var levels: [String: Double] = [:]
        for var address in volumeAddresses() where address.mElement != kAudioObjectPropertyElementMain
            && AudioObjectHasProperty(device, &address) {
            var volume = Float(0)
            var size = UInt32(MemoryLayout<Float>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr,
               MicMuteSupport.shouldSaveVolume(volume) {
                levels[String(address.mElement)] = Double(volume)
            }
        }
        return levels
    }

    private static func setInputVolume(_ volume: Float, of device: AudioDeviceID,
                                       channels: [String: Double] = [:]) -> Bool {
        var applied = false
        for var address in volumeAddresses() where AudioObjectHasProperty(device, &address) {
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                  settable.boolValue else { continue }
            var value = channels[String(address.mElement)].map(Float.init) ?? volume
            if AudioObjectSetPropertyData(device, &address, 0, nil,
                                          UInt32(MemoryLayout<Float>.size), &value) == noErr {
                applied = true
            }
        }
        return applied
    }

    @discardableResult
    private static func read<T>(_ object: AudioObjectID,
                                _ selector: AudioObjectPropertySelector,
                                _ value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size,
                                       UnsafeMutableRawPointer(pointer)) == noErr
        }
    }

    // MARK: - Listeners

    private static let watchedSelectors: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyDevices,
        kAudioHardwarePropertyDefaultInputDevice,
    ]

    private func installListeners() {
        for selector in Self.watchedSelectors where !installedListeners.contains(selector) {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            let status = AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject),
                                                        &address, Self.listenerCallback,
                                                        listenerClient)
            if status == noErr {
                installedListeners.append(selector)
            }
        }
    }

    private func removeListeners() {
        for selector in installedListeners {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListener(AudioObjectID(kAudioObjectSystemObject),
                                              &address, Self.listenerCallback,
                                              listenerClient)
        }
        installedListeners.removeAll()
    }
}
