// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum NotchIslandAlert {
    static func run(_ alert: NSAlert, above island: NSWindow?) -> NSApplication.ModalResponse {
        var observers: [NSObjectProtocol] = []
        if let island, island.isVisible {
            let level = NSWindow.Level(rawValue: island.level.rawValue + 1)
            let raise: (Notification) -> Void = { _ in alert.window.level = level }
            observers = [NSWindow.didBecomeKeyNotification, NSApplication.didBecomeActiveNotification].map {
                NotificationCenter.default.addObserver(forName: $0, object: nil, queue: .main, using: raise)
            }
            DispatchQueue.main.async { alert.window.level = level }
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        observers.forEach(NotificationCenter.default.removeObserver)
        if let island, island.isVisible { island.makeKey() }
        return response
    }
}
