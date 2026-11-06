// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

extension NSScreen {
    static var withMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? main
    }

    var isStillAttached: Bool {
        let id = displayID
        guard id != 0 else { return false }
        return NSScreen.screens.contains { $0.displayID == id }
    }

    static var withMenuBar: NSScreen? {
        screens.first { $0.frame.origin == .zero } ?? screens.first
    }

    static var pointerVisibleFrame: CGRect {
        (withMouse ?? screens.first)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }
}
