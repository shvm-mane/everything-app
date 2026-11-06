// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

final class ScrollWheelHIDStage {
    static let shared = ScrollWheelHIDStage()

    enum Client: Hashable {
        case smoothScroll
        case wheelTap
    }

    private let lock = NSLock()
    private var ledger = ScrollWheelHIDStageLedger()
    private var clients = Set<Client>()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var creationRetryUsed = false

    private init() {}

    func passed(_ event: CGEvent) -> Bool {
        let timestamp = event.timestamp
        let sourceProcessID = event.getIntegerValueField(.eventSourceUnixProcessID)
        return lock.withLock { ledger.passed(timestamp, sourceProcessID: sourceProcessID) }
    }

    func setWatching(_ wanted: Bool, for client: Client) {
        let (port, source) = lock.withLock { () -> (CFMachPort?, CFRunLoopSource?) in
            if wanted {
                clients.insert(client)
            } else {
                clients.remove(client)
            }
            guard clients.isEmpty, tap != nil else { return (nil, nil) }
            let current = (tap, runLoopSource)
            tap = nil
            runLoopSource = nil
            ledger.reset()
            return current
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            if let source {
                PointerTapRunLoop.remove(source, invalidating: port)
            }
            return
        }
        guard wanted, lock.withLock({ tap == nil }) else { return }
        guard let created = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let stage = Unmanaged<ScrollWheelHIDStage>.fromOpaque(userInfo).takeUnretainedValue()
                stage.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            guard !creationRetryUsed else { return }
            creationRetryUsed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, let client = self.lock.withLock({ self.clients.first }) else { return }
                self.setWatching(true, for: client)
            }
            return
        }
        creationRetryUsed = false
        let createdSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        lock.withLock {
            tap = created
            runLoopSource = createdSource
        }
        if let createdSource {
            PointerTapRunLoop.add(createdSource)
        }
        CGEvent.tapEnable(tap: created, enable: true)
        lock.withLock { ledger.isWatching = true }
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if SessionActivity.shared.isActive, let port = lock.withLock({ tap }) {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return
        }
        guard type == .scrollWheel else { return }
        let timestamp = event.timestamp
        lock.withLock { ledger.note(timestamp) }
    }
}
