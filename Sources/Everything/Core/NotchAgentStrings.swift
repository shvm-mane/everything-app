// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchAgentStrings {
    let title: String
    let hubDescription: String
    let settingsDescription: String
    let restingTitle: String
    let limitsCard: String
    let spendCard: String
    let liveCard: String
    let trendCard: String
    let modelsCard: String
    let projectsCard: String
    let activityCard: String
    let today: String
    let week: String
    let month: String
    let session: String
    let weekly: String
    let estimated: String
    let claudeLimitsHint: String
    let waitingForLimits: String
    let noSession: String
    let apiValue: String
    let tokensFormat: String
    let cachedFormat: String
    let writtenFormat: String
    let savedFormat: String
    let planMultipleFormat: String
    let idle: String
    let noActivity: String
    let empty: String
    let loading: String
    let noCards: String
    let unpriced: String
    let streak: String
    let activeDays: String
    let busiestDay: String
    let finishedFormat: String
    let limitRenewed: String
    let budgetTitle: String
    let leftFormat: String
    let usedFormat: String
    let agents: String
    let found: String
    let notFound: String
    let cardsTitle: String
    let cardsHint: String
    let limitsAs: String
    let remaining: String
    let used: String
    let limitFocus: String
    let mostUsed: String
    let liveTitle: String
    let liveActivity: String
    let readout: String
    let readoutElapsed: String
    let readoutTokens: String
    let readoutLimit: String
    let alerts: String
    let finishAlert: String
    let finishAfter: String
    let anyLength: String
    let limitAlert: String
    let limitAt: String
    let budget: String
    let off: String
    let updatedFormat: String
    let claudeLimitsTitle: String
    let claudeLimitsCurrentFormat: String
    let claudeLimitsStaleFormat: String
    let claudeLimitsMenuBar: String
    let claudeLimitsNoApp: String
    let claudeLimitsPrivacy: String
    let claudeCodeMissing: String
    let claudeCodeSignedOut: String
    let claudeCodeOutdated: String
    let claudeCodeUnreachable: String
    let openClaude: String
    let getClaude: String
    let priceUpdates: String
    let priceUpdatesHint: String
    let pricesFromFormat: String
    let valueNote: String
    let resetsCard: String
    let useReset: String
    let resetConfirm: String
    let confirmReset: String
    let resetting: String
    let resetDone: String
    let resetNotNeeded: String
    let resetTaken: String
    let resetFailed: String
    let resetsNone: String
    let resetsExpiryFormat: String
    let resetsNeedCodex: String
    let resetsSignIn: String
    let resetsUpdate: String
    let resetsCheckFailed: String
    let resetsHelp: String

    func tokens(_ count: String) -> String { String(format: tokensFormat, count) }
    func cached(_ share: String) -> String { String(format: cachedFormat, share) }
    func written(_ count: String) -> String { String(format: writtenFormat, count) }
    func saved(_ amount: String) -> String { String(format: savedFormat, amount) }
    func planMultiple(_ multiple: String, plan: String) -> String { String(format: planMultipleFormat, multiple, plan) }
    func finished(_ agent: String) -> String { String(format: finishedFormat, agent) }
    func left(_ share: String) -> String { String(format: leftFormat, share) }
    func usedShare(_ share: String) -> String { String(format: usedFormat, share) }
    func updated(_ when: String) -> String { String(format: updatedFormat, when) }
    func claudeLimitsCurrent(_ when: String) -> String { String(format: claudeLimitsCurrentFormat, when) }
    func claudeLimitsStale(_ when: String) -> String { String(format: claudeLimitsStaleFormat, when) }
    func pricesFrom(_ day: String) -> String { String(format: pricesFromFormat, day) }
    func resetsExpiry(_ when: String) -> String { String(format: resetsExpiryFormat, when) }

    func claudeCode(_ failure: AgentClaudeServer.Failure) -> String {
        switch failure {
        case .missing: return claudeCodeMissing
        case .needsSignIn: return claudeCodeSignedOut
        case .outdated: return claudeCodeOutdated
        case .unreachable: return claudeCodeUnreachable
        }
    }

    func period(_ period: AgentPeriod) -> String {
        switch period {
        case .today: return today
        case .week: return week
        case .month: return month
        }
    }

    func card(_ card: NotchAgentCard) -> String {
        switch card {
        case .limits: return limitsCard
        case .spend: return spendCard
        case .live: return liveCard
        case .trend: return trendCard
        case .models: return modelsCard
        case .projects: return projectsCard
        case .activity: return activityCard
        case .resets: return resetsCard
        }
    }

    func readout(_ readout: NotchAgentReadout) -> String {
        switch readout {
        case .elapsed: return readoutElapsed
        case .tokens: return readoutTokens
        case .cost: return apiValue.prefix(1).uppercased() + apiValue.dropFirst()
        case .limit: return readoutLimit
        }
    }

    func limitFocus(_ focus: NotchAgentLimitFocus) -> String {
        switch focus {
        case .mostUsed: return mostUsed
        case .session: return session
        case .weekly: return weekly
        }
    }
}

extension FeatureStrings {
    static func notchAgents(_ language: AppLanguage) -> NotchAgentStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension NotchAgentStrings {
    static let enUS = NotchAgentStrings(
        title: "Claude Pro Usage",
        hubDescription: "Follow plan limits, tokens, API value and the work in progress of Claude, Codex, OpenCode and GitHub Copilot in the Dynamic Island.",
        settingsDescription: "Reads the usage Claude Code, Codex, OpenCode and GitHub Copilot record on this Mac and the plan limits the Claude app saves. Prompts, replies and files are never kept, and your usage never leaves your Mac.",
        restingTitle: "AI limits",
        limitsCard: "Limits",
        spendCard: "Spending",
        liveCard: "Now",
        trendCard: "Trend",
        modelsCard: "Models",
        projectsCard: "Projects",
        activityCard: "Activity",
        today: "Today",
        week: "7 days",
        month: "30 days",
        session: "Session",
        weekly: "Week",
        estimated: "Estimated from this Mac",
        claudeLimitsHint: "Set up plan limits…",
        waitingForLimits: "Limits appear after the next reply",
        noSession: "No session running",
        apiValue: "API value",
        tokensFormat: "%@ tokens",
        cachedFormat: "%@ from cache",
        writtenFormat: "%@ written",
        savedFormat: "%@ saved by the cache",
        planMultipleFormat: "%1$@ the price of %2$@",
        idle: "Idle",
        noActivity: "Nothing in this period",
        empty: "No usage from Claude Code, Codex, OpenCode or GitHub Copilot yet. It appears here as soon as any of them works on this Mac.",
        loading: "Reading usage…",
        noCards: "Choose what this page shows in Dynamic Island settings.",
        unpriced: "Some models have no known price, so this is a minimum.",
        streak: "Days in a row",
        activeDays: "Active days",
        busiestDay: "Busiest day",
        finishedFormat: "%@ finished",
        limitRenewed: "Limit renewed",
        budgetTitle: "Daily budget",
        leftFormat: "%@ left",
        usedFormat: "%@ used",
        agents: "Agents",
        found: "Found on this Mac",
        notFound: "Not found on this Mac",
        cardsTitle: "Cards",
        cardsHint: "Drag to reorder. Charts take the full width of the island.",
        limitsAs: "Show limits as",
        remaining: "Left",
        used: "Used",
        limitFocus: "Limit to show",
        mostUsed: "Most used",
        liveTitle: "While an agent works",
        liveActivity: "Show it in the closed Dynamic Island",
        readout: "Beside the camera",
        readoutElapsed: "Time",
        readoutTokens: "Tokens written",
        readoutLimit: "Limit",
        alerts: "Alerts",
        finishAlert: "When a task finishes",
        finishAfter: "For tasks longer than",
        anyLength: "Any length",
        limitAlert: "Near a plan limit",
        limitAt: "Warn at",
        budget: "Daily API value budget",
        off: "Off",
        updatedFormat: "Updated %@",
        claudeLimitsTitle: "Claude plan limits",
        claudeLimitsCurrentFormat: "Read from the Claude app, updated %@",
        claudeLimitsStaleFormat: "The Claude app last checked them %@.",
        claudeLimitsMenuBar: "Claude checks your limits only while its icon is in the menu bar. Turn the icon on in the Claude app settings, and your limits appear here within minutes.",
        claudeLimitsNoApp: "Plan limits come from Claude Code or from the Claude app, which is not on this Mac. Until then, the 5-hour session is estimated from Claude Code activity.",
        claudeLimitsPrivacy: "Claude Code checks your account’s limits, including use on other machines, with its own sign-in, which EVERYTHING never reads. No prompt is sent. When it cannot check, the percentages the Claude app saves on this Mac are used.",
        claudeCodeMissing: "Claude Code was not found on this Mac.",
        claudeCodeSignedOut: "Sign in to Claude Code so it can check your account’s limits.",
        claudeCodeOutdated: "Update Claude Code so it can check your account’s limits.",
        claudeCodeUnreachable: "Claude Code could not check your account’s limits. It tries again later.",
        openClaude: "Open Claude",
        getClaude: "Get the Claude app",
        priceUpdates: "Keep prices up to date",
        priceUpdatesHint: "Downloads the public price list from GitHub once a day, so new models get an API value without an app update. Nothing about your usage is sent.",
        pricesFromFormat: "Price list of %@",
        valueNote: "API value is what the same work would cost at API list prices. Plans charge a fixed price instead.",
        resetsCard: "Resets",
        useReset: "Use a reset",
        resetConfirm: "Reset the session and weekly limits now?",
        confirmReset: "Reset",
        resetting: "Resetting…",
        resetDone: "Limits reset",
        resetNotNeeded: "Your usage doesn’t need a reset yet",
        resetTaken: "That reset was already used",
        resetFailed: "Couldn’t use the reset",
        resetsNone: "No resets available",
        resetsExpiryFormat: "Next expires %@",
        resetsNeedCodex: "Needs the Codex app or CLI",
        resetsSignIn: "Sign in to Codex with a plan to see resets",
        resetsUpdate: "Update Codex to use resets here",
        resetsCheckFailed: "Couldn’t check resets",
        resetsHelp: "A reset renews the Codex session and weekly limits at once. Codex checks your resets with its own sign-in, which EVERYTHING never reads.")

}
