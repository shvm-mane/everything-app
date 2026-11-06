// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

final class SessionActivity {
    static let shared = SessionActivity()

    var isActive: Bool { lock.withLock { active } }

    private let lock = NSLock()
    private var active = false

    private let center: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var handlers: [(Bool) -> Void] = []

    init(center: NotificationCenter = NSWorkspace.shared.notificationCenter,
         initialIsActive: () -> Bool = {
             SessionActivitySupport.isOnConsole(CGSessionCopyCurrentDictionary() as? [String: Any])
         }) {
        self.center = center
        observers = [
            center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.update(isActive: false)
            },
            center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.update(isActive: true)
            },
        ]
        active = initialIsActive()
    }

    deinit {
        for observer in observers { center.removeObserver(observer) }
    }

    func onChange(_ handler: @escaping (Bool) -> Void) {
        handlers.append(handler)
    }

    private func update(isActive: Bool) {
        let changed = lock.withLock { () -> Bool in
            guard isActive != active else { return false }
            active = isActive
            return true
        }
        guard changed else { return }
        for handler in handlers { handler(isActive) }
    }
}
