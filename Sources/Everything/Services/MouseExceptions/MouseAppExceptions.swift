// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics

final class MouseAppExceptions: ObservableObject {
    static let shared = MouseAppExceptions()

    private let lock = NSLock()

    @Published private(set) var lists: [MouseExceptionScope: [String]] = [:]
    @Published private(set) var runningScopes = Set<MouseExceptionScope>()

    private var lookups: [MouseExceptionScope: Set<String>] = [:]
    private var allEmpty = true
    private var listsNamePath = false

    private var sourceProcessIDs: [MouseExceptionScope: Set<Int32>] = [:]
    private var trackedSourceScopes: Set<MouseExceptionScope> = []
    private var runningApplicationsObservation: NSKeyValueObservation?

    private var cachedIdentities: [String] = []
    private var cachedRegion: CGRect?
    private var cachedPoint: CGPoint = .zero
    private var cachedAt: TimeInterval = -1
    private var pointerRefreshScheduled = false

    private static let ownProcessID = Int32(getpid())
    private let uptime: () -> TimeInterval
    private let onScreenWindows: () -> [MouseAppExceptionSupport.Window]
    private let receivingWindow: (CGPoint) -> CGWindowID?
    private let identitiesForProcess: ((Int32) -> [String])?

    init(uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         onScreenWindows: @escaping () -> [MouseAppExceptionSupport.Window] = WindowServerSupport.onScreenWindows,
         receivingWindow: @escaping (CGPoint) -> CGWindowID? = WindowServerSupport.receivingWindow(at:),
         identitiesForProcess: ((Int32) -> [String])? = nil) {
        self.uptime = uptime
        self.onScreenWindows = onScreenWindows
        self.receivingWindow = receivingWindow
        self.identitiesForProcess = identitiesForProcess
        reload()
    }

    // MARK: - The lists

    func reload() {
        let defaults = UserDefaults.standard
        for scope in MouseExceptionScope.allCases {
            let raw = defaults.stringArray(forKey: scope.defaultsKey) ?? []
            let sanitized = Defaults.sanitizedBundleIdentifierList(raw)
            if raw != sanitized {
                defaults.set(sanitized, forKey: scope.defaultsKey)
            }
            lists[scope] = sanitized
            lock.withLock { lookups[scope] = Set(sanitized) }
        }
        lock.withLock {
            allEmpty = lookups.values.allSatisfy(\.isEmpty)
            listsNamePath = lookups.values.contains {
                $0.contains(where: MouseAppExceptionSupport.isExecutablePathIdentity)
            }
        }
        invalidateCache()
        refreshSourceTracking()
    }

    func list(_ scope: MouseExceptionScope) -> [String] { lists[scope] ?? [] }

    private func lookup(_ scope: MouseExceptionScope) -> (exceptions: Set<String>, sources: Set<Int32>) {
        lock.withLock { (lookups[scope] ?? [], sourceProcessIDs[scope] ?? []) }
    }

    private static func onMain<T>(_ work: () -> T) -> T {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }

    func add(_ identity: String, to scope: MouseExceptionScope) {
        let updated = Defaults.sanitizedBundleIdentifierList(list(scope) + [identity])
        guard updated != list(scope) else { return }
        UserDefaults.standard.set(updated, forKey: scope.defaultsKey)
        reload()
    }

    func remove(_ bundleID: String, from scope: MouseExceptionScope) {
        guard list(scope).contains(bundleID) else { return }
        UserDefaults.standard.set(list(scope).filter { $0 != bundleID }, forKey: scope.defaultsKey)
        reload()
    }

    // MARK: - The question the taps ask

    func excludesPointerTarget(_ scope: MouseExceptionScope,
                               at point: CGPoint,
                               sourceProcessID: Int64 = 0) -> Bool {
        let (exceptions, sources) = lookup(scope)
        guard !exceptions.isEmpty else { return false }
        if let pid = MouseAppExceptionSupport.sourceProcessID(sourceProcessID),
           sources.contains(pid) {
            return true
        }
        let answer = pointerIdentity(at: point)
        guard answer.known else { return true }
        return MouseAppExceptionSupport.isExcepted(answer.identities, exceptions: exceptions)
    }

    func excludesActionTarget(_ scope: MouseExceptionScope,
                              at point: CGPoint,
                              sourceProcessID: Int64 = 0) -> Bool {
        let (exceptions, sources) = lookup(scope)
        guard !exceptions.isEmpty else { return false }
        if let pid = MouseAppExceptionSupport.sourceProcessID(sourceProcessID),
           sources.contains(pid) {
            return true
        }
        let answer = pointerIdentity(at: point)
        guard answer.known else { return true }
        if MouseAppExceptionSupport.isExcepted(answer.identities, exceptions: exceptions) {
            return true
        }
        let frontmost = Self.onMain { identities(for: NSWorkspace.shared.frontmostApplication) }
        return MouseAppExceptionSupport.isExcepted(frontmost, exceptions: exceptions)
    }

    func setSourceTracking(_ active: Bool, for scope: MouseExceptionScope) {
        lock.withLock {
            if active {
                trackedSourceScopes.insert(scope)
            } else {
                trackedSourceScopes.remove(scope)
            }
        }
        refreshSourceTracking()
    }

    private func refreshSourceTracking() {
        let shouldTrack = lock.withLock {
            trackedSourceScopes.contains { lookups[$0]?.isEmpty == false }
        }
        guard shouldTrack else {
            stopSourceTracking()
            return
        }

        if runningApplicationsObservation == nil {
            runningApplicationsObservation = NSWorkspace.shared.observe(
                \.runningApplications, options: [.initial, .new]) { [weak self] workspace, _ in
                    self?.rebuildSourceProcesses(workspace.runningApplications)
            }
        } else {
            rebuildSourceProcesses(NSWorkspace.shared.runningApplications)
        }
    }

    private func stopSourceTracking() {
        runningApplicationsObservation?.invalidate()
        runningApplicationsObservation = nil
        lock.withLock { sourceProcessIDs.removeAll(keepingCapacity: false) }
        if !runningScopes.isEmpty { runningScopes.removeAll() }
    }

    private func rebuildSourceProcesses(_ applications: [NSRunningApplication]) {
        var rebuilt: [MouseExceptionScope: Set<Int32>] = [:]
        let (scopes, exceptionsByScope) = lock.withLock { (trackedSourceScopes, lookups) }
        for app in applications {
            let bundleIDs = sourceBundleIdentifiers(for: app)
            guard !bundleIDs.isEmpty else { continue }
            for scope in scopes {
                guard let exceptions = exceptionsByScope[scope],
                      MouseAppExceptionSupport.isExcepted(bundleIDs,
                                                          exceptions: exceptions) else { continue }
                rebuilt[scope, default: []].insert(app.processIdentifier)
            }
        }
        lock.withLock { sourceProcessIDs = rebuilt }
        let updatedScopes = Set(rebuilt.keys)
        Self.onMain {
            if runningScopes != updatedScopes { runningScopes = updatedScopes }
        }
    }

    private func sourceBundleIdentifiers(for app: NSRunningApplication) -> [String] {
        var identifiers = identities(for: app)

        var url = (app.bundleURL ?? app.executableURL)?.standardizedFileURL
        while let candidate = url, candidate.path != "/" {
            if candidate.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
               let bundleID = Bundle(url: candidate)?.bundleIdentifier,
               !identifiers.contains(bundleID) {
                identifiers.append(bundleID)
            }
            let parent = candidate.deletingLastPathComponent()
            guard parent != candidate else { break }
            url = parent
        }
        return identifiers
    }

    // MARK: - Resolving

    private func pointerIdentity(at point: CGPoint) -> (known: Bool, identities: [String]) {
        let now = uptime()
        let isMainThread = Thread.isMainThread
        var needsRefresh = false
        let answer = lock.withLock { () -> (settled: Bool, known: Bool, identities: [String]) in
            guard !allEmpty else { return (true, true, []) }
            guard MouseAppExceptionSupport.cacheHolds(region: cachedRegion,
                                                      resolvedPoint: cachedPoint,
                                                      resolvedAt: cachedAt,
                                                      point: point,
                                                      now: now) else {
                if !isMainThread {
                    needsRefresh = !pointerRefreshScheduled
                    if needsRefresh { pointerRefreshScheduled = true }
                    let sameWindow = MouseAppExceptionSupport.cacheNamesWindow(region: cachedRegion,
                                                                              point: point)
                    return (true, sameWindow, sameWindow ? cachedIdentities : [])
                }
                return (false, true, [])
            }
            return (true, true, cachedIdentities)
        }
        if needsRefresh {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                defer { self.lock.withLock { self.pointerRefreshScheduled = false } }
                _ = self.pointerIdentity(at: point)
            }
        }
        if answer.settled { return (answer.known, answer.identities) }

        let windows = onScreenWindows()
        let surface = MouseAppExceptionSupport.pointerSurface(in: windows,
                                                              receivingWindowID: receivingWindow(point),
                                                              ownProcessID: Self.ownProcessID)
        let surfaceIdentities = surface.map {
            MouseAppExceptionSupport.surfaceIdentities(identities(forProcess: $0.processID))
        } ?? []
        let resolved: [String]
        let region: CGRect?
        if let surface, !surfaceIdentities.isEmpty {
            resolved = surfaceIdentities
            let center = CGPoint(x: surface.frame.midX, y: surface.frame.midY)
            region = receivingWindow(center) == surface.number ? surface.frame : nil
        } else {
            let window = MouseAppExceptionSupport.pointerWindow(in: windows,
                                                                at: point,
                                                                ownProcessID: Self.ownProcessID)
            resolved = window.map { identities(forProcess: $0.processID) }
                ?? identities(for: NSWorkspace.shared.frontmostApplication)
            region = window?.frame
        }
        lock.withLock {
            cachedIdentities = resolved
            cachedRegion = region
            cachedPoint = point
            cachedAt = now
        }
        return (true, resolved)
    }

    private func identities(for app: NSRunningApplication?) -> [String] {
        guard let app else { return [] }
        return MouseAppExceptionSupport.identities(bundleID: app.bundleIdentifier,
                                                   executablePath: app.executableURL?.path,
                                                   readsPath: lock.withLock { listsNamePath })
    }

    private func identities(forProcess processID: Int32) -> [String] {
        if let identitiesForProcess { return identitiesForProcess(processID) }
        return identities(for: NSRunningApplication(processIdentifier: processID))
    }

    private func invalidateCache() {
        lock.withLock {
            cachedIdentities = []
            cachedRegion = nil
            cachedAt = -1
        }
    }
}
