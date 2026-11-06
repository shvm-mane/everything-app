// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum SystemShortcutTakeover {
    private static let lock = NSLock()
    private static var suppressed: Set<Int32> = SystemShortcutTakeoverSupport.migratedMarker(
        old: UserDefaults.standard.array(forKey: DefaultsKey.switcherNativeHotkeysSuppressed) as? [Int],
        new: UserDefaults.standard.array(forKey: DefaultsKey.systemShortcutsSuppressed) as? [Int])
    static let switcherSource = "switcher"
    private static var wanted: [String: Set<Int32>] = [:]
    private static var claims: [String: GlobalShortcut] = [:]
    private static var takeOverKeys: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: DefaultsKey.systemShortcutTakeOverKeys) ?? [])
    private static var wakeObserver: NSObjectProtocol?

    static func setWanted(_ ids: Set<Int32>, for source: String) {
        lock.lock()
        defer { lock.unlock() }
        if ids.isEmpty { wanted.removeValue(forKey: source) } else { wanted[source] = ids }
        applyLocked(desired: SystemShortcutTakeoverSupport.union(of: wanted))
    }

    static func claim(_ storageKey: String, shortcut: GlobalShortcut) {
        lock.lock()
        claims[storageKey] = shortcut
        lock.unlock()
        refresh(storageKey)
    }

    static func release(_ storageKey: String) {
        lock.lock()
        claims.removeValue(forKey: storageKey)
        lock.unlock()
        setWanted([], for: storageKey)
    }

    static func setTakeOver(_ storageKey: String, _ on: Bool) {
        lock.lock()
        if on { takeOverKeys.insert(storageKey) } else { takeOverKeys.remove(storageKey) }
        UserDefaults.standard.set(takeOverKeys.sorted(), forKey: DefaultsKey.systemShortcutTakeOverKeys)
        lock.unlock()
        refresh(storageKey)
    }

    static func isTakenOver(_ storageKey: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return takeOverKeys.contains(storageKey)
    }

    static func conflictsWithMacOS(_ shortcut: GlobalShortcut, for role: GlobalShortcutRole? = nil) -> Bool {
        lock.lock()
        let held = suppressed
        lock.unlock()
        return SystemShortcutTakeoverSupport.conflictsWithMacOS(
            shortcut,
            liveEntries: SymbolicHotKeys.liveEntries(),
            symbolicHotKeys: GlobalShortcut.systemSymbolicHotKeys,
            held: held,
            role: role)
    }

    static func reconcile() {
        let keys: [String]
        lock.lock()
        keys = Array(claims.keys)
        lock.unlock()
        for key in keys { refresh(key) }
    }

    private static func refresh(_ storageKey: String) {
        lock.lock()
        let shortcut = takeOverKeys.contains(storageKey) ? claims[storageKey] : nil
        lock.unlock()
        guard let shortcut else {
            setWanted([], for: storageKey)
            return
        }
        guard let entries = SymbolicHotKeys.liveEntries() else { return }
        setWanted(SystemShortcutTakeoverSupport.ids(matching: shortcut, in: entries), for: storageKey)
    }

    static func restoreAll() {
        lock.lock()
        defer { lock.unlock() }
        wanted.removeAll()
        claims.removeAll()
        applyLocked(desired: [])
    }

    private static func applyLocked(desired: Set<Int32>) {
        guard let setEnabled = SymbolicHotKeys.setEnabled,
              let isEnabled = SymbolicHotKeys.isEnabled else { return }
        let candidates = desired.union(suppressed)
        let currentlyEnabled = candidates.filter { isEnabled($0) }
        let transition = SystemShortcutTakeoverSupport.transition(
            from: suppressed, to: desired, currentlyEnabled: currentlyEnabled)
        suppressed = SystemShortcutTakeoverSupport.apply(
            transition, owned: suppressed,
            setEnabled: { setEnabled($0, $1) == .success },
            persist: persist)
        observeWake(!suppressed.isEmpty)
    }

    static func recoverIfNeeded(keeping desired: Set<Int32>) {
        lock.lock()
        defer { lock.unlock() }
        persist(suppressed)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.switcherNativeHotkeysSuppressed)
        guard let setEnabled = SymbolicHotKeys.setEnabled else { return }
        let keep = desired.union(SystemShortcutTakeoverSupport.union(of: wanted))
        suppressed = SystemShortcutTakeoverSupport.apply(
            SystemShortcutTakeoverSupport.recoveryTransition(from: suppressed, keeping: keep),
            owned: suppressed,
            setEnabled: { setEnabled($0, $1) == .success },
            persist: persist)
        observeWake(!suppressed.isEmpty)
        let isEnabled = SymbolicHotKeys.isEnabled
        let held = desired.intersection(suppressed).filter { isEnabled?($0) != true }
        if !held.isEmpty { wanted[switcherSource] = held }
    }

    private static func observeWake(_ holding: Bool) {
        if holding, wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { reconcile() }
                }
        } else if !holding, let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
    }

    private static func persist(_ ids: Set<Int32>) {
        if ids.isEmpty {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.systemShortcutsSuppressed)
        } else {
            UserDefaults.standard.set(ids.map(Int.init).sorted(), forKey: DefaultsKey.systemShortcutsSuppressed)
        }
    }
}
