// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum HomebrewEnvironment {
    static let forBrew: [String: String] = ProcessInfo.processInfo.environment
        .merging(exportsFromLoginShell(shellPath: HomebrewCommandBuilder.currentShellPath)) { _, shell in shell }

    static let loginShellTimeout: TimeInterval = 10

    static let passedThroughNames: Set<String> = [
        "http_proxy", "https_proxy", "ftp_proxy", "no_proxy", "all_proxy",
        "HTTPS_PROXY", "FTP_PROXY", "ALL_PROXY",
    ]

    static func isPassedThrough(_ name: String) -> Bool {
        passedThroughNames.contains(name) || name.hasPrefix("HOMEBREW_")
    }

    static func passthrough(_ environment: [String: String]) -> [String: String] {
        environment.filter { isPassedThrough($0.key) }
    }

    static let dumpMarker = "__VORSSAINT_ENV_DUMP__"

    static let resolvingVariable = "VORSSAINT_RESOLVING_ENVIRONMENT"

    static func loginShellCommand(shellPath: String, interactive: Bool = true) -> HomebrewCommand {
        HomebrewCommand(executable: shellPath,
                        arguments: (interactive ? ["-l", "-i"] : ["-l"])
                            + ["-c", "printf %s \(dumpMarker); /usr/bin/env -0"])
    }

    static func loginShellEnvironment(base: [String: String]) -> [String: String] {
        base.merging([resolvingVariable: "1"]) { _, resolving in resolving }
    }

    static func exportsFromLoginShell(shellPath: String,
                                      timeout: TimeInterval = loginShellTimeout,
                                      baseEnvironment: [String: String] = ProcessInfo.processInfo.environment)
        -> [String: String] {
        passthrough(loginShellExports(shellPath: shellPath, timeout: timeout, baseEnvironment: baseEnvironment))
    }

    static func loginShellExports(shellPath: String,
                                  timeout: TimeInterval = loginShellTimeout,
                                  baseEnvironment: [String: String] = ProcessInfo.processInfo.environment)
        -> [String: String] {
        guard !shellPath.isEmpty else { return [:] }
        let environment = loginShellEnvironment(base: baseEnvironment)
        for interactive in [true, false] {
            let command = loginShellCommand(shellPath: shellPath, interactive: interactive)
            let result = BoundedProcessRunner.runInNewSession(command.executable, command.arguments,
                                                              timeout: timeout, maxOutputBytes: 1024 * 1024,
                                                              environment: environment)
            guard result.status == 0, !result.timedOut,
                  result.output.range(of: Data(dumpMarker.utf8)) != nil else { continue }
            return parse(nullSeparated: result.output)
        }
        return [:]
    }

    static func parse(nullSeparated data: Data) -> [String: String] {
        var environment: [String: String] = [:]
        var dump = data[...]
        if let marker = data.range(of: Data(dumpMarker.utf8), options: .backwards) {
            dump = data[marker.upperBound...]
        }
        for entry in dump.split(separator: 0) {
            guard let separator = entry.firstIndex(of: UInt8(ascii: "=")) else { continue }
            let name = String(decoding: entry[entry.startIndex..<separator], as: UTF8.self)
            guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { continue }
            environment[name] = String(decoding: entry[entry.index(after: separator)...], as: UTF8.self)
        }
        return environment
    }
}
