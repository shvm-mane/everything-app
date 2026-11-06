// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import ServiceManagement

enum LaunchAtLogin {
    private static let operationQueue = DispatchQueue(
        label: "com.vorssaint.utils.launch-at-login", qos: .userInitiated)

    static var registration: LaunchAtLoginSupport.Registration {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .needsApproval
        default: return .off
        }
    }

    static var isEnabled: Bool { registration == .enabled }

    struct UnstableLocationError: LocalizedError {
        var errorDescription: String? { L10n.shared.s.launchAtLoginNeedsApplications }
    }

    struct NeedsApprovalError: LocalizedError {
        var errorDescription: String? { L10n.shared.s.launchAtLoginNeedsApproval }
    }

    static func refresh(_ completion: @escaping (LaunchAtLoginSupport.Registration) -> Void) {
        operationQueue.async {
            let current = registration
            DispatchQueue.main.async { completion(current) }
        }
    }

    static func setEnabled(_ enabled: Bool,
                           completion: @escaping (LaunchAtLoginSupport.Registration, Error?) -> Void) {
        operationQueue.async {
            let failure: Error?
            do {
                try setEnabledNow(enabled)
                failure = nil
            } catch {
                failure = error
            }
            let current = registration
            DispatchQueue.main.async { completion(current, failure) }
        }
    }

    private static func setEnabledNow(_ enabled: Bool) throws {
        if enabled, locationIsUnstable { throw UnstableLocationError() }
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.launchAtLoginWanted)
        var failure: Error?
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            failure = error
        }
        if enabled, registration == .needsApproval { throw NeedsApprovalError() }
        if let failure, isEnabled != enabled {
            UserDefaults.standard.set(isEnabled, forKey: DefaultsKey.launchAtLoginWanted)
            throw failure
        }
    }

    static func repairAtStartup() {
        operationQueue.async { repairNow() }
    }

    private static func repairNow() {
        let defaults = UserDefaults.standard
        switch LaunchAtLoginSupport.startupAction(
            wanted: defaults.bool(forKey: DefaultsKey.launchAtLoginWanted),
            registration: registration,
            locationIsUnstable: locationIsUnstable) {
        case .none:
            break
        case .adoptEnabled:
            defaults.set(true, forKey: DefaultsKey.launchAtLoginWanted)
        case .register:
            try? SMAppService.mainApp.register()
        }
    }

    private static var locationIsUnstable: Bool {
        UpdateInstallerSupport.runsFromImmutableLocation(
            appPath: Bundle.main.bundlePath,
            volumeIsReadOnly: { path in
                let values = try? URL(fileURLWithPath: path)
                    .resourceValues(forKeys: [.volumeIsReadOnlyKey])
                return values?.volumeIsReadOnly ?? true
            })
    }
}
