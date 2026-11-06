// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import CoreGraphics
import SwiftUI

private struct SwitcherSourceContext {
    let itemID: String?
    let pid: pid_t
    let windowID: CGWindowID?
    let windowOwnerPID: pid_t?
    let isFullscreen: Bool
    let frame: CGRect
}

private struct SwitcherPendingSessionStart {
    let generation: UInt64
    let shortcut: GlobalShortcut
    let scope: SwitcherSessionScope
    let reversed: Bool
    var additionalNavigation = 0
    var commitWhenReady = false
}

final class AppSwitcher: ObservableObject {
    static let shared = AppSwitcher()

    @Published private(set) var windows: [SwitcherItem] = []
    @Published private(set) var previews: [CGWindowID: CGImage] = [:]
    @Published private(set) var selectedIndex = 0 {
        didSet {
            guard oldValue != selectedIndex else { return }
            cancelLetterConfirmation()
            updateIconRowLayoutForCurrentSelection()
            revealSelectedIconInVisibleRow()
            if sessionActive, simpleModeEnabled, !usesWindowRow {
                resizePanel(animated: !UserDefaults.standard.bool(forKey: DefaultsKey.switcherInstantSelection))
            }
        }
    }
    @Published private(set) var grid = SwitcherGrid.empty
    @Published private(set) var iconRowLayout = SwitcherIconRowLayout.empty
    @Published private(set) var iconRowFirstVisibleIndex = 0
    @Published private(set) var searchQuery = ""
    @Published private(set) var isSearchPinned = false
    @Published private(set) var totalWindowCount = 0

    private var sessionActive: Bool {
        get { routeLock.withLock { routeSessionActive } }
        set { routeLock.withLock { routeSessionActive = newValue } }
    }

    var keyboardInputOwnership: (isOwned: Bool, generation: UInt64) {
        routeLock.withLock {
            (!routeCapturing && (routeSessionActive
                || (routeCanStartSession && routePendingSessionStart != nil)),
             sessionStartGeneration)
        }
    }

    var scrollNavigationActive: Bool {
        routeLock.withLock { routeSessionActive && !routeCapturing }
    }

    private var panel: NSPanel?
    private var sessionItems: [SwitcherItem] = []

    private let lifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingStartAfterStop = false
    private var keyboardLayoutObserver: NSObjectProtocol?
    private lazy var secureInputWatch = SecureInputWatch { [weak self] enabled in
        self?.secureInputChanged(enabled)
    }
    private var wakeObserver: NSObjectProtocol?
    private var wakeRetry: DispatchWorkItem?

    private let routeLock = NSLock()
    private var routeSessionActive = false
    private var routeShortcut = GlobalShortcut.switcherDefault
    private var routeWindowShortcut = GlobalShortcut.switcherWindowDefault
    private var routeAllWindowsShortcut: GlobalShortcut?
    private var routeCapturing = false
    private var routeCanStartSession = false
    private var routePendingSessionStart: SwitcherPendingSessionStart?
    private var sessionStartGeneration: UInt64 = 0

    private let enumerationQueue = DispatchQueue(label: "com.vorssaint.switcher.enumeration",
                                                  qos: .userInitiated)
    private var pendingShow: DispatchWorkItem?
    private var userNavigated = false
    private var hoverAnchor: NSPoint?
    private var sessionPlacementVisibleFrame: CGRect?
    private var hoveredWindowIndex: Int?
    private var scrollNavigation = SwitcherScrollNavigation()
    private struct PendingLetterConfirmation {
        let action: SwitcherLetterAction
        let itemID: String
        let expiry: DispatchWorkItem
    }
    private var pendingLetterConfirmation: PendingLetterConfirmation?
    private var swallowingMiddleMouseUp = false
    private var iconRowEdgeHoverWork: DispatchWorkItem?
    private var iconRowEdgeHoverIndex: Int?
    private var pendingPreviewUpdates: [CGWindowID: CGImage] = [:]
    private var previewBatchWorkItem: DispatchWorkItem?

    private var sessionStartWindowID: CGWindowID?
    private var sessionSourceContext: SwitcherSourceContext?
    private(set) var sessionShortcut: GlobalShortcut?
    @Published private(set) var sessionScope: SwitcherSessionScope = .allApps
    private var shiftBackNavigationHeld = false
    private var shiftBackChordDeadline: TimeInterval = 0

    private var closingItemIDs: Set<String> = []
    private var commitPendingForClose = false
    private var terminationObserver: NSObjectProtocol?
    private var quittingPIDs: Set<pid_t> = []

    private enum KeyCode {
        static let tab: Int64 = 48
        static let delete: Int64 = 51
        static let escape: Int64 = 53
        static let enter: Int64 = 36
        static let leftArrow: Int64 = 123
        static let rightArrow: Int64 = 124
        static let downArrow: Int64 = 125
        static let upArrow: Int64 = 126
    }

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    private var isTapLive: Bool {
        lifecycleLock.withLock {
            guard let tap else { return false }
            return CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap)
        }
    }

    private var tapIsWanted: Bool {
        SessionActivitySupport.tapShouldRun(
            featureWanted: AppFeature.switcher.isAvailable
                && UserDefaults.standard.bool(forKey: DefaultsKey.switcherEnabled),
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive)
    }

    func syncWithPreferences() {
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.switcherShortcut,
                                            fallback: .switcherDefault)
        let windowShortcut = GlobalShortcut.saved(for: DefaultsKey.switcherWindowShortcut,
                                                  fallback: .switcherWindowDefault)
        let allWindowsShortcut = Self.allWindowsShortcut
        routeLock.withLock {
            routeShortcut = shortcut
            routeWindowShortcut = windowShortcut
            routeAllWindowsShortcut = allWindowsShortcut
        }
        let canStartSession = tapIsWanted
        routeLock.withLock { routeCanStartSession = canStartSession }
        if canStartSession {
            startObservingKeyboardLayout()
            startObservingWake()
            installTap()
            if !UserDefaults.standard.bool(forKey: DefaultsKey.switcherTakeOverSystemShortcuts) {
                secureInputWatch.stop()
                restoreNativeHotkeys()
            } else {
                secureInputWatch.start()
                applyNativeHotkeySuppressionIfTapLive()
            }
            let panel = ensurePanel()
            panel.contentViewController?.view.layoutSubtreeIfNeeded()
            if !capturesPreviews {
                WindowPreviewProvider.shared.stopWarming()
            } else {
                WindowPreviewProvider.shared.startWarming()
            }
        } else {
            secureInputWatch.stop()
            restoreNativeHotkeys()
            stopObservingKeyboardLayout()
            stopObservingWake()
            removeTap()
            WindowPreviewProvider.shared.stopWarming()
        }
    }

    func suspend() {
        secureInputWatch.stop()
        restoreNativeHotkeys()
        stopObservingWake()
        routeLock.withLock { routeCanStartSession = false }
        removeTap()
    }

    func setCapturingShortcut(_ capturing: Bool) {
        if capturing, sessionActive { cancelSession() }
        routeLock.withLock {
            routeCapturing = capturing
            if capturing {
                routePendingSessionStart = nil
            }
        }
    }

    // MARK: - Event tap

    private func startObservingKeyboardLayout() {
        GlobalShortcut.refreshLayoutLabels()
        guard keyboardLayoutObserver == nil else { return }
        keyboardLayoutObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in GlobalShortcut.refreshLayoutLabels() }
    }

    private func stopObservingKeyboardLayout() {
        if let keyboardLayoutObserver {
            DistributedNotificationCenter.default().removeObserver(keyboardLayoutObserver)
        }
        keyboardLayoutObserver = nil
    }

    private func startObservingWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.recoverTapAfterWake() }
    }

    private func stopObservingWake() {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        wakeRetry?.cancel()
        wakeRetry = nil
    }

    private func recoverTapAfterWake() {
        reconcileTakeover()
        wakeRetry?.cancel()
        let retry = DispatchWorkItem { [weak self] in self?.reconcileTakeover() }
        wakeRetry = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: retry)
    }

    private func reconcileTakeover() {
        guard tapIsWanted else {
            restoreNativeHotkeys()
            return
        }
        if !isTapLive {
            restoreNativeHotkeys()
            removeTap()
            installTap()
        } else {
            applyNativeHotkeySuppressionIfTapLive()
        }
    }

    private func installTap() {
        let thread = lifecycleLock.withLock { () -> Thread? in
            if tapThread != nil {
                if shouldStopTapThread { pendingStartAfterStop = true }
                return nil
            }
            shouldStopTapThread = false
            pendingStartAfterStop = false
            let thread = Thread { [weak self] in
                self?.runEventTap()
            }
            thread.name = "EVERYTHING Switcher"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return thread
        }
        thread?.start()
    }

    private func removeTap() {
        if sessionActive { cancelSession() }
        routeLock.withLock { routePendingSessionStart = nil }
        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool) in
            shouldStopTapThread = true
            pendingStartAfterStop = false
            return (tapRunLoop, tap, tapThread != nil)
        }
        if let tap = snapshot.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoop = snapshot.runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else if !snapshot.threadExists {
            lifecycleLock.withLock {
                shouldStopTapThread = false
                tapThread = nil
            }
        }
    }

    private func runEventTap() {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock { tapRunLoop = runLoop }

            let shouldStopBeforeCreatingTap = lifecycleLock.withLock { shouldStopTapThread }
            guard !shouldStopBeforeCreatingTap else {
                if clearEventTapThread() { installTap() }
                return
            }

            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
                | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
                | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
                | CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
                | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
                | CGEventMask(1 << CGEventType.scrollWheel.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let switcher = Unmanaged<AppSwitcher>.fromOpaque(userInfo).takeUnretainedValue()
                    return switcher.route(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearEventTapThread()
                DispatchQueue.main.async { [weak self] in self?.restoreNativeHotkeys() }
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            lifecycleLock.withLock {
                self.tap = tap
                runLoopSource = source
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            let shouldStop = lifecycleLock.withLock { shouldStopTapThread }
            if shouldStop {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.applyNativeHotkeySuppressionIfTapLive()
                }
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            if clearEventTapThread() { installTap() }
        }
    }

    private func applyNativeHotkeySuppression() {
        let (apps, windows, allWindows) = routeLock.withLock {
            (routeShortcut, routeWindowShortcut, routeAllWindowsShortcut)
        }
        let takeOver = UserDefaults.standard.bool(
            forKey: DefaultsKey.switcherTakeOverSystemShortcuts)
        SystemShortcutTakeover.setWanted(
            SwitcherSupport.nativeHotkeyIDs(
                takeOverSystemShortcuts: takeOver,
                secureInputEnabled: IsSecureEventInputEnabled(),
                appsShortcut: apps,
                windowShortcut: windows,
                allWindowsShortcut: allWindows,
                liveEntries: SymbolicHotKeys.entries(for: SwitcherNativeSymbolicHotKey.ids) ?? []),
            for: SystemShortcutTakeover.switcherSource)
    }

    static func launchTakeoverIDs() -> Set<Int32> {
        guard SessionActivitySupport.tapShouldRun(
                  featureWanted: AppFeature.switcher.isAvailable
                      && UserDefaults.standard.bool(forKey: DefaultsKey.switcherEnabled),
                  accessibilityGranted: AXIsProcessTrusted(),
                  sessionIsActive: SessionActivity.shared.isActive),
              UserDefaults.standard.bool(forKey: DefaultsKey.switcherTakeOverSystemShortcuts)
        else { return [] }
        return SwitcherSupport.nativeHotkeyIDs(
            takeOverSystemShortcuts: true,
            secureInputEnabled: IsSecureEventInputEnabled(),
            appsShortcut: GlobalShortcut.saved(for: DefaultsKey.switcherShortcut,
                                               fallback: .switcherDefault),
            windowShortcut: GlobalShortcut.saved(for: DefaultsKey.switcherWindowShortcut,
                                                 fallback: .switcherWindowDefault),
            allWindowsShortcut: allWindowsShortcut,
            liveEntries: SymbolicHotKeys.entries(for: SwitcherNativeSymbolicHotKey.ids) ?? [])
    }

    private static var allWindowsShortcut: GlobalShortcut? {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.switcherAllWindowsShortcutEnabled) else { return nil }
        return GlobalShortcut.saved(for: DefaultsKey.switcherAllWindowsShortcut,
                                     fallback: .switcherAllWindowsDefault)
    }

    private func applyNativeHotkeySuppressionIfTapLive() {
        let canStart = routeLock.withLock { routeCanStartSession }
        guard isTapLive, canStart else { return }
        applyNativeHotkeySuppression()
    }

    private func restoreNativeHotkeys() {
        SystemShortcutTakeover.setWanted([], for: SystemShortcutTakeover.switcherSource)
    }

    private func secureInputChanged(_ enabled: Bool) {
        guard enabled else {
            applyNativeHotkeySuppressionIfTapLive()
            return
        }
        routeLock.withLock { routePendingSessionStart = nil }
        if sessionActive { cancelSession() }
        restoreNativeHotkeys()
    }

    private func clearEventTapThread() -> Bool {
        lifecycleLock.withLock {
            let shouldRestart = pendingStartAfterStop
            tap = nil
            runLoopSource = nil
            tapRunLoop = nil
            tapThread = nil
            shouldStopTapThread = false
            pendingStartAfterStop = false
            return shouldRestart
        }
    }

    private func route(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let currentTap = lifecycleLock.withLock { shouldStopTapThread ? nil : tap }
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let currentTap {
                CGEvent.tapEnable(tap: currentTap, enable: true)
            } else if currentTap != nil {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            routeLock.withLock { routePendingSessionStart = nil }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.sessionActive else { return }
                self.cancelSession()
            }
            return Unmanaged.passUnretained(event)
        }

        let (active, shortcut, windowShortcut, allWindowsShortcut, capturing, canStartSession, hasPendingStart) = routeLock.withLock {
            (routeSessionActive, routeShortcut, routeWindowShortcut, routeAllWindowsShortcut, routeCapturing,
             routeCanStartSession, routePendingSessionStart != nil)
        }
        if capturing { return Unmanaged.passUnretained(event) }
        if !active {
            guard canStartSession else { return Unmanaged.passUnretained(event) }
            if type == .flagsChanged {
                let stillInactive = routeLock.withLock { () -> Bool in
                    guard !routeSessionActive else { return false }
                    if var pending = routePendingSessionStart,
                       !pending.shortcut.requiredModifiersHeld(in: event.flags) {
                        pending.commitWhenReady = true
                        routePendingSessionStart = pending
                    }
                    return true
                }
                if stillInactive { return Unmanaged.passUnretained(event) }
                var verdict: Unmanaged<CGEvent>?
                DispatchQueue.main.sync {
                    verdict = self.handle(type: type, event: event)
                }
                return verdict
            }
            if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown || type == .otherMouseUp {
                let startPending = routeLock.withLock {
                    !routeSessionActive && routePendingSessionStart != nil
                }
                let clickPressedAKey = startPending && AssistiveKeyboard.ownsPoint(event.location)
                let stillInactive = routeLock.withLock { () -> Bool in
                    guard !routeSessionActive else { return false }
                    if !clickPressedAKey { routePendingSessionStart = nil }
                    return true
                }
                if stillInactive { return Unmanaged.passUnretained(event) }
                var verdict: Unmanaged<CGEvent>?
                DispatchQueue.main.sync {
                    verdict = self.handle(type: type, event: event)
                }
                return verdict
            }
            guard type == .keyDown else { return Unmanaged.passUnretained(event) }
            let match = SwitcherSupport.shortcutMatch(event: event,
                                                       appsShortcut: shortcut,
                                                       windowShortcut: windowShortcut,
                                                       allWindowsShortcut: allWindowsShortcut)
            let matchesShortcut = match != nil
            guard matchesShortcut || hasPendingStart else {
                return Unmanaged.passUnretained(event)
            }
            let pendingKeyDecision = routeLock.withLock { () -> SwitcherPendingKeyDecision in
                let decision = SwitcherSupport.pendingKeyDecision(
                    sessionIsActive: routeSessionActive,
                    hasPendingStart: routePendingSessionStart != nil,
                    commitWhenReady: routePendingSessionStart?.commitWhenReady ?? false,
                    matchesShortcut: matchesShortcut
                )
                if decision == .cancelAndSwallow {
                    routePendingSessionStart = nil
                }
                return decision
            }
            switch pendingKeyDecision {
            case .swallow, .cancelAndSwallow:
                return nil
            case .handleActiveSession:
                break
            case .routeShortcut:
                guard let match else { return Unmanaged.passUnretained(event) }
                let (requestedShortcut, requestedScope, reversed) = match

                var generationToSchedule: UInt64?
                let claimedWhileInactive = routeLock.withLock { () -> Bool in
                    guard !routeSessionActive else { return false }
                    if var pending = routePendingSessionStart {
                        if pending.commitWhenReady {
                            sessionStartGeneration &+= 1
                            let generation = sessionStartGeneration
                            routePendingSessionStart = SwitcherPendingSessionStart(
                                generation: generation,
                                shortcut: requestedShortcut,
                                scope: requestedScope,
                                reversed: reversed
                            )
                            generationToSchedule = generation
                            return true
                        }
                        if pending.scope == requestedScope {
                            let next = pending.additionalNavigation + (reversed ? -1 : 1)
                            pending.additionalNavigation = max(-64, min(64, next))
                            routePendingSessionStart = pending
                        }
                        return true
                    }
                    sessionStartGeneration &+= 1
                    let generation = sessionStartGeneration
                    routePendingSessionStart = SwitcherPendingSessionStart(
                        generation: generation,
                        shortcut: requestedShortcut,
                        scope: requestedScope,
                        reversed: reversed
                    )
                    generationToSchedule = generation
                    return true
                }
                if claimedWhileInactive {
                    if let generationToSchedule {
                        DispatchQueue.main.async { [weak self] in
                            self?.beginPendingSession(generation: generationToSchedule)
                        }
                    }
                    return nil
                }
            }
        }

        var verdict: Unmanaged<CGEvent>?
        DispatchQueue.main.sync {
            verdict = self.handle(type: type, event: event)
        }
        return verdict
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard Permissions.shared.accessibility else {
            if sessionActive { cancelSession() }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .scrollWheel:
            guard sessionActive else { return Unmanaged.passUnretained(event) }
            let direction = ScrollDirectionPreferences(defaults: .standard)
            let directionApplies = direction.isEnabled
                && ScrollWheelHIDStage.shared.passed(event)
                && !MouseAppExceptions.shared.excludesPointerTarget(
                    .scrollDirection, at: event.location,
                    sourceProcessID: event.getIntegerValueField(.eventSourceUnixProcessID))
            let delta = scrollNavigation.selectionDelta(for: event, direction: directionApplies ? direction : nil)
            if delta != 0 {
                hoverAnchor = NSEvent.mouseLocation
                hoveredWindowIndex = nil
                advanceSelection(by: delta, wrapping: false)
            }
            return nil
        case .keyDown:
            return handleKeyDown(event)
        case .flagsChanged:
            if sessionActive, !isSearchPinned {
                if let shortcut = sessionShortcut,
                   !shortcut.requiredModifiersHeld(in: event.flags) {
                    commitSession()
                } else if handleShiftBackNavigation(flags: event.flags) {
                    return nil
                }
            }
            return Unmanaged.passUnretained(event)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if type == .otherMouseDown,
               let panel,
               let hoveredWindowIndex,
               windows.indices.contains(hoveredWindowIndex),
               SwitcherSupport.isMiddleClickInsidePanel(
                   eventType: type,
                   buttonNumber: event.getIntegerValueField(.mouseEventButtonNumber),
                   panelIsVisible: panel.isVisible,
                   panelFrame: panel.frame,
                   location: NSEvent.mouseLocation,
                   itemIsHovered: true
               ) {
                swallowingMiddleMouseUp = true
                self.hoveredWindowIndex = nil
                closeWindow(windows[hoveredWindowIndex])
                return nil
            }
            swallowingMiddleMouseUp = false
            dismissForClickOutsidePanel(event)
            return Unmanaged.passUnretained(event)
        case .otherMouseUp:
            let shouldSwallow = SwitcherSupport.shouldSwallowMiddleMouseUp(
                   eventType: type,
                   buttonNumber: event.getIntegerValueField(.mouseEventButtonNumber),
                   swallowedMouseDown: swallowingMiddleMouseUp
               )
            swallowingMiddleMouseUp = false
            if shouldSwallow {
                return nil
            }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        guard sessionActive else { return nil }

        let (appsShortcut, windowShortcut) = routeLock.withLock {
            (routeShortcut, routeWindowShortcut)
        }
        let shortcut = sessionShortcut ?? appsShortcut
        switch keyCode {
        case _ where keyCode == shortcut.keyCode && shortcut.matches(event: event, allowingExtraShift: true):
            if shortcut.shiftIsNavigationModifier, flags.contains(.maskShift), consumesShiftBackChordTab() {
                break
            }
            let delta = shortcut.shiftIsNavigationModifier && flags.contains(.maskShift) ? -1 : 1
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            advanceSelection(by: delta, wrapping: !isRepeat)
        case _ where sessionScope != .allApps
            && keyCode == appsShortcut.keyCode
            && appsShortcut.matches(event: event,
                                    allowingExtraShift: true,
                                    tolerating: shortcut.modifiers):
            if appsShortcut.shiftIsNavigationModifier, flags.contains(.maskShift), consumesShiftBackChordTab() {
                break
            }
            let delta = appsShortcut.shiftIsNavigationModifier && flags.contains(.maskShift) ? -1 : 1
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            advanceSelection(by: delta, wrapping: !isRepeat)
        case _ where searchQuery.isEmpty
            && (windowShortcut.matches(event: event, allowingExtraShift: true,
                                       tolerating: shortcut.modifiers)
                || windowShortcut.matchesByCharacter(event: event,
                                                     tolerating: shortcut.modifiers)):
            let positional = windowShortcut.matches(event: event, allowingExtraShift: true,
                                                    tolerating: shortcut.modifiers)
            let delta = SwitcherSupport.windowNavigationDelta(
                positionalMatch: positional,
                shiftIsNavigationModifier: windowShortcut.shiftIsNavigationModifier,
                shiftHeld: flags.contains(.maskShift)
            )
            if sessionScope == .frontmostApp {
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                advanceSelection(by: delta, wrapping: !isRepeat)
            } else {
                advanceWindowInSelectedApp(by: delta)
            }
        case KeyCode.rightArrow:
            advanceSelection(by: 1)
        case KeyCode.leftArrow:
            advanceSelection(by: -1)
        case KeyCode.downArrow:
            moveSelection(by: grid.columns)
        case KeyCode.upArrow:
            moveSelection(by: -grid.columns)
        case KeyCode.delete:
            removeLastSearchCharacter()
        case KeyCode.escape:
            cancelSession()
        case KeyCode.enter:
            commitSession()
        default:
            let text = printableSearchText(from: event)
            if searchQuery.isEmpty, !isSearchPinned,
               let action = SwitcherSupport.letterAction(typedCharacter: text, keyCode: keyCode, pinSearchEnabled: searchPinEnabled) {
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    switch action {
                    case .closeWindow, .quitApp: runProtectedLetterAction(action)
                    case .pinSearch: pinSearch()
                    }
                }
            } else if let text {
                appendSearchText(text)
            }
        }
        return nil
    }

    // MARK: - Session lifecycle

    private func beginPendingSession(generation: UInt64) {
        guard routeLock.withLock({
            SwitcherSupport.isCurrentSessionStart(
                generation: generation,
                pendingGeneration: routePendingSessionStart?.generation
            )
        }) else { return }
        guard Permissions.shared.accessibility,
              AXIsProcessTrusted(),
              lifecycleLock.withLock({ tap != nil && !shouldStopTapThread })
        else {
            discardPendingSessionStart(generation: generation)
            return
        }

        guard let requested = routeLock.withLock({ () -> SwitcherPendingSessionStart? in
            guard SwitcherSupport.isCurrentSessionStart(
                generation: generation,
                pendingGeneration: routePendingSessionStart?.generation
            ) else { return nil }
            return routePendingSessionStart
        }) else { return }
        let allApps = requested.scope == .allApps
        let mergeWindowsByApp = UserDefaults.standard.bool(forKey: DefaultsKey.switcherMergeTabs)
        let groupByApp = allApps && mergeWindowsByApp
        let preservesGroupedWindows = SwitcherSupport.preservesGroupedWindowsDuringEnumeration(
            allApps: allApps,
            mergeWindowsByApp: mergeWindowsByApp,
            simpleMode: simpleModeEnabled
        )
        guard let reportedFrontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            discardPendingSessionStart(generation: generation)
            return
        }
        let enumerationSnapshot = WindowEnumerator.snapshot()
        let displayScope = currentDisplayScope
        enumerationQueue.async { [weak self] in
            guard let self,
                  self.routeLock.withLock({
                      SwitcherSupport.isCurrentSessionStart(
                          generation: generation,
                          pendingGeneration: self.routePendingSessionStart?.generation
                      )
                  })
            else { return }
            var focusedSourceWindowID: CGWindowID?
            let enumeration = WindowEnumerator.enumerateSwitcherWindows(
                groupByApp: groupByApp,
                preservingGroupedWindows: preservesGroupedWindows,
                snapshot: enumerationSnapshot,
                windowsOnly: requested.scope == .allWindows,
                displayScope: displayScope,
                scopedToFrontmostPID: requested.scope == .frontmostApp ? reportedFrontPID : nil,
                resolveSource: { items in
                    let sourceItems = SwitcherSupport.windowsForSession(
                        items, scope: requested.scope, frontmostPID: reportedFrontPID)
                    guard !sourceItems.isEmpty else { return nil }
                    focusedSourceWindowID = SwitcherSupport.needsFocusedWindowLookup(
                        frontmostPID: reportedFrontPID, items: sourceItems)
                        ? self.focusedWindowID(for: reportedFrontPID,
                                               accessibilityGranted: enumerationSnapshot.accessibilityGranted)
                        : nil
                    return SwitcherSupport.sessionSourceItem(frontmostPID: reportedFrontPID,
                                                             focusedWindowID: focusedSourceWindowID,
                                                             items: sourceItems)
                },
                isCancelled: { [weak self] in
                    guard let self else { return true }
                    return !self.routeLock.withLock {
                        SwitcherSupport.isCurrentSessionStart(
                            generation: generation,
                            pendingGeneration: self.routePendingSessionStart?.generation
                        )
                    }
                }
            )
            guard self.routeLock.withLock({
                SwitcherSupport.isCurrentSessionStart(
                    generation: generation,
                    pendingGeneration: self.routePendingSessionStart?.generation
                )
            }) else { return }
            let sessionWindows = SwitcherSupport.windowsForSession(
                enumeration.items, scope: requested.scope, frontmostPID: reportedFrontPID)
            DispatchQueue.main.async { [weak self] in
                self?.finishPendingSession(generation: generation,
                                           reportedFrontPID: reportedFrontPID,
                                           focusedSourceWindowID: focusedSourceWindowID,
                                           windows: sessionWindows,
                                           sourceItems: enumeration.sourceItems)
            }
        }
    }

    private func finishPendingSession(generation: UInt64,
                                      reportedFrontPID: pid_t,
                                      focusedSourceWindowID: CGWindowID?,
                                      windows: [SwitcherItem],
                                      sourceItems: [SwitcherItem]) {
        guard routeLock.withLock({
            SwitcherSupport.isCurrentSessionStart(
                generation: generation,
                pendingGeneration: routePendingSessionStart?.generation
            )
        }) else { return }
        guard !windows.isEmpty else {
            discardPendingSessionStart(generation: generation)
            return
        }
        let source = SwitcherSupport.sessionSourceItem(frontmostPID: reportedFrontPID,
                                                       focusedWindowID: focusedSourceWindowID,
                                                       items: sourceItems)
        let listedSource = source.flatMap { item in
            windows.contains { $0.id == item.id } ? item : nil
        }

        let list = SwitcherSupport.orderedForSession(windows, currentID: listedSource?.id)
        guard let pending = routeLock.withLock({ () -> SwitcherPendingSessionStart? in
            guard SwitcherSupport.isCurrentSessionStart(
                generation: generation,
                pendingGeneration: routePendingSessionStart?.generation
            ) else { return nil }
            let pending = routePendingSessionStart
            routePendingSessionStart = nil
            routeSessionActive = true
            return pending
        }) else { return }
        sessionItems = list
        totalWindowCount = list.count
        searchQuery = ""
        isSearchPinned = false
        SwitcherAppIconCache.beginSession()
        self.windows = list
        sessionSourceContext = source.map { source in
            SwitcherSourceContext(itemID: source.id,
                                  pid: source.pid,
                                  windowID: source.windowID,
                                  windowOwnerPID: source.windowOwnerPID,
                                  isFullscreen: source.isFullscreen,
                                  frame: source.frame)
        }
        sessionStartWindowID = source?.windowID
        sessionScope = pending.scope
        recomputeLayouts(for: list)
        if !capturesPreviews {
            previews = [:]
        } else {
            previews = Dictionary(uniqueKeysWithValues: list.compactMap { item in
                item.previewWindowID.flatMap { id in
                    WindowPreviewProvider.shared.cachedPreview(for: id).map { (id, $0) }
                }
            })
        }
        userNavigated = false
        selectedIndex = initialSelectionIndex(in: list,
                                              reversed: pending.reversed,
                                              hasForegroundItem: listedSource != nil,
                                              frontmostPID: SwitcherSupport.appPID(forFrontmost: reportedFrontPID,
                                                                                   items: list))
        sessionShortcut = pending.shortcut
        shiftBackNavigationHeld = pending.reversed && pending.shortcut.shiftIsNavigationModifier

        if pending.additionalNavigation != 0 {
            let delta = pending.additionalNavigation < 0 ? -1 : 1
            for _ in 0..<abs(pending.additionalNavigation) {
                advanceSelection(by: delta)
            }
        }

        startObservingTermination(generation: generation)
        if pending.commitWhenReady {
            commitSession()
        } else if capturesPreviews {
            WindowPreviewProvider.shared.refreshPreviews(for: list, maxPixelSize: 640 * PreviewSizing.switcherScale,
                                                          excludedAppsKey: DefaultsKey.switcherPreviewExcludedApps) { [weak self] windowID, image in
                guard let self,
                      self.sessionActive,
                      self.sessionItems.contains(where: { $0.previewWindowID == windowID }) else { return }
                self.enqueuePreviewUpdate(windowID: windowID, image: image)
            }
        }
        if !pending.commitWhenReady {
            scheduleShowPanel()
        }
    }

    private func discardPendingSessionStart(generation: UInt64) {
        routeLock.withLock {
            guard SwitcherSupport.isCurrentSessionStart(
                generation: generation,
                pendingGeneration: routePendingSessionStart?.generation
            ) else { return }
            routePendingSessionStart = nil
        }
    }

    private func handleShiftBackNavigation(flags: CGEventFlags) -> Bool {
        let shiftHeld = flags.contains(.maskShift)
        defer { shiftBackNavigationHeld = shiftHeld }
        guard let shortcut = sessionShortcut,
              SwitcherSupport.shouldNavigateBackwardOnShiftPress(shiftIsNavigationModifier: shortcut.shiftIsNavigationModifier,
                                                                  wasShiftHeld: shiftBackNavigationHeld,
                                                                  isShiftHeld: shiftHeld)
        else { return false }
        advanceSelection(by: -1)
        shiftBackChordDeadline = ProcessInfo.processInfo.systemUptime
            + SwitcherSupport.shiftBackChordWindow
        return true
    }

    private func consumesShiftBackChordTab() -> Bool {
        guard ProcessInfo.processInfo.systemUptime < shiftBackChordDeadline else { return false }
        shiftBackChordDeadline = 0
        return true
    }

    private func initialSelectionIndex(in items: [SwitcherItem],
                                       reversed: Bool,
                                       hasForegroundItem: Bool,
                                       frontmostPID: pid_t) -> Int {
        guard !items.isEmpty else { return 0 }
        if sessionScope != .allApps {
            return SwitcherSupport.initialWindowScopedSelectionIndex(itemCount: items.count,
                                                                      hasForegroundItem: hasForegroundItem,
                                                                      reversed: reversed)
        }
        guard SwitcherSupport.usesAppGroupsForMainShortcut(
            iconRowLayout: usesIconRowLayout,
            windowRow: usesWindowRow
        ) else {
            return SwitcherSupport.initialSelectionPosition(pids: items.map(\.pid),
                                                            hasForegroundEntry: hasForegroundItem,
                                                            frontmostPID: frontmostPID,
                                                            reversed: reversed)
        }

        let groups = SwitcherSupport.appGroups(items: items, currentSpaceOnly: currentSpaceOnly)
        guard !groups.isEmpty else { return 0 }
        let groupIndex = SwitcherSupport.initialSelectionPosition(pids: groups.map(\.pid),
                                                                  hasForegroundEntry: hasForegroundItem,
                                                                  frontmostPID: frontmostPID,
                                                                  reversed: reversed)
        return groups[groupIndex].representativeIndex
    }

    private func focusedWindowID(for pid: pid_t, accessibilityGranted: Bool) -> CGWindowID? {
        guard accessibilityGranted else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.35)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let window = value as! AXUIElement
        return AXWindowResolver.windowID(for: window)
    }

    private func recordUse(_ activated: SwitcherItem, previous: CGWindowID?) {
        WindowUseTracker.shared.recordSwitch(to: activated.windowID, pid: activated.pid, from: previous)
    }

    func select(index: Int) {
        guard sessionActive, windows.indices.contains(index) else { return }
        userNavigated = true
        selectedIndex = index
    }

    func hoverSelect(index: Int) {
        guard sessionActive, windows.indices.contains(index) else { return }
        hoveredWindowIndex = index
        let mouse = NSEvent.mouseLocation
        if let anchor = hoverAnchor {
            guard hypot(mouse.x - anchor.x, mouse.y - anchor.y) > 4 else { return }
            hoverAnchor = nil
        }
        select(index: index)
    }

    func hoverSelectEnded(index: Int) {
        if hoveredWindowIndex == index { hoveredWindowIndex = nil }
    }

    func hoverSelectIconRow(index: Int) {
        hoverSelect(index: index)
        guard hoverAnchor == nil else { return }
        beginIconRowEdgeHoverIfNeeded(at: index)
    }

    func hoverSelectIconRowEnded(index: Int) {
        hoverSelectEnded(index: index)
        guard iconRowEdgeHoverIndex == iconRowIndex(forSelectionIndex: index) else { return }
        cancelIconRowEdgeHover()
    }

    private var selectedItemID: String? {
        guard windows.indices.contains(selectedIndex) else { return nil }
        return windows[selectedIndex].id
    }

    private func appendSearchText(_ text: String) {
        let clean = sanitizedSearchInput(text)
        guard !clean.isEmpty else { return }
        let preferredID = selectedItemID
        let remaining = max(0, 64 - searchQuery.count)
        guard remaining > 0 else { return }
        searchQuery += String(clean.prefix(remaining))
        applySearchFilter(preferredItemID: preferredID)
    }

    private func removeLastSearchCharacter() {
        guard !searchQuery.isEmpty else { return }
        let preferredID = selectedItemID
        searchQuery.removeLast()
        applySearchFilter(preferredItemID: preferredID)
    }

    private func printableSearchText(from event: CGEvent) -> String? {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 16)
        event.keyboardGetUnicodeString(maxStringLength: chars.count,
                                       actualStringLength: &length,
                                       unicodeString: &chars)
        guard length > 0 else { return nil }
        return sanitizedSearchInput(String(utf16CodeUnits: chars, count: length))
    }

    private func sanitizedSearchInput(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                && !CharacterSet.newlines.contains(scalar)
        }))
    }

    private func pinSearch() {
        isSearchPinned = true
        recomputeLayouts(for: windows)
        resizePanel()
    }

    private func applySearchFilter(preferredItemID: String?) {
        let records = sessionItems.map { item in
            SwitcherSearchRecord(id: item.id, title: item.title, appName: item.appName)
        }
        let visibleIDs = Set(SwitcherSupport.filteredSearchIDs(records: records, query: searchQuery))
        windows = sessionItems.filter { visibleIDs.contains($0.id) }
        selectedIndex = SwitcherSupport.searchSelectionIndex(itemIDs: windows.map(\.id),
                                                             preferredID: preferredItemID,
                                                             previousIndex: selectedIndex)
        recomputeLayouts(for: windows)
        resizePanel()
    }

    func closeWindow(_ item: SwitcherItem) {
        guard sessionActive,
              windows.contains(where: { $0.id == item.id }),
              !closingItemIDs.contains(item.id),
              let windowID = item.windowID
        else { return }

        closingItemIDs.insert(item.id)
        WindowActivator.closeWindowIncludingHiddenState(item) { [weak self] didClose in
            guard let self else { return }
            guard didClose else {
                self.closingItemIDs.remove(item.id)
                self.resumePendingCommitAfterClose()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                self?.finishClosingWindow(itemID: item.id,
                                          windowID: windowID,
                                          pid: item.pid,
                                          attempt: 0)
            }
        }
    }

    private func advanceSelection(by delta: Int, wrapping: Bool = true) {
        cancelIconRowEdgeHover()
        guard !windows.isEmpty else { return }
        if SwitcherSupport.usesAppGroupsForMainShortcut(
            iconRowLayout: usesIconRowLayout,
            windowRow: usesWindowRow
        ), sessionScope == .allApps {
            advanceAppSelection(by: delta, wrapping: wrapping)
            return
        }
        userNavigated = true
        let next = selectedIndex + delta
        if !wrapping, !windows.indices.contains(next) { return }
        selectedIndex = (next + windows.count) % windows.count
    }

    private func advanceAppSelection(by delta: Int, wrapping: Bool = true) {
        cancelIconRowEdgeHover()
        userNavigated = true
        selectedIndex = SwitcherSupport.nextAppSelectionIndex(items: windows,
                                                              selectedIndex: selectedIndex,
                                                              delta: delta,
                                                              wrapping: wrapping,
                                                              currentSpaceOnly: currentSpaceOnly)
    }

    private func advanceWindowInSelectedApp(by delta: Int) {
        userNavigated = true
        selectedIndex = SwitcherSupport.nextWindowSelectionIndexWithinApp(items: windows,
                                                                          selectedIndex: selectedIndex,
                                                                          delta: delta)
    }

    private func runProtectedLetterAction(_ action: SwitcherLetterAction) {
        guard windows.indices.contains(selectedIndex) else { return }
        let item = windows[selectedIndex]
        let shortcut: QuitProtectionShortcut = action == .quitApp ? .quit : .close
        guard let confirmation = QuitProtectionService.shared.selectionConfirmation(
            for: shortcut,
            bundleIdentifier: NSRunningApplication(processIdentifier: item.pid)?.bundleIdentifier
        ) else {
            performLetterAction(action)
            return
        }

        let pending = pendingLetterConfirmation
        cancelLetterConfirmation()
        if let pending, pending.action == action, pending.itemID == item.id {
            performLetterAction(action)
            return
        }

        let expiry = DispatchWorkItem { [weak self] in self?.cancelLetterConfirmation() }
        pendingLetterConfirmation = PendingLetterConfirmation(action: action,
                                                             itemID: item.id,
                                                             expiry: expiry)
        if confirmation.showsFeedback {
            QuitProtectionService.shared.showSelectionHUD(for: shortcut, on: placementScreen)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + confirmation.intervalMilliseconds / 1_000,
                                      execute: expiry)
    }

    private func performLetterAction(_ action: SwitcherLetterAction) {
        switch action {
        case .closeWindow: closeSelectedWindow()
        case .quitApp: quitSelectedApp()
        case .pinSearch: break
        }
    }

    private func cancelLetterConfirmation() {
        guard let pending = pendingLetterConfirmation else { return }
        pending.expiry.cancel()
        pendingLetterConfirmation = nil
        QuitProtectionService.shared.hideSelectionHUD()
    }

    private func closeSelectedWindow() {
        guard windows.indices.contains(selectedIndex) else { return }
        closeWindow(windows[selectedIndex])
    }

    private func quitSelectedApp() {
        guard windows.indices.contains(selectedIndex) else { return }
        let pid = windows[selectedIndex].pid
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier != Defaults.finderBundleIdentifier else { return }
        guard !quittingPIDs.contains(pid), app.terminate() else { return }
        quittingPIDs.insert(pid)
        let markedIDs = Set(sessionItems.lazy.filter { $0.pid == pid }.map(\.id))
            .subtracting(closingItemIDs)
        closingItemIDs.formUnion(markedIDs)
        let generation = routeLock.withLock { sessionStartGeneration }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, self.sessionActive,
                  self.routeLock.withLock({ self.sessionStartGeneration == generation }),
                  self.quittingPIDs.contains(pid) else { return }
            if app.isTerminated {
                self.removeTerminatedApp(pid: pid)
            } else {
                self.quittingPIDs.remove(pid)
                self.closingItemIDs.subtract(markedIDs)
                self.resumePendingCommitAfterClose()
            }
        }
    }

    private func startObservingTermination(generation: UInt64) {
        stopObservingTermination()
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, self.sessionActive,
                  self.routeLock.withLock({ self.sessionStartGeneration == generation }),
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self.removeTerminatedApp(pid: app.processIdentifier)
        }
    }

    private func stopObservingTermination() {
        guard let terminationObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        self.terminationObserver = nil
    }

    private func removeTerminatedApp(pid: pid_t) {
        quittingPIDs.remove(pid)
        guard sessionActive, sessionItems.contains(where: { $0.pid == pid }) else { return }
        let removedIDs = Set(sessionItems.lazy.filter { $0.pid == pid }.map(\.id))
        closingItemIDs.subtract(removedIDs)
        let removedBeforeSelection = windows[..<selectedIndex].filter { $0.pid == pid }.count
        sessionItems.removeAll { $0.pid == pid }
        totalWindowCount = sessionItems.count
        windows.removeAll { $0.pid == pid }
        let remaining = Set(windows.compactMap(\.previewWindowID))
        previews = previews.filter { remaining.contains($0.key) }

        guard !sessionItems.isEmpty else {
            endSession()
            return
        }
        guard !windows.isEmpty else {
            selectedIndex = 0
            recomputeLayouts(for: windows)
            resizePanel()
            resumePendingCommitAfterClose()
            return
        }
        selectedIndex = min(max(0, selectedIndex - removedBeforeSelection), windows.count - 1)
        recomputeLayouts(for: windows)
        resizePanel()
        resumePendingCommitAfterClose()
    }

    private func finishClosingWindow(itemID: String, windowID: CGWindowID, pid: pid_t, attempt: Int) {
        guard sessionActive else { return }
        guard sessionItems.contains(where: { $0.id == itemID }) else {
            finishTrackingClose(itemID: itemID)
            return
        }

        let refreshed = WindowEnumerator.listWindows(for: pid, maximumCount: 64)
        guard !refreshed.contains(where: { $0.windowID == windowID }) else {
            guard attempt < 2 else {
                closingItemIDs.remove(itemID)
                resumePendingCommitAfterClose()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.finishClosingWindow(itemID: itemID,
                                          windowID: windowID,
                                          pid: pid,
                                          attempt: attempt + 1)
            }
            return
        }

        applyClosedWindowRemoval(itemID: itemID, windowID: windowID)
    }

    private func applyClosedWindowRemoval(itemID: String, windowID: CGWindowID) {
        let state = SwitcherSupport.closeState(afterRemoving: itemID,
                                               itemIDs: windows.map(\.id),
                                               selectedIndex: selectedIndex)
        guard state.didRemove else {
            sessionItems.removeAll { $0.id == itemID }
            totalWindowCount = sessionItems.count
            previews.removeValue(forKey: windowID)
            closingItemIDs.remove(itemID)
            if sessionSourceContext?.itemID == itemID {
                sessionStartWindowID = nil
            }
            guard !sessionItems.isEmpty else {
                endSession()
                return
            }
            applySearchFilter(preferredItemID: selectedItemID)
            resumePendingCommitAfterClose()
            return
        }

        sessionItems.removeAll { $0.id == itemID }
        totalWindowCount = sessionItems.count
        let remaining = Set(state.remainingItemIDs)
        windows = windows.filter { remaining.contains($0.id) }
        let remainingPreviews = Set(windows.compactMap(\.previewWindowID))
        previews = previews.filter { remainingPreviews.contains($0.key) && $0.key != windowID }
        closingItemIDs.remove(itemID)
        if sessionSourceContext?.itemID == itemID {
            sessionStartWindowID = nil
        }

        guard !state.shouldEndSession else {
            if sessionItems.isEmpty || searchQuery.isEmpty {
                endSession()
            } else {
                selectedIndex = 0
                recomputeLayouts(for: windows)
                resizePanel()
                resumePendingCommitAfterClose()
            }
            return
        }

        selectedIndex = state.selectedIndex
        recomputeLayouts(for: windows)
        resizePanel()
        resumePendingCommitAfterClose()
    }

    private func finishTrackingClose(itemID: String) {
        closingItemIDs.remove(itemID)
        resumePendingCommitAfterClose()
    }

    private func moveSelection(by delta: Int) {
        if usesIconRowLayout {
            if iconRowLayout.isWrapped {
                moveIconRowSelection(movingDown: delta > 0)
            } else {
                advanceWindowInSelectedApp(by: delta < 0 ? -1 : 1)
            }
            return
        }
        guard delta != 0 else { return }
        let target = SwitcherSupport.gridSelectionIndex(after: selectedIndex,
                                                        itemCount: windows.count,
                                                        columns: grid.columns,
                                                        movingDown: delta > 0)
        guard target != selectedIndex else { return }
        userNavigated = true
        selectedIndex = target
    }

    private func moveIconRowSelection(movingDown: Bool) {
        guard let next = SwitcherSupport.iconRowSelectionIndex(after: selectedIndex,
                                                               items: windows,
                                                               windowRow: usesWindowRow,
                                                               columns: iconRowLayout.columns,
                                                               movingDown: movingDown,
                                                               currentSpaceOnly: currentSpaceOnly)
        else { return }
        userNavigated = true
        selectedIndex = next
    }

    func commitSession() {
        guard sessionActive else { return }
        guard closingItemIDs.isEmpty else {
            commitPendingForClose = true
            return
        }
        let selection = SwitcherSupport.commitTargetID(itemIDs: windows.map(\.id),
                                                       selectedIndex: selectedIndex,
                                                       closingItemIDs: closingItemIDs)
            .flatMap { id in windows.first { $0.id == id } }
        let source = sessionSourceContext
        let handoffSourcePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let previousWindowID = sessionStartWindowID
        endSession()
        if let selection {
            recordUse(selection, previous: previousWindowID)
            WindowActivator.activate(selection,
                                     sourceWasFullscreen: source?.isFullscreen ?? false,
                                     sourcePID: source?.pid,
                                     handoffSourcePID: handoffSourcePID,
                                     sourceWindowID: source?.isFullscreen == true ? nil : source?.windowID,
                                     sourceWindowOwnerPID: source?.windowOwnerPID)
        }
    }

    private func resumePendingCommitAfterClose() {
        guard commitPendingForClose, closingItemIDs.isEmpty, sessionActive else { return }
        commitPendingForClose = false
        commitSession()
    }

    private func cancelSession() {
        guard sessionActive else { return }
        endSession()
    }

    private func endSession() {
        stopObservingTermination()
        cancelLetterConfirmation()
        SwitcherAppIconCache.endSession()
        sessionActive = false
        pendingShow?.cancel()
        pendingShow = nil
        WindowPreviewProvider.shared.cancel()
        cancelPendingPreviewBatch()
        panel?.orderOut(nil)
        sessionItems = []
        windows = []
        previews = [:]
        selectedIndex = 0
        grid = .empty
        iconRowLayout = .empty
        searchQuery = ""
        isSearchPinned = false
        totalWindowCount = 0
        hoverAnchor = nil
        hoveredWindowIndex = nil
        cancelIconRowEdgeHover()
        scrollNavigation = SwitcherScrollNavigation()
        iconRowFirstVisibleIndex = 0
        userNavigated = false
        sessionStartWindowID = nil
        sessionPlacementVisibleFrame = nil
        sessionSourceContext = nil
        sessionShortcut = nil
        sessionScope = .allApps
        shiftBackNavigationHeld = false
        shiftBackChordDeadline = 0
        closingItemIDs = []
        quittingPIDs = []
        commitPendingForClose = false
    }

    private func enqueuePreviewUpdate(windowID: CGWindowID, image: CGImage) {
        pendingPreviewUpdates[windowID] = image
        guard previewBatchWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.previewBatchWorkItem = nil
            guard self.sessionActive else { return }
            let listed = Set(self.sessionItems.compactMap(\.previewWindowID))
            let updates = self.pendingPreviewUpdates.filter { listed.contains($0.key) }
            self.pendingPreviewUpdates.removeAll()
            guard !updates.isEmpty else { return }
            self.previews.merge(updates) { _, new in new }
        }
        previewBatchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
    }

    private func cancelPendingPreviewBatch() {
        previewBatchWorkItem?.cancel()
        previewBatchWorkItem = nil
        pendingPreviewUpdates.removeAll()
    }

    // MARK: - Panel

    private func scheduleShowPanel() {
        pendingShow?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.sessionActive else { return }
            self.showPanel()
        }
        pendingShow = work
        let appearanceDelay = SwitcherSupport.appearanceDelay(
            milliseconds: UserDefaults.standard.integer(forKey: DefaultsKey.switcherAppearanceDelay))
        DispatchQueue.main.asyncAfter(deadline: .now() + appearanceDelay, execute: work)
    }

    private func showPanel() {
        let panel = ensurePanel()
        panel.hasShadow = !usesIconRowLayout
        hoverAnchor = NSEvent.mouseLocation
        panel.setFrame(centeredFrame(for: currentPanelSize), display: true)
        panel.invalidateShadow()
        let animationBehavior = panel.animationBehavior
        panel.animationBehavior = .none
        panel.orderFrontRegardless()
        panel.animationBehavior = animationBehavior
    }

    private func dismissForClickOutsidePanel(_ event: CGEvent) {
        guard sessionActive, let panel else { return }
        if AssistiveKeyboard.ownsPoint(event.location) { return }
        guard SwitcherSupport.shouldDismissForClick(panelIsVisible: panel.isVisible,
                                                    panelFrame: panel.frame,
                                                    location: NSEvent.mouseLocation)
        else { return }
        cancelSession()
    }

    private func resizePanel(animated: Bool = true) {
        guard let panel else { return }
        let frame = centeredFrame(for: currentPanelSize)
        panel.hasShadow = !usesIconRowLayout
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: true, animate: panel.isVisible && animated)
        panel.invalidateShadow()
    }

    private var currentPanelSize: CGSize {
        let contentSize = usesIconRowLayout && !windows.isEmpty
            ? (simpleModeEnabled
                ? (usesWindowRow ? iconRowLayout.simpleWindowPanelSize : iconRowLayout.simplePanelSize)
                : iconRowLayout.panelSize)
            : grid.panelSize
        return CGSize(width: contentSize.width, height: contentSize.height + searchTopInset)
    }

    var searchTopInset: CGFloat {
        SwitcherSearchLayout.topInset(
            query: searchQuery,
            isPinned: isSearchPinned,
            contentPadding: usesIconRowLayout && !windows.isEmpty
                ? SwitcherIconRowLayout.padding : SwitcherGrid.padding
        )
    }

    private var iconRowModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.switcherIconRowMode)
    }

    private var simpleModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.switcherSimpleMode)
    }

    private var currentSpaceOnly: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.switcherCurrentSpaceOnly)
    }

    private var usesWindowRow: Bool {
        SwitcherSupport.usesWindowRow(
            simpleMode: simpleModeEnabled,
            mergeWindowsByApp: UserDefaults.standard.bool(forKey: DefaultsKey.switcherMergeTabs),
            sessionScope: sessionScope
        )
    }

    private var searchPinEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.switcherSearchPinEnabled)
    }

    private var showsShortcutHints: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.switcherShowShortcutHints)
    }

    private var usesIconRowLayout: Bool {
        SwitcherSupport.usesIconRowLayout(iconRowMode: iconRowModeEnabled,
                                          simpleMode: simpleModeEnabled)
    }

    private var capturesPreviews: Bool {
        SwitcherSupport.capturesPreviews(simpleMode: simpleModeEnabled)
    }

    // MARK: - Placement screen

    private var screenPlacement: SwitcherScreenPlacement {
        SwitcherScreenPlacement.placement(
            storedValue: UserDefaults.standard.string(forKey: DefaultsKey.switcherScreenPlacement))
    }

    private var placementScreen: NSScreen? {
        switch screenPlacement {
        case .pointer:
            return NSScreen.withMouse
        case .menuBar:
            return NSScreen.withMenuBar ?? NSScreen.withMouse
        case .activeWindow:
            return activeWindowScreen ?? NSScreen.withMouse
        }
    }

    private var activeWindowScreen: NSScreen? {
        guard let frame = sessionSourceContext?.frame else { return nil }
        let screens = NSScreen.screens
        let bounds = screens.map { CGDisplayBounds($0.displayID) }
        guard let index = SwitcherSupport.displayIndex(showingMostOf: frame, displayBounds: bounds) else {
            return nil
        }
        return screens[index]
    }

    private var currentDisplayScope: WindowEnumerator.DisplayScope? {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.switcherCurrentDisplayOnly) else {
            return nil
        }
        let screens = NSScreen.screens
        let targetID = NSScreen.withMouse?.displayID
        return WindowEnumerator.DisplayScope(
            bounds: screens.map { CGDisplayBounds($0.displayID) },
            targetIndex: screens.firstIndex { $0.displayID == targetID } ?? -1)
    }

    private var placementVisibleFrame: CGRect {
        if sessionActive, let cached = sessionPlacementVisibleFrame {
            return cached
        }
        return placementScreen?.visibleFrame ?? NSScreen.pointerVisibleFrame
    }

    private func recomputeLayouts(for items: [SwitcherItem]) {
        guard let screen = placementScreen ?? NSScreen.screens.first else { return }
        sessionPlacementVisibleFrame = screen.visibleFrame
        grid = SwitcherGrid.compute(count: max(items.count, 1), on: screen,
                                    maxColumns: SwitcherSupport.userMaxColumns,
                                    searchTopInset: searchTopInset)
        let appGroups = SwitcherSupport.appGroups(items: items)
        iconRowLayout = SwitcherIconRowLayout.compute(
            appCount: usesWindowRow ? items.count : appGroups.count,
            selectedWindowCount: usesWindowRow ? 1 : selectedAppWindowCount(in: items),
            maximumWindowCount: usesWindowRow ? 1 : appGroups.map(\.windowCount).max() ?? 1,
            sessionScope: sessionScope,
            screenVisibleFrame: screen.visibleFrame,
            showsShortcutHints: showsShortcutHints,
            tileWidth: usesWindowRow ? SwitcherIconRowLayout.windowTileWidth
                                     : SwitcherIconRowLayout.appTileWidth,
            maxColumns: SwitcherSupport.userMaxColumns,
            searchTopInset: searchTopInset
        )
    }

    private func updateIconRowLayoutForCurrentSelection() {
        guard !windows.isEmpty else { return }
        let appGroups = SwitcherSupport.appGroups(items: windows)
        let newLayout = SwitcherIconRowLayout.compute(
            appCount: usesWindowRow ? windows.count : appGroups.count,
            selectedWindowCount: usesWindowRow ? 1 : selectedAppWindowCount(in: windows),
            maximumWindowCount: usesWindowRow ? 1 : appGroups.map(\.windowCount).max() ?? 1,
            sessionScope: sessionScope,
            screenVisibleFrame: placementVisibleFrame,
            showsShortcutHints: showsShortcutHints,
            tileWidth: usesWindowRow ? SwitcherIconRowLayout.windowTileWidth
                                     : SwitcherIconRowLayout.appTileWidth,
            maxColumns: SwitcherSupport.userMaxColumns,
            searchTopInset: searchTopInset
        )
        if iconRowLayout != newLayout {
            iconRowLayout = newLayout
        }
        revealSelectedIconInVisibleRow()
    }

    private var iconRowItemCount: Int {
        usesWindowRow ? windows.count : SwitcherSupport.appGroups(items: windows).count
    }

    private func iconRowIndex(forSelectionIndex selectionIndex: Int) -> Int? {
        guard windows.indices.contains(selectionIndex) else { return nil }
        if usesWindowRow { return selectionIndex }
        let groups = SwitcherSupport.appGroups(items: windows)
        return groups.firstIndex { $0.pid == windows[selectionIndex].pid }
    }

    private func selectionIndex(forIconRowIndex iconIndex: Int) -> Int? {
        if usesWindowRow {
            return windows.indices.contains(iconIndex) ? iconIndex : nil
        }
        let groups = SwitcherSupport.appGroups(items: windows, currentSpaceOnly: currentSpaceOnly)
        return groups.indices.contains(iconIndex) ? groups[iconIndex].representativeIndex : nil
    }

    private func revealSelectedIconInVisibleRow() {
        guard usesIconRowLayout,
              let iconIndex = iconRowIndex(forSelectionIndex: selectedIndex)
        else { return }
        let newFirst = SwitcherSupport.iconRowFirstVisibleIndex(
            revealing: iconIndex,
            itemCount: iconRowItemCount,
            visibleCount: iconRowLayout.visibleIconCount,
            currentFirstVisibleIndex: iconRowFirstVisibleIndex
        )
        if iconRowFirstVisibleIndex != newFirst {
            iconRowFirstVisibleIndex = newFirst
        }
    }

    private func beginIconRowEdgeHoverIfNeeded(at selectionIndex: Int) {
        guard usesIconRowLayout,
              let iconIndex = iconRowIndex(forSelectionIndex: selectionIndex),
              SwitcherSupport.iconRowEdgeHoverDelta(
                hoveredIndex: iconIndex,
                firstVisibleIndex: iconRowFirstVisibleIndex,
                visibleCount: iconRowLayout.visibleIconCount,
                itemCount: iconRowItemCount
              ) != nil
        else {
            cancelIconRowEdgeHover()
            return
        }
        guard iconRowEdgeHoverIndex != iconIndex else { return }
        cancelIconRowEdgeHover()
        iconRowEdgeHoverIndex = iconIndex
        let work = DispatchWorkItem { [weak self] in
            self?.stepIconRowFromEdgeHover()
        }
        iconRowEdgeHoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + SwitcherSupport.iconRowEdgeHoverInterval,
                                      execute: work)
    }

    private func stepIconRowFromEdgeHover() {
        guard sessionActive, usesIconRowLayout,
              let hovered = iconRowEdgeHoverIndex,
              let delta = SwitcherSupport.iconRowEdgeHoverDelta(
                hoveredIndex: hovered,
                firstVisibleIndex: iconRowFirstVisibleIndex,
                visibleCount: iconRowLayout.visibleIconCount,
                itemCount: iconRowItemCount
              )
        else {
            cancelIconRowEdgeHover()
            return
        }

        let nextFirst = SwitcherSupport.clampedIconRowFirstVisibleIndex(
            itemCount: iconRowItemCount,
            visibleCount: iconRowLayout.visibleIconCount,
            firstVisibleIndex: iconRowFirstVisibleIndex + delta
        )
        guard nextFirst != iconRowFirstVisibleIndex else {
            cancelIconRowEdgeHover()
            return
        }

        let nextIcon = SwitcherSupport.iconRowIndexAfterEdgeHoverStep(
            firstVisibleIndex: nextFirst,
            visibleCount: iconRowLayout.visibleIconCount,
            itemCount: iconRowItemCount,
            delta: delta
        )
        iconRowEdgeHoverIndex = nextIcon
        iconRowFirstVisibleIndex = nextFirst
        if let nextSelection = selectionIndex(forIconRowIndex: nextIcon) {
            userNavigated = true
            selectedIndex = nextSelection
        }

        let work = DispatchWorkItem { [weak self] in
            self?.stepIconRowFromEdgeHover()
        }
        iconRowEdgeHoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + SwitcherSupport.iconRowEdgeHoverRepeatInterval,
                                      execute: work)
    }

    private func cancelIconRowEdgeHover() {
        iconRowEdgeHoverWork?.cancel()
        iconRowEdgeHoverWork = nil
        iconRowEdgeHoverIndex = nil
    }

    private func selectedAppWindowCount(in items: [SwitcherItem]) -> Int {
        guard items.indices.contains(selectedIndex) else { return 1 }
        let pid = items[selectedIndex].pid
        return max(1, items.filter { $0.pid == pid }.count)
    }

    private func centeredFrame(for size: CGSize) -> NSRect {
        let screen = placementVisibleFrame
        return NSRect(x: screen.midX - size.width / 2,
                      y: screen.midY - size.height / 2,
                      width: size.width,
                      height: size.height)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = OverlayPanel(contentRect: .zero,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered,
                                 defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentViewController = NSHostingController(rootView: SwitcherView().environmentObject(self))
        self.panel = panel
        return panel
    }
}

struct SwitcherGrid: Equatable {
    let columns: Int
    let rows: Int
    let visibleRows: Int
    let panelSize: CGSize

    static var cardWidth: CGFloat { SwitcherGridCard.width }
    static var cardHeight: CGFloat { SwitcherGridCard.height }
    static var spacing: CGFloat { 12 * PreviewSizing.switcherScale }
    static var padding: CGFloat { 20 * PreviewSizing.switcherScale }

    static let empty = SwitcherGrid(columns: 1, rows: 1, visibleRows: 1, panelSize: .zero)

    static func compute(count: Int, on screen: NSScreen, maxColumns userMax: Int? = nil,
                        searchTopInset: CGFloat = 0) -> SwitcherGrid {
        let usableWidth = screen.visibleFrame.width * 0.92
        let usableHeight = screen.visibleFrame.height * 0.85 - searchTopInset

        let fitByWidth = max(1, Int((usableWidth - padding * 2 + spacing) / (cardWidth + spacing)))
        let columns = SwitcherSupport.wrappingColumnCount(itemCount: count, fitByWidth: fitByWidth,
                                                          userMax: userMax)
        let rows = Int(ceil(Double(count) / Double(columns)))

        let maxRows = max(1, Int((usableHeight - padding * 2 + spacing) / (cardHeight + spacing)))
        let visibleRows = min(rows, maxRows)

        let width = CGFloat(columns) * cardWidth + CGFloat(columns - 1) * spacing + padding * 2
        let height = CGFloat(visibleRows) * cardHeight + CGFloat(visibleRows - 1) * spacing + padding * 2
        return SwitcherGrid(columns: columns, rows: rows, visibleRows: visibleRows,
                            panelSize: CGSize(width: width, height: height))
    }
}
