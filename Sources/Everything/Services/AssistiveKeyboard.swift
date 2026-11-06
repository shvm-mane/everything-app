// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

enum AssistiveKeyboard {
    static let bundleID = "com.apple.inputmethod.AssistiveControl"

    private static func currentPID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first?.processIdentifier
    }

    static var isRunning: Bool { currentPID() != nil }

    private static func onScreenWindows() -> [[String: Any]]? {
        CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]]
    }

    static func ownsPoint(_ point: CGPoint) -> Bool {
        ownsPoint(point, keyboardPID: currentPID, windows: onScreenWindows)
    }

    static func ownsPoint(_ point: CGPoint,
                          keyboardPID: () -> pid_t?,
                          windows: () -> [[String: Any]]?) -> Bool {
        guard let pid = keyboardPID(), let windows = windows() else { return false }

        for window in windows {
            guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"],
                  CGRect(x: x, y: y, width: width, height: height).contains(point)
            else { continue }
            if let alpha = window[kCGWindowAlpha as String] as? CGFloat, alpha <= 0 { continue }
            let owner = window[kCGWindowOwnerPID as String] as? pid_t
            if owner == pid { return true }
            if owner == ProcessInfo.processInfo.processIdentifier { continue }
            return false
        }
        return false
    }

    static func ownsCocoaPoint(_ point: NSPoint) -> Bool {
        guard let primary = NSScreen.screens.first else { return false }
        return ownsPoint(CGPoint(x: point.x, y: primary.frame.maxY - point.y))
    }
}
