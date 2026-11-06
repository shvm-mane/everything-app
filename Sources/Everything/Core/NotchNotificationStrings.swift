// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchNotificationStrings {
    let title: String
    let description: String
    let privacy: String
    let empty: String
    let waiting: String
    let open: String
    let dismiss: String
    let clearAll: String
    let unavailable: String
    let hideSystemBanner: String
    let hideSystemBannerHint: String
}

extension FeatureStrings {
    static func notchNotifications(_ language: AppLanguage) -> NotchNotificationStrings {
        switch language {
        case .enUS: return NotchNotificationStrings(
            title: "Notifications",
            description: "New system notifications in the Dynamic Island.",
            privacy: "Show new visible banners only. Messages stay in memory and are cleared when you lock this Mac or turn this off.",
            empty: "New notifications will appear here",
            waiting: "Waiting for the system notification service",
            open: "Open",
            dismiss: "Dismiss",
            clearAll: "Clear All",
            unavailable: "This notification can no longer accept this action.",
            hideSystemBanner: "Hide the system banner",
            hideSystemBannerHint: "Hide the original while the Dynamic Island shows it.")
        }
    }
}
