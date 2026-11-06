// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum QuickTogglesSupport {
    static let finderDomain = "com.apple.finder"
    static let showAllFilesKey = "AppleShowAllFiles"
    static let createDesktopKey = "CreateDesktop"

    static let emptyTrashSource = "tell application \"Finder\" to empty trash"
    static let quitFinderSource = "tell application \"Finder\" to quit"

    static let permissionErrorNumbers: Set<Int> = [-1743, -1744]

    static func isPermissionError(_ errorNumber: Int?) -> Bool {
        guard let errorNumber else { return false }
        return permissionErrorNumbers.contains(errorNumber)
    }

    static func finderFlag(_ value: Any?, default defaultValue: Bool) -> Bool {
        switch value {
        case let flag as Bool:
            return flag
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            switch string.lowercased() {
            case "yes", "true", "1": return true
            case "no", "false", "0": return false
            default: return defaultValue
            }
        default:
            return defaultValue
        }
    }

    static func shouldOfferEject(isInternal: Bool,
                                 isRemovable: Bool,
                                 isEjectable: Bool,
                                 isLocal: Bool,
                                 isRootFileSystem: Bool,
                                 volumeName: String? = nil,
                                 volumeUUID: String? = nil,
                                 mountPath: String? = nil,
                                 excludedVolumes: Set<String> = []) -> Bool {
        guard isLocal && !isRootFileSystem && (!isInternal || isRemovable || isEjectable) else {
            return false
        }
        guard !excludedVolumes.isEmpty else { return true }
        return !isExcluded(volumeName: volumeName,
                           volumeUUID: volumeUUID,
                           mountPath: mountPath,
                           excludedVolumes: excludedVolumes)
    }

    static func isExcluded(volumeName: String?,
                           volumeUUID: String?,
                           mountPath: String?,
                           excludedVolumes: Set<String>) -> Bool {
        guard !excludedVolumes.isEmpty else { return false }
        if let name = volumeName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            if excludedVolumes.contains(name) || excludedVolumes.contains(name.lowercased()) {
                return true
            }
        }
        if let uuid = volumeUUID?.trimmingCharacters(in: .whitespacesAndNewlines), !uuid.isEmpty {
            if excludedVolumes.contains(uuid) || excludedVolumes.contains(uuid.lowercased()) {
                return true
            }
        }
        if let mountPath = mountPath?.trimmingCharacters(in: .whitespacesAndNewlines), !mountPath.isEmpty {
            if excludedVolumes.contains(mountPath) || excludedVolumes.contains(mountPath.lowercased()) {
                return true
            }
            let lastComponent = (mountPath as NSString).lastPathComponent
            if !lastComponent.isEmpty && (excludedVolumes.contains(lastComponent) || excludedVolumes.contains(lastComponent.lowercased())) {
                return true
            }
        }
        return false
    }

    // MARK: - Quit all apps

    static let vorssaintBundleIdentifiers = [
        "com.vorssaint.utils",
        "com.vorssaint.utils.dev",
    ]

    static let regularActivationPolicy = 0

    static func sanitizedQuitAllExceptions(_ bundleIDs: [String]) -> [String] {
        Defaults.sanitizedBundleIdentifierList(Defaults.mandatoryAutoQuitExceptionBundleIDs + bundleIDs)
            .filter { !vorssaintBundleIdentifiers.contains($0) }
    }

    static func shouldQuitApp(bundleIdentifier: String?,
                              activationPolicyRawValue: Int,
                              isTerminated: Bool,
                              exceptions: Set<String>) -> Bool {
        guard !isTerminated else { return false }
        guard activationPolicyRawValue == regularActivationPolicy else { return false }
        guard let bundleIdentifier, !bundleIdentifier.isEmpty,
              !vorssaintBundleIdentifiers.contains(bundleIdentifier) else { return false }
        return !exceptions.contains(bundleIdentifier)
    }

    static func listsApp(bundleIdentifier: String?,
                         activationPolicyRawValue: Int,
                         isTerminated: Bool) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        guard bundleIdentifier != Defaults.finderBundleIdentifier,
              !vorssaintBundleIdentifiers.contains(bundleIdentifier) else { return false }
        return !isTerminated && activationPolicyRawValue == regularActivationPolicy
    }

    static func batchQuitTargets(_ apps: [QuitAppsCandidate],
                                 exceptions: Set<String>,
                                 keepingPID: Int32?) -> [Int32] {
        apps.filter { app in
            app.pid != keepingPID
                && shouldQuitApp(bundleIdentifier: app.bundleIdentifier,
                                 activationPolicyRawValue: app.activationPolicyRawValue,
                                 isTerminated: app.isTerminated,
                                 exceptions: exceptions)
        }
        .map(\.pid)
    }

}

struct QuitAppsCandidate: Equatable {
    let pid: Int32
    let bundleIdentifier: String?
    let activationPolicyRawValue: Int
    let isTerminated: Bool
}

enum QuitAppsScope: Equatable {
    case all
    case allExceptFront
}

enum QuitAppsButton: Equatable {
    case cancel, allExceptFront, all
}

enum QuitAppsFocus: Equatable {
    case row(Int32)
    case button(QuitAppsButton)
}

enum QuitAppsMove: Equatable {
    case up, down, left, right, next, previous
}

extension QuickTogglesSupport {
    static func quitAppsButtons(offersExceptFront: Bool, canQuitAll: Bool) -> [QuitAppsButton] {
        [.cancel] + (offersExceptFront ? [.allExceptFront] : []) + (canQuitAll ? [.all] : [])
    }

    static func restingQuitAppsButton(scope: QuitAppsScope?,
                                      buttons: [QuitAppsButton]) -> QuitAppsButton {
        let wanted: QuitAppsButton?
        switch scope {
        case .all: wanted = .all
        case .allExceptFront: wanted = .allExceptFront
        case nil: wanted = nil
        }
        if let wanted, buttons.contains(wanted) { return wanted }
        return .cancel
    }

    static func movedQuitAppsFocus(_ focus: QuitAppsFocus,
                                   _ move: QuitAppsMove,
                                   rows: [Int32],
                                   buttons: [QuitAppsButton],
                                   resting: QuitAppsButton) -> QuitAppsFocus {
        switch focus {
        case .row(let pid):
            guard let index = rows.firstIndex(of: pid) else { return .button(resting) }
            switch move {
            case .up: return .row(rows[max(index - 1, 0)])
            case .down: return index + 1 < rows.count ? .row(rows[index + 1]) : .button(resting)
            case .left, .right: return focus
            case .next, .previous: return .button(resting)
            }
        case .button(let button):
            guard let index = buttons.firstIndex(of: button) else { return .button(resting) }
            switch move {
            case .up: return rows.last.map { .row($0) } ?? focus
            case .down: return focus
            case .left: return .button(buttons[max(index - 1, 0)])
            case .right: return .button(buttons[min(index + 1, buttons.count - 1)])
            case .next: return .button(buttons[(index + 1) % buttons.count])
            case .previous: return .button(buttons[(index - 1 + buttons.count) % buttons.count])
            }
        }
    }

    static func quitAppsFocusAfterListChange(_ focus: QuitAppsFocus,
                                             previousRows: [Int32],
                                             rows: [Int32],
                                             buttons: [QuitAppsButton],
                                             resting: QuitAppsButton) -> QuitAppsFocus {
        switch focus {
        case .row(let pid):
            if rows.contains(pid) { return focus }
            guard !rows.isEmpty else { return .button(resting) }
            let index = previousRows.firstIndex(of: pid) ?? 0
            return .row(rows[min(index, rows.count - 1)])
        case .button(let button):
            return buttons.contains(button) ? focus : .button(resting)
        }
    }

    static func quitAppsRow(matching prefix: String,
                            in rows: [(pid: Int32, name: String)]) -> Int32? {
        guard !prefix.isEmpty else { return nil }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .anchored]
        return rows.first { $0.name.range(of: prefix, options: options) != nil }?.pid
    }
}
