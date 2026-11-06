// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LaunchAtLoginSupport {
    static let settingsRefreshRequested = Notification.Name("EVERYTHING.launchAtLoginSettingsRefreshRequested")

    enum Registration: Equatable {
        case enabled
        case needsApproval
        case off
    }

    enum StartupAction: Equatable {
        case none
        case adoptEnabled
        case register
    }

    static func startupAction(wanted: Bool, registration: Registration,
                              locationIsUnstable: Bool) -> StartupAction {
        switch registration {
        case .enabled:
            return wanted ? .none : .adoptEnabled
        case .needsApproval:
            return .none
        case .off:
            return wanted && !locationIsUnstable ? .register : .none
        }
    }
}
