// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics

final class WindowUseTracker {
    static let shared = WindowUseTracker()

    private static let messagingTimeout: Float = 0.35

    private let stateLock = NSLock()
    private var windowHistory: [CGWindowID] = []
    private var appHistory: [pid_t] = []
    private var focusHistory = WindowFocusHistory()
    private var recording = false

    private let lifecycleLock = NSLock()
    private var started = false
    private var watcherThread: Thread?
    private var watcherRunLoop: CFRunLoop?
    private var shouldStopWatcher = false
    private var pendingStartAfterStop = false
    private var seedRunningPIDs: Set<pid_t> = []

    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var retryTimer: CFRunLoopTimer?
    private var keepAliveSource: CFRunLoopSource?

    private init() {}

    // MARK: - History

    var windows: [CGWindowID] { stateLock.withLock { windowHistory } }

    var apps: [pid_t] { stateLock.withLock { appHistory } }

    var historyRevision: UUID { stateLock.withLock { focusHistory.revision } }

    func rank(of pid: pid_t) -> Int {
        stateLock.withLock { appHistory.firstIndex(of: pid) ?? Int.max }
    }

    func recordSwitch(to windowID: CGWindowID?, pid: pid_t, from previous: CGWindowID?) {
        stateLock.withLock {
            guard recording else { return }
            focusHistory.switched(to: windowID, pid: pid, previous: previous)
            windowHistory = WindowUseOrder.promoting(target: windowID,
                                                     previous: previous,
                                                     in: windowHistory)
        }
    }

    func reconcile(existingWindows: Set<CGWindowID>, frontToBack: FrontToBack,
                   running: Set<pid_t>, revision: UUID) {
        stateLock.withLock {
            guard recording else { return }
            windowHistory = WindowUseOrder.reconciled(windowHistory,
                                                      existing: existingWindows,
                                                      frontToBack: frontToBack.windows)
            appHistory = WindowUseOrder.reconciled(appHistory,
                                                   running: running,
                                                   frontToBack: frontToBack.apps)
            focusHistory.reconcile(windows: existingWindows, revision: revision)
        }
    }

    func order(_ entries: [WindowUseOrder.Entry], frontToBack: [CGWindowID]) -> [Int] {
        stateLock.withLock {
            let baseline = WindowUseOrder.order(entries, windowHistory: windowHistory,
                                                appHistory: appHistory, frontToBack: frontToBack)
            return focusHistory.order(entries, baseline: baseline)
        }
    }

    private func promote(window windowID: CGWindowID, for request: WindowFocusHistory.Request) {
        stateLock.withLock {
            guard recording, focusHistory.focus(windowID, for: request) else { return }
            windowHistory = WindowUseOrder.promoting(windowID, in: windowHistory)
        }
    }

    private func promote(app pid: pid_t) {
        stateLock.withLock {
            guard recording else { return }
            appHistory = WindowUseOrder.promoting(pid, in: appHistory)
        }
    }

    // MARK: - Lifecycle

    func syncWithFeatures() {
        if AppFeature.switcher.isAvailable || AppFeature.windowLayout.isAvailable {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard !started else { return }
        started = true
        stateLock.withLock { recording = true }
        lifecycleLock.withLock {
            seedRunningPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appActivated(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appTerminated(_:)),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        if let front = NSWorkspace.shared.frontmostApplication {
            promote(app: front.processIdentifier)
            stateLock.withLock { _ = focusHistory.activate(front.processIdentifier) }
        }
        startWatcher()
    }

    func stop() {
        guard started else { return }
        started = false
        stateLock.withLock {
            recording = false
            windowHistory.removeAll()
            appHistory.removeAll()
            focusHistory = WindowFocusHistory()
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        stopWatcher()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        let own = pid == ProcessInfo.processInfo.processIdentifier && ActivationHandoff.isHandingOff
        let request = stateLock.withLock { () -> WindowFocusHistory.Request? in
            guard recording else { return nil }
            if !own { appHistory = WindowUseOrder.promoting(pid, in: appHistory) }
            return focusHistory.activate(pid, recording: !own)
        }
        performOnWatcher { [weak self] in self?.retargetObserver(request: request) }
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        stateLock.withLock {
            appHistory.removeAll { $0 == pid }
            focusHistory.terminated(pid)
        }
    }

    // MARK: - Watcher thread

    private func startWatcher() {
        let thread = lifecycleLock.withLock { () -> Thread? in
            if watcherThread != nil {
                if shouldStopWatcher { pendingStartAfterStop = true }
                return nil
            }
            shouldStopWatcher = false
            pendingStartAfterStop = false
            let thread = Thread { [weak self] in self?.runWatcher() }
            thread.name = "EVERYTHING Window Focus"
            thread.qualityOfService = .userInitiated
            watcherThread = thread
            return thread
        }
        thread?.start()
    }

    private func stopWatcher() {
        let snapshot = lifecycleLock.withLock { () -> (runLoop: CFRunLoop?, threadExists: Bool) in
            shouldStopWatcher = true
            pendingStartAfterStop = false
            return (watcherRunLoop, watcherThread != nil)
        }
        if let runLoop = snapshot.runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(runLoop) }
            CFRunLoopWakeUp(runLoop)
        } else if !snapshot.threadExists {
            lifecycleLock.withLock {
                shouldStopWatcher = false
                watcherThread = nil
            }
        }
    }

    private func performOnWatcher(_ work: @escaping () -> Void) {
        guard let runLoop = lifecycleLock.withLock({ watcherRunLoop }) else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, work)
        CFRunLoopWakeUp(runLoop)
    }

    private func runWatcher() {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock { watcherRunLoop = runLoop }

            var context = CFRunLoopSourceContext()
            context.perform = { _ in }
            if let source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context) {
                CFRunLoopAddSource(runLoop, source, .defaultMode)
                keepAliveSource = source
            }

            seedFromWindowServer()
            retargetObserver(request: stateLock.withLock { focusHistory.current })

            while !lifecycleLock.withLock({ shouldStopWatcher }) {
                CFRunLoopRun()
            }

            cancelRetry()
            detachObserver()
            if let source = keepAliveSource {
                CFRunLoopRemoveSource(runLoop, source, .defaultMode)
                keepAliveSource = nil
            }

            let restart = lifecycleLock.withLock { () -> Bool in
                watcherRunLoop = nil
                watcherThread = nil
                shouldStopWatcher = false
                defer { pendingStartAfterStop = false }
                return pendingStartAfterStop
            }
            if restart { startWatcher() }
        }
    }

    private func seedFromWindowServer() {
        let revision = historyRevision
        reconcile(existingWindows: Set(Self.allWindows()),
                  frontToBack: Self.frontToBack(),
                  running: lifecycleLock.withLock { seedRunningPIDs }, revision: revision)
    }

    // MARK: - Accessibility observation (watcher thread only)

    private func retargetObserver(request: WindowFocusHistory.Request?, attempt: Int = 0) {
        guard !lifecycleLock.withLock({ shouldStopWatcher }),
              stateLock.withLock({ recording && focusHistory.current == request }) else { return }
        cancelRetry()
        detachObserver()
        guard let request, AXIsProcessTrusted() else { return }
        let pid = request.pid

        var created: AXObserver?
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        var needsRetry = false
        if AXObserverCreate(pid, Self.focusCallback, &created) == .success, let created {
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            for notification in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
                let result = AXObserverAddNotification(created, application, notification as CFString, refcon)
                if result != .success && result != .notificationUnsupported { needsRetry = true }
            }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(created), .defaultMode)
            observer = created
            observedPID = pid
        } else {
            needsRetry = true
        }

        let foundFocus = readFocusedWindow(for: request)
        if needsRetry || !foundFocus { scheduleRetry(request, attempt: attempt) }
    }

    private func cancelRetry() {
        if let retryTimer { CFRunLoopTimerInvalidate(retryTimer) }
        retryTimer = nil
    }

    private func scheduleRetry(_ request: WindowFocusHistory.Request, attempt: Int) {
        guard attempt < 3, stateLock.withLock({ recording && focusHistory.current == request }) else { return }
        let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault,
            CFAbsoluteTimeGetCurrent() + 0.2 * Double(attempt + 1), 0, 0, 0) { [weak self] _ in
                self?.retargetObserver(request: request, attempt: attempt + 1)
            }
        retryTimer = timer
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
    }

    private func detachObserver() {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        if let observedPID {
            let application = AXUIElementCreateApplication(observedPID)
            AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
            for notification in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
                _ = AXObserverRemoveNotification(observer, application, notification as CFString)
            }
        }
        self.observer = nil
        observedPID = nil
    }

    private func readFocusedWindow(for request: WindowFocusHistory.Request) -> Bool {
        guard AXIsProcessTrusted(), stateLock.withLock({ recording && focusHistory.current == request }) else { return false }
        let application = AXUIElementCreateApplication(request.pid)
        AXUIElementSetMessagingTimeout(application, Self.messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return false }
        let window = value as! AXUIElement
        guard let windowID = AXWindowResolver.windowID(for: window) else { return false }
        promote(window: windowID, for: request)
        return true
    }

    private static let focusCallback: AXObserverCallback = { observer, _, _, refcon in
        guard let refcon else { return }
        let tracker = Unmanaged<WindowUseTracker>.fromOpaque(refcon).takeUnretainedValue()
        guard let active = tracker.observer, CFEqual(active, observer),
              let request = tracker.stateLock.withLock({ tracker.focusHistory.current }),
              request.pid == tracker.observedPID else { return }
        _ = tracker.readFocusedWindow(for: request)
    }

    // MARK: - Window server

    struct FrontToBack {
        let windows: [CGWindowID]
        let apps: [pid_t]
    }

    static func frontToBack() -> FrontToBack {
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                             kCGNullWindowID) as? [[String: Any]] ?? []
        var windows: [CGWindowID] = []
        var apps: [pid_t] = []
        var seenApps = Set<pid_t>()
        for entry in raw where (entry[kCGWindowLayer as String] as? Int) == 0 {
            guard let windowID = entry[kCGWindowNumber as String] as? CGWindowID else { continue }
            windows.append(windowID)
            if let pid = entry[kCGWindowOwnerPID as String] as? pid_t, seenApps.insert(pid).inserted {
                apps.append(pid)
            }
        }
        return FrontToBack(windows: windows, apps: apps)
    }

    private static func allWindows() -> [CGWindowID] {
        let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return raw.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
    }
}
