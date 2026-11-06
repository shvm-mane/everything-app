// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ClaudeAccountStrings {
    let title: String
    let defaultAccount: String
    let chooseFolder: String
    let explanation: String
    let invalidFolder: String
    let unknownAccount: String
    let noLimits: String
    let signInHelp: String
}

extension FeatureStrings {
    static func claudeAccount(_ language: AppLanguage) -> ClaudeAccountStrings {
        switch language {
        case .enUS: return ClaudeAccountStrings(
            title: "Claude account", defaultAccount: "Default account", chooseFolder: "Choose account folder…",
            explanation: "Choose a profile already signed in to Claude Code. Usage comes from that profile’s sessions, and Claude Code checks its account’s limits. Changing this selection does not change the account in your other apps.",
            invalidFolder: "Choose an existing Claude Code profile folder that belongs to you and contains its own .claude.json file. The folder must not be writable by others, and the file must not be a link.",
            unknownAccount: "No account identified in this profile.",
            noLimits: "Claude Code has not returned limits for this account yet.",
            signInHelp: "How to sign in to another Claude account")
        }
    }
}
