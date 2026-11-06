// SPDX-License-Identifier: GPL-3.0-or-later
// InstantSpaceSwitcher inside Everything. This replaces ISS's AppDelegate:
// it starts the C core (Sources/ISS, MIT licensed), binds the hotkeys,
// and watches space changes.

import AppKit
import ISS
import ApplicationServices
import Combine

enum SpacesDefaults {
    static let enabled = "iss.enabled"
    static let swipeOverride = "iss.swipeOverride"
    static let gestureSpeed = "iss.gestureSpeed"
    static let overlayDetectionEnabled = "iss.overlayDetectionEnabled"

    static let registered: [String: Any] = [
        enabled: true,
        swipeOverride: false,
        gestureSpeed: 2000.0,
        overlayDetectionEnabled: false,
    ]
}

@MainActor
final class SpaceSwitcher: ObservableObject {
    static let shared = SpaceSwitcher()

    private let hotkeyStore = HotkeyStore.shared
    private var currentSpaceIndex: UInt32?
    private var lastSpaceIndex: UInt32?
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var coreStarted = false
    private var running = false

    /// Opens Everything's settings; set by the app delegate.
    var openSettings: () -> Void = {}

    private init() {
        UserDefaults.standard.register(defaults: SpacesDefaults.registered)
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: SpacesDefaults.enabled) }

    /// Called at launch and whenever a Spaces setting changes.
    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        if isEnabled {
            start()
            iss_set_swipe_override(defaults.bool(forKey: SpacesDefaults.swipeOverride))
            let speed = defaults.double(forKey: SpacesDefaults.gestureSpeed)
            if speed > 0 { iss_set_gesture_speed(speed) }
            iss_set_overlay_detection_enabled(defaults.bool(forKey: SpacesDefaults.overlayDetectionEnabled))
        } else {
            stop()
        }
    }

    private func start() {
        if !coreStarted {
            coreStarted = iss_init()
            if !coreStarted { retryCoreInit() }
        }
        guard !running else { return }
        running = true
        bindHotkeys()
        observeSpaceChanges()
        refreshSpaceInfo()
    }

    private func stop() {
        guard running else { return }
        running = false
        cancellables.removeAll()
        HotKeyManager.shared.unregisterAll()
        iss_set_swipe_override(false)
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }

    /// Before quitting: release the core's event taps.
    func shutdown() {
        stop()
        if coreStarted { iss_destroy(); coreStarted = false }
    }

    private func retryCoreInit() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, !self.coreStarted, self.isEnabled else { return }
            self.coreStarted = iss_init()
            if !self.coreStarted { self.retryCoreInit() }
        }
    }

    // MARK: Hotkeys

    private func bindHotkeys() {
        cancellables.removeAll()
        // Every published hotkey and the enabled map re-register everything:
        // simpler than one sink per identifier and identical in effect.
        hotkeyStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.reregisterAllHotkeys() }
            }
            .store(in: &cancellables)
        reregisterAllHotkeys()
    }

    func reregisterAllHotkeys() {
        for identifier in HotkeyIdentifier.allCases {
            registerHotkey(for: identifier, combination: hotkeyStore.combination(for: identifier))
        }
    }

    private func registerHotkey(for identifier: HotkeyIdentifier, combination: HotkeyCombination) {
        guard running, hotkeyStore.isEnabled(identifier) else {
            HotKeyManager.shared.unregister(identifier: identifier)
            return
        }
        HotKeyManager.shared.register(identifier: identifier, combination: combination) { [weak self] in
            guard let self else { return }
            switch identifier {
            case .left: self.performSpaceSwitch(ISSDirectionLeft)
            case .right: self.performSpaceSwitch(ISSDirectionRight)
            case .lastSpace: self.performSpaceLastSpace()
            default:
                if let index = HotkeyIdentifier.spaceNumber(identifier) {
                    self.performSpaceSwitchToIndex(UInt32(index - 1))
                }
            }
        }
    }

    // MARK: Switching

    func performSpaceSwitch(_ direction: ISSDirection) {
        if !iss_switch(direction) {
            NSSound.beep()
            return
        }
        refreshSpaceInfo()
    }

    func performSpaceSwitchToIndex(_ index: UInt32) {
        if !iss_switch_to_index(index) {
            NSSound.beep()
            return
        }
        refreshSpaceInfo()
    }

    private func performSpaceLastSpace() {
        guard let lastSpaceIndex, lastSpaceIndex != currentSpaceIndex else {
            NSSound.beep()
            return
        }
        performSpaceSwitchToIndex(lastSpaceIndex)
    }

    /// Reads the current space, for the last-space keybind.
    private func refreshSpaceInfo() {
        var info = ISSSpaceInfo()
        guard iss_get_menubar_space_info(&info) else { return }
        if currentSpaceIndex != info.currentIndex {
            lastSpaceIndex = currentSpaceIndex
            currentSpaceIndex = info.currentIndex
        }
    }

    /// Event-driven only: no polling.
    private func observeSpaceChanges() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                iss_reset_predictions()
                self.refreshSpaceInfo()
                // The core can read the old space for a moment after the change.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    MainActor.assumeIsolated { self?.refreshSpaceInfo() }
                }
            }
        })
    }
}

extension HotkeyIdentifier {
    static func spaceNumber(_ identifier: HotkeyIdentifier) -> Int? {
        guard identifier.rawValue.hasPrefix("space") else { return nil }
        return Int(identifier.rawValue.dropFirst(5))
    }
}
