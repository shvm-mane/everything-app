// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct OpenCodeReader: AgentHarnessReader {
    var provider: AgentProvider { .opencode }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard AgentLogParser.contains(line, #""role":""#) || AgentLogParser.contains(line, #""type":"reset""#) else { return [] }
        guard let json = AgentLogParser.object(line) else { return [] }
        if json["type"] as? String == "reset" {
            state.openCodeSessions.removeAll()
            state.turnOpen = false
            return [.reset(now)]
        }
        guard let role = json["role"] as? String else { return [] }
        let id = json["id"] as? String ?? ""
        let session = json["session_id"] as? String ?? ""
        let sessionID = session.isEmpty ? state.session : AgentLogParser.native(session)
        state.session = sessionID
        state.parentSession = json["parent_session_id"] as? String ?? ""

        var sessionState = state.openCodeSessions[sessionID] ?? OpenCodeSessionState()

        let cwd = (json["path"] as? [String: Any])?["cwd"] as? String ?? json["directory"] as? String ?? ""
        if !cwd.isEmpty {
            sessionState.project = AgentLogParser.projectName(cwd)
        }

        let timeCreated = (json["time"] as? [String: Any])?["created"] ?? json["time_created"]
        let date = AgentLogParser.seconds(timeCreated) ?? now
        if state.openCodeSessions[sessionID] == nil {
            state.openCodeSessions = state.openCodeSessions.filter { _, kept in
                !kept.writingReplyID.isEmpty
                    || date.timeIntervalSince(kept.lastActivity ?? date) < NotchAgentSupport.idleTurn
            }
        }
        let lastActivity = sessionState.lastActivity
        sessionState.lastActivity = max(lastActivity ?? date, date)

        switch role {
        case "user":
            if !id.isEmpty {
                if sessionState.seenUserMessageIDs.contains(id) { return [] }
                remember(id, in: &sessionState.seenUserMessageIDs)
                sessionState.activeUserMessageID = id
            }
            var entries: [AgentLogEntry] = []
            let quiet: Bool
            if let settled = sessionState.settledAt {
                quiet = date.timeIntervalSince(settled) >= AgentLogParser.openCodeSettle
            } else if sessionState.writingReplyID.isEmpty, let lastActivity {
                quiet = date.timeIntervalSince(lastActivity) >= NotchAgentSupport.idleTurn
            } else {
                quiet = false
            }
            sessionState.settledAt = nil
            sessionState.activePromptDate = date
            if sessionState.turnOpen && !quiet {
                entries.append(.turnActive(date))
            } else {
                if sessionState.turnOpen {
                    entries.append(.turnEnded(lastActivity, completed: false, duration: nil))
                }
                sessionState.turnOpen = true
                sessionState.turnStarted = date
                entries.append(.turnBegan(date))
            }
            let userModel = json["model_id"] as? String
                ?? json["modelID"] as? String
                ?? (json["model"] as? [String: Any])?["modelID"] as? String
                ?? (json["model"] as? [String: Any])?["id"] as? String
                ?? json["model"] as? String
            if let userModel, !userModel.isEmpty {
                sessionState.model = AgentLogParser.native(userModel)
            }
            state.openCodeSessions[sessionID] = sessionState
            state.project = sessionState.project
            state.model = sessionState.model
            state.turnOpen = true
            return entries

        case "assistant":
            let rawModel = json["model_id"] as? String
                ?? json["modelID"] as? String
                ?? (json["model"] as? [String: Any])?["modelID"] as? String
                ?? (json["model"] as? [String: Any])?["id"] as? String
                ?? json["model"] as? String
            if let rawModel, !rawModel.isEmpty {
                sessionState.model = AgentLogParser.native(rawModel)
            }

            let parentID = json["parentID"] as? String ?? ""
            let isAlreadyCompleted = (!id.isEmpty && sessionState.completedAssistantMessageIDs.contains(id))
                || (!parentID.isEmpty && sessionState.completedUserMessageIDs.contains(parentID))
            let matchesActivePrompt = parentID.isEmpty || parentID == sessionState.activeUserMessageID

            let timeCompleted = (json["time"] as? [String: Any])?["completed"]
            let completed = AgentLogParser.seconds(timeCompleted)
            let hasError = json["error"].map { !($0 is NSNull) } ?? false
            let finish = json["finish"] as? String
            if let completed { sessionState.lastActivity = max(sessionState.lastActivity ?? completed, completed) }
            if let settled = sessionState.settledAt, date >= settled { sessionState.settledAt = nil }

            var entries: [AgentLogEntry] = []
            if !id.isEmpty, !sessionState.writingReplyID.isEmpty, sessionState.writingReplyID != id,
               sessionState.turnOpen, !parentID.isEmpty, parentID == sessionState.activeUserMessageID,
               let prompt = sessionState.activePromptDate, let started = sessionState.turnStarted, prompt > started {
                entries.append(.turnEnded(nil, completed: false, duration: nil))
                entries.append(.turnBegan(prompt))
                sessionState.turnStarted = prompt
            }
            if completed == nil && finish == nil && !hasError && !id.isEmpty {
                sessionState.writingReplyID = id
            } else if sessionState.writingReplyID == id {
                sessionState.writingReplyID = ""
            }
            if !isAlreadyCompleted && matchesActivePrompt && !sessionState.turnOpen {
                sessionState.turnOpen = true
                sessionState.turnStarted = date
                entries.append(.turnBegan(date))
            }
            if let usage = openCodeUsage(json, id: id, session: sessionID, date: date,
                                         model: sessionState.model, project: sessionState.project) {
                entries.append(usage)
            }

            let ends: Bool
            if hasError {
                ends = true
            } else if let finish {
                ends = !["tool-calls", "unknown"].contains(finish)
                    && json["tool_calls"] as? Bool != true && json["auto_compaction"] as? Bool != true
            } else {
                ends = completed != nil
            }

            if ends {
                if !isAlreadyCompleted && matchesActivePrompt && sessionState.turnOpen {
                    let endDate = completed ?? AgentLogParser.seconds(json["time_updated"]) ?? date
                    var duration: TimeInterval?
                    if let turnStarted = sessionState.turnStarted {
                        if endDate >= turnStarted {
                            duration = endDate.timeIntervalSince(turnStarted)
                        }
                    } else if endDate >= date {
                        duration = endDate.timeIntervalSince(date)
                    }
                    sessionState.turnOpen = false
                    sessionState.turnStarted = nil
                    sessionState.activeUserMessageID = ""
                    sessionState.settledAt = nil
                    entries.append(.turnEnded(endDate, completed: !hasError, duration: duration))
                }
                if !id.isEmpty { remember(id, in: &sessionState.completedAssistantMessageIDs) }
                if !parentID.isEmpty { remember(parentID, in: &sessionState.completedUserMessageIDs) }
            } else if !isAlreadyCompleted && matchesActivePrompt {
                if let completed, sessionState.turnOpen {
                    if json["version"] as? Int == 2 {
                        entries.append(.turnActive(completed))
                    } else {
                        sessionState.settledAt = completed
                        entries.append(.turnSettled(completed))
                    }
                } else {
                    entries.append(.turnActive(date))
                }
            }
            state.openCodeSessions[sessionID] = sessionState
            state.project = sessionState.project
            state.model = sessionState.model
            state.turnOpen = sessionState.turnOpen
            return entries

        case "compaction":
            let ownModel = ((json["model"] as? [String: Any])?["id"] as? String).flatMap { $0.isEmpty ? nil : AgentLogParser.native($0) }
            var entries: [AgentLogEntry] = []
            if let usage = openCodeUsage(json, id: id, session: sessionID, date: date,
                                         model: ownModel ?? sessionState.model, project: sessionState.project) {
                entries.append(usage)
            }
            if sessionState.turnOpen {
                let moment = max(date, AgentLogParser.seconds(json["time_updated"]) ?? date)
                sessionState.lastActivity = max(sessionState.lastActivity ?? moment, moment)
                sessionState.settledAt = nil
                entries.append(.turnActive(moment))
            }
            state.openCodeSessions[sessionID] = sessionState
            state.project = sessionState.project
            state.model = sessionState.model
            state.turnOpen = sessionState.turnOpen
            return entries

        case "idle":
            sessionState.writingReplyID = ""
            sessionState.settledAt = nil
            var entries: [AgentLogEntry] = []
            if sessionState.turnOpen {
                var duration: TimeInterval?
                if let turnStarted = sessionState.turnStarted, date >= turnStarted {
                    duration = date.timeIntervalSince(turnStarted)
                }
                sessionState.turnOpen = false
                sessionState.turnStarted = nil
                sessionState.activeUserMessageID = ""
                entries.append(.turnEnded(date, completed: json["outcome"] as? String == "succeeded",
                                          duration: duration))
            }
            state.openCodeSessions[sessionID] = sessionState
            state.turnOpen = false
            return entries

        default:
            return []
        }
    }

    private func remember(_ id: String, in ids: inout Set<String>) {
        if ids.count > 100 { ids.removeFirst() }
        ids.insert(id)
    }

    private func openCodeUsage(_ json: [String: Any], id: String, session: String, date: Date,
                               model: String, project: String) -> AgentLogEntry? {
        let tokensDict = json["tokens"] as? [String: Any] ?? [:]
        let reasoning = AgentLogParser.int(tokensDict["reasoning"])
        let cacheDict = tokensDict["cache"] as? [String: Any] ?? [:]
        let tokens = AgentTokens(input: AgentLogParser.int(tokensDict["input"]), cacheWrite: AgentLogParser.int(cacheDict["write"]),
                                 cacheRead: AgentLogParser.int(cacheDict["read"]),
                                 output: AgentLogParser.int(tokensDict["output"]) + reasoning, reasoning: reasoning)
        let recordedCost = (json["cost"] as? NSNumber)?.doubleValue
        guard tokens.total > 0 || (recordedCost ?? 0) > 0 else { return nil }
        let billable = AgentBillable(tokens: tokens)
        let priced = AgentPricing.cost(billable, model: model)
        let cost: Double?
        let isReported: Bool
        if let calculated = priced.cost {
            cost = calculated
            isReported = false
        } else if let recordedCost {
            cost = recordedCost
            isReported = recordedCost > 0
        } else {
            cost = nil
            isReported = false
        }
        let key = "opencode:\(session):\(id.isEmpty ? "\(date.timeIntervalSince1970)" : id)"
        let record = AgentUsageRecord(provider: .opencode, date: date, model: model, project: project,
                                      session: session, tokens: tokens, cost: cost, savings: priced.savings,
                                      reportedCost: isReported)
        return .usage(key: key, record: record, billable: billable)
    }
}
