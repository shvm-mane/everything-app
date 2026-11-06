// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

final class PointerDisplayService: ObservableObject {
    static let shared = PointerDisplayService()

    @Published private(set) var shortcutRegistrationFailed = false

    private let hotkey = QuickToolHotkey(id: 80)

    private init() {
        hotkey.onPress = { [weak self] in self?.moveToNextDisplay() }
    }

    func syncWithPreferences() {
        let enabled = AppFeature.windowLayout.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.pointerDisplayEnabled)
        let front = NSWorkspace.shared.frontmostApplication
        let paused = WindowLayoutIgnoredApps.shared.contains(bundleID: front?.bundleIdentifier,
                                                             executablePath: front?.executableURL?.path)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled && !paused,
                                                  shortcut: GlobalShortcutRole.pointerNextDisplay.savedShortcut,
                                                  storageKey: DefaultsKey.pointerDisplayShortcut)
    }

    func suspend() {
        hotkey.unregister()
    }

    func moveToNextDisplay() {
        let screens = NSScreen.screens
        guard let currentIndex = screens.firstIndex(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }),
              let target = WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: currentIndex,
                                                                      frames: screens.map(\.frame),
                                                                      movingForward: true)
        else { return }
        let displayID = screens[target].displayID
        guard displayID != 0 else { return }
        let bounds = CGDisplayBounds(displayID)
        CGWarpMouseCursorPosition(CGPoint(x: bounds.midX, y: bounds.midY))
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
