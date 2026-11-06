// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct SystemShortcutTransition: Equatable {
    let suppress: Set<Int32>
    let restore: Set<Int32>
}

enum SystemShortcutTakeoverSupport {
    static func recoveryTransition(from current: Set<Int32>, keeping desired: Set<Int32>)
        -> SystemShortcutTransition {
        SystemShortcutTransition(suppress: [], restore: current.subtracting(desired))
    }

    static func transition(from current: Set<Int32>, to desired: Set<Int32>,
                           currentlyEnabled: Set<Int32>) -> SystemShortcutTransition {
        SystemShortcutTransition(suppress: desired.intersection(currentlyEnabled),
                                 restore: current.subtracting(desired))
    }

    static func apply(_ transition: SystemShortcutTransition, owned: Set<Int32>,
                      setEnabled: (Int32, Bool) -> Bool,
                      persist: (Set<Int32>) -> Void) -> Set<Int32> {
        var next = owned
        for id in transition.suppress {
            let newlyOwned = next.insert(id).inserted
            if newlyOwned { persist(next) }
            if !setEnabled(id, false), newlyOwned {
                next.remove(id)
                persist(next)
            }
        }
        for id in transition.restore where setEnabled(id, true) {
            next.remove(id)
            persist(next)
        }
        return next
    }

    static func ids(matching shortcut: GlobalShortcut, in entries: [LiveSystemShortcut]) -> Set<Int32> {
        Set(entries.filter { $0.shortcut == shortcut }.map(\.id))
    }

    static func union(of wanted: [String: Set<Int32>]) -> Set<Int32> {
        wanted.values.reduce(into: Set<Int32>()) { $0.formUnion($1) }
    }

    static func migratedMarker(old: [Int]?, new: [Int]?) -> Set<Int32> {
        Set(((old ?? []) + (new ?? [])).compactMap { Int32(exactly: $0) })
    }
}

enum RecorderTakeOverDecision: Equatable {
    case save(clearTakeOver: Bool)
    case offer
}

extension SystemShortcutTakeoverSupport {
    static func conflictsWithMacOS(_ shortcut: GlobalShortcut,
                                   liveEntries: [LiveSystemShortcut]?,
                                   symbolicHotKeys: @autoclosure () -> [String: Any]?,
                                   held: Set<Int32>,
                                   role: GlobalShortcutRole? = nil) -> Bool {
        if GlobalShortcut.conflictsWithSystemShortcut(shortcut,
                                                      liveEntries: liveEntries,
                                                      symbolicHotKeys: symbolicHotKeys(),
                                                      role: role) {
            return true
        }
        guard let liveEntries else { return false }
        let permitted = role?.permittedSystemShortcutIDs ?? []
        return !ids(matching: shortcut, in: liveEntries).subtracting(permitted).isDisjoint(with: held)
    }

    static func recorderDecision(shortcut: GlobalShortcut,
                                 conflictsWithMacOS: Bool,
                                 takenOver: Bool,
                                 current: GlobalShortcut?) -> RecorderTakeOverDecision {
        guard conflictsWithMacOS else { return .save(clearTakeOver: true) }
        if takenOver, current == shortcut { return .save(clearTakeOver: false) }
        return .offer
    }
}
