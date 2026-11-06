// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import CoreGraphics
import IOKit
import IOKit.hidsystem

final class SuperKeyService: ObservableObject {
    static let shared = SuperKeyService()

    @Published private(set) var isRunning = false
    @Published private(set) var isPausedForApplication = false
    @Published private(set) var mappingFailure: SuperKeyMappingFailure?
    @Published private(set) var modifiers = SuperKeySupport.defaultModifiers
    @Published private(set) var source = SuperKeySource.capsLock

    private(set) static var isEngaged = false

    var onHoldEnded: ((_ released: Bool) -> Void)?
    var isHeld: Bool { stateLock.withLock { state.isHeld } }

    private let hidutilPath = "/usr/bin/hidutil"
    private let keyboardMatch = "keyboard"

    private let lifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var mouseTap: CFMachPort?
    private var mouseTapRefusals = 0
    private static let mouseDownTypes: [CGEventType] = [
        .leftMouseDown, .rightMouseDown, .otherMouseDown,
    ]
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingTapRestart = false
    private var mappingGeneration: UInt = 0
    private let stateLock = NSLock()
    private var state = SuperKeySupport.State()
    private var soloAction: SuperKeySoloAction = .none
    private var eventModifiers = SuperKeySupport.defaultModifiers
    private var eventSource = SuperKeySource.capsLock
    private var wakeObserver: NSObjectProtocol?
    private var exceptionObservation: AnyCancellable?
    private let mappingQueue = DispatchQueue(label: "com.vorssaint.utils.superkey-mapping")
    private var mappingGuard: SuperKeyMappingGuard.Handle?
    private var lastMappingAt: TimeInterval = 0
    private var pendingMappingEnableCount = 0
    private let mappingRepairInterval: TimeInterval = 3
    private var heldKeyWatchdog: DispatchWorkItem?
    private var heldKeyTimeout: TimeInterval {
        let firstRepeat = NSEvent.keyRepeatDelay
        guard firstRepeat.isFinite, firstRepeat > 0 else { return 3 }
        return min(30, max(3, firstRepeat * 2))
    }

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let action = SuperKeySoloAction.sanitized(
            defaults.string(forKey: DefaultsKey.superKeySoloAction)
        )
        let modifiers = SuperKeySupport.modifiers(
            from: defaults.string(forKey: DefaultsKey.superKeyModifiers)
        )
        let source = SuperKeySource.sanitized(
            defaults.string(forKey: DefaultsKey.superKeySource)
        )
        let sourceChanged = self.source != source
        stateLock.withLock {
            soloAction = action
            eventModifiers = modifiers
            eventSource = source
        }
        self.modifiers = modifiers
        self.source = source
        let enabled = AppFeature.superKey.isAvailable
            && defaults.bool(forKey: DefaultsKey.superKeyEnabled)
            && SessionActivity.shared.isActive
        syncExceptionMonitoring(enabled: enabled && AXIsProcessTrusted())
        guard enabled, !isPausedForApplication else {
            stop()
            return
        }
        let deadTap = lifecycleLock.withLock { () -> Bool in
            let keyboardDead = tap.map { !CGEvent.tapIsEnabled(tap: $0) } ?? false
            let mouseDead = mouseTap.map { !CGEvent.tapIsEnabled(tap: $0) }
                ?? (mouseTapRefusals == 1)
            return keyboardDead || mouseDead
        }
        if deadTap || sourceChanged { stop() }
        start()
    }

    func suspend() {
        syncExceptionMonitoring(enabled: false)
        stop(synchronously: true)
    }

    private func syncExceptionMonitoring(enabled: Bool) {
        let exceptions = MouseAppExceptions.shared
        if enabled {
            if exceptionObservation == nil {
                exceptionObservation = exceptions.$runningScopes
                    .map { $0.contains(.superKey) }
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in self?.syncWithPreferences() }
            }
        } else {
            exceptionObservation = nil
        }
        exceptions.setSourceTracking(enabled, for: .superKey)
        let paused = enabled && exceptions.runningScopes.contains(.superKey)
        if isPausedForApplication != paused { isPausedForApplication = paused }
    }

    private func start() {
        let tapExists = lifecycleLock.withLock { tap != nil && !shouldStopTapThread }
        guard !tapExists else { return }
        guard AXIsProcessTrusted() else {
            clearLeftoverMapping()
            isRunning = false
            return
        }
        forgetHeldKey()
        let thread = lifecycleLock.withLock { () -> Thread? in
            if tapThread != nil {
                if shouldStopTapThread { pendingTapRestart = true }
                return nil
            }
            shouldStopTapThread = false
            pendingTapRestart = false
            let thread = Thread { [weak self] in self?.runEventTap() }
            thread.name = "EVERYTHING Super Key"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return thread
        }
        thread?.start()
    }

    private func stop(synchronously: Bool = false) {
        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, mouseTap: CFMachPort?, threadExists: Bool) in
            shouldStopTapThread = true
            pendingTapRestart = false
            mappingGeneration &+= 1
            return (tapRunLoop, tap, mouseTap, tapThread != nil)
        }
        if let tap = snapshot.tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let mouseTap = snapshot.mouseTap { CGEvent.tapEnable(tap: mouseTap, enable: false) }
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
        forgetHeldKey()
        Self.isEngaged = false
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        clearLeftoverMapping(synchronously: synchronously)
        isRunning = false
        setMappingFailure(nil)
    }

    private func runEventTap() {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock { tapRunLoop = runLoop }
            guard !lifecycleLock.withLock({ shouldStopTapThread }) else {
                if clearEventTapThread() { startOnMain() }
                return
            }

            let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
                | (CGEventMask(1) << CGEventType.keyUp.rawValue)
                | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .tailAppendEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<SuperKeyService>.fromOpaque(userInfo)
                        .takeUnretainedValue()
                    return service.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearEventTapThread()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let stillStopped = self.lifecycleLock.withLock {
                        self.tap == nil && self.tapThread == nil
                    }
                    guard stillStopped else { return }
                    self.clearLeftoverMapping()
                    self.isRunning = false
                    Self.isEngaged = false
                    self.setMappingFailure(.keyboardTapRefused)
                }
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            lifecycleLock.withLock { self.tap = tap }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            let mouseMask = Self.mouseDownTypes.reduce(CGEventMask(0)) {
                $0 | (CGEventMask(1) << $1.rawValue)
            }
            let mouseTap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mouseMask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<SuperKeyService>.fromOpaque(userInfo)
                        .takeUnretainedValue()
                    return service.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
            var mouseSource: CFRunLoopSource?
            lifecycleLock.withLock {
                self.mouseTap = mouseTap
                self.mouseTapRefusals = mouseTap == nil ? self.mouseTapRefusals + 1 : 0
            }
            if let mouseTap {
                mouseSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, mouseTap, 0)
                CFRunLoopAddSource(runLoop, mouseSource, .commonModes)
                CGEvent.tapEnable(tap: mouseTap, enable: true)
            }

            DispatchQueue.main.async { [weak self] in self?.tapDidStart(tap) }
            if lifecycleLock.withLock({ shouldStopTapThread }) {
                CGEvent.tapEnable(tap: tap, enable: false)
                if let mouseTap { CGEvent.tapEnable(tap: mouseTap, enable: false) }
            } else {
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            if let mouseTap {
                CGEvent.tapEnable(tap: mouseTap, enable: false)
                if let mouseSource { CFRunLoopRemoveSource(runLoop, mouseSource, .commonModes) }
                CFMachPortInvalidate(mouseTap)
            }
            if clearEventTapThread() { startOnMain() }
        }
    }

    private func clearEventTapThread() -> Bool {
        lifecycleLock.withLock {
            let shouldRestart = pendingTapRestart
            tap = nil
            mouseTap = nil
            tapRunLoop = nil
            tapThread = nil
            shouldStopTapThread = false
            pendingTapRestart = false
            return shouldRestart
        }
    }

    private func startOnMain() {
        DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
    }

    private func tapDidStart(_ startedTap: CFMachPort) {
        let generation = lifecycleLock.withLock { () -> UInt? in
            guard tap === startedTap, !shouldStopTapThread else { return nil }
            return mappingGeneration
        }
        guard let generation else { return }
        confirmMapping(for: startedTap, generation: generation, publishingRunState: true)
    }

    private func clearLeftoverMapping(synchronously: Bool = false) {
        let mappingMayBeApplied = UserDefaults.standard.bool(
            forKey: DefaultsKey.superKeyMappingApplied
        ) || stateLock.withLock { pendingMappingEnableCount > 0 }
        if mappingMayBeApplied {
            applyMapping(false, synchronously: synchronously)
        }
    }

    private func observeWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self,
                  let active = self.lifecycleLock.withLock({
                      self.shouldStopTapThread ? nil : self.tap.map { ($0, self.mappingGeneration) }
                  })
            else { return }
            self.confirmMapping(for: active.0, generation: active.1, publishingRunState: false)
        }
    }

    // MARK: - The key mapping

    private func applyMapping(_ enabled: Bool,
                              expectedTap: CFMachPort? = nil,
                              generation: UInt? = nil,
                              synchronously: Bool = false,
                              completion: ((SuperKeyMappingFailure?) -> Void)? = nil) {
        let source = stateLock.withLock { eventSource }
        stateLock.withLock {
            lastMappingAt = ProcessInfo.processInfo.systemUptime
            if enabled { pendingMappingEnableCount += 1 }
        }
        let work = { [weak self] in
            guard let self else { return }
            defer {
                if enabled {
                    self.stateLock.withLock { self.pendingMappingEnableCount -= 1 }
                }
            }
            if enabled {
                guard let expectedTap, let generation,
                      self.lifecycleLock.withLock({
                          SuperKeySupport.mappingRequestIsAuthorized(
                              requestGeneration: generation,
                              currentGeneration: self.mappingGeneration,
                              tapIsCurrent: self.tap === expectedTap,
                              stopping: self.shouldStopTapThread
                          )
                      })
                else { return }
            }
            let defaults = UserDefaults.standard
            let previousMarker = defaults.bool(forKey: DefaultsKey.superKeyMappingApplied)
            let ownedSource = previousMarker ? SuperKeySource.sanitized(
                defaults.string(forKey: DefaultsKey.superKeyMappedSource)
            ) : nil
            let failure = self.performMapping(
                enabled,
                source: source,
                ownedSource: ownedSource
            )
            if !enabled {
                let guardConfirmed = self.mappingGuard?.stop() ?? false
                self.mappingGuard = nil
                let marker = SuperKeySupport.mappingMarkerAfterClear(
                    previous: previousMarker,
                    readbackConfirmed: failure == nil || guardConfirmed
                )
                defaults.set(marker, forKey: DefaultsKey.superKeyMappingApplied)
                if !marker { defaults.removeObject(forKey: DefaultsKey.superKeyMappedSource) }
            }
            if let completion {
                DispatchQueue.main.async { completion(failure) }
            }
        }
        if synchronously {
            mappingQueue.sync(execute: work)
        } else {
            mappingQueue.async(execute: work)
        }
    }

    private func performMapping(_ enabled: Bool,
                                source: SuperKeySource,
                                ownedSource: SuperKeySource?) -> SuperKeyMappingFailure? {
        let report = Shell.run(
            hidutilPath,
            ["property", "--matching", keyboardMatch,
             "--get", SuperKeySupport.userMappingProperty]
        )
        guard report.status == 0 else { return .systemRefused }
        guard let existing = SuperKeySupport.consistentMappings(
            report.output,
            property: SuperKeySupport.userMappingProperty,
            ownedSource: ownedSource
        ) else { return .foreignMapping }
        guard !enabled || !SuperKeySupport.hasMappingConflict(
            in: existing,
            source: source,
            ownedSource: ownedSource
        )
        else { return .foreignMapping }
        let wanted = SuperKeySupport.mappings(
            enablingSuperKey: enabled,
            existing: existing,
            source: source,
            ownedSource: ownedSource
        )
        if !enabled, ownedSource == nil,
           SuperKeySupport.mappingsMatch(existing, wanted) { return nil }
        var startedGuard = false
        var mappingConfirmed = false
        if enabled {
            if let mappingGuard, mappingGuard.source != source {
                guard mappingGuard.stop() else { return .systemRefused }
                self.mappingGuard = nil
            }
            if mappingGuard == nil {
                guard let guardHandle = SuperKeyMappingGuard.start(source: source) else {
                    return .systemRefused
                }
                mappingGuard = guardHandle
                startedGuard = true
            }
            UserDefaults.standard.set(true, forKey: DefaultsKey.superKeyMappingApplied)
            UserDefaults.standard.set(source.rawValue, forKey: DefaultsKey.superKeyMappedSource)
        }
        defer {
            if startedGuard, !mappingConfirmed {
                let cleared = mappingGuard?.stop() ?? false
                mappingGuard = nil
                if cleared {
                    UserDefaults.standard.set(false, forKey: DefaultsKey.superKeyMappingApplied)
                    UserDefaults.standard.removeObject(forKey: DefaultsKey.superKeyMappedSource)
                }
            }
        }
        let write = Shell.run(
            hidutilPath,
            ["property", "--matching", keyboardMatch,
             "--set", SuperKeySupport.mappingArgument(wanted)]
        )
        guard write.status == 0 else { return .systemRefused }
        let readback = Shell.run(
            hidutilPath,
            ["property", "--matching", keyboardMatch,
             "--get", SuperKeySupport.userMappingProperty]
        )
        guard readback.status == 0 else { return .systemRefused }
        mappingConfirmed = SuperKeySupport.mappingReportConfirms(readback.output, expected: wanted)
        return mappingConfirmed ? nil : .systemRefused
    }

    private func confirmMapping(for expectedTap: CFMachPort,
                                generation: UInt,
                                publishingRunState: Bool) {
        applyMapping(true, expectedTap: expectedTap, generation: generation) { [weak self] failure in
            guard let self else { return }
            let active = self.lifecycleLock.withLock {
                SuperKeySupport.mappingRequestIsAuthorized(
                    requestGeneration: generation,
                    currentGeneration: self.mappingGeneration,
                    tapIsCurrent: self.tap === expectedTap,
                    stopping: self.shouldStopTapThread
                )
            }
            guard active else { return }
            guard let failure else {
                self.setMappingFailure(nil)
                if publishingRunState || !self.isRunning { self.finishStart() }
                return
            }
            if publishingRunState {
                self.stop()
            } else {
                self.isRunning = false
            }
            self.setMappingFailure(failure)
        }
    }

    private func finishStart() {
        if source == .capsLock { setCapsLock(false) }
        observeWake()
        isRunning = true
        Self.isEngaged = true
    }

    private func setMappingFailure(_ failure: SuperKeyMappingFailure?) {
        guard mappingFailure != failure else { return }
        mappingFailure = failure
    }

    private func repairMappingIfStale() {
        guard let active = lifecycleLock.withLock({
            shouldStopTapThread ? nil : tap.map { ($0, mappingGeneration) }
        }) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let shouldRepair = stateLock.withLock {
            now - lastMappingAt >= mappingRepairInterval
        }
        if shouldRepair {
            confirmMapping(for: active.0, generation: active.1, publishingRunState: false)
        }
    }

    // MARK: - The tap

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let currentTaps = lifecycleLock.withLock {
                shouldStopTapThread ? (nil, nil) : (tap, mouseTap)
            }
            if SessionActivity.shared.isActive, AXIsProcessTrusted() {
                if let currentTap = currentTaps.0 { CGEvent.tapEnable(tap: currentTap, enable: true) }
                if let currentMouseTap = currentTaps.1 { CGEvent.tapEnable(tap: currentMouseTap, enable: true) }
            } else {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            forgetHeldKey()
            return Unmanaged.passUnretained(event)
        }
        let source = stateLock.withLock { eventSource }
        let event0 = SuperKeyService.classify(type: type, source: source, event: event)
        let decision = stateLock.withLock { state.decide(event0) }
        switch event0 {
        case .triggerDown:
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.lifecycleLock.withLock({
                          self.tap != nil && !self.shouldStopTapThread
                      }),
                      self.stateLock.withLock({ self.state.isHeld })
                else { return }
                self.armHeldKeyWatchdog()
            }
        case .triggerUp:
            DispatchQueue.main.async { [weak self] in
                self?.cancelHeldKeyWatchdog()
                self?.onHoldEnded?(true)
            }
        case .otherKey, .otherModifier, .sourceKey:
            break
        }
        switch decision {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .swallow:
            return nil
        case .addModifiers:
            let modifierFlags = stateLock.withLock { eventModifiers.cgFlags }
            event.flags = event.flags.union(modifierFlags)
            return Unmanaged.passUnretained(event)
        case .soloTap(repeated: let repeated):
            performSoloAction(longHold: false, repeated: repeated)
            return nil
        case .soloHold(repeated: let repeated):
            performSoloAction(longHold: true, repeated: repeated)
            return nil
        case .interceptAndRemap:
            repairMappingIfStale()
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.lifecycleLock.withLock({
                          self.tap != nil && !self.shouldStopTapThread
                      })
                else { return }
                if source == .capsLock { self.setCapsLock(false) }
            }
            return nil
        }
    }

    // MARK: - A press whose release never came

    private func armHeldKeyWatchdog() {
        heldKeyWatchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reevaluateHold() }
        heldKeyWatchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + heldKeyTimeout, execute: work)
    }

    private func reevaluateHold() {
        guard stateLock.withLock({ state.isHeld }),
              lifecycleLock.withLock({ tap != nil && !shouldStopTapThread })
        else { forgetHeldKey(); return }
        readPhysicalKeyDown { [weak self] physicalKeyDown in
            guard let self else { return }
            let stateThinksHeld = self.stateLock.withLock { self.state.isHeld }
            let tapAlive = self.lifecycleLock.withLock { self.tap != nil && !self.shouldStopTapThread }
            switch SuperKeySupport.heldKeyWatchdogOutcome(physicalKeyDown: physicalKeyDown,
                                                          stateThinksHeld: stateThinksHeld,
                                                          tapAlive: tapAlive) {
            case .reArm:
                self.armHeldKeyWatchdog()
            case .forget:
                self.forgetHeldKey()
            }
        }
    }

    private func readPhysicalKeyDown(_ handler: @escaping (Bool) -> Void) {
        let key = CGKeyCode(SuperKeySupport.triggerKeyCode)
        DispatchQueue.global(qos: .userInitiated).async {
            let physicalKeyDown = CGEventSource.keyState(.hidSystemState, key: key)
            DispatchQueue.main.async { handler(physicalKeyDown) }
        }
    }

    private func cancelHeldKeyWatchdog() {
        heldKeyWatchdog?.cancel()
        heldKeyWatchdog = nil
    }

    private func forgetHeldKey() {
        let wasHeld = stateLock.withLock { () -> Bool in
            let held = state.isHeld
            state.reset()
            return held
        }
        let notify = { [weak self] in
            self?.cancelHeldKeyWatchdog()
            if wasHeld { self?.onHoldEnded?(false) }
        }
        if Thread.isMainThread {
            notify()
        } else {
            DispatchQueue.main.async(execute: notify)
        }
    }

    private static func classify(type: CGEventType, source: SuperKeySource,
                                 event: CGEvent) -> SuperKeySupport.Event {
        if mouseDownTypes.contains(type) { return .otherKey }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged {
            return keyCode == source.keyCode ? .sourceKey : .otherModifier
        }
        guard keyCode == SuperKeySupport.triggerKeyCode else { return .otherKey }
        let timestamp = EventTimestamp.nanoseconds(of: event)
        if type == .keyDown {
            return .triggerDown(
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                hasPrimaryModifiers: !GlobalShortcutModifiers(cgFlags: event.flags).isEmpty,
                timestamp: timestamp
            )
        }
        return .triggerUp(timestamp: timestamp)
    }

    // MARK: - Tapped on its own

    private func performSoloAction(longHold: Bool, repeated: Bool) {
        let action = stateLock.withLock { soloAction }
        switch SuperKeySupport.soloEffect(action: action,
                                          longHold: longHold,
                                          repeated: repeated) {
        case .none:
            return
        case .escape:
            runOnMainIfNeeded { _ = Self.postKey(CGKeyCode(kVK_Escape)) }
        case .capsLock:
            runOnMainIfNeeded { self.setCapsLock(!self.capsLockIsOn()) }
        case .inputSource:
            Self.selectNextInputSource()
        }
    }

    private func runOnMainIfNeeded(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private static func postKey(_ keyCode: CGKeyCode) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }
        down.flags = []
        up.flags = []
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        return true
    }

    private static func selectNextInputSource() {
        let apply = {
            let sources = InputSourceSelection.selectableInputSources()
            let ids = sources.compactMap {
                InputSourceSelection.inputSourceString($0, property: kTISPropertyInputSourceID)
            }
            guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
            let currentID = InputSourceSelection.inputSourceString(current, property: kTISPropertyInputSourceID)
            guard let nextID = SuperKeySupport.nextInputSourceID(currentID: currentID,
                                                                 enabledIDs: ids),
                  let next = sources.first(where: {
                      InputSourceSelection.inputSourceString($0, property: kTISPropertyInputSourceID) == nextID
                  })
            else { return }
            _ = TISSelectInputSource(next)
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.sync(execute: apply)
        }
    }

    // MARK: - Caps Lock itself

    private func withHIDSystem<T>(_ body: (io_connect_t) -> T?) -> T? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection) == KERN_SUCCESS
        else { return nil }
        defer { IOServiceClose(connection) }
        return body(connection)
    }

    private func capsLockIsOn() -> Bool {
        withHIDSystem { connection in
            var state = false
            guard IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &state) == KERN_SUCCESS
            else { return nil }
            return state
        } ?? false
    }

    private func setCapsLock(_ on: Bool) {
        _ = withHIDSystem { connection in
            IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), on)
        }
    }
}
