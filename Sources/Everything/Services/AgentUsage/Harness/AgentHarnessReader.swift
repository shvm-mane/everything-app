// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

protocol AgentHarnessReader {
    var provider: AgentProvider { get }
    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry]
    var readsFullHistoryFirst: Bool { get }
}

extension AgentHarnessReader {
    var readsFullHistoryFirst: Bool { false }
}

extension AgentProvider {
    var reader: any AgentHarnessReader {
        switch self {
        case .claude: ClaudeReader()
        case .codex: CodexReader()
        case .opencode: OpenCodeReader()
        case .copilot: CopilotReader()
        }
    }
}
