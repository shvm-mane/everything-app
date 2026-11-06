// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import IOKit

final class MiddleClickService: ObservableObject {
    static let shared = MiddleClickService()

    @Published private(set) var isRunning = false
    @Published private(set) var systemDragGestureConflict = false
    @Published private(set) var touchDeviceMissing = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let tapStateLock = NSLock()
    private let dragLock = NSLock()
    private var dragGestureRefreshScheduled = false
    private var deviceList: CFArray?
    private var observers: [Any] = []
    private var hotplugPort: IONotificationPortRef?
    private var hotplugIterators: [io_iterator_t] = []
    private var middleClickOn = false
    private var middleButtonHeld = false
    private var suppressedButtonSequence = false
    private var middleButtonTargetPID: pid_t?
    private var middleButtonHeldSince: TimeInterval = 0
    private var lastTransformEnd: TimeInterval?
    private var dragGestureCache: (enabled: Bool, readAt: TimeInterval) = (false, -10)

    private let stateLock = NSLock()
    private var fingerCount = 0
    private var lastFrameUptime: TimeInterval = 0
    private var fingerCountSince: TimeInterval = 0

    private var tapFingers = 0
    private var radialMenuTapFingers = 0
    private var tapCandidateFingers = 0
    private var tapDragConflict = false
    private var tapStartUptime: TimeInterval?
    private var tapStartPosition: (x: Float, y: Float)?
    private var tapStartSpread: Float?
    private var tapMaxMovement: Float = 0
    private var tapMaxSpreadChange: Float = 0
    private var tapExceededCount = false
    private var tapSawButton = false
    private var tapPositionUnavailable = false

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let enabled = AppFeature.middleClick.isAvailable
            && defaults.bool(forKey: DefaultsKey.middleClickEnabled)
        let tap = enabled ? Defaults.sanitizedMiddleClickTapFingers(
            defaults.integer(forKey: DefaultsKey.middleClickTapFingers)) : 0
        let radialMenuTap = MiddleClickSupport.radialMenuTapFingers(
            radialMenuWantsTap: AppFeature.radialMenu.isAvailable
                && defaults.bool(forKey: DefaultsKey.radialMenuEnabled)
                && RadialMenuSupport.decodeProfiles(defaults.data(forKey: DefaultsKey.radialMenuProfiles),
                                                    defaults: defaults).contains(where: \.trackpadTap),
            middleClickTapFingers: tap)
        tapStateLock.withLock { middleClickOn = enabled }
        stateLock.lock()
        tapFingers = tap
        radialMenuTapFingers = radialMenuTap
        resetTapCandidateLocked()
        stateLock.unlock()
        refreshDragGestureConflict()
        if SessionActivitySupport.tapShouldRun(
            featureWanted: enabled || radialMenuTap > 0,
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive
        ) {
            start()
        } else {
            stop()
        }
    }

    func refreshDragGestureConflict() {
        let enabled = Self.systemThreeFingerDragEnabled()
        dragLock.lock()
        dragGestureCache = (enabled, ProcessInfo.processInfo.systemUptime)
        dragGestureRefreshScheduled = false
        dragLock.unlock()
        if systemDragGestureConflict != enabled {
            systemDragGestureConflict = enabled
        }
        stateLock.lock()
        tapDragConflict = enabled
        stateLock.unlock()
    }

    private func dragGestureEnabled(now: TimeInterval) -> Bool {
        dragLock.lock()
        let cache = dragGestureCache
        let needsRefresh = now - cache.readAt > 2 && !dragGestureRefreshScheduled
        if needsRefresh { dragGestureRefreshScheduled = true }
        dragLock.unlock()
        if needsRefresh {
            DispatchQueue.main.async { [weak self] in self?.refreshDragGestureConflict() }
        }
        return cache.enabled
    }

    private static func systemThreeFingerDragEnabled() -> Bool {
        boolPreference("TrackpadThreeFingerDrag", domain: "com.apple.AppleMultitouchTrackpad")
            || boolPreference("TrackpadThreeFingerDrag",
                              domain: "com.apple.driver.AppleBluetoothMultitouch.trackpad")
    }

    private static func boolPreference(_ key: String, domain: String) -> Bool {
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) else {
            return false
        }
        return (value as? NSNumber)?.boolValue ?? false
    }

    func suspend() { stop() }

    // MARK: - Lifecycle

    private func start() {
        guard tapStateLock.withLock({ tap }) == nil else { return }
        guard Multitouch.available else {
            touchDeviceMissing = true
            return
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
                | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
                | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
                | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
                | CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
                | CGEventMask(1 << CGEventType.rightMouseDragged.rawValue),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<MiddleClickService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapStateLock.withLock {
            self.tap = tap
            runLoopSource = source
        }
        if let source {
            PointerTapRunLoop.add(source)
        }
        CGEvent.tapEnable(tap: tap, enable: true)

        startMultitouch()
        installObservers()
        isRunning = true
    }

    private func stop() {
        releaseHeldMiddleButton()
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
        stopMultitouch()
        removeObservers()
        tapStateLock.withLock {
            lastTransformEnd = nil
            suppressedButtonSequence = false
        }
        stateLock.lock()
        fingerCount = 0
        lastFrameUptime = 0
        fingerCountSince = 0
        resetTapCandidateLocked()
        stateLock.unlock()
        isRunning = false
        touchDeviceMissing = false
    }

    private func restartMultitouch() {
        guard tapStateLock.withLock({ tap }) != nil else { return }
        stopMultitouch()
        startMultitouch()
    }

    private func startMultitouch() {
        guard deviceList == nil else { return }
        guard let list = Multitouch.deviceList() else {
            touchDeviceMissing = true
            return
        }
        touchDeviceMissing = false
        deviceList = list
        for index in 0..<CFArrayGetCount(list) {
            guard let device = CFArrayGetValueAtIndex(list, index) else { continue }
            Multitouch.register(UnsafeMutableRawPointer(mutating: device), middleClickContactCallback)
            Multitouch.start(UnsafeMutableRawPointer(mutating: device))
        }
    }

    private func stopMultitouch() {
        guard let list = deviceList else { return }
        for index in 0..<CFArrayGetCount(list) {
            guard let device = CFArrayGetValueAtIndex(list, index) else { continue }
            Multitouch.stop(UnsafeMutableRawPointer(mutating: device))
            Multitouch.register(UnsafeMutableRawPointer(mutating: device), nil)
        }
        deviceList = nil
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                            object: nil,
                                            queue: .main) { [weak self] _ in
            self?.restartMultitouch()
        })
        installHotplugObserver()
    }

    private func installHotplugObserver() {
        guard hotplugPort == nil else { return }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        var iterators: [io_iterator_t] = []
        for notification in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port,
                notification,
                IOServiceMatching("AppleMultitouchDevice"),
                { context, iterator in
                    guard let context else { return }
                    while case let entry = IOIteratorNext(iterator), entry != 0 {
                        IOObjectRelease(entry)
                    }
                    let service = Unmanaged<MiddleClickService>.fromOpaque(context).takeUnretainedValue()
                    service.restartMultitouch()
                },
                context,
                &iterator
            )
            guard result == KERN_SUCCESS else {
                if iterator != 0 { IOObjectRelease(iterator) }
                for registered in iterators { IOObjectRelease(registered) }
                IONotificationPortDestroy(port)
                return
            }
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                IOObjectRelease(entry)
            }
            iterators.append(iterator)
        }
        hotplugPort = port
        hotplugIterators = iterators
    }

    private func removeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers = []
        for iterator in hotplugIterators { IOObjectRelease(iterator) }
        hotplugIterators.removeAll()
        if let hotplugPort {
            IONotificationPortDestroy(hotplugPort)
            self.hotplugPort = nil
        }
    }

    // MARK: - Contact frames (multitouch callback thread)

    fileprivate func contactFrame(fingerCount count: Int,
                                  touches: UnsafeMutableRawPointer?) {
        let now = ProcessInfo.processInfo.systemUptime
        var firedFingers: Int?
        stateLock.lock()
        if count != fingerCount { fingerCountSince = now }
        fingerCount = count
        lastFrameUptime = now
        if tapFingers > 0 || radialMenuTapFingers > 0 {
            let geometry = Multitouch.touchGeometry(touches: touches, count: count)
            firedFingers = trackTapLocked(count: count, geometry: geometry, now: now)
        }
        let radialMenuFingers = radialMenuTapFingers
        stateLock.unlock()
        if let firedFingers {
            if firedFingers == radialMenuFingers {
                DispatchQueue.main.async { RadialMenuService.shared.toggleFromTrackpad() }
            } else {
                postMiddleTap()
            }
        }
    }

    private func trackTapLocked(count: Int,
                                geometry: (center: (x: Float, y: Float), spread: Float)?,
                                now: TimeInterval) -> Int? {
        if count == 0 {
            defer { resetTapCandidateLocked() }
            guard let startedAt = tapStartUptime else { return nil }
            let secondsSinceLastKeyDown = CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: .keyDown
            )
            let fires = MiddleClickSupport.tapShouldFire(duration: now - startedAt,
                                                         maxMovement: tapMaxMovement,
                                                         maxSpreadChange: tapMaxSpreadChange,
                                                         exceededFingerCount: tapExceededCount,
                                                         buttonPressedDuring: tapSawButton,
                                                         positionUnavailable: tapPositionUnavailable,
                                                         systemDragGestureEnabled: tapDragConflict,
                                                         tapFingers: tapCandidateFingers,
                                                         secondsSinceLastKeyDown: secondsSinceLastKeyDown)
            return fires ? tapCandidateFingers : nil
        }
        if count > max(tapFingers, radialMenuTapFingers) {
            tapExceededCount = true
            return nil
        }
        if count == tapFingers || count == radialMenuTapFingers {
            if tapStartUptime == nil || count > tapCandidateFingers {
                guard !tapExceededCount else { return nil }
                tapCandidateFingers = count
                tapStartUptime = now
                tapStartPosition = geometry?.center
                tapStartSpread = geometry?.spread
                tapMaxMovement = 0
                tapMaxSpreadChange = 0
                tapSawButton = false
                tapPositionUnavailable = geometry == nil
            } else if count < tapCandidateFingers {
            } else if let start = tapStartPosition, let geometry {
                tapMaxMovement = max(tapMaxMovement,
                                     max(abs(geometry.center.x - start.x),
                                         abs(geometry.center.y - start.y)))
                if let startSpread = tapStartSpread {
                    tapMaxSpreadChange = max(tapMaxSpreadChange,
                                             abs(geometry.spread - startSpread))
                }
            } else if geometry == nil {
                tapPositionUnavailable = true
            }
        }
        return nil
    }

    private func resetTapCandidateLocked() {
        tapCandidateFingers = 0
        tapStartUptime = nil
        tapStartPosition = nil
        tapStartSpread = nil
        tapMaxMovement = 0
        tapMaxSpreadChange = 0
        tapExceededCount = false
        tapSawButton = false
        tapPositionUnavailable = false
    }

    private func postMiddleTap() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.tapStateLock.withLock({ self.tap }) != nil else { return }
            let position = CGEvent(source: nil)?.location ?? .zero
            guard !MouseAppExceptions.shared.excludesPointerTarget(.middleClick, at: position) else { return }
            let source = CGEventSource(stateID: .hidSystemState)
            guard let down = CGEvent(mouseEventSource: source,
                                     mouseType: .otherMouseDown,
                                     mouseCursorPosition: position,
                                     mouseButton: .center),
                  let up = CGEvent(mouseEventSource: source,
                                   mouseType: .otherMouseUp,
                                   mouseCursorPosition: position,
                                   mouseButton: .center) else { return }
            down.setIntegerValueField(.mouseEventClickState, value: 1)
            up.setIntegerValueField(.mouseEventClickState, value: 1)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            self.tapStateLock.withLock {
                self.lastTransformEnd = ProcessInfo.processInfo.systemUptime
            }
        }
    }

    // MARK: - Event tap (pointer thread)

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            releaseHeldMiddleButton()
            let enabled = AppFeature.middleClick.isAvailable
                && UserDefaults.standard.bool(forKey: DefaultsKey.middleClickEnabled)
                || stateLock.withLock { radialMenuTapFingers > 0 }
            let shouldRearm = SessionActivitySupport.tapShouldRun(
                featureWanted: enabled,
                accessibilityGranted: AXIsProcessTrusted(),
                sessionIsActive: SessionActivity.shared.isActive
            )
            let port = tapStateLock.withLock { tap }
            switch SessionActivitySupport.disabledTapRecovery(tapHeld: port != nil,
                                                              tapShouldRun: shouldRearm) {
            case .rearm:
                if let port { CGEvent.tapEnable(tap: port, enable: true) }
            case .tearDown:
                DispatchQueue.main.async { [weak self] in
                    self?.stop()
                    self?.syncWithPreferences()
                }
            case .leaveStopped:
                break
            }
            return Unmanaged.passUnretained(event)
        }

        let now = ProcessInfo.processInfo.systemUptime
        switch type {
        case .leftMouseDown, .rightMouseDown:
            stateLock.lock()
            if tapStartUptime != nil { tapSawButton = true }
            stateLock.unlock()
            tapStateLock.lock()
            guard middleClickOn else {
                tapStateLock.unlock()
                return Unmanaged.passUnretained(event)
            }
            if suppressedButtonSequence {
                tapStateLock.unlock()
                return nil
            }
            var releaseLostHold = false
            if middleButtonHeld {
                if now - middleButtonHeldSince > 10 {
                    releaseLostHold = true
                } else {
                    suppressedButtonSequence = true
                    tapStateLock.unlock()
                    return nil
                }
            }
            tapStateLock.unlock()
            if releaseLostHold { releaseHeldMiddleButton() }
            if MouseAppExceptions.shared.excludesPointerTarget(.middleClick, at: event.location) {
                return Unmanaged.passUnretained(event)
            }
            stateLock.lock()
            let count = fingerCount
            let age = now - lastFrameUptime
            let settledFor = now - fingerCountSince
            stateLock.unlock()
            let sinceLastTransformEnd = tapStateLock.withLock { lastTransformEnd }
            let action = MiddleClickSupport.actionForClick(
                fingerCount: count,
                frameAge: age,
                settledFor: settledFor,
                sinceLastTransformEnd: sinceLastTransformEnd.map { now - $0 },
                systemDragGestureEnabled: dragGestureEnabled(now: now)
            )
            switch action {
            case .passThrough:
                return Unmanaged.passUnretained(event)
            case .swallow:
                tapStateLock.withLock { suppressedButtonSequence = true }
                return nil
            case .transform:
                let targetPID = event.getIntegerValueField(.eventTargetUnixProcessID)
                tapStateLock.withLock {
                    middleButtonHeld = true
                    middleButtonHeldSince = now
                    middleButtonTargetPID = targetPID > 0 ? pid_t(targetPID) : nil
                }
                return Unmanaged.passUnretained(asMiddle(event, type: .otherMouseDown))
            }
        case .leftMouseDragged, .rightMouseDragged:
            let (held, suppressed) = tapStateLock.withLock {
                (middleButtonHeld, suppressedButtonSequence)
            }
            if held {
                return Unmanaged.passUnretained(asMiddle(event, type: .otherMouseDragged))
            }
            return suppressed ? nil : Unmanaged.passUnretained(event)
        case .leftMouseUp, .rightMouseUp:
            tapStateLock.lock()
            if suppressedButtonSequence {
                suppressedButtonSequence = false
                tapStateLock.unlock()
                return nil
            }
            guard middleButtonHeld else {
                tapStateLock.unlock()
                return Unmanaged.passUnretained(event)
            }
            middleButtonHeld = false
            middleButtonTargetPID = nil
            lastTransformEnd = now
            tapStateLock.unlock()
            return Unmanaged.passUnretained(asMiddle(event, type: .otherMouseUp))
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func releaseHeldMiddleButton() {
        tapStateLock.lock()
        suppressedButtonSequence = false
        guard middleButtonHeld else {
            tapStateLock.unlock()
            return
        }
        middleButtonHeld = false
        let targetPID = middleButtonTargetPID
        middleButtonTargetPID = nil
        tapStateLock.unlock()
        let position = CGEvent(source: nil)?.location ?? .zero
        let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState),
                            mouseType: .otherMouseUp,
                            mouseCursorPosition: position,
                            mouseButton: .center)
        if let targetPID {
            event?.postToPid(targetPID)
        } else {
            event?.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.02)
        tapStateLock.withLock { lastTransformEnd = ProcessInfo.processInfo.systemUptime }
    }

    private func asMiddle(_ event: CGEvent, type: CGEventType) -> CGEvent {
        event.type = type
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        return event
    }
}

// MARK: - MultitouchSupport bridge

private func middleClickContactCallback(_ device: UnsafeMutableRawPointer?,
                                        _ touches: UnsafeMutableRawPointer?,
                                        _ count: Int32,
                                        _ timestamp: Double,
                                        _ frame: Int32) -> Int32 {
    MiddleClickService.shared.contactFrame(fingerCount: Int(count), touches: touches)
    return 0
}

private enum Multitouch {
    typealias ContactCallback = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
    ) -> Int32
    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer, ContactCallback?) -> Void
    private typealias StartFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias StopFn = @convention(c) (UnsafeMutableRawPointer) -> Void

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
        RTLD_NOW
    )

    private static let createListFn: CreateListFn? = symbol("MTDeviceCreateList")
    private static let registerFn: RegisterFn? = symbol("MTRegisterContactFrameCallback")
    private static let startFn: StartFn? = symbol("MTDeviceStart")
    private static let stopFn: StopFn? = symbol("MTDeviceStop")

    static var available: Bool {
        createListFn != nil && registerFn != nil && startFn != nil && stopFn != nil
    }

    static func deviceList() -> CFArray? {
        guard let createListFn else { return nil }
        let list = createListFn()?.takeRetainedValue()
        guard let list, CFArrayGetCount(list) > 0 else { return nil }
        return list
    }

    static func register(_ device: UnsafeMutableRawPointer, _ callback: ContactCallback?) {
        registerFn?(device, callback)
    }

    static func start(_ device: UnsafeMutableRawPointer) {
        startFn?(device, 0)
    }

    static func stop(_ device: UnsafeMutableRawPointer) {
        stopFn?(device)
    }

    private static let touchStride = 96
    private static let touchPositionXOffset = 32
    private static let touchPositionYOffset = 36

    static func touchGeometry(touches: UnsafeMutableRawPointer?,
                              count: Int) -> (center: (x: Float, y: Float), spread: Float)? {
        guard let touches, count > 0 else { return nil }
        var sumX: Float = 0
        var sumY: Float = 0
        for index in 0..<count {
            let base = touches.advanced(by: index * touchStride)
            let x = base.loadUnaligned(fromByteOffset: touchPositionXOffset, as: Float.self)
            let y = base.loadUnaligned(fromByteOffset: touchPositionYOffset, as: Float.self)
            guard x.isFinite, y.isFinite,
                  x >= -0.2, x <= 1.2, y >= -0.2, y <= 1.2 else { return nil }
            sumX += x
            sumY += y
        }
        let centerX = sumX / Float(count)
        let centerY = sumY / Float(count)
        var spread: Float = 0
        for index in 0..<count {
            let base = touches.advanced(by: index * touchStride)
            let x = base.loadUnaligned(fromByteOffset: touchPositionXOffset, as: Float.self)
            let y = base.loadUnaligned(fromByteOffset: touchPositionYOffset, as: Float.self)
            let dx = x - centerX
            let dy = y - centerY
            spread += (dx * dx + dy * dy).squareRoot()
        }
        spread /= Float(count)
        return ((centerX, centerY), spread)
    }

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let raw = dlsym(handle, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }
}
