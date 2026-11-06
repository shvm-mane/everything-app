// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

struct AgentCodexReset: Equatable, Identifiable {
    let id: String
    let expiresAt: Date?
}

struct AgentCodexResetSummary: Equatable {
    let available: Int
    let resets: [AgentCodexReset]
    let limits: AgentLimits?
    let checkedAt: Date

    var nextExpiry: Date? { resets.lazy.compactMap(\.expiresAt).min() }
}

enum AgentCodexServer {
    enum Failure: Error, Equatable {
        case missing
        case needsSignIn
        case outdated
        case unreachable
        case refused
    }

    enum Outcome: String, Equatable {
        case reset, nothingToReset, noCredit, alreadyRedeemed
    }

    static let appIdentifiers = ["com.openai.codex", "com.openai.chat"]
    static let checkTimeout: TimeInterval = 20
    static let redeemTimeout: TimeInterval = 30

    static func candidates(apps: [URL], home: URL, searchPath: String? = nil) -> [URL] {
        let bundled = apps.flatMap { app in
            ["Contents/Resources/codex-cli/bin/codex", "Contents/Resources/codex"].map {
                app.appending(path: $0, directoryHint: .notDirectory)
            }
        }
        let folders = [home.appending(path: ".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
            + (searchPath ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        return bundled + folders.map { URL(fileURLWithPath: $0, isDirectory: true).appending(path: "codex") }
    }

    static func executable(apps: [URL], home: URL, searchPath: String? = nil) -> URL? {
        candidates(apps: apps, home: home, searchPath: searchPath).first { url in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && !directory.boolValue
                && FileManager.default.isExecutableFile(atPath: url.path)
        }
    }

    static func loginShellPath() -> String? {
        HomebrewEnvironment.loginShellExports(shellPath: HomebrewCommandBuilder.currentShellPath)["PATH"]
    }

    static func environment(for executable: URL, searchPath: String?,
                            base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base
        let folders = [executable.deletingLastPathComponent().path]
            + (searchPath.map { [$0] } ?? ["/opt/homebrew/bin", "/usr/local/bin"])
            + [base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]
        environment["PATH"] = folders.joined(separator: ":")
        return environment
    }

    // MARK: Conversations

    static func check(_ executable: URL, environment: [String: String]) -> Result<AgentCodexResetSummary, Failure> {
        guard let conversation = AgentCodexConversation(executable, environment: environment,
                                                        timeout: checkTimeout) else { return .failure(.unreachable) }
        defer { conversation.end() }
        return conversation.start()
            .flatMap { _ in conversation.ask("account/read") }
            .flatMap { account -> Result<Void, Failure> in
                if let failure = signInFailure(account) { return .failure(failure) }
                return .success(())
            }
            .flatMap { _ in conversation.summary() }
    }

    static func redeem(_ executable: URL, environment: [String: String], credit: String?,
                       key: String) -> (outcome: Result<Outcome, Failure>, summary: AgentCodexResetSummary?) {
        guard let conversation = AgentCodexConversation(executable, environment: environment,
                                                        timeout: redeemTimeout) else { return (.failure(.unreachable), nil) }
        defer { conversation.end() }
        var params: [String: Any] = ["idempotencyKey": key]
        if let credit { params["creditId"] = credit }
        let outcome = conversation.start()
            .flatMap { _ in conversation.ask("account/rateLimitResetCredit/consume", params) }
            .flatMap { result -> Result<Outcome, Failure> in
                guard let outcome = Self.outcome(result) else { return .failure(.unreachable) }
                return .success(outcome)
            }
        return (outcome, try? conversation.summary().get())
    }

    // MARK: Answers

    static func signInFailure(_ result: [String: Any]) -> Failure? {
        (result["account"] as? [String: Any])?["type"] as? String == "chatgpt" ? nil : .needsSignIn
    }

    static func summary(_ result: [String: Any], now: Date) -> AgentCodexResetSummary? {
        guard result.keys.contains("rateLimitResetCredits") else { return nil }
        let credits = result["rateLimitResetCredits"] as? [String: Any]
        let listed = (credits?["credits"] as? [[String: Any]] ?? []).compactMap { credit -> AgentCodexReset? in
            guard let id = credit["id"] as? String, !id.isEmpty,
                  (credit["status"] as? String ?? "available") == "available" else { return nil }
            let expires = AgentLogParser.seconds(credit["expiresAt"])
            if let expires, expires <= now { return nil }
            return AgentCodexReset(id: id, expiresAt: expires)
        }
        let resets = listed.sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
        let count = max(resets.count, AgentLogParser.int(credits?["availableCount"]))
        return AgentCodexResetSummary(available: count, resets: resets, limits: limits(result, observed: now),
                                      checkedAt: now)
    }

    static func limits(_ result: [String: Any], observed: Date) -> AgentLimits? {
        var snapshot = (result["rateLimitsByLimitId"] as? [String: Any])?["codex"] as? [String: Any]
        if snapshot == nil, let single = result["rateLimits"] as? [String: Any],
           AgentLogParser.isMainBucket(["limit_id": single["limitId"] as? String ?? ""]) {
            snapshot = single
        }
        guard let snapshot,
              let windows = AgentLogParser.codexWindows(snapshot, observed: observed,
                                                        keys: ("usedPercent", "windowDurationMins", "resetsAt",
                                                               "individualLimit", "remainingPercent")),
              !windows.isEmpty else { return nil }
        return AgentLimits(provider: .codex, windows: windows, observedAt: observed, source: .account)
    }

    static func outcome(_ result: [String: Any]) -> Outcome? {
        (result["outcome"] as? String).flatMap(Outcome.init(rawValue:))
    }

    static func failure(_ error: Any?) -> Failure {
        let error = error as? [String: Any]
        let message = (error?["message"] as? String ?? "").lowercased()
        if (error?["code"] as? NSNumber)?.intValue == -32601 || message.contains("unknown variant")
            || message.contains("method not found") { return .outdated }
        if message.contains("authentication") || message.contains("not logged in") { return .needsSignIn }
        return .refused
    }
}

final class AgentCodexConversation: AgentCLIConversation {
    private var lastID = 0
    init?(_ executable: URL, environment: [String: String], timeout: TimeInterval,
          cancellation: BoundedProcessCancellation? = nil) {
        super.init(executable, arguments: ["-c", "features.plugins=false", "app-server"],
                   environment: environment, timeout: timeout, cancellation: cancellation)
    }

    func start() -> Result<Void, AgentCodexServer.Failure> {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let client: [String: Any] = ["name": "vorssaint", "title": "EVERYTHING", "version": version]
        return ask("initialize", ["clientInfo": client, "capabilities": NSNull()])
            .flatMap { _ -> Result<Void, AgentCodexServer.Failure> in
                send(["method": "initialized"]) ? .success(()) : .failure(.unreachable)
            }
    }

    func ask(_ method: String, _ params: [String: Any] = [:]) -> Result<[String: Any], AgentCodexServer.Failure> {
        lastID += 1
        let id = lastID
        guard send(["id": id, "method": method, "params": params]) else { return .failure(.unreachable) }
        while let message = next() {
            guard message["method"] == nil, (message["id"] as? NSNumber)?.intValue == id else { continue }
            if let result = message["result"] as? [String: Any] { return .success(result) }
            return .failure(AgentCodexServer.failure(message["error"]))
        }
        return .failure(.unreachable)
    }

    func summary(now: Date = Date()) -> Result<AgentCodexResetSummary, AgentCodexServer.Failure> {
        ask("account/rateLimits/read").flatMap { result -> Result<AgentCodexResetSummary, AgentCodexServer.Failure> in
            guard let summary = AgentCodexServer.summary(result, now: now) else { return .failure(.outdated) }
            return .success(summary)
        }
    }

}
