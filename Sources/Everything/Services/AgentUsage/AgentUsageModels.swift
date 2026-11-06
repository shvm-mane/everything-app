// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentProvider: String, CaseIterable, Identifiable, Codable {
    case claude, codex, opencode, copilot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        case .copilot: return "GitHub Copilot"
        }
    }

    var symbol: String {
        switch self {
        case .claude: return "sparkle"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .opencode: return "terminal"
        case .copilot: return "infinity"
        }
    }

    var reportsLimits: Bool { self != .copilot }
}

struct AgentTokens: Equatable {
    var input = 0
    var cacheWrite = 0
    var cacheRead = 0
    var output = 0
    var reasoning = 0

    var total: Int { input + cacheWrite + cacheRead + output }
    var prompt: Int { input + cacheWrite + cacheRead }
    var cacheHitRate: Double? { prompt > 0 ? Double(cacheRead) / Double(prompt) : nil }

    static func += (lhs: inout AgentTokens, rhs: AgentTokens) {
        lhs.input += rhs.input
        lhs.cacheWrite += rhs.cacheWrite
        lhs.cacheRead += rhs.cacheRead
        lhs.output += rhs.output
        lhs.reasoning += rhs.reasoning
    }

    func merged(with other: AgentTokens) -> AgentTokens {
        AgentTokens(input: max(input, other.input), cacheWrite: max(cacheWrite, other.cacheWrite),
                    cacheRead: max(cacheRead, other.cacheRead), output: max(output, other.output),
                    reasoning: max(reasoning, other.reasoning))
    }
}

struct AgentUsageRecord: Equatable {
    let provider: AgentProvider
    let date: Date
    let model: String
    let project: String
    let session: String
    let requests: Int
    var tokens: AgentTokens
    var cost: Double?
    var savings: Double
    var reportedCost: Bool = false

    init(provider: AgentProvider, date: Date, model: String, project: String, session: String,
         requests: Int = 1, tokens: AgentTokens, cost: Double?, savings: Double, reportedCost: Bool = false) {
        self.provider = provider
        self.date = date
        self.model = model
        self.project = project
        self.session = session
        self.requests = requests
        self.tokens = tokens
        self.cost = cost
        self.savings = savings
        self.reportedCost = reportedCost
    }
}

struct AgentLimitWindow: Equatable, Identifiable {
    enum Kind: String {
        case session, weekly, other
    }

    let id: String
    let kind: Kind
    let minutes: Int?
    let scope: String?
    let usedPercent: Double
    let resetsAt: Date?
    var estimatedResetsAt: Date? = nil

    var usedFraction: Double { min(1, max(0, usedPercent / 100)) }
    var remainingFraction: Double { 1 - usedFraction }
}

struct AgentLimits: Equatable {
    enum Source: Equatable {
        case claudeApp
        case sessionLog
        case account
    }

    let provider: AgentProvider
    var windows: [AgentLimitWindow]
    let observedAt: Date
    let source: Source
}

struct AgentPlan: Equatable {
    let name: String
    let monthlyPrice: Double?
}

struct AgentLiveSession: Equatable, Identifiable {
    let id: String
    let provider: AgentProvider
    let started: Date
    var lastActivity: Date
    var model: String
    var project: String
    var tokens: AgentTokens
    var cost: Double
}

enum AgentUsageEvent: Equatable {
    case finished(provider: AgentProvider, duration: TimeInterval, cost: Double, tokens: Int, project: String)
    case limitWarning(provider: AgentProvider, window: AgentLimitWindow)
    case limitReset(provider: AgentProvider, window: AgentLimitWindow)
    case budgetReached(spent: Double, budget: Double)
}
