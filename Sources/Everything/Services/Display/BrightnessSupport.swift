// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum BrightnessSupport {
    static func sliderShowsFocusedDisplay(controlEnabled: Bool, shown: [UInt32], focused: UInt32?) -> Bool {
        guard controlEnabled else { return false }
        guard let focused else { return !shown.isEmpty }
        return shown.contains(focused)
    }

    static func keyMovesFocus(islandOpen: Bool, focused: UInt32?, key: UInt32) -> Bool {
        islandOpen && focused != key
    }

    struct DisplayTopology: Equatable {
        let online: Set<UInt32>
        let active: Set<UInt32>
        var mirrorSources: [UInt32: UInt32] = [:]
    }

    static func shouldQueueRebuild(topology: DisplayTopology,
                                   pending: DisplayTopology?,
                                   force: Bool = false) -> Bool {
        force || pending != topology
    }

    static func brightnessAfterRebuild(probed: Double, pending: Double?) -> Double {
        pending ?? probed
    }

    static let luminanceCode: UInt8 = 0x10
    static let chipAddress: UInt32 = 0x37
    static let dataAddress: UInt32 = 0x51

    static let writePauseMicroseconds: UInt32 = 10_000
    static let readPauseMicroseconds: UInt32 = 50_000
    static let retryPauseMicroseconds: UInt32 = 20_000
    static let writeCycles = 2
    static let retryAttempts = 4
    static let replyLength = 11

    static func ddcProbeAttempts() -> Int {
        retryAttempts + 1
    }

    static func ddcProbeWriteCycles(classifyingChannel: Bool,
                                    isFinalAttempt: Bool = false) -> Int {
        classifyingChannel && !isFinalAttempt ? 1 : writeCycles
    }

    static let defaultKeyboardLightLevel: Float = 0.5
    static let keyboardLightStep: Float = 1.0 / 16.0

    static func keyboardLightOnLevel(lastNonzero: Float?) -> Float {
        guard let lastNonzero, lastNonzero > 0 else { return defaultKeyboardLightLevel }
        return min(lastNonzero, 1)
    }

    static func sliderKeyboardLightLevel(_ level: Float) -> Float? {
        guard level.isFinite else { return nil }
        return min(max(level, 0), 1)
    }

    static func steppedKeyboardLightLevel(current: Float, direction: Int) -> Float {
        guard current.isFinite else { return 0 }
        let step = direction < 0 ? -keyboardLightStep : keyboardLightStep
        return min(max(current + step, 0), 1)
    }

    static let commandIntervalMicroseconds: UInt64 = 50_000

    static func ddcCommandDelay(nowMicroseconds: UInt64,
                                lastCommandEndMicroseconds: UInt64?) -> UInt32 {
        guard let last = lastCommandEndMicroseconds, last <= nowMicroseconds else { return 0 }
        let elapsed = nowMicroseconds - last
        guard elapsed < commandIntervalMicroseconds else { return 0 }
        return UInt32(commandIntervalMicroseconds - elapsed)
    }

    static func packet(payload: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [UInt8(0x80 | (payload.count + 1)), UInt8(payload.count)]
        bytes.append(contentsOf: payload)
        let seed = UInt8(chipAddress << 1) ^ (payload.count == 1 ? 0 : UInt8(dataAddress))
        bytes.append(bytes.reduce(seed) { $0 ^ $1 })
        return bytes
    }

    static func writePacket(code: UInt8, value: UInt16) -> [UInt8] {
        packet(payload: [code, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    static func readRequestPacket(code: UInt8) -> [UInt8] {
        packet(payload: [code])
    }

    static func parseReply(_ reply: [UInt8], code: UInt8) -> (current: UInt16, maximum: UInt16)? {
        guard reply.count >= replyLength else { return nil }
        let checksum = reply[0..<(reply.count - 1)].reduce(UInt8(0x50)) { $0 ^ $1 }
        guard checksum == reply[reply.count - 1], reply[2] == 0x02, reply[4] == code else { return nil }
        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        return (current, maximum)
    }

    static func sanitizedMaximum(_ maximum: UInt16) -> UInt16 {
        maximum > 0 ? maximum : 100
    }

    enum DDCChannelOutcome: Equatable {
        case live
        case writeOnly
        case dead
    }

    static func channelOutcome(writeAccepted: Bool, replyParsed: Bool) -> DDCChannelOutcome {
        if replyParsed { return .live }
        return writeAccepted ? .writeOnly : .dead
    }

    static func ddcPathKey(displayFingerprint: String,
                           ioDisplayLocation: String) -> String? {
        guard !displayFingerprint.isEmpty, !ioDisplayLocation.isEmpty else { return nil }
        return "\(displayFingerprint)|\(ioDisplayLocation)"
    }

    static func updatedWriteOnlyDDCPaths(_ stored: [String],
                                         path: String,
                                         isWriteOnly: Bool,
                                         limit: Int = 16) -> [String] {
        guard !path.isEmpty, limit > 0 else { return [] }
        var updated = stored.filter { !$0.isEmpty && $0 != path }
        if isWriteOnly { updated.append(path) }
        return Array(updated.suffix(limit))
    }

    static func shouldProbeDDC(pathKey: String?, writeOnlyPaths: Set<String>) -> Bool {
        guard let pathKey else { return true }
        return !writeOnlyPaths.contains(pathKey)
    }

    // MARK: - Display switching

    enum DisplayConfigurationResult: Equatable {
        case success, closedLid, failed
    }

    struct DeferredDisplayRestoration {
        private(set) var ids = Set<UInt32>()
        private var headlessIDs = Set<UInt32>()
        private var keptIDs = Set<UInt32>()
        private var lastLidClosed: Bool? = true

        mutating func record(_ id: UInt32, result: DisplayConfigurationResult) {
            if result == .closedLid {
                ids.insert(id)
                lastLidClosed = true
            }
            if result == .failed, keptIDs.contains(id) {
                ids.insert(id)
            }
            if result == .success {
                ids.remove(id)
                headlessIDs.remove(id)
                keptIDs.remove(id)
            }
        }

        mutating func keep(_ id: UInt32) {
            keptIDs.insert(id)
        }

        mutating func recordHeadless(_ id: UInt32,
                                     result: DisplayConfigurationResult) {
            record(id, result: result)
            if result == .closedLid && !keptIDs.contains(id) {
                headlessIDs.insert(id)
            }
        }

        mutating func cancelHeadless() {
            ids.subtract(headlessIDs.subtracting(keptIDs))
            headlessIDs.removeAll()
        }

        mutating func candidates(lidClosed: Bool?, retryFailures: Bool = false) -> Set<UInt32> {
            let opened = lidClosed == false && lastLidClosed != false
            if let lidClosed { lastLidClosed = lidClosed }
            return opened || retryFailures ? ids : []
        }
    }

    static func canConfigureDisplay(enabled: Bool, isBuiltIn: Bool, lidClosed: Bool?) -> Bool {
        !(enabled && isBuiltIn && lidClosed == true)
    }

    static func canDisableDisplay(drawableDisplayIDs: Set<UInt32>, target: UInt32) -> Bool {
        drawableDisplayIDs.contains(target) && drawableDisplayIDs.count > 1
    }

    static func participatingDisplayIDs(activeDisplayIDs: Set<UInt32>,
                                        mirrorSources: [UInt32: UInt32]) -> Set<UInt32> {
        activeDisplayIDs.union(mirrorSources.compactMap { mirror, source in
            activeDisplayIDs.contains(source) ? mirror : nil
        })
    }

    static func drawableDisplayIDs(onlineDisplayIDs: Set<UInt32>,
                                   activeDisplayIDs: Set<UInt32>,
                                   virtualDisplayIDs: Set<UInt32>) -> Set<UInt32> {
        onlineDisplayIDs.intersection(activeDisplayIDs).subtracting(virtualDisplayIDs)
    }

    static func headlessRecoveryCandidates(drawableDisplayIDs: Set<UInt32>,
                                           managedDisabledIDs: Set<UInt32>,
                                           builtInDisabledIDs: Set<UInt32>) -> [UInt32] {
        guard drawableDisplayIDs.isEmpty else { return [] }
        let builtIn = managedDisabledIDs.intersection(builtInDisabledIDs)
        return builtIn.sorted() + managedDisabledIDs.subtracting(builtIn).sorted()
    }

    // MARK: - Software dimming (gamma curve)

    static func softwareDimFactor(for value: Double) -> Float {
        Float(min(max(value, 0), 1))
    }

    static func scaledGammaTable(_ table: [Float], factor: Float) -> [Float] {
        guard factor < 1 else { return table }
        return table.map { $0 * factor }
    }

    static func softwareDimToRestore(remembered: Double?, appliedByApp: Bool) -> Double {
        appliedByApp ? (remembered ?? 1.0) : 1.0
    }

    static let reconnectionDimFloor = 0.25

    static func reconnectedDimLevel(_ saved: Double) -> Double {
        max(min(saved, 1), reconnectionDimFloor)
    }

    // MARK: - Brightness keys

    static let brightnessKeyStep = 1.0 / 16.0

    enum KeyStep: String, CaseIterable {
        case standard, half, quarter

        static func sanitized(_ raw: String?) -> KeyStep {
            KeyStep(rawValue: raw ?? "") ?? .standard
        }

        var fraction: Double {
            switch self {
            case .standard: return brightnessKeyStep
            case .half: return brightnessKeyStep / 2
            case .quarter: return brightnessKeyStep / 4
            }
        }

        func limited(_ delta: Double) -> Double {
            guard abs(delta) > fraction else { return delta }
            return delta < 0 ? -fraction : fraction
        }

        var systemQuarterSteps: Int? {
            switch self {
            case .standard: return nil
            case .half: return 2
            case .quarter: return 1
            }
        }
    }

    static func systemQuarterSteps(for step: KeyStep, command: Bool, control: Bool,
                                   option: Bool) -> Int? {
        guard !command, !control, !option else { return nil }
        return step.systemQuarterSteps
    }

    static func systemQuarterStepHalves(increase: Bool) -> [(data1: Int, flags: UInt)] {
        let keyCode = increase ? 2 : 3
        let optionShift: UInt = 0x80000 | 0x20000
        return [0x0A, 0x0B].map { state in
            ((keyCode << 16) | (state << 8), UInt(state << 8) | optionShift)
        }
    }

    static let systemQuarterStepMarker: Int64 = 0x564F4252

    static func systemQuarterStepEvents(increase: Bool, count: Int) -> [CGEvent] {
        let halves = systemQuarterStepHalves(increase: increase)
        return (0..<max(0, count)).flatMap { _ in
            halves.compactMap { half -> CGEvent? in
                guard let event = NSEvent.otherEvent(
                    with: .systemDefined, location: .zero,
                    modifierFlags: NSEvent.ModifierFlags(rawValue: half.flags),
                    timestamp: 0, windowNumber: 0, context: nil,
                    subtype: 8, data1: half.data1, data2: -1)?.cgEvent
                else { return nil }
                event.setIntegerValueField(.eventSourceUserData, value: systemQuarterStepMarker)
                return event
            }
        }
    }

    struct BrightnessKeyEvent: Equatable {
        let delta: Double
        let isKeyDown: Bool
        let isRepeat: Bool
    }

    enum BrightnessKeyOwner: Equatable {
        case system
        case app(delta: Double)
    }

    struct BrightnessKeyOwnership {
        private var owners = [Bool: BrightnessKeyOwner]()

        mutating func owner(of press: BrightnessKeyEvent, option: Bool, shift: Bool,
                            commandOrControl: Bool) -> BrightnessKeyOwner {
            let increases = press.delta > 0
            guard press.isKeyDown else { return owners.removeValue(forKey: increases) ?? .system }
            if !press.isRepeat {
                if commandOrControl || (option && !shift) {
                    owners[increases] = .system
                } else {
                    owners[increases] = .app(delta: option ? press.delta / 4 : press.delta)
                }
            }
            return owners[increases] ?? .system
        }
    }

    static func brightnessKeyEvent(subtype: Int, data1: Int) -> BrightnessKeyEvent? {
        guard subtype == 8 else { return nil }
        let raw = UInt32(truncatingIfNeeded: data1)
        let state = Int((raw >> 8) & 0xFF)
        guard state == 10 || state == 11 else { return nil }
        let delta: Double
        switch (raw >> 16) & 0xFFFF {
        case 2: delta = brightnessKeyStep
        case 3: delta = -brightnessKeyStep
        default: return nil
        }
        return BrightnessKeyEvent(delta: delta, isKeyDown: state == 10, isRepeat: (raw & 0x1) != 0)
    }

    static func isKeyboardLightPress(subtype: Int, data1: Int) -> Bool {
        guard subtype == 8 else { return false }
        let raw = UInt32(truncatingIfNeeded: data1)
        return (21...23).contains((raw >> 16) & 0xFFFF) && ((raw >> 8) & 0xFF) == 10
    }

    enum BrightnessKeyCode {
        static let increase = 144
        static let decrease = 145
        static let functionIncrease = 113
        static let functionDecrease = 107
    }

    static func isBrightnessKeyCode(_ keyCode: Int) -> Bool {
        keyCode == BrightnessKeyCode.increase || keyCode == BrightnessKeyCode.decrease
            || keyCode == BrightnessKeyCode.functionIncrease
            || keyCode == BrightnessKeyCode.functionDecrease
    }

    static func brightnessFunctionKeyEvent(keyCode: Int,
                                           isKeyDown: Bool,
                                           isRepeat: Bool,
                                           hasModifiers: Bool,
                                           functionKeysAdjustBrightness: Bool) -> BrightnessKeyEvent? {
        guard !hasModifiers else { return nil }
        let delta: Double
        switch keyCode {
        case BrightnessKeyCode.increase: delta = brightnessKeyStep
        case BrightnessKeyCode.decrease: delta = -brightnessKeyStep
        case BrightnessKeyCode.functionIncrease where functionKeysAdjustBrightness:
            delta = brightnessKeyStep
        case BrightnessKeyCode.functionDecrease where functionKeysAdjustBrightness:
            delta = -brightnessKeyStep
        default: return nil
        }
        return BrightnessKeyEvent(delta: delta, isKeyDown: isKeyDown, isRepeat: isRepeat)
    }

    static func functionKeysAdjustBrightness(symbolicHotKeys: [String: Any]?) -> Bool {
        guard let symbolicHotKeys else { return true }
        for identifier in ["53", "54"] {
            guard let entry = symbolicHotKeys[identifier] as? [String: Any] else { continue }
            if let enabled = entry["enabled"] as? Bool, !enabled { return false }
            if let enabled = entry["enabled"] as? NSNumber, !enabled.boolValue { return false }
        }
        return true
    }

    static func answersPlainBrightnessKeys(followsPointer: Bool, overlayReplacesNative: Bool,
                                           finerSteps: Bool) -> Bool {
        followsPointer || overlayReplacesNative || finerSteps
    }

    static func plainKeyTarget(followsPointer: Bool, pointerDisplay: UInt32?, systemTarget: UInt32?) -> UInt32? {
        followsPointer ? pointerDisplay : systemTarget
    }

    static func shortcutDisplay(followsPointer: Bool, pointerDisplay: UInt32?,
                                primaryDisplay: UInt32, eligible: Set<UInt32>) -> UInt32? {
        let target = followsPointer ? pointerDisplay : primaryDisplay
        guard let target, eligible.contains(target) else { return nil }
        return target
    }

    static func steppedBrightness(_ current: Double, delta: Double) -> Double {
        min(max(current + delta, 0), 1)
    }

    static func easedBrightnessChange(to target: Double, from reported: Float) -> Float? {
        guard target.isFinite, reported.isFinite, reported >= 0, reported <= 1 else { return nil }
        let change = Float(min(max(target, 0), 1)) - reported
        return change == 0 ? nil : change
    }

    static func easedBrightnessLanded(on target: Double, reported: Float) -> Bool {
        reported.isFinite && abs(Double(reported) - target) < 0.001
    }

    static func stepsSystemRoutedDisplay(followsPointer: Bool,
                                         displayIsBuiltIn: Bool,
                                         overlayReplacesNative: Bool) -> Bool {
        if followsPointer, !displayIsBuiltIn { return true }
        return overlayReplacesNative
    }

    static func overlayReplacesNative(overlayEnabled: Bool, islandRoutes: Bool,
                                      islandShowsNotices: Bool) -> Bool {
        overlayEnabled || (islandRoutes && islandShowsNotices)
    }

    static func filledBrightnessSegments(_ brightness: Double) -> Int {
        let clamped = min(max(brightness, 0), 1)
        guard clamped > 0 else { return 0 }
        return min(Int((clamped * 16).rounded(.up)), 16)
    }

    static func wholePercent(_ brightness: Double) -> Int {
        guard brightness.isFinite else { return 0 }
        return Int((min(max(brightness, 0), 1) * 100).rounded())
    }

    static func trustsRememberedLevel(lastKnownAt: Date?,
                                      now: Date,
                                      window: TimeInterval) -> Bool {
        guard let lastKnownAt else { return false }
        let age = now.timeIntervalSince(lastKnownAt)
        return age >= 0 && age < window
    }

    static func normalized(current: UInt16, maximum: UInt16) -> Double {
        let ceiling = sanitizedMaximum(maximum)
        return min(max(Double(current) / Double(ceiling), 0), 1)
    }

    static func deviceValue(for normalized: Double, maximum: UInt16) -> UInt16 {
        let ceiling = sanitizedMaximum(maximum)
        let clamped = min(max(normalized, 0), 1)
        return UInt16((clamped * Double(ceiling)).rounded())
    }

    static let extendedDimmingRange = 0.25

    static func extendedDimmingComponents(for brightness: Double) -> (hardware: Double, picture: Double) {
        let level = min(max(brightness, 0), 1)
        if level < extendedDimmingRange {
            return (0, level / extendedDimmingRange)
        }
        return ((level - extendedDimmingRange) / (1 - extendedDimmingRange), 1)
    }

    static func extendedDimmingLevel(hardware: Double, remembered: Double?, pictureDimmed: Bool) -> Double {
        let physical = extendedDimmingRange
            + min(max(hardware, 0), 1) * (1 - extendedDimmingRange)
        guard pictureDimmed, hardware <= 0.001, let remembered,
              remembered < extendedDimmingRange else { return physical }
        return min(max(remembered, 0), extendedDimmingRange)
    }

    // MARK: - Display to service matching

    struct DisplayIdentity {
        var vendorID: Int64?
        var productID: Int64?
        var weekOfManufacture: Int64?
        var yearOfManufacture: Int64?
        var horizontalImageSize: Int64?
        var verticalImageSize: Int64?
        var ioDisplayLocation: String?
        var productName: String?
        var serialNumber: Int64?
    }

    struct ServiceIdentity {
        var edidUUID = ""
        var ioDisplayLocation = ""
        var productName = ""
        var serialNumber: Int64 = 0
        var ordinal = 0
    }

    static func matchScore(service: ServiceIdentity, display: DisplayIdentity) -> Int {
        var score = 0
        func uuidChunk(at location: Int) -> String {
            String(service.edidUUID.prefix(location + 4).suffix(4))
        }
        if let vendor = display.vendorID, vendor > 0 {
            let key = String(format: "%04X", UInt16(clamping: vendor))
            if key != "0000", key == uuidChunk(at: 0) { score += 1 }
        }
        if let product = display.productID, product > 0 {
            let value = UInt16(clamping: product)
            let key = String(format: "%02X%02X", UInt8(value & 0xFF), UInt8(value >> 8))
            if key != "0000", key == uuidChunk(at: 4) { score += 1 }
        }
        if let week = display.weekOfManufacture, let year = display.yearOfManufacture, year >= 1990 {
            let key = String(format: "%02X%02X",
                             UInt8(clamping: week),
                             UInt8(clamping: year - 1990))
            if key != "0000", key == uuidChunk(at: 19) { score += 1 }
        }
        if let horizontal = display.horizontalImageSize, let vertical = display.verticalImageSize {
            let key = String(format: "%02X%02X",
                             UInt8(clamping: horizontal / 10),
                             UInt8(clamping: vertical / 10))
            if key != "0000", key == uuidChunk(at: 30) { score += 1 }
        }
        if !service.ioDisplayLocation.isEmpty, service.ioDisplayLocation == display.ioDisplayLocation {
            score += 10
        }
        if !service.productName.isEmpty,
           service.productName.lowercased() == display.productName?.lowercased() {
            score += 1
        }
        if service.serialNumber != 0, service.serialNumber == display.serialNumber {
            score += 1
        }
        return score
    }

    static func assignServices(scores: [(displayIndex: Int, serviceOrdinal: Int, score: Int)])
        -> [Int: Int] {
        var assignment: [Int: Int] = [:]
        var takenServices = Set<Int>()
        for entry in scores.sorted(by: { $0.score > $1.score }) where entry.score > 0 {
            guard assignment[entry.displayIndex] == nil,
                  !takenServices.contains(entry.serviceOrdinal) else { continue }
            assignment[entry.displayIndex] = entry.serviceOrdinal
            takenServices.insert(entry.serviceOrdinal)
        }
        return assignment
    }
}
