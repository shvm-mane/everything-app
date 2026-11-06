// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

final class SpaceHop {
    private static var current: SpaceHop?

    private static let arrivalPollInterval: TimeInterval = 0.05
    private static let arrivalTimeout: TimeInterval = 1.2

    static func beginIfNeeded(windowID: CGWindowID,
                              appPID: pid_t,
                              windowOwnerPID: pid_t,
                              sourcePID: pid_t?,
                              app: NSRunningApplication) -> Bool {
        guard let topology = SpaceWindowBridge.topology(),
              SpaceWindowBridge.isParkedOnHiddenSpace(windowID, visibleSpaces: topology.visibleSpaces)
        else { return false }
        cancelPending()
        let focusState = SwitcherWindowFocusRetryState(
            targetWindowID: windowID,
            targetStartedMinimized: false,
            knownWindowIDs: WindowActivator.focusSnapshot(ownerPID: windowOwnerPID))
        let hop = SpaceHop(windowID: windowID, appPID: appPID, windowOwnerPID: windowOwnerPID,
                           sourcePID: sourcePID, focusState: focusState, app: app)
        current = hop
        hop.start()
        return true
    }

    static func cancelPending() {
        current?.restoreCursorIfNeeded()
        current?.cancelled = true
        current = nil
    }

    private let windowID: CGWindowID
    private let appPID: pid_t
    private let windowOwnerPID: pid_t
    private let sourcePID: pid_t?
    private let focusState: SwitcherWindowFocusRetryState
    private let app: NSRunningApplication
    private var cancelled = false
    private var arrowPressesLeft = SpaceHopSupport.maximumArrowSteps
    private var originalCursorLocation: CGPoint?
    private var warpedCursorLocation: CGPoint?

    private init(windowID: CGWindowID, appPID: pid_t, windowOwnerPID: pid_t,
                 sourcePID: pid_t?, focusState: SwitcherWindowFocusRetryState,
                 app: NSRunningApplication) {
        self.windowID = windowID
        self.appPID = appPID
        self.windowOwnerPID = windowOwnerPID
        self.sourcePID = sourcePID
        self.focusState = focusState
        self.app = app
    }

    private func start() {
        if app.isHidden { app.unhide() }
        let appIsAlreadyHere = appHasWindowOnVisibleSpace()
        let directRaiseSucceeded = WindowActivator.raiseWindowOnHiddenSpace(windowID: windowID,
                                                                             pid: windowOwnerPID)
        let firstStage = SpaceHopSupport.firstStage(appHasWindowOnVisibleSpace: appIsAlreadyHere,
                                                    directRaiseSucceeded: directRaiseSucceeded)
        if firstStage == .moveASpace {
            SpaceWindowBridge.frontWindow(windowID, ownerPID: windowOwnerPID)
        }
        let options: NSApplication.ActivationOptions =
            appIsAlreadyHere || directRaiseSucceeded ? [] : [.activateAllWindows]
        ActivationHandoff.yield(to: app)
        if !app.activate(from: NSRunningApplication.current, options: options) {
            app.activate(options: options)
        }
        switch firstStage {
        case .moveASpace:
            stepWithSpaceShortcut()
        case .waitForActivationTravel:
            let visibleBefore = SpaceWindowBridge.topology()?.visibleSpaces ?? []
            waitForTravel(from: visibleBefore) { outcome in
                if outcome == .arrived {
                    self.focusOnArrival()
                } else {
                    self.stepWithSpaceShortcut()
                }
            }
        }
    }

    private enum TravelOutcome {
        case arrived
        case landedShort
        case stalled
    }

    private func waitForTravel(from visibleBefore: Set<UInt64>,
                                deadline: DispatchTime? = nil,
                                then completion: @escaping (TravelOutcome) -> Void) {
        let deadline = deadline ?? .now() + Self.arrivalTimeout
        schedule(after: Self.arrivalPollInterval) {
            guard !self.cancelled else { return }
            guard let visibleNow = SpaceWindowBridge.topology()?.visibleSpaces else {
                completion(.stalled)
                return
            }
            if !SpaceWindowBridge.isParkedOnHiddenSpace(self.windowID, visibleSpaces: visibleNow) {
                completion(.arrived)
            } else if visibleNow != visibleBefore {
                completion(.landedShort)
            } else if .now() < deadline {
                self.waitForTravel(from: visibleBefore, deadline: deadline, then: completion)
            } else {
                completion(.stalled)
            }
        }
    }

    private func finish() {
        restoreCursorIfNeeded()
        if SpaceHop.current === self { SpaceHop.current = nil }
    }

    private func restoreCursorIfNeeded() {
        guard let original = originalCursorLocation,
              let warped = warpedCursorLocation else { return }
        originalCursorLocation = nil
        warpedCursorLocation = nil
        if let current = CGEvent(source: nil)?.location,
           abs(current.x - warped.x) < 2 && abs(current.y - warped.y) < 2 {
            CGWarpMouseCursorPosition(original)
        }
    }

    private func stepWithSpaceShortcut() {
        guard !cancelled else { return }
        if windowSpaceIsVisible() {
            focusOnArrival()
            return
        }
        guard arrowPressesLeft > 0 else { finish(); return }
        arrowPressesLeft -= 1
        guard let topology = SpaceWindowBridge.topology(),
              let targetSpace = SpaceWindowBridge.spaces(of: windowID).first,
              let steps = SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: topology.orderedSpacesPerDisplay,
                                                    visibleSpaces: topology.visibleSpaces,
                                                    target: targetSpace),
              let shortcut = SpaceWindowBridge.spaceShortcut(steps > 0 ? .right : .left)
        else {
            focusOnArrival()
            return
        }
        if topology.displays.count > 1,
           let targetDisplay = topology.displays.first(where: { $0.spaces.contains(targetSpace) }),
           let displayID = targetDisplay.displayID {
            let bounds = CGDisplayBounds(displayID)
            let currentMouse = NSEvent.mouseLocation
            let screenFrame = NSScreen.screens.first(where: {
                (($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value) == displayID
            })?.frame
            if let screenFrame, !NSMouseInRect(currentMouse, screenFrame, false) {
                if originalCursorLocation == nil {
                    originalCursorLocation = CGEvent(source: nil)?.location
                }
                let targetPoint = CGPoint(x: bounds.midX, y: bounds.midY)
                warpedCursorLocation = targetPoint
                CGWarpMouseCursorPosition(targetPoint)
            }
        }
        let visibleBefore = topology.visibleSpaces
        SpaceWindowBridge.pressSpaceShortcut(shortcut)
        waitForTravel(from: visibleBefore) { outcome in
            switch outcome {
            case .arrived:
                self.focusOnArrival()
            case .landedShort:
                self.stepWithSpaceShortcut()
            case .stalled:
                self.finish()
            }
        }
    }

    private func focusOnArrival() {
        for (index, delay) in [0.15, 0.45, 0.9].enumerated() {
            schedule(after: delay) {
                guard !self.cancelled, !self.app.isTerminated else { return }
                guard SpaceHopSupport.arrivalPulseShouldFocus(
                    isFirstPulse: index == 0,
                    targetSpaceIsVisible: self.windowSpaceIsVisible(),
                    targetWindowID: self.windowID,
                    windowOwnerPID: self.windowOwnerPID,
                    frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                    focusedWindowID: WindowActivator.focusedWindowID(for: self.windowOwnerPID))
                else { return }
                WindowActivator.focusAfterSpaceHop(windowID: self.windowID,
                                                   appPID: self.appPID,
                                                   windowOwnerPID: self.windowOwnerPID,
                                                   sourcePID: self.sourcePID,
                                                   state: self.focusState)
            }
        }
        schedule(after: 1.0) { self.finish() }
    }

    private func windowSpaceIsVisible() -> Bool {
        !SpaceWindowBridge.isParkedOnHiddenSpace(windowID)
    }

    private func appHasWindowOnVisibleSpace() -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains { info in
            guard let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == appPID || ownerPID == windowOwnerPID,
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0
            else { return false }
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            return alpha > 0
        }
    }

    private func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
