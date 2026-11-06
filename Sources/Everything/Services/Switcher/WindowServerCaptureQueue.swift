// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os

final class WindowServerCaptureQueue: @unchecked Sendable {
    static let slowPermissionCheck: TimeInterval = 0.5
    static let slowCapture: TimeInterval = 2
    static let permissionCheckLifetime: TimeInterval = 5

    static func pause(afterSlowTurns count: Int) -> TimeInterval {
        let doublings = Double(min(max(count, 1), 6) - 1)
        return min(600, 30 * pow(2, doublings))
    }

    private typealias PermissionPreflight = @convention(c) (CFString, CFDictionary?) -> Int32

    static let screenRecordingCheck: (() -> Void)? = {
        guard let framework = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_LAZY),
              let symbol = dlsym(framework, "TCCAccessPreflight")
        else { return nil }
        let preflight = unsafeBitCast(symbol, to: PermissionPreflight.self)
        return { _ = preflight("kTCCServiceScreenCapture" as CFString, nil) }
    }()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "window-capture")

    private let queue = DispatchQueue(label: "com.vorssaint.window-capture", qos: .userInitiated)
    private let lock = NSLock()
    private let now: () -> TimeInterval
    private let checkPermission: () -> Void
    private var pendingCount = 0
    private var turnStartedAt: TimeInterval?
    private var pausedUntil: TimeInterval = 0
    private var slowTurns = 0
    private var promptCheckAt: TimeInterval?

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         checkPermission: @escaping () -> Void = {}) {
        self.now = now
        self.checkPermission = checkPermission
    }

    func capture<Value>(waitingForOtherCaptures: Bool = true,
                        _ operation: @escaping () -> Value?) async -> Value? {
        await submit(waitingForOtherCaptures: waitingForOtherCaptures) { finish in
            finish(autoreleasepool(invoking: operation))
        }
    }

    func perform<Value>(waitingForOtherCaptures: Bool = true,
                        _ operation: @escaping () async -> Value?) async -> Value? {
        await submit(waitingForOtherCaptures: waitingForOtherCaptures) { finish in
            self.queue.suspend()
            Task.detached(priority: .userInitiated) {
                finish(await operation())
                self.queue.resume()
            }
        }
    }

    private func submit<Value>(waitingForOtherCaptures: Bool,
                               _ run: @escaping (_ finish: @escaping (Value?) -> Void) -> Void) async -> Value? {
        guard !Task.isCancelled else { return nil }
        let request = Request<Value>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard request.install(continuation) else { return }
                let accepted = lock.withLock {
                    guard acceptsTurns(at: now()), waitingForOtherCaptures || pendingCount == 0 else { return false }
                    pendingCount += 1
                    return true
                }
                guard accepted else {
                    request.finish(nil)
                    return
                }
                queue.async {
                    guard let start = self.beginTurn(unlessCancelled: { request.isFinished }) else {
                        self.lock.withLock { self.pendingCount -= 1 }
                        request.finish(nil)
                        return
                    }
                    run { value in
                        self.endTurn(startedAt: start)
                        request.finish(value)
                    }
                }
            }
        } onCancel: {
            request.finish(nil)
        }
    }

    private func acceptsTurns(at time: TimeInterval) -> Bool {
        guard time >= pausedUntil else { return false }
        guard let turnStartedAt else { return true }
        return time - turnStartedAt < Self.slowCapture
    }

    var acceptsCaptures: Bool { lock.withLock { acceptsTurns(at: now()) } }

    private func beginTurn(unlessCancelled cancelled: () -> Bool) -> TimeInterval? {
        guard !cancelled() else { return nil }
        let checkIsDue = lock.withLock { () -> Bool? in
            let time = now()
            guard time >= pausedUntil else { return nil }
            turnStartedAt = time
            return promptCheckAt.map { time - $0 >= Self.permissionCheckLifetime } ?? true
        }
        guard let checkIsDue else { return nil }
        if checkIsDue {
            let asked = now()
            checkPermission()
            let answered = now()
            let prompt = answered - asked < Self.slowPermissionCheck
            lock.withLock {
                if prompt {
                    promptCheckAt = answered
                } else {
                    turnStartedAt = nil
                    pauseAfterSlowTurn(at: answered, took: answered - asked, reason: "Screen Recording check")
                }
            }
            guard prompt else { return nil }
        }
        guard !cancelled() else {
            lock.withLock { turnStartedAt = nil }
            return nil
        }
        return now()
    }

    private func endTurn(startedAt start: TimeInterval) {
        lock.withLock {
            let time = now()
            pendingCount -= 1
            turnStartedAt = nil
            if time - start >= Self.slowCapture {
                pauseAfterSlowTurn(at: time, took: time - start, reason: "capture")
            } else {
                slowTurns = 0
            }
        }
    }

    private func pauseAfterSlowTurn(at time: TimeInterval, took: TimeInterval, reason: String) {
        slowTurns += 1
        let pause = Self.pause(afterSlowTurns: slowTurns)
        pausedUntil = time + pause
        promptCheckAt = nil
        Self.log.notice("Window captures paused for \(Int(pause), privacy: .public) s: a \(reason, privacy: .public) took \(Int(took * 1000), privacy: .public) ms")
    }

    private final class Request<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Value?, Never>?
        private var finished = false

        var isFinished: Bool { lock.withLock { finished } }

        func install(_ continuation: CheckedContinuation<Value?, Never>) -> Bool {
            let installed = lock.withLock {
                guard !finished else { return false }
                self.continuation = continuation
                return true
            }
            if !installed { continuation.resume(returning: nil) }
            return installed
        }

        func finish(_ value: Value?) {
            let continuation = lock.withLock {
                finished = true
                defer { self.continuation = nil }
                return self.continuation
            }
            continuation?.resume(returning: value)
        }
    }
}
