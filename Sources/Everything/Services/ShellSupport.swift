// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreServices
import Darwin

enum Shell {
    static let defaultTimeout: TimeInterval = 5

    @discardableResult
    static func run(_ path: String,
                    _ args: [String],
                    timeout: TimeInterval = defaultTimeout,
                    maxOutputBytes: Int = 4 * 1024 * 1024)
        -> (status: Int32, output: String) {
        let result = BoundedProcessRunner.run(path, args,
                                              timeout: timeout,
                                              maxOutputBytes: maxOutputBytes)
        return (result.status, String(decoding: result.output, as: UTF8.self))
    }
}

enum AdminShell {
    private static let promptLock = NSLock()
    private static var prompting = false

    private enum RequestOrigin {
        case systemScript
        case signedApp
    }

    static func runSync(_ command: String, prompt: String) -> Bool {
        runSync(command, prompt: prompt, origin: .systemScript)
    }

    private static func runSync(_ command: String, prompt: String, origin: RequestOrigin) -> Bool {
        promptLock.lock()
        if prompting {
            promptLock.unlock()
            return false
        }
        prompting = true
        promptLock.unlock()
        defer {
            promptLock.lock()
            prompting = false
            promptLock.unlock()
        }

        bringAppToFront()
        let source = appleScriptSource(command: command, prompt: prompt)
        switch origin {
        case .systemScript:
            return Shell.run("/usr/bin/osascript", ["-e", source], timeout: 600).status == 0
        case .signedApp:
            return DispatchQueue.main.sync {
                AppleScriptRunner.run(source).ok
            }
        }
    }

    static func run(_ command: String, prompt: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            completion(runSync(command, prompt: prompt))
        }
    }

    static func runInProcess(_ command: String, prompt: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            completion(runSync(command, prompt: prompt, origin: .signedApp))
        }
    }

    private static func bringAppToFront() {
        if Thread.isMainThread {
            NSApp.activate(ignoringOtherApps: true)
        } else {
            DispatchQueue.main.sync {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        Thread.sleep(forTimeInterval: 0.12)
    }

    static func appleScriptSource(command: String, prompt: String) -> String {
        "do shell script \(appleScriptString(command)) with administrator privileges with prompt \(appleScriptString(prompt))"
    }

    private static func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

enum Sudoers {
    static let rulePath = "/etc/sudoers.d/vorssaint-clamshell"
    private static let legacyRulePaths = [
        "/etc/sudoers.d/vorssaint-utils-clamshell",
        "/etc/sudoers.d/vorss-clamshell",
    ]

    private static let sleepStateQueue = DispatchQueue(label: "com.vorssaint.utils.pmset-state")
    private static var sleepStateProbeSuspensions = 0

    static func isConfigured() -> Bool {
        sleepStateQueue.sync {
            guard sleepStateProbeSuspensions == 0 else { return false }
            let report = Shell.run("/usr/bin/pmset", ["-g"])
            guard report.status == 0 else { return false }
            return pmsetDisableSleepOnQueue(SudoersSupport.sleepDisabled(inPmsetOutput: report.output))
        }
    }

    static var ruleFilesPresent: Bool {
        ([rulePath] + legacyRulePaths).contains { FileManager.default.fileExists(atPath: $0) }
    }

    static func install(completion: @escaping (Bool) -> Void) {
        let rule = SudoersSupport.clamshellRule(uid: getuid())
        let legacy = legacyRulePaths.joined(separator: " ")
        let command = "mkdir -p /etc/sudoers.d && chmod 0755 /etc/sudoers.d && rm -f \(legacy) && echo '\(rule)' > \(rulePath) && chmod 0440 \(rulePath) && /usr/sbin/visudo -c -f \(rulePath) || { rm -f \(rulePath); exit 1; }"
        AdminShell.run(command, prompt: L10n.shared.s.adminPromptSudoersInstall) { ok in
            completion(ok && isConfigured())
        }
    }

    static func remove(completion: @escaping (Bool) -> Void) {
        let all = ([rulePath] + legacyRulePaths).joined(separator: " ")
        AdminShell.run("rm -f \(all)",
                       prompt: L10n.shared.s.adminPromptSudoersRemove) { ok in
            completion(ok)
        }
    }

    @discardableResult
    static func pmsetDisableSleep(_ on: Bool) -> Bool {
        sleepStateQueue.sync { pmsetDisableSleepOnQueue(on) }
    }

    static func pmsetDisableSleep(_ on: Bool, completion: @escaping (Bool) -> Void) {
        sleepStateQueue.async {
            completion(pmsetDisableSleepOnQueue(on))
        }
    }

    static func restoreSleepWithAuthorization(prompt: String,
                                              shouldProceed: @escaping () -> Bool,
                                              completion: @escaping (Bool) -> Void) {
        sleepStateQueue.async {
            sleepStateProbeSuspensions += 1
            let finish: (Bool) -> Void = { ok in
                sleepStateQueue.async {
                    sleepStateProbeSuspensions -= 1
                    completion(ok)
                }
            }
            let report = Shell.run("/usr/bin/pmset", ["-g"])
            if report.status == 0, !SudoersSupport.sleepDisabled(inPmsetOutput: report.output) {
                finish(true)
                return
            }
            DispatchQueue.main.async {
                guard shouldProceed() else {
                    finish(false)
                    return
                }
                AdminShell.run("pmset disablesleep 0", prompt: prompt, completion: finish)
            }
        }
    }

    private static func pmsetDisableSleepOnQueue(_ on: Bool) -> Bool {
        Shell.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "disablesleep", on ? "1" : "0"]).status == 0
    }
}

enum AppleScriptRunner {
    @discardableResult
    static func consentToAutomate(bundleID: String) -> Bool {
        var target = AEAddressDesc()
        let created = bundleID.withCString { ptr in
            AECreateDesc(typeApplicationBundleID, ptr, bundleID.utf8.count, &target)
        }
        guard created == noErr else { return false }
        defer { AEDisposeDesc(&target) }
        let status = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, true)
        if bundleID == "com.apple.Music", status != -600, status != -1744 {
            UserDefaults.standard.set(status == noErr, forKey: "everythingMusicAutomationGranted")
        }
        return status == noErr
    }

    @discardableResult
    static func run(_ source: String) -> (ok: Bool, output: String) {
        let result = runDetailed(source)
        return (result.ok, result.ok ? result.output : result.message)
    }

    @discardableResult
    static func runDetailed(_ source: String) -> (ok: Bool, errorNumber: Int?, message: String, output: String) {
        guard let script = NSAppleScript(source: source) else { return (false, nil, "", "") }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            return (false,
                    error[NSAppleScript.errorNumber] as? Int,
                    (error[NSAppleScript.errorMessage] as? String) ?? "",
                    "")
        }
        return (true, nil, "", result.stringValue ?? "")
    }

    static func literal(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
