// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum ActivationHandoff {
    private static let selfActivationWindow: CFTimeInterval = 1

    private static var lastSelfActivation: CFAbsoluteTime = 0

    static var isHandingOff: Bool {
        CFAbsoluteTimeGetCurrent() - lastSelfActivation < selfActivationWindow
    }

    static func yield(to app: NSRunningApplication) {
        lastSelfActivation = CFAbsoluteTimeGetCurrent()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.yieldActivation(to: app)
    }
}
