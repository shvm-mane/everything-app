// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics

final class ScrollInverter: ObservableObject {
    static let shared = ScrollInverter()

    @Published private(set) var isRunning = false

    private static let ownProcessID = Int64(getpid())

    static func directionApplied(to event: CGEvent) -> CGEvent {
        let traits = ScrollWheelEventTraits(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            scrollCount: event.getIntegerValueField(.scrollWheelEventScrollCount)
        )
        let direction = ScrollDirectionPreferences(defaults: UserDefaults.standard)
        guard direction.invertVertical || direction.invertHorizontal,
              ScrollWheelSupport.isMouseWheel(traits, secondsSinceLastGesturePhase: nil),
              ScrollWheelHIDStage.shared.passed(event),
              !MouseAppExceptions.shared.excludesPointerTarget(
                  .scrollDirection, at: event.location,
                  sourceProcessID: event.getIntegerValueField(.eventSourceUnixProcessID)),
              let turned = event.copy() else { return event }
        ScrollWheelSupport.applyDirection(to: turned, isContinuous: traits.isContinuous,
                                          invertVertical: direction.invertVertical,
                                          invertHorizontal: direction.invertHorizontal,
                                          horizontalModifier: nil)
        return turned
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let tapStateLock = NSLock()
    private var lastGesturePhaseTimestamp: UInt64?
    private var linearCarryVertical: Double = 0
    private var linearCarryHorizontal: Double = 0
    private let pinchZoomLock = NSLock()
    private var zoomState = ScrollZoomGestureState()
    private var tapCreationRetryUsed = false
    private var tapCreationRetryWork: DispatchWorkItem?

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    func syncWithPreferences() {
        let direction = ScrollDirectionPreferences()
        pinchZoomLock.withLock {
            let pinchLocation = zoomState.pinchLocation
            if zoomState.update(direction.zoom) {
                postPinch(phase: 4, magnification: 0, at: pinchLocation)
            }
        }
        if SessionActivitySupport.tapShouldRun(featureWanted: direction.isEnabled || Self.linearScrollWanted,
                                               accessibilityGranted: Permissions.shared.accessibility,
                                               sessionIsActive: SessionActivity.shared.isActive) {
            ScrollWheelTarget.shared.setEnabled(direction.horizontalModifier != nil || direction.zoom.isEnabled)
            start()
        } else {
            stop()
        }
    }

    func suspend() { stop() }

    private static var linearScrollWanted: Bool {
        AppFeature.linearScroll.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.linearScrollEnabled)
    }

    private func setSourceTracking(_ running: Bool) {
        let exceptions = MouseAppExceptions.shared
        exceptions.setSourceTracking(running && ScrollDirectionPreferences().isEnabled, for: .scrollDirection)
        exceptions.setSourceTracking(running && Self.linearScrollWanted, for: .linearScroll)
    }

    private func start() {
        ScrollWheelHIDStage.shared.setWatching(true, for: .wheelTap)
        if let port = tapStateLock.withLock({ tap }) {
            CGEvent.tapEnable(tap: port, enable: true)
            setSourceTracking(true)
            pinchZoomLock.withLock { zoomState.start() }
            isRunning = true
            return
        }
        setSourceTracking(true)
        guard let tap = CGEvent.tapCreate(
            tap: ScrollWheelSupport.tapLocation,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: (CGEventMask(1 << CGEventType.scrollWheel.rawValue)
                | CGEventMask(1 << CGEventType.flagsChanged.rawValue)),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let inverter = Unmanaged<ScrollInverter>.fromOpaque(userInfo).takeUnretainedValue()
                return inverter.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            ScrollWheelTarget.shared.setEnabled(false)
            setSourceTracking(false)
            ScrollWheelHIDStage.shared.setWatching(false, for: .wheelTap)
            isRunning = false
            guard !tapCreationRetryUsed else { return }
            tapCreationRetryUsed = true
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.tapCreationRetryWork = nil
                self.syncWithPreferences()
            }
            tapCreationRetryWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
            return
        }

        tapCreationRetryUsed = false
        tapCreationRetryWork?.cancel()
        tapCreationRetryWork = nil
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapStateLock.withLock {
            self.tap = tap
            runLoopSource = source
        }
        if let source {
            PointerTapRunLoop.add(source)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        pinchZoomLock.withLock { zoomState.start() }
        isRunning = true
    }

    private func stop() {
        pinchZoomLock.withLock {
            let pinchLocation = zoomState.pinchLocation
            if zoomState.stop() { postPinch(phase: 4, magnification: 0, at: pinchLocation) }
        }
        ScrollWheelTarget.shared.setEnabled(false)
        tapCreationRetryWork?.cancel()
        tapCreationRetryWork = nil
        tapCreationRetryUsed = false
        setSourceTracking(false)
        ScrollWheelHIDStage.shared.setWatching(false, for: .wheelTap)
        let (port, source) = tapStateLock.withLock { () -> (CFMachPort?, CFRunLoopSource?) in
            let current = (tap, runLoopSource)
            tap = nil
            runLoopSource = nil
            return current
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let source {
            PointerTapRunLoop.remove(source, invalidating: port)
        }
        linearCarryVertical = 0
        linearCarryHorizontal = 0
        isRunning = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if SessionActivity.shared.isActive, let port = tapStateLock.withLock({ tap }) {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        if type == .flagsChanged {
            guard event.getIntegerValueField(.eventSourceUserData) != ScrollWheelSupport.syntheticTag else {
                return Unmanaged.passUnretained(event)
            }
            pinchZoomLock.withLock {
                if let modifier = zoomState.pinchModifier,
                   event.flags.intersection([.maskShift, .maskAlternate, .maskControl, .maskCommand]) != modifier.flag {
                    endPinchZoomLocked()
                }
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
        guard ScrollWheelHIDStage.shared.passed(event) else {
            return Unmanaged.passUnretained(event)
        }
        let sourceProcessID = event.getIntegerValueField(.eventSourceUnixProcessID)
        guard event.getIntegerValueField(.eventSourceUserData) != ScrollWheelSupport.syntheticTag,
              sourceProcessID != Self.ownProcessID else {
            return Unmanaged.passUnretained(event)
        }

        let traits = ScrollWheelEventTraits(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            scrollCount: event.getIntegerValueField(.scrollWheelEventScrollCount)
        )
        let timestamp = EventTimestamp.nanoseconds(of: event)
        let secondsSinceGesturePhase = lastGesturePhaseTimestamp.map {
            Double(timestamp &- $0) / 1_000_000_000.0
        }
        if traits.momentumPhase != 0 || traits.scrollPhase != 0 {
            lastGesturePhaseTimestamp = timestamp
        }

        guard ScrollWheelSupport.isMouseWheel(traits,
                                              secondsSinceLastGesturePhase: secondsSinceGesturePhase)
        else { return Unmanaged.passUnretained(event) }

        let defaults = UserDefaults.standard
        let direction = ScrollDirectionPreferences(defaults: defaults)
        let directionApplies = direction.isEnabled
            && !MouseAppExceptions.shared.excludesPointerTarget(
                .scrollDirection, at: event.location, sourceProcessID: sourceProcessID)
        if directionApplies, !AppSwitcher.shared.scrollNavigationActive,
           direction.zoom.action(for: event) != nil {
            if consumeZoom(event, direction: direction) { return nil }
            if !ScrollWheelTarget.shared.contains(event.location) { return Unmanaged.passUnretained(event) }
        }
        let controlRedirects = directionApplies
            && direction.horizontalModifier == .control
            && event.flags.intersection([.maskShift, .maskAlternate, .maskControl, .maskCommand]) == .maskControl
            && ScrollWheelSupport.isVerticalOnly(event)
            && !ScrollWheelTarget.shared.contains(event.location)
        let nativeZoom = event.flags.contains(.maskControl) && !controlRedirects
        if let linesPerNotch = nativeZoom ? nil : ScrollWheelSupport.linearLinesPerNotch(
            defaults: defaults,
            isAvailable: AppFeature.linearScroll.isAvailable,
            isExcepted: {
                MouseAppExceptions.shared.excludesPointerTarget(
                    .linearScroll,
                    at: event.location,
                    sourceProcessID: sourceProcessID)
            }) {
            let rawVertical = ScrollWheelAxisDelta(
                line: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
                fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
            let rawHorizontal = ScrollWheelAxisDelta(
                line: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
                point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
                fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2))
            let linearVertical = ScrollWheelSupport.linearDelta(
                rawVertical, isContinuous: traits.isContinuous,
                linesPerNotch: linesPerNotch, carry: linearCarryVertical)
            let linearHorizontal = ScrollWheelSupport.linearDelta(
                rawHorizontal, isContinuous: traits.isContinuous,
                linesPerNotch: linesPerNotch, carry: linearCarryHorizontal)
            linearCarryVertical = linearVertical.carry
            linearCarryHorizontal = linearHorizontal.carry
            if rawVertical.hasMovement || rawHorizontal.hasMovement,
               !linearVertical.delta.hasMovement, !linearHorizontal.delta.hasMovement {
                return nil
            }
            ScrollWheelSupport.writeLinear(
                vertical: rawVertical.hasMovement ? linearVertical.delta : nil,
                horizontal: rawHorizontal.hasMovement ? linearHorizontal.delta : nil,
                to: event, isContinuous: traits.isContinuous)
        } else {
            linearCarryVertical = 0
            linearCarryHorizontal = 0
        }

        if directionApplies {
            ScrollWheelSupport.applyDirection(
                to: event, isContinuous: traits.isContinuous,
                invertVertical: direction.invertVertical,
                invertHorizontal: direction.invertHorizontal,
                horizontalModifier: direction.horizontalModifier,
                targetsOwnWindow: ScrollWheelTarget.shared.contains(event.location)
            )
        }
        return Unmanaged.passUnretained(event)
    }

    func consumeZoom(_ event: CGEvent, direction: ScrollDirectionPreferences) -> Bool {
        guard !AppSwitcher.shared.scrollNavigationActive else { return false }
        guard let action = direction.zoom.action(for: event) else { return false }
        guard !ScrollWheelTarget.shared.contains(event.location) else {
            pinchZoomLock.withLock {
                endPinchZoomLocked()
            }
            return false
        }
        let delta = ScrollWheelSupport.zoomDelta(action.delta, axis: action.axis,
                                                  invertVertical: direction.invertVertical,
                                                  invertHorizontal: direction.invertHorizontal)
        return pinchZoomLock.withLock {
            guard zoomState.accepts(direction.zoom) else { return false }
            postPinchZoomLocked(delta, modifier: action.modifier, at: event.location)
            return true
        }
    }

    private func postPinchZoomLocked(_ delta: Double, modifier: ScrollHorizontalModifier, at point: CGPoint) {
        let previous = zoomState.pinchLocation
        let transition = zoomState.beginPinch(modifier, at: point)
        if transition.endPrevious { postPinch(phase: 4, magnification: 0, at: previous) }
        if transition.begin { postPinch(phase: 1, magnification: 0, at: point) }
        postPinch(phase: 2, magnification: delta * 0.005, at: point)
    }

    private func endPinchZoomLocked() {
        let point = zoomState.pinchLocation
        if zoomState.endPinch() { postPinch(phase: 4, magnification: 0, at: point) }
    }

    private func postPinch(phase: Int64, magnification: Double, at point: CGPoint?) {
        guard let gesture = CGEvent(source: nil) else { return }
        if let point { gesture.location = point }
        gesture.type = CGEventType(rawValue: UInt32(NSEvent.EventType.gesture.rawValue))!
        gesture.setIntegerValueField(CGEventField(rawValue: 110)!, value: 8)
        gesture.setIntegerValueField(CGEventField(rawValue: 132)!, value: phase)
        gesture.setDoubleValueField(CGEventField(rawValue: 113)!, value: magnification)
        gesture.post(tap: .cgSessionEventTap)
    }
}
