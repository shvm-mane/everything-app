// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentClaudeServer {
    enum Failure: Error, Equatable {
        case missing, needsSignIn, outdated, unreachable
    }
    struct Summary: Equatable {
        let limits: AgentLimits
        let identity: ClaudeAccountProfile.Identity?
    }
    static let timeout: TimeInterval = 25
    static let freshness: TimeInterval = 60
    static let backgroundFreshness: TimeInterval = 5 * 60
    static let retryAfter: TimeInterval = 5 * 60
    static let settledRetry: TimeInterval = 30 * 60
    static let reuse: TimeInterval = 60
    static let optOuts = ["DISABLE_TELEMETRY", "DISABLE_ERROR_REPORTING", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"]
    static let networkSettings = ["HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY", "NODE_EXTRA_CA_CERTS"]

    static func interval(after failure: Failure?, repeated: Int = 1, pageVisible: Bool) -> TimeInterval {
        switch failure {
        case nil: return pageVisible ? freshness : backgroundFreshness
        case .unreachable?: return min(settledRetry, retryAfter * Double(1 << min(3, max(0, repeated - 1))))
        case .missing?, .needsSignIn?, .outdated?: return settledRetry
        }
    }

    static func candidates(home: URL, searchPath: String? = nil) -> [URL] {
        var folders: [String] = [home.appending(path: ".local/bin").path,
                                 home.appending(path: ".claude/local").path, "/opt/homebrew/bin", "/usr/local/bin"]
        folders += (searchPath ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        folders += toolFolders(home: home)
        return folders.map { URL(fileURLWithPath: $0, isDirectory: true).appending(path: "claude") }
    }

    static func toolFolders(home: URL) -> [String] {
        let path = { (relative: String) -> String in home.appending(path: relative).path }
        let fnm: [String] = ["Library/Application Support/fnm", ".local/share/fnm", ".fnm"].map(path)
        var folders: [String] = [path(".volta/bin")]
        folders += fnm.map { $0 + "/aliases/default/bin" }
        folders += newest(in: path(".nvm/versions/node")).map { $0 + "/bin" }
        folders += fnm.flatMap { root in newest(in: root + "/node-versions").map { $0 + "/installation/bin" } }
        folders += newest(in: path(".asdf/installs/nodejs")).map { $0 + "/bin" }
        folders += newest(in: path(".local/share/mise/installs/node")).map { $0 + "/bin" }
        folders += [path(".bun/bin"), path("Library/pnpm"), path(".local/share/pnpm"), path(".npm-global/bin")]
        return folders
    }

    private static func newest(in folder: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return names.compactMap { name -> (version: [Int], path: String)? in
            let parts = (name.hasPrefix("v") ? String(name.dropFirst()) : name).split(separator: ".").map { Int($0) }
            guard !parts.isEmpty, !parts.contains(nil) else { return nil }
            return (parts.compactMap { $0 }, folder + "/" + name)
        }
        .sorted { $1.version.lexicographicallyPrecedes($0.version) }
        .map(\.path)
    }

    static func searchPath(after path: String, home: URL) -> String {
        ([path] + toolFolders(home: home)).joined(separator: ":")
    }

    static func executable(home: URL, searchPath: String? = nil) -> URL? {
        candidates(home: home, searchPath: searchPath).first {
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: $0.path, isDirectory: &directory) && !directory.boolValue
                && FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    static func environment(_ base: [String: String], home: URL,
                            profile: ClaudeAccountProfile = ClaudeAccountProfile()) -> [String: String] {
        var environment = base.filter {
            optOuts.contains($0.key) || (!$0.key.hasPrefix("CLAUDE_") && !$0.key.hasPrefix("ANTHROPIC_"))
        }
        environment.removeValue(forKey: "CLAUDECODE")
        if !profile.isDefault { environment["CLAUDE_CONFIG_DIR"] = profile.directory }
        environment["DISABLE_AUTOUPDATER"] = "1"
        guard let data = try? Data(contentsOf: profile.configurationURL(home: home).appending(path: "settings.json")),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let settings = json["env"] as? [String: Any] else { return environment }
        for key in optOuts + networkSettings {
            switch settings[key] {
            case let text as String: environment[key] = text
            case let number as NSNumber:
                environment[key] = CFGetTypeID(number) == CFBooleanGetTypeID()
                    ? (number.boolValue ? "true" : "false") : number.stringValue
            default: break
            }
        }
        return environment
    }

    static func limits(_ result: [String: Any], observed: Date) -> AgentLimits? {
        guard result["rate_limits_available"] as? Bool == true,
              let limits = result["rate_limits"] as? [String: Any] else { return nil }
        let windows: [AgentLimitWindow] = [
            ("five_hour", AgentLimitWindow.Kind.session, 300, nil as String?),
            ("seven_day", .weekly, 10_080, nil),
            ("seven_day_opus", .weekly, 10_080, "Opus"),
            ("seven_day_sonnet", .weekly, 10_080, "Sonnet")].compactMap { key, kind, minutes, scope in
                guard let window = limits[key] as? [String: Any],
                      let percent = window["utilization"] as? NSNumber,
                      CFGetTypeID(percent) != CFBooleanGetTypeID(), percent.doubleValue.isFinite else { return nil }
                let resets = window["resets_at"].flatMap { $0 is NSNull ? nil : $0 }
                let end = (resets as? String).flatMap(AgentTimestamp.parse)
                guard resets == nil || end.map({ $0 > observed }) == true else { return nil }
                let id = ["five_hour": "fh", "seven_day": "sd", "seven_day_opus": "so", "seven_day_sonnet": "sn"][key]!
                return AgentLimitWindow(id: "claude.\(id)", kind: kind, minutes: minutes, scope: scope,
                                        usedPercent: min(100, max(0, percent.doubleValue)), resetsAt: end)
            }
        guard !windows.isEmpty else { return nil }
        return AgentLimits(provider: .claude, windows: windows, observedAt: observed, source: .account)
    }

    static func current(_ reading: AgentLimits?, now: Date) -> AgentLimits? {
        guard var reading else { return nil }
        let age = now.timeIntervalSince(reading.observedAt)
        reading.windows.removeAll { window in
            if let resets = window.resetsAt { return resets <= now }
            return age >= (window.kind == .session ? TimeInterval(window.minutes ?? 300) * 60 : 86_400)
        }
        return reading.windows.isEmpty ? nil : reading
    }

    final class Request {
        private let lock = NSLock()
        private var cancelled = false
        private var conversation: AgentCLIConversation?

        func cancel() {
            let active = lock.withLock { () -> AgentCLIConversation? in
                cancelled = true
                return conversation
            }
            active?.end()
        }

        func run(_ executable: URL, home: URL, environment: [String: String],
                 profile: ClaudeAccountProfile = ClaudeAccountProfile(),
                 timeout: TimeInterval = AgentClaudeServer.timeout) -> Result<Summary, Failure> {
            guard !lock.withLock({ cancelled }) else { return .failure(.unreachable) }
            guard profile.isAvailable(home: home) else { return .failure(.needsSignIn) }
            let started = Date()
            let identity = profile.read(home: home).identity
            let environment = AgentClaudeServer.environment(environment, home: home, profile: profile)
            let arguments = ["--print", "--input-format", "stream-json", "--output-format", "stream-json",
                "--verbose", "--no-session-persistence", "--tools", "", "--strict-mcp-config", "--mcp-config",
                "{\"mcpServers\":{}}", "--setting-sources", "", "--settings", "{\"disableAllHooks\":true}"]
            guard let channel = AgentCLIConversation(executable, arguments: arguments,
                                                     environment: environment, timeout: timeout) else { return .failure(.unreachable) }
            let accepted = lock.withLock { () -> Bool in
                guard !cancelled else { return false }
                conversation = channel
                return true
            }
            defer {
                channel.end()
                lock.withLock { conversation = nil }
            }
            guard accepted else { return .failure(.unreachable) }
            switch ask(channel, id: "initialize", request: ["subtype": "initialize"]) {
            case .failure(let failure): return .failure(failure)
            case .success: break
            }
            return ask(channel, id: "usage", request: ["subtype": "get_usage", "skip_behaviors": true])
                .flatMap { result in
                    guard !self.lock.withLock({ self.cancelled }) else { return .failure(.unreachable) }
                    guard result["rate_limits_available"] as? Bool == true else { return .failure(.needsSignIn) }
                    channel.end()
                    channel.waitForExit(timeout: 3)
                    let saved = profile.read(home: home)
                    guard !self.lock.withLock({ self.cancelled }),
                          identity == saved.identity, profile.isAvailable(home: home) else { return .failure(.unreachable) }
                    if let fetched = saved.usageFetched, started.timeIntervalSince(fetched) > AgentClaudeServer.reuse {
                        return .failure(.unreachable)
                    }
                    guard let reading = AgentClaudeServer.limits(result, observed: min(Date(), saved.usageFetched ?? Date()))
                    else { return .failure(.unreachable) }
                    return .success(Summary(limits: reading, identity: identity))
                }
        }

        private func ask(_ channel: AgentCLIConversation, id: String,
                         request: [String: Any]) -> Result<[String: Any], Failure> {
            guard channel.send(["type": "control_request", "request_id": id, "request": request]) else { return .failure(.unreachable) }
            while let message = channel.next() {
                guard message["type"] as? String == "control_response",
                      let response = message["response"] as? [String: Any], response["request_id"] as? String == id else { continue }
                guard response["subtype"] as? String == "success" else {
                    let error = (response["error"] as? String ?? "").lowercased()
                    if error.contains("supported") || error.contains("unknown") { return .failure(.outdated) }
                    if error.contains("auth") || error.contains("login") || error.contains("sign in") { return .failure(.needsSignIn) }
                    return .failure(.unreachable)
                }
                return .success(response["response"] as? [String: Any] ?? [:])
            }
            return .failure(.unreachable)
        }
    }
}
