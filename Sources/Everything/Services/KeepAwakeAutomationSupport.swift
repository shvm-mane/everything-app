// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum KeepAwakeAutomationCondition: String, CaseIterable, Hashable {
    case externalDisplay
    case power
    case runningApps
}

enum KeepAwakeAutomationAction: Equatable {
    case none
    case activate
    case deactivate
}

enum KeepAwakeAutomationSupport {
    private static let screenLockedKey = "CGSSessionScreenIsLocked"

    static func hasExternalDisplay(builtInFlags: [Bool]) -> Bool {
        builtInFlags.contains(false)
    }

    static func lidSleepIsAllowed(systemAllowsSleep: Bool?, assertions: [[String: Any]]?) -> Bool {
        guard systemAllowsSleep == true, let assertions else { return false }
        return !assertions.contains { assertion in
            switch assertion["AssertType"] as? String {
            case "UserIsActive", "DisplayWake", "PreventSystemSleep", nil: break
            default: return false
            }
            let appliesToLid = assertion["AppliesOnLidClose"] as? Bool == true
                || assertion["ProcessingHotPlug"] as? Bool == true
            return appliesToLid && assertion["AssertLevel"] as? Int != 0
        }
    }

    static func isScreenLocked(sessionDictionary: [String: Any]?) -> Bool {
        guard let value = sessionDictionary?[screenLockedKey] else { return false }
        if let locked = value as? Bool { return locked }
        return (value as? NSNumber)?.boolValue ?? false
    }

    static func selectedAppsAreRunning(selectedBundleIDs: [String],
                                       runningBundleIDs: [String]) -> Bool {
        guard !selectedBundleIDs.isEmpty else { return false }
        let selected = Set(selectedBundleIDs)
        return runningBundleIDs.contains(where: selected.contains)
    }

    static func matchingConditions(externalDisplayEnabled: Bool,
                                   externalDisplayConnected: Bool,
                                   powerEnabled: Bool,
                                   connectedToPower: Bool,
                                   runningAppsEnabled: Bool,
                                   selectedAppsRunning: Bool) -> Set<KeepAwakeAutomationCondition> {
        var matches = Set<KeepAwakeAutomationCondition>()
        if externalDisplayEnabled, externalDisplayConnected {
            matches.insert(.externalDisplay)
        }
        if powerEnabled, connectedToPower {
            matches.insert(.power)
        }
        if runningAppsEnabled, selectedAppsRunning {
            matches.insert(.runningApps)
        }
        return matches
    }

    static func enabledConditions(externalDisplayEnabled: Bool,
                                  powerEnabled: Bool,
                                  runningAppsEnabled: Bool,
                                  hasSelectedApps: Bool = true) -> Set<KeepAwakeAutomationCondition> {
        var enabled = Set<KeepAwakeAutomationCondition>()
        if externalDisplayEnabled { enabled.insert(.externalDisplay) }
        if powerEnabled { enabled.insert(.power) }
        if runningAppsEnabled, hasSelectedApps { enabled.insert(.runningApps) }
        return enabled
    }

    static func conditionsSatisfied(matching: Set<KeepAwakeAutomationCondition>,
                                    enabled: Set<KeepAwakeAutomationCondition>,
                                    requireAll: Bool) -> Bool {
        guard !matching.isEmpty else { return false }
        return requireAll ? matching == enabled : true
    }

    static func resolvedUntilDate(picked: Date, now: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: picked)
        guard let candidate = calendar.nextDate(after: now.addingTimeInterval(-60),
                                                matching: components,
                                                matchingPolicy: .nextTime) else {
            return picked
        }
        if candidate > now { return candidate }
        return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate.addingTimeInterval(24 * 3600)
    }

    static func action(featureAvailable: Bool,
                       matchingConditions: Set<KeepAwakeAutomationCondition>,
                       enabledConditions: Set<KeepAwakeAutomationCondition> = [],
                       requireAll: Bool = false,
                       sessionActive: Bool,
                       automaticSessionActive: Bool) -> KeepAwakeAutomationAction {
        guard featureAvailable,
              conditionsSatisfied(matching: matchingConditions,
                                  enabled: enabledConditions,
                                  requireAll: requireAll) else {
            return automaticSessionActive ? .deactivate : .none
        }
        return sessionActive ? .none : .activate
    }
}
