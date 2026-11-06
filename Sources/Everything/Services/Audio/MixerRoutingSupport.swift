// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

struct MixerInputRouteResolution: Equatable {
    let effectiveUID: String?
    let selectedUnavailable: Bool
    let shouldApplyPreferred: Bool
}

struct MixerOutputPreferences: Equatable {
    let outputDeviceUIDs: [String: String]
    let volumes: [String: Double]
}

struct MixerRowIdentity: Equatable {
    let rowID: String
    let persistenceID: String?
}

struct MixerEngineBuilds {
    private var tokens: [String: Int] = [:]
    private var nextToken = 1

    var isEmpty: Bool { tokens.isEmpty }

    mutating func begin(_ id: String) -> Int? {
        guard tokens[id] == nil else { return nil }
        let token = nextToken
        nextToken += 1
        tokens[id] = token
        return token
    }

    func isCurrent(_ id: String, token: Int) -> Bool { tokens[id] == token }

    mutating func finish(_ id: String, token: Int) {
        guard tokens[id] == token else { return }
        tokens.removeValue(forKey: id)
    }

    mutating func invalidate(_ id: String) { tokens.removeValue(forKey: id) }

    mutating func invalidateAll() { tokens.removeAll() }

}

struct MixerEngineRecovery {
    struct Configuration: Equatable {
        let objects: [AudioObjectID]
        let outputDeviceUID: String
    }

    private struct Failure {
        let configuration: Configuration
        var count: Int
    }

    private var failures: [String: Failure] = [:]

    func allowsBuild(_ id: String, configuration: Configuration) -> Bool {
        guard let failure = failures[id], failure.configuration == configuration else {
            return true
        }
        return failure.count < 2
    }

    mutating func recordFailure(_ id: String, configuration: Configuration) -> Bool {
        let count = failures[id]?.configuration == configuration
            ? (failures[id]?.count ?? 0) + 1
            : 1
        failures[id] = Failure(configuration: configuration, count: count)
        return count < 2
    }

    mutating func clear(_ id: String) {
        failures.removeValue(forKey: id)
    }

    mutating func clearAll() {
        failures.removeAll()
    }
}

struct MixerRefreshCoordinator {
    private(set) var generation = 0
    private(set) var isReading = false
    private var requestedAgain = false

    mutating func begin() -> Int? {
        guard !isReading else {
            requestedAgain = true
            return nil
        }
        isReading = true
        generation += 1
        return generation
    }

    mutating func finish(_ generation: Int) -> Bool {
        guard generation == self.generation else { return false }
        isReading = false
        return true
    }

    mutating func takeRepeatRequest() -> Bool {
        defer { requestedAgain = false }
        return requestedAgain
    }

    mutating func discardInFlight() {
        generation += 1
        isReading = false
        requestedAgain = false
    }
}

enum MixerRoutingSupport {
    static func observationNeeds(isAvailable: (AppFeature) -> Bool)
        -> (devices: Bool, processes: Bool) {
        let mixer = isAvailable(.mixer)
        return (mixer || isAvailable(.audioPriority) || isAvailable(.soundOutputSwitcher), mixer)
    }

    static let systemDefaultSelectionID = "__system_default__"
    static let finderBundleIdentifier = "com.apple.finder"

    private static let forbiddenScalars = CharacterSet.controlCharacters.union(.newlines)

    static func displayPercent(forVolume volume: Double) -> Int {
        guard volume.isFinite else { return 0 }
        return Int((min(max(volume, -1000), 1000) * 100).rounded())
    }

    static func isUnity(_ volume: Double) -> Bool {
        abs(volume - 1) < 0.005
    }

    static func gain(forVolume volume: Double) -> Float {
        guard volume.isFinite else { return 1 }
        let level = max(volume, 0)
        return Float(level < 1 ? level * level : level)
    }

    static func volume(forGain gain: Double) -> Double {
        guard gain.isFinite else { return 1 }
        let level = max(gain, 0)
        return level < 1 ? level.squareRoot() : level
    }

    static let maximumTapLevelCompensation: Double = 4

    static func tapLevelCompensation(streamChannels: [Int?]) -> Double {
        guard let fewest = streamChannels.map({ $0 ?? 2 }).filter({ $0 > 0 }).min() else { return 1 }
        return min(max(Double(fewest) / 2, 1), maximumTapLevelCompensation)
    }

    static func tapLevelBeforeReading(devices: Set<AudioObjectID>,
                                      lastDevices: Set<AudioObjectID>,
                                      defaultOutputDevices: Set<AudioObjectID>) -> Double? {
        if devices.isEmpty {
            guard !defaultOutputDevices.isEmpty,
                  defaultOutputDevices.isSubset(of: lastDevices) else { return 1 }
            return nil
        }
        return devices == lastDevices ? nil : 1
    }

    static let tapLevelBackstopInterval: Double = 1

    static func tapLevelReadIsDue(immediately: Bool, sinceLastRead: Double) -> Bool {
        immediately || sinceLastRead >= tapLevelBackstopInterval
    }

    static let tapLevelRampDuration: Double = 0.03
    static let tapLevelDropDuration: Double = 0.005

    static func tapLevelRampStep(applied: Float?, target: Float, seconds: Double) -> Float {
        guard let applied, applied > 0 else { return target }
        let duration = target < applied ? tapLevelDropDuration : tapLevelRampDuration
        let limit = Float(pow(maximumTapLevelCompensation, min(max(seconds, 0) / duration, 1)))
        return min(max(target, applied / limit), applied * limit)
    }

    static func outputDevices(of output: AudioObjectID,
                              subDeviceUIDs: (AudioObjectID) -> [String],
                              deviceForUID: (String) -> AudioObjectID?,
                              depth: Int = 0) -> Set<AudioObjectID> {
        let inside = subDeviceUIDs(output).compactMap(deviceForUID)
        guard !inside.isEmpty, depth < 4 else { return [output] }
        return inside.reduce(into: Set<AudioObjectID>()) { devices, device in
            devices.formUnion(outputDevices(of: device, subDeviceUIDs: subDeviceUIDs,
                                            deviceForUID: deviceForUID, depth: depth + 1))
        }
    }

    static func enginesKeepingTheirOutput(engineOutputs: [String: String],
                                          targets: [String: String]) -> Set<String> {
        Set(engineOutputs.compactMap { id, output in targets[id] == output ? id : nil })
    }

    static func listenerChanges<Object: Hashable>(listened: Set<Object>, wanted: Set<Object>)
        -> (add: Set<Object>, remove: Set<Object>) {
        (wanted.subtracting(listened), listened.subtracting(wanted))
    }

    static func stereoStreamChannels(streamChannels: [Int], preferredLeftChannel: Int) -> Int? {
        var firstChannel = 1
        for channels in streamChannels where channels > 0 {
            if preferredLeftChannel >= firstChannel, preferredLeftChannel < firstChannel + channels {
                return channels
            }
            firstChannel += channels
        }
        return streamChannels.first { $0 > 0 }
    }

    static func mutesOutput(atVolume volume: Double) -> Bool {
        volume < 0.005
    }

    static func shouldShowApp(isPlaying: Bool,
                              volume: Double,
                              selectedOutputDeviceUID: String?,
                              hideInactiveApps: Bool) -> Bool {
        guard hideInactiveApps else { return true }
        return isPlaying || !isUnity(volume) || selectedOutputDeviceUID != nil
    }

    static func volumeFraction(fromPercentageText text: String,
                               maximumPercent: Int) -> Double? {
        guard maximumPercent >= 0 else { return nil }
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasSuffix("%") {
            normalized.removeLast()
            normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let separator = Locale.current.decimalSeparator, separator != "." {
            normalized = normalized.replacingOccurrences(of: separator, with: ".")
        }
        guard let percent = Double(normalized), percent.isFinite else { return nil }
        return min(max(percent, 0), Double(maximumPercent)) / 100
    }

    static func sanitizedDeviceUID(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 512 else { return nil }
        guard !trimmed.unicodeScalars.contains(where: { forbiddenScalars.contains($0) }) else {
            return nil
        }
        return trimmed
    }

    static func sanitizedRouteMap(_ raw: [String: Any]) -> [String: String] {
        var sanitized: [String: String] = [:]
        for (rawID, rawUID) in raw {
            guard let appID = sanitizedAppID(rawID),
                  let deviceUID = sanitizedDeviceUID(rawUID) else { continue }
            sanitized[appID] = deviceUID
        }
        return sanitized
    }

    static func effectiveDeviceUID(selectedUID: String?,
                                   availableUIDs: Set<String>,
                                   defaultUID: String?) -> String? {
        if let selectedUID, availableUIDs.contains(selectedUID) {
            return selectedUID
        }
        return defaultUID
    }

    static func selectedDeviceUnavailable(selectedUID: String?,
                                          availableUIDs: Set<String>) -> Bool {
        guard let selectedUID else { return false }
        return !availableUIDs.contains(selectedUID)
    }

    static func preferencesAfterUniversalOutputSwitch(outputDeviceUIDs: [String: String],
                                                      volumes: [String: Double],
                                                      switchSucceeded: Bool) -> MixerOutputPreferences {
        MixerOutputPreferences(outputDeviceUIDs: switchSucceeded ? [:] : outputDeviceUIDs,
                               volumes: volumes)
    }

    static func isAirPlaySentinel(_ uid: String) -> Bool {
        uid == AirPlayRouteManager.airPlaySentinelUID
    }

    static func playsOnAirPlay(isPlaying: Bool, effectiveOutputDeviceUID: String?) -> Bool {
        isPlaying && effectiveOutputDeviceUID.map(isAirPlaySentinel) == true
    }

    static let airPlaySpeakerChoiceID = "vorssaint.output.airplay.choose"

    static func engineOutputIsPresent(_ uid: String, clockUID: String? = nil, listedUIDs: [String],
                                      airPlayConnected: Bool) -> Bool {
        guard listedUIDs.contains(uid) else { return false }
        guard isAirPlaySentinel(uid) else { return true }
        return airPlayConnected && clockUID.map(listedUIDs.contains) != false
    }

    static func needsUnavailableOutputRow(selectedUID: String?, isUnavailable: Bool,
                                          listedUIDs: [String]) -> Bool {
        guard let selectedUID, isUnavailable else { return false }
        return !listedUIDs.contains(selectedUID)
    }

    static func routableOutputUIDs(_ uids: [String], airPlayConnected: Bool) -> Set<String> {
        Set(uids.filter { airPlayConnected || !isAirPlaySentinel($0) })
    }

    static func nextSelectedOutputDeviceUID(currentUID: String?,
                                            selectedUIDs: [String],
                                            availableUIDs: Set<String>) -> String? {
        var seen = Set<String>()
        let candidates = selectedUIDs.compactMap { rawUID -> String? in
            guard let uid = sanitizedDeviceUID(rawUID),
                  availableUIDs.contains(uid),
                  seen.insert(uid).inserted else { return nil }
            return uid
        }
        guard !candidates.isEmpty else { return nil }
        guard let currentUID,
              let index = candidates.firstIndex(of: currentUID) else {
            return candidates[0]
        }
        guard candidates.count > 1 else { return nil }
        return candidates[(index + 1) % candidates.count]
    }

    static func outputLooksLikeHeadphones(name: String,
                                          uid: String,
                                          dataSourceName: String?,
                                          terminalTypes: [UInt32] = []) -> Bool {
        if terminalTypes.contains(kAudioStreamTerminalTypeHeadphones) { return true }
        if terminalTypes.contains(where: {
            $0 == kAudioStreamTerminalTypeSpeaker || $0 == kAudioStreamTerminalTypeLFESpeaker
                || $0 == kAudioStreamTerminalTypeReceiverSpeaker
        }) { return false }
        let haystack = [name, uid, dataSourceName ?? ""]
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
        let normalized = haystack.replacingOccurrences(of: #"[^a-z0-9]+"#,
                                                       with: " ",
                                                       options: .regularExpression)
        let directTerms = [
            "headphone", "headphones", "headset",
            "earphone", "earphones", "earbud", "earbuds",
            "airpod", "airpods", "earpod", "earpods",
            "galaxy buds", "pixel buds", "beats", "bose qc",
            "sony wh", "sony wf", "jabra", "soundcore"
        ]
        return directTerms.contains { normalized.contains($0) }
    }

    static func requiresEngine(hasAudioObjects: Bool = true,
                               volume: Double,
                               selectedOutputDeviceUID: String?,
                               targetOutputDeviceUID: String?,
                               defaultOutputDeviceUID: String?,
                               universalOutputRouteUID: String? = nil) -> Bool {
        guard hasAudioObjects else { return false }
        guard let targetOutputDeviceUID else { return false }
        if !isUnity(volume) { return true }
        if let selectedOutputDeviceUID {
            return selectedOutputDeviceUID == targetOutputDeviceUID
        }
        return universalOutputRouteUID == targetOutputDeviceUID
            && targetOutputDeviceUID == defaultOutputDeviceUID
    }

    static func rowMayBeTapped(savedVolume: Double?,
                               savedRouteUID: String?,
                               defaultOutputDeviceUID: String?,
                               universalOutputRouteUID: String? = nil) -> Bool {
        if let savedVolume, !isUnity(savedVolume) { return true }
        if savedRouteUID != nil { return true }
        guard let universalOutputRouteUID else { return false }
        return universalOutputRouteUID == defaultOutputDeviceUID
    }

    static func requiresUniversalOutputRouting(requestedUID: String?,
                                                defaultUID: String?,
                                                selectedUID: String?,
                                                audioObjects: [AudioObjectID],
                                                previouslyRoutedObjects: [AudioObjectID]?,
                                                processDevices: Set<AudioObjectID>,
                                                defaultDevices: Set<AudioObjectID>) -> Bool {
        guard let requestedUID, requestedUID == defaultUID,
              selectedUID == nil, !audioObjects.isEmpty, !defaultDevices.isEmpty else { return false }
        if processDevices.isEmpty {
            return previouslyRoutedObjects == audioObjects
        }
        return !processDevices.isSubset(of: defaultDevices)
    }

    static func rowIdentity(bundleIdentifier: String?,
                            ownerPid: pid_t,
                            displayName: String?) -> MixerRowIdentity {
        guard let bundleID = sanitizedAppID(bundleIdentifier ?? "") else {
            return MixerRowIdentity(rowID: "\(unidentifiedRowPrefix)\(ownerPid)",
                                    persistenceID: sanitizedAppID(displayName ?? ""))
        }
        return MixerRowIdentity(rowID: bundleID, persistenceID: bundleID)
    }

    static let unidentifiedRowPrefix = "process:"

    static let engineChurnCoalescingWindow: Double = 0.2

    static func engineTeardownDelay(hasAudioObjects: Bool,
                                    lastChangeAt: Double?,
                                    now: Double,
                                    window: Double = engineChurnCoalescingWindow) -> Double? {
        guard !hasAudioObjects else { return nil }
        guard let lastChangeAt else { return window }
        let elapsed = max(0, now - lastChangeAt)
        guard elapsed < window else { return nil }
        return window - elapsed
    }

    struct EngineRenderObservation: Equatable {
        let cycles: UInt64
        let at: Double
    }

    enum EngineRenderVerdict: Equatable {
        case note(EngineRenderObservation, recheckAfter: Double)
        case stalled(recheckAfter: Double)
        case wedged
    }

    static let engineRenderStallWindow: Double = 1.5

    static func engineRenderVerdict(previous: EngineRenderObservation?,
                                    cycles: UInt64,
                                    isPlaying: Bool,
                                    now: Double,
                                    window: Double = engineRenderStallWindow) -> EngineRenderVerdict? {
        guard isPlaying else { return nil }
        guard let previous else {
            return .note(EngineRenderObservation(cycles: cycles, at: now), recheckAfter: window)
        }
        guard cycles == previous.cycles else {
            return .note(EngineRenderObservation(cycles: cycles, at: now), recheckAfter: window)
        }
        let elapsed = max(0, now - previous.at)
        guard elapsed >= window else { return .stalled(recheckAfter: window - elapsed) }
        return .wedged
    }

    static func restorableInputDeviceUID(originalUID: String?,
                                         appliedUID: String?,
                                         currentUID: String?,
                                         availableUIDs: Set<String>) -> String? {
        guard let originalUID, let appliedUID, originalUID != appliedUID else { return nil }
        guard currentUID == appliedUID else { return nil }
        guard availableUIDs.contains(originalUID) else { return nil }
        return originalUID
    }

    static func shouldRestoreOutputVolume(appliedVolume: Double, currentVolume: Double?) -> Bool {
        guard let currentVolume else { return false }
        return abs(currentVolume - appliedVolume) < 0.005
    }

    static func shouldMuteOutputLoweredForDisconnect(lowerToPercent: Int, currentlyMuted: Bool?) -> Bool {
        lowerToPercent <= 0 && currentlyMuted == false
    }

    private static let proAudioBundlePrefixes = [
        "com.apple.logic",
        "com.apple.garageband",
        "com.apple.mainstage",
        "com.ableton.",
        "com.avid.",
        "com.cockos.reaper",
        "com.steinberg.",
        "com.presonus.",
        "com.fender.studioapp",
        "com.bitwig.",
        "com.image-line.",
        "com.motu.",
    ]

    static func sanitizedHiddenApps(_ raw: [String: Any]) -> [String: String] {
        var sanitized: [String: String] = [:]
        for (rawID, rawName) in raw {
            guard let appID = sanitizedAppID(rawID),
                  appID != finderBundleIdentifier,
                  let name = sanitizedAppID((rawName as? String) ?? "") else { continue }
            sanitized[appID] = name
        }
        return sanitized
    }

    static func hiddenRowIDs(hiddenApps: [String: String], showFinder: Bool) -> Set<String> {
        var ids = Set(hiddenApps.keys)
        if !showFinder { ids.insert(finderBundleIdentifier) }
        return ids
    }

    static func isHiddenFromMixer(persistenceID: String?, hiddenIDs: Set<String>) -> Bool {
        guard let persistenceID else { return false }
        return hiddenIDs.contains(persistenceID)
    }

    static let owningAppSearchDepth = 6

    static func owningRegularAppPid(responsiblePid: pid_t,
                                    isRegularApp: (pid_t) -> Bool,
                                    parentPid: (pid_t) -> pid_t) -> pid_t? {
        guard responsiblePid > 0 else { return nil }
        if isRegularApp(responsiblePid) { return responsiblePid }
        var current = responsiblePid
        for _ in 0..<owningAppSearchDepth {
            current = parentPid(current)
            guard current > 1 else { return nil }
            if isRegularApp(current) { return current }
        }
        return nil
    }

    static func needsPersistentFinderRow(showFinder: Bool, hasFinderRow: Bool) -> Bool {
        showFinder && !hasFinderRow
    }

    static func needsScreenSharingProtection(bundleIdentifier: String?) -> Bool {
        guard let bundle = bundleIdentifier?.lowercased() else { return false }
        return ["com.hnc.discord", "com.hnc.discordptb", "com.hnc.discordcanary",
                "com.hnc.discorddevelopment", "com.microsoft.teams", "com.microsoft.teams2"]
            .contains { bundle == $0 || bundle.hasPrefix($0 + ".") }
    }

    static func sanitizedCallAppVolumeIDs(_ ids: [String]) -> Set<String> {
        Set(ids.map { $0.lowercased() }.filter { needsScreenSharingProtection(bundleIdentifier: $0) })
    }

    static func bypassesProcessTap(bundleIdentifier: String?, name: String,
                                  allowCallAppVolume: Bool = false) -> Bool {
        if !allowCallAppVolume, needsScreenSharingProtection(bundleIdentifier: bundleIdentifier) {
            return true
        }
        let bundle = (bundleIdentifier ?? "")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
        if bundle == "us.zoom.xos" || bundle.hasPrefix("us.zoom.") {
            return true
        }
        if proAudioBundlePrefixes.contains(where: { bundle.hasPrefix($0) }) {
            return true
        }

        let normalizedName = name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedName == "zoom"
            || normalizedName == "zoom.us"
            || normalizedName == "zoom workplace"
    }

    static func displayOrderedBefore(name: String, id: String,
                                     otherName: String, otherID: String) -> Bool {
        switch name.localizedCaseInsensitiveCompare(otherName) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return id < otherID
        }
    }

    static func deviceDisplayOrderedBefore(isDefault: Bool, name: String, uid: String,
                                           otherIsDefault: Bool, otherName: String,
                                           otherUID: String) -> Bool {
        if isDefault != otherIsDefault { return isDefault }
        return displayOrderedBefore(name: name, id: uid, otherName: otherName, otherID: otherUID)
    }

    static func firstAvailablePriorityDeviceUID(
        orderedUIDs: [String],
        availableUIDs: Set<String>
    ) -> String? {
        var seen = Set<String>()
        for rawUID in orderedUIDs {
            guard let uid = sanitizedDeviceUID(rawUID),
                  seen.insert(uid).inserted,
                  availableUIDs.contains(uid) else { continue }
            return uid
        }
        return nil
    }

    enum PriorityTier: Int {
        case builtIn, hardware, virtual

        init(transportType: UInt32) {
            switch transportType {
            case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
            case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate,
                 kAudioDeviceTransportTypeAutoAggregate: self = .virtual
            default: self = .hardware
            }
        }
    }

    static func initialPriorityList(availableUIDs: [String],
                                    currentUID: String?,
                                    tier: (String) -> PriorityTier) -> [String] {
        var seen = Set<String>()
        let unique = availableUIDs.compactMap { sanitizedDeviceUID($0) }.filter { seen.insert($0).inserted }
        let lead = unique.filter { $0 == currentUID }
        let rest = unique.enumerated()
            .filter { $0.element != currentUID }
            .sorted { lhs, rhs in
                let (a, b) = (tier(lhs.element).rawValue, tier(rhs.element).rawValue)
                return a == b ? lhs.offset < rhs.offset : a < b
            }
            .map(\.element)
        return lead + rest
    }

    static func placingNewPriorityDevice(_ rawUID: String,
                                         in list: [String],
                                         isCurrent: Bool,
                                         tier: (String) -> PriorityTier) -> [String] {
        guard let uid = sanitizedDeviceUID(rawUID), !list.contains(uid) else { return list }
        if isCurrent { return [uid] + list }
        guard tier(uid) != .virtual,
              let firstVirtual = list.firstIndex(where: { tier($0) == .virtual }) else {
            return list + [uid]
        }
        var placed = list
        placed.insert(uid, at: firstVirtual)
        return placed
    }

    static func shouldSwitchToDevice(targetUID: String?, currentUID: String?) -> Bool {
        guard let targetUID else { return false }
        guard targetUID != currentUID else { return false }
        return true
    }

    static func deviceAvailabilityChanged(previousUIDs: Set<String>?,
                                          currentUIDs: Set<String>) -> Bool {
        guard let previousUIDs else { return false }
        return previousUIDs != currentUIDs
    }

    static func resolveInputDevice(preferredUID: String?,
                                   availableUIDs: Set<String>,
                                   currentUID: String?,
                                   priorityIsActive: Bool = false,
                                   preferredInputIsActive: Bool = true) -> MixerInputRouteResolution {
        if priorityIsActive || !preferredInputIsActive {
            return MixerInputRouteResolution(effectiveUID: currentUID,
                                             selectedUnavailable: false,
                                             shouldApplyPreferred: false)
        }
        guard let preferredUID else {
            return MixerInputRouteResolution(effectiveUID: currentUID,
                                             selectedUnavailable: false,
                                             shouldApplyPreferred: false)
        }
        guard availableUIDs.contains(preferredUID) else {
            return MixerInputRouteResolution(effectiveUID: currentUID,
                                             selectedUnavailable: true,
                                             shouldApplyPreferred: false)
        }
        return MixerInputRouteResolution(effectiveUID: preferredUID,
                                         selectedUnavailable: false,
                                         shouldApplyPreferred: preferredUID != currentUID)
    }

    static func selectedInputDeviceUID(preferredUID: String?,
                                       currentUID: String?,
                                       priorityIsActive: Bool) -> String? {
        priorityIsActive ? currentUID : preferredUID
    }

    private static func sanitizedAppID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 512 else { return nil }
        guard !trimmed.unicodeScalars.contains(where: { forbiddenScalars.contains($0) }) else {
            return nil
        }
        return trimmed
    }
}

final class TapLevelRamp {
    private var applied: Float?
    private var lastHostTime: UInt64?

    func next(toward target: Float, hostTime: UInt64) -> Float {
        let elapsed = lastHostTime.map { hostTime > $0 ? hostTime - $0 : 0 } ?? 0
        lastHostTime = hostTime
        let value = MixerRoutingSupport.tapLevelRampStep(
            applied: applied, target: target,
            seconds: Double(AudioConvertHostTimeToNanos(elapsed)) / 1_000_000_000)
        applied = value
        return value
    }
}

enum AudioListenerClients {
    private struct Entry {
        weak var owner: AnyObject?
    }

    private static let lock = NSLock()
    private static var entries: [UInt: Entry] = [:]
    private static var counter: UInt = 0

    static func reserve(for owner: AnyObject) -> UnsafeMutableRawPointer {
        lock.withLock {
            counter &+= 1
            if counter == 0 { counter = 1 }
            entries[counter] = Entry(owner: owner)
            return UnsafeMutableRawPointer(bitPattern: counter).unsafelyUnwrapped
        }
    }

    static func owner(of client: UnsafeMutableRawPointer?) -> AnyObject? {
        guard let client else { return nil }
        return lock.withLock { entries[UInt(bitPattern: client)]?.owner }
    }

    static func forget(_ client: UnsafeMutableRawPointer) {
        lock.withLock { entries[UInt(bitPattern: client)] = nil }
    }
}
