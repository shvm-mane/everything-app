// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ClaudeReader: AgentHarnessReader {
    var provider: AgentProvider { .claude }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        if AgentLogParser.contains(line, #""type":"assistant""#) { return claudeAssistant(line, state: &state, now: now) }
        guard AgentLogParser.contains(line, #""type":"user""#) else { return [] }
        if AgentLogParser.contains(line, "[Request interrupted by user") || AgentLogParser.contains(line, "<local-command-std"),
           let json = AgentLogParser.object(line), json["type"] as? String == "user", endsTurn(json) {
            let open = state.turnOpen
            state.turnOpen = false
            return open ? [.turnEnded(nil, completed: false, duration: nil)] : []
        }
        if AgentLogParser.contains(line, #""toolEndsTurn":true"#), let json = AgentLogParser.object(line), json["type"] as? String == "user",
           json["toolEndsTurn"] as? Bool == true, json["isSidechain"] as? Bool != true {
            let open = state.turnOpen
            state.turnOpen = false
            return open ? [.turnEnded(AgentLogParser.timestamp(json["timestamp"]) ?? now, completed: true, duration: nil)] : []
        }
        if state.turnOpen {
            if !state.runningCommands.isEmpty, let json = AgentLogParser.object(line), json["type"] as? String == "user",
               json["isMeta"] as? Bool != true, json["isSidechain"] as? Bool != true {
                let content = (json["message"] as? [String: Any])?["content"]
                let results = (content as? [[String: Any]] ?? []).filter { $0["type"] as? String == "tool_result" }
                if !results.isEmpty {
                    for result in results {
                        if let id = result["tool_use_id"] as? String { state.runningCommands.remove(id) }
                    }
                } else {
                    state.runningCommands = []
                }
            }
            return [.turnActive(nil)]
        }
        if AgentLogParser.contains(line, #""isSidechain":true"#) { return [] }
        guard let json = AgentLogParser.object(line), json["type"] as? String == "user",
              json["isMeta"] as? Bool != true, json["isSidechain"] as? Bool != true else { return [] }
        adopt(json, into: &state)
        state.turnOpen = true
        state.runningCommands = []
        return [.turnBegan(AgentLogParser.timestamp(json["timestamp"]) ?? now)]
    }

    private func claudeAssistant(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let json = AgentLogParser.object(line), json["type"] as? String == "assistant",
              let message = json["message"] as? [String: Any] else { return [] }
        adopt(json, into: &state)
        let date = AgentLogParser.timestamp(json["timestamp"]) ?? now
        var entries: [AgentLogEntry] = []
        let model = AgentLogParser.native(message["model"] as? String ?? "")
        if let usage = message["usage"] as? [String: Any], !model.isEmpty, !model.hasPrefix("<") {
            state.model = model
            var billable = AgentBillable()
            billable.tokens = AgentTokens(
                input: AgentLogParser.int(usage["input_tokens"]),
                cacheWrite: AgentLogParser.int(usage["cache_creation_input_tokens"]),
                cacheRead: AgentLogParser.int(usage["cache_read_input_tokens"]),
                output: AgentLogParser.int(usage["output_tokens"]),
                reasoning: AgentLogParser.int((usage["output_tokens_details"] as? [String: Any])?["thinking_tokens"]))
            billable.longCacheWrite = AgentLogParser.int((usage["cache_creation"] as? [String: Any])?["ephemeral_1h_input_tokens"])
            billable.fast = usage["speed"] as? String == "fast"
            billable.domestic = usage["inference_geo"] as? String == "us"
            billable.webSearches = AgentLogParser.int((usage["server_tool_use"] as? [String: Any])?["web_search_requests"])
            let id = message["id"] as? String ?? ""
            let request = json["requestId"] as? String ?? ""
            let key = id.isEmpty && request.isEmpty
                ? "claude:\(state.session):\(date.timeIntervalSince1970)" : "claude:\(id):\(request)"
            let priced = AgentPricing.cost(billable, model: model)
            entries.append(.usage(key: key, record: AgentUsageRecord(
                provider: .claude, date: date, model: model, project: state.project, session: state.session,
                tokens: billable.tokens, cost: priced.cost, savings: priced.savings), billable: billable))
        }
        guard json["isSidechain"] as? Bool != true else { return entries }
        switch message["stop_reason"] as? String {
        case "end_turn", "stop_sequence", "max_tokens", "refusal":
            let failed = json["isApiErrorMessage"] as? Bool == true || model.hasPrefix("<")
            if state.turnOpen { entries.append(.turnEnded(date, completed: !failed, duration: nil)) }
            state.turnOpen = false
        default:
            for block in message["content"] as? [[String: Any]] ?? []
            where block["type"] as? String == "tool_use" && block["name"] as? String == "Bash" {
                if let id = block["id"] as? String { state.runningCommands.insert(id) }
            }
            entries.insert(state.turnOpen ? .turnActive(date) : .turnBegan(date), at: 0)
            state.turnOpen = true
        }
        return entries
    }

    private func endsTurn(_ json: [String: Any]) -> Bool {
        let content = (json["message"] as? [String: Any])?["content"]
        let texts: [String]
        if let text = content as? String {
            texts = [text]
        } else if let blocks = content as? [[String: Any]] {
            texts = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        } else {
            texts = []
        }
        return texts.contains {
            $0.hasPrefix("[Request interrupted by user") || $0.hasPrefix("<local-command-std")
        }
    }

    private func adopt(_ json: [String: Any], into state: inout AgentLogState) {
        if let session = json["sessionId"] as? String, !session.isEmpty { state.session = AgentLogParser.native(session) }
        if let cwd = json["cwd"] as? String, !cwd.isEmpty { state.project = AgentLogParser.projectName(cwd) }
    }
}
