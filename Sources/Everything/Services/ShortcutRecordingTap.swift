// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import CoreGraphics
import Foundation

enum ShortcutRecordingTap {
    private static var tap: CFMachPort?
    private static var runLoopSource: CFRunLoopSource?
    private static var handler: ((Int64, GlobalShortcutModifiers, CGEventFlags) -> Void)?
    private static var heldKeyCode: Int64?
    private static var drainingKeyCode: Int64?
    private static var drainWatchdog: DispatchWorkItem?
    private static var superState = SuperKeySupport.State()
    private static var observingSession = false

    @discardableResult
    static func begin(_ newHandler: @escaping (Int64, GlobalShortcutModifiers, CGEventFlags) -> Void) -> Bool {
        drainWatchdog?.cancel()
        drainWatchdog = nil
        drainingKeyCode = nil
        heldKeyCode = nil
        superState.reset()
        if !observingSession {
            observingSession = true
            SessionActivity.shared.onChange { if !$0 { tearDown(); ShortcutCapture.end() } }
        }
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            tearDown()
        }
        if tap == nil {
            guard AXIsProcessTrusted() else { return false }
            let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
                | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            guard let created = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, _ in
                    ShortcutRecordingTap.handle(type: type, event: event)
                },
                userInfo: nil
            ) else { return false }
            tap = created
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: created, enable: true)
        }
        handler = newHandler
        return true
    }

    static func end() {
        handler = nil
        guard tap != nil else { return }
        if let heldKeyCode {
            drainingKeyCode = heldKeyCode
            armDrainWatchdog()
        } else {
            tearDown()
        }
    }

    private static func armDrainWatchdog() {
        drainWatchdog?.cancel()
        let watchdog = DispatchWorkItem { tearDown() }
        drainWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: watchdog)
    }

    private static func tearDown() {
        drainWatchdog?.cancel()
        drainWatchdog = nil
        drainingKeyCode = nil
        heldKeyCode = nil
        handler = nil
        superState.reset()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    private static func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                DispatchQueue.main.async { tearDown(); ShortcutCapture.end() }
            }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if let handler {
            var heldModifiers: GlobalShortcutModifiers = []
            if SuperKeyService.isEngaged {
                let superEvent: SuperKeySupport.Event
                if keyCode == SuperKeySupport.triggerKeyCode {
                    let timestamp = EventTimestamp.nanoseconds(of: event)
                    superEvent = type == .keyDown
                        ? .triggerDown(
                            isRepeat: isRepeat,
                            hasPrimaryModifiers: !GlobalShortcutModifiers(cgFlags: event.flags).isEmpty,
                            timestamp: timestamp
                        )
                        : .triggerUp(timestamp: timestamp)
                } else {
                    superEvent = .otherKey
                }
                switch superState.decide(superEvent) {
                case .swallow, .soloTap(repeated: _), .soloHold(repeated: _): return nil
                case .addModifiers: heldModifiers = SuperKeyService.shared.modifiers
                case .pass, .interceptAndRemap: break
                }
            }
            if type == .keyDown {
                heldKeyCode = keyCode
                if !isRepeat {
                    handler(keyCode, GlobalShortcutModifiers(cgFlags: event.flags).union(heldModifiers),
                            event.flags)
                }
            } else if keyCode == heldKeyCode {
                heldKeyCode = nil
            }
            return nil
        }
        if let drainingKeyCode, keyCode == drainingKeyCode {
            if type == .keyUp {
                tearDown()
            } else {
                armDrainWatchdog()
            }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
