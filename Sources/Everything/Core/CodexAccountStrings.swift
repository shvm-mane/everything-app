// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct CodexAccountStrings {
    let title: String
    let explanation: String
    let accountName: String
    let remove: String
    let find: String
    let add: String
    let check: String
    let fallback: String
    let resetsNote: String
    let chooseFolder: String
    let invalidFolder: String
    let folderProblem: String
    let defaultName: String
    let defaultAccount: String
    let refreshHint: String
    let signIn: String
    let update: String
    let failed: String
}

extension FeatureStrings {
    static func codexAccounts(_ language: AppLanguage) -> CodexAccountStrings {
        switch language {
        case .enUS: return CodexAccountStrings(
            title: "Codex accounts",
            explanation: "Each CODEX_HOME folder you add gets its own limits card. While the AI Agents page is open, Codex checks each one about every five minutes with that folder’s own sign-in. No prompt is sent.",
            accountName: "Account name",
            remove: "Remove this account’s card",
            find: "Find local accounts",
            add: "Add folder…",
            check: "Check limits",
            fallback: "With no accounts added, Codex limits come from its local sessions.",
            resetsNote: "The Resets card still belongs to the default Codex account.",
            chooseFolder: "Choose a Codex folder",
            invalidFolder: "Choose a separate CODEX_HOME folder with config.toml or auth.json in it. The folder must be yours and not writable by others, and auth.json must be private and not a link. Codex may refresh its own sign-in and caches there.",
            folderProblem: "Choose this account’s folder again in Settings.",
            defaultName: "Default",
            defaultAccount: "Default account",
            refreshHint: "Refresh to check this account’s limits.",
            signIn: "Sign in with ChatGPT in this Codex folder.",
            update: "Update Codex to check limits.",
            failed: "Could not check limits. Try again.")
        }
    }
}
