// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ShortcutCapture {
    private(set) static var isCapturing = false

    static func begin() {
        guard !isCapturing else { return }
        isCapturing = true
        AppSwitcher.shared.setCapturingShortcut(true)
        HotkeyManager.shared.setEnabled(false)
        ShelfService.shared.suspendShortcut()
        ClipboardHistoryService.shared.suspendShortcut()
        SoundOutputSwitcher.shared.suspendShortcut()
        WindowLayoutService.shared.suspendShortcuts()
        QuickToolHotkey.unregisterAll()
    }

    static func end() {
        guard isCapturing else { return }
        isCapturing = false
        AppSwitcher.shared.setCapturingShortcut(false)
        FeatureRuntime.shared.sync(GlobalShortcutRole.featuresToSilenceWhileRecording)
    }
}
