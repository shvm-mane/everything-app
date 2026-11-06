// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics

final class MouseButtonShortcutService: ObservableObject {
    static let shared = MouseButtonShortcutService()
    private static let replayedPressMarker: Int64 = 0x564F5253
    private(set) static var hasActiveSideWheelInterest = false

    @Published private(set) var isRunning = false
    @Published private(set) var lastInputSeen: Int64?

    private(set) static var isCaptureActive = false

    private var mappings: [Int64: GlobalShortcut] = [:]
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapIncludesSideWheel = false
    private var isCapturing = false
    private var isCapturingSpacesGesture = false
    private var consumedButtons: Set<Int64> = []
    private var isDraining = false
    private var restartAfterDrain = false
    private var lastGesturePhaseTimestamp: UInt64?
    private var wantsSideWheelEvents = false
    private var sideWheelGesture = MouseButtonShortcutSupport.SideWheelGestureGate()
    private var spacesButton: Int64?
    private var spacesGesture: SpacesGesturePress?

    private struct SpacesGesturePress {
        let button: Int64
        let down: CGEvent
        let followsDrag: Bool
        var tracker: MouseSpacesGestureSupport.Tracker
    }

    private init() {
        SessionActivity.shared.onChange { [weak self] active in
            guard let self else { return }
            if active {
                self.syncWithPreferences()
            } else {
                self.tearDownTap(replayPendingSpacesPress: false)
            }
        }
    }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let enabled = AppFeature.mouseButtonShortcuts.isAvailable
            && defaults.bool(forKey: DefaultsKey.mouseButtonShortcutsEnabled)
        mappings = MouseButtonShortcutSupport.decode(
            defaults.dictionary(forKey: DefaultsKey.mouseButtonShortcuts) as? [String: String])
        wantsSideWheelEvents = enabled && (isCapturing
            || mappings[MouseButtonShortcutSupport.sideWheelLeftInput] != nil
            || mappings[MouseButtonShortcutSupport.sideWheelRightInput] != nil)
        spacesButton = MouseButtonShortcutSupport.spacesGestureButton()
        let canOwnTap = SessionActivitySupport.tapShouldRun(
            featureWanted: true,
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive
        )
        guard canOwnTap else {
            tearDownTap(replayPendingSpacesPress: false)
            return
        }
        if let spacesGesture, spacesGesture.button != spacesButton {
            flushSpacesPress(proxy: nil, at: nil)
        }
        let wanted = (enabled && !mappings.isEmpty) || isCapturing || spacesButton != nil
        guard wanted else {
            stop()
            return
        }
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            tearDownTap(replayPendingSpacesPress: false)
        }
        if isDraining, tap != nil {
            restartAfterDrain = true
            return
        }
        start()
    }

    func suspend() {
        let mayReplayPendingPress = SessionActivity.shared.isActive && AXIsProcessTrusted()
        tearDownTap(replayPendingSpacesPress: mayReplayPendingPress)
    }

    func setCapturing(_ capturing: Bool, forSpacesGesture: Bool = false) {
        let capturesSpaces = capturing && forSpacesGesture
        guard isCapturing != capturing || isCapturingSpacesGesture != capturesSpaces else { return }
        isCapturing = capturing
        isCapturingSpacesGesture = capturesSpaces
        Self.isCaptureActive = capturing
        lastInputSeen = nil
        syncWithPreferences()
    }

    private func start() {
        if tap != nil, tapIncludesSideWheel != wantsSideWheelEvents {
            if !consumedButtons.isEmpty {
                Self.hasActiveSideWheelInterest = false
                MouseAppExceptions.shared.setSourceTracking(false, for: .buttonShortcuts)
                isDraining = true
                restartAfterDrain = true
                isRunning = false
                return
            }
            tearDownTap()
        }
        guard tap == nil else {
            Self.hasActiveSideWheelInterest = wantsSideWheelEvents
            MouseAppExceptions.shared.setSourceTracking(wantsSideWheelEvents, for: .buttonShortcuts)
            isRunning = true
            return
        }
        guard AXIsProcessTrusted() else {
            Self.hasActiveSideWheelInterest = false
            MouseAppExceptions.shared.setSourceTracking(false, for: .buttonShortcuts)
            isRunning = false
            return
        }
        var mask = (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseDragged.rawValue)
        if wantsSideWheelEvents {
            mask |= CGEventMask(1) << CGEventType.scrollWheel.rawValue
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<MouseButtonShortcutService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            tapIncludesSideWheel = false
            Self.hasActiveSideWheelInterest = false
            MouseAppExceptions.shared.setSourceTracking(false, for: .buttonShortcuts)
            isRunning = false
            return
        }
        self.tap = tap
        tapIncludesSideWheel = wantsSideWheelEvents
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Self.hasActiveSideWheelInterest = wantsSideWheelEvents
        MouseAppExceptions.shared.setSourceTracking(wantsSideWheelEvents, for: .buttonShortcuts)
        isRunning = true
    }

    private func stop() {
        Self.hasActiveSideWheelInterest = false
        MouseAppExceptions.shared.setSourceTracking(false, for: .buttonShortcuts)
        restartAfterDrain = false
        if !consumedButtons.isEmpty, tap != nil {
            isDraining = true
            isRunning = false
            return
        }
        tearDownTap()
    }

    private func tearDownTap(replayPendingSpacesPress: Bool = true) {
        Self.hasActiveSideWheelInterest = false
        MouseAppExceptions.shared.setSourceTracking(false, for: .buttonShortcuts)
        if replayPendingSpacesPress {
            flushSpacesPress(proxy: nil, at: nil)
        } else {
            spacesGesture = nil
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        tapIncludesSideWheel = false
        consumedButtons.removeAll()
        lastGesturePhaseTimestamp = nil
        sideWheelGesture.reset()
        isDraining = false
        restartAfterDrain = false
        isRunning = false
    }

    private func handle(proxy: CGEventTapProxy?, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            sideWheelGesture.reset()
            flushSpacesPress(proxy: nil, at: nil)
            consumedButtons = consumedButtons.filter {
                MouseButtonShortcutSupport.isPressed(
                    $0, pressedButtons: NSEvent.pressedMouseButtons)
            }

            let enabled = AppFeature.mouseButtonShortcuts.isAvailable
                && UserDefaults.standard.bool(forKey: DefaultsKey.mouseButtonShortcutsEnabled)
            let wanted = (enabled && !mappings.isEmpty) || isCapturing || spacesButton != nil
            let shouldRun = SessionActivitySupport.tapShouldRun(
                featureWanted: wanted || !consumedButtons.isEmpty,
                accessibilityGranted: AXIsProcessTrusted(),
                sessionIsActive: SessionActivity.shared.isActive
            )
            if shouldRun, let tap,
               !restartAfterDrain || !consumedButtons.isEmpty {
                if !wanted || restartAfterDrain {
                    isDraining = true
                    isRunning = false
                }
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.tearDownTap(replayPendingSpacesPress: false)
                    self.syncWithPreferences()
                }
            }
            return Unmanaged.passUnretained(event)
        }
        if type == .scrollWheel {
            return handleSideWheel(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayedPressMarker {
            return Unmanaged.passUnretained(event)
        }
        let button = event.getIntegerValueField(.mouseEventButtonNumber)

        if type == .otherMouseDown {
            if isDraining {
                return Unmanaged.passUnretained(event)
            }
            if isCapturing {
                let consumesPress = isCapturingSpacesGesture
                    ? MouseSpacesGestureSupport.canBind(button)
                    : MouseButtonShortcutSupport.canMap(button)
                if consumesPress { consumedButtons.insert(button) }
                lastInputSeen = button
                return consumesPress ? nil : Unmanaged.passUnretained(event)
            }
            guard !MouseAppExceptions.shared.excludesActionTarget(.buttonShortcuts, at: event.location) else {
                return Unmanaged.passUnretained(event)
            }
            if button == spacesButton {
                return armSpacesGesture(event, button: button)
            }
            guard let shortcut = MouseButtonShortcutSupport.firesShortcut(
                for: button,
                isAvailable: AppFeature.mouseButtonShortcuts.isAvailable,
                isEnabled: UserDefaults.standard.bool(forKey: DefaultsKey.mouseButtonShortcutsEnabled),
                mappings: mappings,
                claimedByWheel: RadialMenuSupport.claimsMouseButton)
            else { return Unmanaged.passUnretained(event) }
            consumedButtons.insert(button)
            post(shortcut)
            return nil
        }

        if let gesture = spacesGesture, gesture.button == button {
            switch type {
            case .otherMouseDragged:
                advanceSpacesGesture(to: event.location)
                return nil
            case .otherMouseUp:
                spacesGesture = nil
                guard gesture.tracker.didFire else {
                    replaySpacesPress(gesture.down, proxy: proxy, at: event.location)
                    return Unmanaged.passUnretained(event)
                }
            default:
                return nil
            }
        }

        guard consumedButtons.contains(button) else {
            return Unmanaged.passUnretained(event)
        }
        if type == .otherMouseUp {
            consumedButtons.remove(button)
            if isDraining, consumedButtons.isEmpty {
                let shouldRestart = restartAfterDrain
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isDraining, self.consumedButtons.isEmpty else { return }
                    self.tearDownTap()
                    if shouldRestart {
                        self.syncWithPreferences()
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Spaces and Mission Control drag

    private func armSpacesGesture(_ event: CGEvent, button: Int64) -> Unmanaged<CGEvent>? {
        guard let down = event.copy() else { return Unmanaged.passUnretained(event) }
        spacesGesture = SpacesGesturePress(
            button: button,
            down: down,
            followsDrag: UserDefaults.standard.bool(forKey: DefaultsKey.mouseSpacesGestureFollowsDrag),
            tracker: .init(origin: event.location))
        return nil
    }

    private func advanceSpacesGesture(to point: CGPoint) {
        guard var gesture = spacesGesture else { return }
        let action = gesture.tracker.advance(to: point,
                                             now: ProcessInfo.processInfo.systemUptime)
        spacesGesture = gesture
        guard let action else { return }
        consumedButtons.insert(gesture.button)
        perform(MouseSpacesGestureSupport.resolved(action, followsDrag: gesture.followsDrag))
    }

    private func perform(_ action: MouseSpacesGestureSupport.Action) {
        let shortcut: SpaceWindowBridge.SpaceShortcut?
        switch action {
        case .spaceLeft: shortcut = SpaceWindowBridge.spaceShortcut(.left)
        case .spaceRight: shortcut = SpaceWindowBridge.spaceShortcut(.right)
        case .missionControl: shortcut = SpaceWindowBridge.overviewShortcut(.missionControl)
        case .appExpose: shortcut = SpaceWindowBridge.overviewShortcut(.appExpose)
        }
        guard let shortcut else { return }
        SpaceWindowBridge.pressSpaceShortcut(shortcut)
    }

    private func flushSpacesPress(proxy: CGEventTapProxy?, at point: CGPoint?) {
        guard let gesture = spacesGesture else { return }
        spacesGesture = nil
        guard !gesture.tracker.didFire,
              MouseButtonShortcutSupport.isPressed(
                  gesture.button, pressedButtons: NSEvent.pressedMouseButtons
              ) else { return }
        replaySpacesPress(gesture.down, proxy: proxy, at: point)
    }

    private func replaySpacesPress(_ down: CGEvent, proxy: CGEventTapProxy?, at point: CGPoint?) {
        if let point { down.location = point }
        down.timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        down.setIntegerValueField(.eventSourceUserData, value: Self.replayedPressMarker)
        if let proxy {
            down.tapPostEvent(proxy)
        } else {
            down.post(tap: .cgSessionEventTap)
        }
    }

    private func handleSideWheel(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if AppSwitcher.shared.scrollNavigationActive {
            return Unmanaged.passUnretained(event)
        }
        guard Self.hasActiveSideWheelInterest,
              !isDraining,
              event.getIntegerValueField(.eventSourceUserData) != ScrollWheelSupport.syntheticTag,
              event.getIntegerValueField(.eventSourceUserData) != ScrollWheelSupport.horizontalRedirectTag,
              let input = sideWheelInput(for: event) else {
            return Unmanaged.passUnretained(event)
        }
        let timestamp = UInt64(event.timestamp)
        if isCapturing {
            guard sideWheelGesture.shouldFire(input, at: timestamp) else { return nil }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCapturing else { return }
                self.lastInputSeen = input
            }
            return nil
        }
        guard let shortcut = mappings[input] else { return Unmanaged.passUnretained(event) }
        let sourceProcessID = event.getIntegerValueField(.eventSourceUnixProcessID)
        if MouseAppExceptions.shared.excludesActionTarget(
            .buttonShortcuts, at: event.location, sourceProcessID: sourceProcessID) {
            return Unmanaged.passUnretained(event)
        }
        guard sideWheelGesture.shouldFire(input, at: timestamp) else { return nil }
        post(shortcut)
        return nil
    }

    private func sideWheelInput(for event: CGEvent) -> Int64? {
        let traits = ScrollWheelEventTraits(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            scrollCount: event.getIntegerValueField(.scrollWheelEventScrollCount)
        )
        let timestamp = UInt64(event.timestamp)
        let secondsSinceGesturePhase = lastGesturePhaseTimestamp.map {
            Double(timestamp &- $0) / 1_000_000_000.0
        }
        if traits.momentumPhase != 0 || traits.scrollPhase != 0 {
            lastGesturePhaseTimestamp = timestamp
        }
        guard ScrollWheelSupport.isMouseWheel(
            traits,
            secondsSinceLastGesturePhase: secondsSinceGesturePhase) else { return nil }
        let wheel = ScrollInverter.directionApplied(to: event)
        return MouseButtonShortcutSupport.sideWheelInput(
            isContinuous: traits.isContinuous,
            vertical: (
                line: Double(wheel.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
                fixedPoint: wheel.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                point: Double(wheel.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            ),
            horizontal: (
                line: Double(wheel.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
                fixedPoint: wheel.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
                point: Double(wheel.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
            )
        )
    }

    private func post(_ shortcut: GlobalShortcut) {
        guard shortcut.hasUsableKeyCode else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source,
                                 virtualKey: CGKeyCode(shortcut.keyCode),
                                 keyDown: true),
              let up = CGEvent(keyboardEventSource: source,
                               virtualKey: CGKeyCode(shortcut.keyCode),
                               keyDown: false) else { return }
        let flags = shortcut.syntheticEventFlags
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
