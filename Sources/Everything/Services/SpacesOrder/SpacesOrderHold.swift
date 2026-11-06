// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin
import Foundation
import os

enum SpacesRearrangeSetting: Equatable {
    case absent, on, off
    case unsupported
    case unreadable
}

enum SpacesOrderSupport {
    static let dockDomain = "com.apple.dock"
    static let preferenceKey = "mru-spaces"
    static let restoreAbsent = "absent"
    static let restoreOn = "on"
    static let restoreOff = "off"

    static func setting(raw: Any?, isForced: Bool) -> SpacesRearrangeSetting {
        if isForced { return .unsupported }
        guard let raw else { return .absent }
        guard let number = raw as? NSNumber else { return .unsupported }
        return number.boolValue ? .on : .off
    }

    enum Step: Equatable {
        case none
        case hold(marker: String)
        case remember
        case release(removeKey: Bool)
        case forget
        case letGo
        case restart
    }

    enum DockState: String {
        case rearranging, fixed

        init?(_ setting: SpacesRearrangeSetting) {
            switch setting {
            case .absent, .on: self = .rearranging
            case .off: self = .fixed
            case .unsupported, .unreadable: return nil
            }
        }
    }

    struct RestartJournal: Equatable {
        var dockPID: pid_t
        var dockRuns: DockState
        var wrote: [SpacesRearrangeSetting]

        func holds(dockPID current: pid_t?, reads: SpacesRearrangeSetting) -> Bool {
            dockPID > 0 && current == dockPID && wrote.contains(reads)
        }

        private static let tokens: [SpacesRearrangeSetting: String] = [.absent: "absent", .on: "on", .off: "off"]

        var encoded: String {
            ([String(dockPID), dockRuns.rawValue] + wrote.compactMap { Self.tokens[$0] }).joined(separator: " ")
        }

        init(dockPID: pid_t, dockRuns: DockState, wrote: [SpacesRearrangeSetting]) {
            self.dockPID = dockPID
            self.dockRuns = dockRuns
            self.wrote = wrote
        }

        init?(encoded: String) {
            let parts = encoded.split(separator: " ").map(String.init)
            guard parts.count > 2, let pid = pid_t(parts[0]), let runs = DockState(rawValue: parts[1]) else { return nil }
            let values = parts.dropFirst(2).map { token in Self.tokens.first { $0.value == token }?.key }
            guard values.allSatisfy({ $0 != nil }) else { return nil }
            self.init(dockPID: pid, dockRuns: runs, wrote: values.compactMap { $0 })
        }
    }

    static func step(wanted: Bool, current: SpacesRearrangeSetting, marker: String?,
                     dockRuns: DockState? = nil) -> Step {
        guard current != .unreadable else { return .none }
        if let dockRuns {
            let reads = DockState(current)
            let owesBack = marker != nil && marker != restoreOff
            let target: DockState? = wanted ? .fixed : (owesBack ? .rearranging : reads)
            if let reads, reads != dockRuns, reads == target { return .restart }
            let next = step(wanted: wanted, current: current, marker: marker)
            if next == .letGo, let marker { return .hold(marker: marker) }
            return next
        }
        if wanted {
            switch current {
            case .off: return marker == nil ? .remember : .none
            case .unsupported, .unreadable: return .none
            case .absent, .on:
                guard marker == nil else { return .letGo }
                return .hold(marker: current == .absent ? restoreAbsent : restoreOn)
            }
        }
        guard let marker else { return .none }
        guard marker != restoreOff else { return .forget }
        return current == .off ? .release(removeKey: marker == restoreAbsent) : .forget
    }
}

struct SpacesOrderSystem {
    var read: () -> SpacesRearrangeSetting
    var write: (Bool?) -> Bool
    var restartDock: () -> Bool
    var dockPID: () -> pid_t?
}

extension SpacesOrderSystem {
    static let live = SpacesOrderSystem(
        read: {
            let key = SpacesOrderSupport.preferenceKey as CFString
            let domain = SpacesOrderSupport.dockDomain as CFString
            guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            else { return .unreadable }
            let raw = CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            return SpacesOrderSupport.setting(raw: raw,
                                              isForced: CFPreferencesAppValueIsForced(key, domain))
        },
        write: { value in
            let domain = SpacesOrderSupport.dockDomain as CFString
            CFPreferencesSetValue(SpacesOrderSupport.preferenceKey as CFString,
                                  value.map { NSNumber(value: $0) },
                                  domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            return CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        },
        restartDock: { Shell.run("/usr/bin/killall", ["Dock"]).status == 0 },
        dockPID: {
            NSRunningApplication.runningApplications(withBundleIdentifier: SpacesOrderSupport.dockDomain)
                .first?.processIdentifier
        }
    )
}

final class SpacesOrderHold {
    static let shared = SpacesOrderHold(defaults: .standard, system: .live)

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "spaces-order")
    private let defaults: UserDefaults
    private let system: SpacesOrderSystem
    private let queue = DispatchQueue(label: "com.vorssaint.spaces-order")
    private let queueKey = DispatchSpecificKey<Bool>()
    private let requestLock = NSRecursiveLock()
    private var requestGeneration: UInt64 = 0
    private var pendingLetGoOwner: UInt64?
    private var markerGeneration: UInt64 = 0
    private var watchTokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init(defaults: UserDefaults, system: SpacesOrderSystem) {
        self.defaults = defaults
        self.system = system
        queue.setSpecific(key: queueKey, value: true)
    }

    private func onQueue<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) == true { return work() }
        return queue.sync(execute: work)
    }

    private func newRequest() -> UInt64 {
        requestLock.lock()
        defer { requestLock.unlock() }
        requestGeneration &+= 1
        return requestGeneration
    }

    private func currentRequest() -> UInt64 {
        requestLock.lock()
        defer { requestLock.unlock() }
        return requestGeneration
    }

    private func awaitingLetGoPersistence() -> Bool {
        requestLock.lock()
        defer { requestLock.unlock() }
        return pendingLetGoOwner == markerGeneration
    }

    deinit {
        watchTokens.forEach { $0.center.removeObserver($0.token) }
    }

    static var hasPendingRestore: Bool { isOwed(in: .standard) }

    private static func isOwed(in defaults: UserDefaults) -> Bool {
        defaults.string(forKey: DefaultsKey.spacesOrderRestore) != nil
            || defaults.string(forKey: DefaultsKey.spacesOrderRestartPending) != nil
    }

    private var journal: SpacesOrderSupport.RestartJournal? {
        defaults.string(forKey: DefaultsKey.spacesOrderRestartPending)
            .flatMap(SpacesOrderSupport.RestartJournal.init(encoded:))
    }

    private func heldJournal(reads current: SpacesRearrangeSetting) -> SpacesOrderSupport.RestartJournal? {
        journal.flatMap { $0.holds(dockPID: system.dockPID(), reads: current) ? $0 : nil }
    }

    private var isWanted: Bool {
        AppFeature.spacesOrder.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.spacesOrderEnabled)
    }

    func syncWithPreferences() {
        let generation = newRequest()
        queue.async { [self] in
            guard generation == currentRequest() else { return }
            let wanted = isWanted
            let completed = reconcileOnQueue(wanted: wanted, generation: generation)
            guard generation == currentRequest() else { return }
            if !completed {
                Self.log.error("Space rearranging did not change (fixed order wanted: \(wanted, privacy: .public))")
            }
            watch(isWanted)
        }
    }

    @discardableResult
    func letGoIfRearrangingReturned() -> Bool {
        let generation = currentRequest()
        return onQueue { letGoIfRearrangingReturnedOnQueue(generation: generation) }
    }

    private func letGoIfRearrangingReturnedOnQueue(generation: UInt64) -> Bool {
        guard generation == currentRequest() else { return false }
        guard isWanted, let marker = defaults.string(forKey: DefaultsKey.spacesOrderRestore) else { return false }
        let current = system.read()
        guard SpacesOrderSupport.step(wanted: true, current: current, marker: marker,
                                      dockRuns: heldJournal(reads: current)?.dockRuns) == .letGo
        else { return false }
        letGo(generation: generation)
        return true
    }

    private func watch(_ enabled: Bool) {
        guard enabled == watchTokens.isEmpty else { return }
        guard enabled else {
            watchTokens.forEach { $0.center.removeObserver($0.token) }
            watchTokens = []
            return
        }
        let moments: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification),
            (NotificationCenter.default, NSApplication.didBecomeActiveNotification),
        ]
        watchTokens = moments.map { center, name in
            (center: center, token: center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                guard let self else { return }
                let generation = self.currentRequest()
                self.queue.async { [weak self] in
                    guard let self, !self.watchTokens.isEmpty else { return }
                    _ = self.letGoIfRearrangingReturnedOnQueue(generation: generation)
                }
            })
        }
    }

    static func recoverIfNeeded() {
        guard hasPendingRestore, !AppFeature.spacesOrder.isAvailable else { return }
        shared.syncWithPreferences()
    }

    static func restoreForRemoval() -> Bool {
        shared.restoreForRemoval()
    }

    func restoreForRemoval() -> Bool {
        let generation = newRequest()
        return onQueue {
            guard generation == currentRequest() else { return false }
            guard Self.isOwed(in: defaults) else { return true }
            return reconcileOnQueue(wanted: false, generation: generation)
        }
    }

    @discardableResult
    func reconcile(wanted: Bool) -> Bool {
        let generation = newRequest()
        return onQueue { reconcileOnQueue(wanted: wanted, generation: generation) }
    }

    private func reconcileOnQueue(wanted: Bool, generation: UInt64) -> Bool {
        guard generation == currentRequest() else { return false }
        let resumesAfterFailedPublication = awaitingLetGoPersistence()
        if resumesAfterFailedPublication && !wanted {
            letGo(generation: generation)
            return false
        }
        let current = system.read()
        guard generation == currentRequest(), current != .unreadable else { return false }
        if resumesAfterFailedPublication {
            requestLock.lock()
            guard generation == requestGeneration else {
                requestLock.unlock()
                return false
            }
            pendingLetGoOwner = nil
            requestLock.unlock()
            clearMarker()
        }
        let marker = defaults.string(forKey: DefaultsKey.spacesOrderRestore)
        let held = heldJournal(reads: current)
        if held == nil, defaults.object(forKey: DefaultsKey.spacesOrderRestartPending) != nil { saveJournal(nil) }
        switch SpacesOrderSupport.step(wanted: wanted, current: current, marker: marker, dockRuns: held?.dockRuns) {
        case .restart:
            guard system.restartDock() else { return false }
            saveJournal(nil)
            return reconcileOnQueue(wanted: wanted, generation: generation)
        case .none:
            if held != nil { saveJournal(nil) }
            return true
        case .hold(let restore):
            guard saveMarker(restore) else { return false }
            let result = apply(rearranging: false, removeKey: false, current: current, held: held)
            guard result.done else {
                if marker == nil, result.unchanged { clearMarker() }
                return false
            }
            return true
        case .remember:
            guard saveMarker(SpacesOrderSupport.restoreOff) else { return false }
            if held != nil { saveJournal(nil) }
            return true
        case .release(let removeKey):
            let result = apply(rearranging: true, removeKey: removeKey, current: current, held: held)
            if result.wrote { clearMarker() }
            return result.done
        case .forget:
            clearMarker()
            if held != nil { saveJournal(nil) }
            return true
        case .letGo:
            letGo(generation: generation)
            return true
        }
    }

    private func letGo(generation: UInt64) {
        let owner = markerGeneration
        DispatchQueue.main.async { [self] in
            requestLock.lock()
            defer { requestLock.unlock() }
            guard generation == requestGeneration else { return }
            pendingLetGoOwner = owner
            defaults.set(false, forKey: DefaultsKey.spacesOrderEnabled)
            let persisted = defaults.synchronize()
            guard !defaults.bool(forKey: DefaultsKey.spacesOrderEnabled) else {
                if pendingLetGoOwner == owner { pendingLetGoOwner = nil }
                return
            }
            guard persisted else { return }
            if pendingLetGoOwner == owner { pendingLetGoOwner = nil }
            queue.async { [self] in
                if markerGeneration == owner {
                    clearMarker()
                    watch(false)
                } else {
                    watch(isWanted)
                }
            }
            Self.log.info("Space rearranging was turned back on outside EVERYTHING; fixed order turned off")
        }
    }

    private func apply(rearranging: Bool, removeKey: Bool, current: SpacesRearrangeSetting,
                       held: SpacesOrderSupport.RestartJournal?) -> (done: Bool, wrote: Bool, unchanged: Bool) {
        let value: SpacesRearrangeSetting = removeKey ? .absent : (rearranging ? .on : .off)
        let dockRuns = held?.dockRuns ?? (rearranging ? .fixed : .rearranging)
        guard saveJournal(SpacesOrderSupport.RestartJournal(dockPID: held?.dockPID ?? system.dockPID() ?? 0,
                                                            dockRuns: dockRuns, wrote: (held?.wrote ?? []) + [value]))
        else { return (false, false, true) }
        guard system.write(removeKey ? nil : rearranging) else {
            let after = system.read()
            if after == current { saveJournal(held) }
            return (false, after == value, after == current)
        }
        guard SpacesOrderSupport.DockState(value) != dockRuns else {
            saveJournal(nil)
            return (true, true, false)
        }
        guard system.restartDock() else { return (false, true, false) }
        saveJournal(nil)
        return (true, true, false)
    }

    private func saveMarker(_ value: String) -> Bool {
        markerGeneration &+= 1
        defaults.set(value, forKey: DefaultsKey.spacesOrderRestore)
        return defaults.synchronize()
    }

    private func clearMarker() {
        markerGeneration &+= 1
        defaults.removeObject(forKey: DefaultsKey.spacesOrderRestore)
        defaults.synchronize()
    }

    @discardableResult
    private func saveJournal(_ journal: SpacesOrderSupport.RestartJournal?) -> Bool {
        if let journal {
            defaults.set(journal.encoded, forKey: DefaultsKey.spacesOrderRestartPending)
        } else {
            defaults.removeObject(forKey: DefaultsKey.spacesOrderRestartPending)
        }
        return defaults.synchronize()
    }
}
