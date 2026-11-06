// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AppInfo {
    static let name = "EVERYTHING"
    static let copyright = "© 2026 EVERYTHING"
    static let websiteURL = URL(string: "https://vorssaint.com")!
    static let repositoryURL = URL(string: "https://github.com/vorssaint/vorssaint-utils")!
    static let coffeeURL = URL(string: "https://buymeacoffee.com/vorssaint")!
    static let discordURL = URL(string: "https://discord.gg/M6BwWH4BJp")!
    static let socialURL = URL(string: "https://x.com/vorssaint")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static var isDeveloperBuild: Bool {
        (Bundle.main.bundleIdentifier ?? "").hasSuffix(".dev")
    }

    static var isBeta: Bool {
        if isDeveloperBuild && UserDefaults.standard.bool(forKey: DefaultsKey.simulateBetaUI) {
            return true
        }
        let v = version.lowercased()
        return v.contains("-beta") || v.contains("-rc") || v.contains("-alpha")
    }

    static var buildCommit: String? {
        Bundle.main.object(forInfoDictionaryKey: "VorssaintBuildCommit") as? String
    }
}
