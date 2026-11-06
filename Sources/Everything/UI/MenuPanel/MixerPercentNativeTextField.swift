// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

final class MixerPercentNativeTextField: NSTextField {
    var didAttachToWindow: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { didAttachToWindow?() }
    }

    @discardableResult
    func focusAndSelectAll() -> Bool {
        guard let window else { return false }
        window.makeKey()
        guard window.makeFirstResponder(self) else { return false }
        selectText(nil)
        return true
    }
}
