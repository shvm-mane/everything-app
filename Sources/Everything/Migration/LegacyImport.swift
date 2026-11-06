// SPDX-License-Identifier: GPL-3.0-or-later
// Brings settings and data over from the three apps Everything replaces:
// Vorssaint (com.vorssaint.utils), Wisp (com.sulemaanhamza.wisp) and
// InstantSpaceSwitcher (com.interversehq.InstantSpaceSwitcher).
// Runs once on first launch, before any feature reads its preferences, and
// again on request from Settings › General. Never touches the old apps' data.

import Foundation

enum LegacyImport {
    static let doneKey = "everything.legacyImportDone"
    static let vorssaintDomain = "com.vorssaint.utils"
    static let wispDomain = "com.sulemaanhamza.wisp"
    static let issDomain = "com.interversehq.InstantSpaceSwitcher"

    struct Report {
        var vorssaintKeys = 0
        var wispKeys = 0
        var issKeys = 0
        var copiedFiles: [String] = []

        var summary: String {
            var parts: [String] = []
            parts.append("EVERYTHING: \(vorssaintKeys) settings")
            parts.append("Wisp: \(wispKeys) settings")
            parts.append("InstantSpaceSwitcher: \(issKeys) settings")
            if !copiedFiles.isEmpty { parts.append("files: " + copiedFiles.joined(separator: ", ")) }
            return parts.joined(separator: " · ")
        }
    }

    static func runIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        _ = run(defaults: defaults)
        defaults.set(true, forKey: doneKey)
    }

    /// Vorssaint keys that describe Vorssaint itself (its window, update and
    /// onboarding bookkeeping, its feature hub) rather than a preference.
    private static func skipsVorssaintKey(_ key: String) -> Bool {
        let prefixes = ["NS", "featureAvailable.", "appUpdates", "update", "whatsNew", "lastUpdate",
                        "supportUpdate", "onboarding", "featuresOnboarding", "settingsWindow",
                        "commandBar", "startupDidNotFinish", "panelCollapsed"]
        return prefixes.contains { key.hasPrefix($0) }
    }

    @discardableResult
    static func run(defaults: UserDefaults = .standard) -> Report {
        var report = Report()

        // Vorssaint: same key names, so values carry over as they are.
        if let domain = defaults.persistentDomain(forName: vorssaintDomain) {
            for (key, value) in domain where !skipsVorssaintKey(key) {
                defaults.set(value, forKey: key)
                report.vorssaintKeys += 1
            }
        }

        // Wisp: its keys live under "wisp." here.
        if let domain = defaults.persistentDomain(forName: wispDomain) {
            let mapped = ["FontFace", "FontSize", "Theme", "Transparency", "DismissOnOutsideClick",
                          "OpensOnPointerScreen", "SeenTipsVersion", "HasSeenFirstRunTour", "ScratchpadFolder"]
            for key in mapped {
                if let value = domain[key] {
                    defaults.set(value, forKey: "wisp." + key)
                    report.wispKeys += 1
                }
            }
        }

        // InstantSpaceSwitcher: its keys live under "iss." here.
        if let domain = defaults.persistentDomain(forName: issDomain) {
            for (key, value) in domain where key.hasPrefix("hotkey.") || key.hasPrefix("enabled.") {
                defaults.set(value, forKey: "iss." + key)
                report.issKeys += 1
            }
            let plain = ["gestureSpeed", "swipeOverride", "overlayDetectionEnabled"]
            for key in plain {
                if let value = domain[key] {
                    defaults.set(value, forKey: "iss." + key)
                    report.issKeys += 1
                }
            }
        }

        applyEverythingChoices(defaults: defaults)
        report.copiedFiles = copyFiles()
        return report
    }

    /// The choices that make Everything different from what was imported.
    static func applyEverythingChoices(defaults: UserDefaults) {
        // Claude Pro usage only: no other agents are read or shown.
        defaults.set(true, forKey: DefaultsKey.notchAgentsClaude)
        for key in [DefaultsKey.notchAgentsCodex, DefaultsKey.notchAgentsOpenCode, DefaultsKey.notchAgentsCopilot] {
            defaults.set(false, forKey: key)
        }
        defaults.set("", forKey: DefaultsKey.notchAgentsCodexProfiles)
        // The island opens on click, never on hover.
        defaults.set(false, forKey: DefaultsKey.notchOpenOnHover)
        defaults.set(false, forKey: DefaultsKey.notchHoverExpands)
        // EVERYTHING has no menu bar item; the space number shows in the island.
        defaults.set(true, forKey: DefaultsKey.notchHidesMenuBarIcon)
        // No first-run or update screens from Vorssaint.
        defaults.set(true, forKey: DefaultsKey.hasOnboarded)
        // The scratchpad lives in the island.
        defaults.set(true, forKey: DefaultsKey.notchScratchpad)
        // Liquid Glass is always on, in windows and in the island.
        defaults.set(true, forKey: DefaultsKey.notchLiquidGlassEnabled)
        defaults.set(true, forKey: DefaultsKey.liquidGlassEnabled)
        // The scratchpad is always 14 pt; instant swiping between spaces is always on.
        defaults.set(FontSize.fixed.rawValue, forKey: "wisp.FontSize")
        defaults.set(true, forKey: SpacesDefaults.swipeOverride)
        defaults.set(2000.0, forKey: SpacesDefaults.gestureSpeed)
        for identifier in HotkeyIdentifier.allCases where identifier != .left && identifier != .right {
            defaults.set(false, forKey: identifier.enabledKey)
        }
        // Island: always spacious, haptics and both indicators on; no lock
        // screen, no hiding in full screen, no timer sound.
        defaults.set(NotchSize.spacious.rawValue, forKey: DefaultsKey.notchSize)
        defaults.set(true, forKey: DefaultsKey.notchHapticFeedback)
        defaults.set(true, forKey: DefaultsKey.notchAgentsEnabled)
        defaults.set(true, forKey: DefaultsKey.notchKeepAwakeActivity)
        defaults.set(false, forKey: DefaultsKey.notchLockScreen)
        defaults.set(false, forKey: DefaultsKey.notchHideInFullscreen)
        defaults.set(false, forKey: DefaultsKey.notchTimerSoundEnabled)
        // Keep Awake is a plain switch: nothing starts it, nudges the pointer
        // or watches the menu bar.
        defaults.set(false, forKey: DefaultsKey.keepAwakeAutoStart)
        defaults.set(false, forKey: DefaultsKey.keepAwakeRightClickToggle)
        defaults.set(false, forKey: DefaultsKey.keepAwakeMouseJiggleEnabled)
        // Auto Quit is gone; the radial menu opens at the pointer.
        defaults.set(false, forKey: DefaultsKey.autoQuitEnabled)
        defaults.set(true, forKey: DefaultsKey.radialMenuAtPointer)
        // The battery shows in the island like volume and brightness.
        defaults.set(true, forKey: DefaultsKey.notchBattery)
        // No Keep Awake and no timer in EVERYTHING.
        defaults.set(false, forKey: DefaultsKey.notchTimerEnabled)
        defaults.set(false, forKey: DefaultsKey.notchKeepAwakeActivity)
        // No live equalizer.
        defaults.set(false, forKey: DefaultsKey.notchLiveEqualizer)
        // The color picker opens from the radial menu or Settings, never a keybind.
        defaults.set(false, forKey: DefaultsKey.colorPickerShortcutEnabled)
        defaults.set(false, forKey: DefaultsKey.screenshotShortcutEnabled)
        // App volumes stop at 100%.
        if let volumes = defaults.dictionary(forKey: DefaultsKey.appVolumes) as? [String: Double] {
            defaults.set(volumes.mapValues { min($0, 1) }, forKey: DefaultsKey.appVolumes)
        }
    }

    /// Wisp's note, history, inbox and reminders, and Vorssaint's private
    /// files, copied only where Everything has nothing of its own yet.
    private static func copyFiles() -> [String] {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return [] }
        var copied: [String] = []

        let wisp = support.appendingPathComponent("Wisp")
        let pad = StorageLocation.defaultFolder
        try? fm.createDirectory(at: pad, withIntermediateDirectories: true)
        for name in ["scratchpad.md", "History", "Inbox", "Reminders.json"] {
            let source = wisp.appendingPathComponent(name)
            let target = pad.appendingPathComponent(name)
            guard fm.fileExists(atPath: source.path), !fm.fileExists(atPath: target.path) else { continue }
            if (try? fm.copyItem(at: source, to: target)) != nil { copied.append("Wisp/\(name)") }
        }

        if let container = PrivateFileStore.containerURL {
            let vorssaint = support.appendingPathComponent(vorssaintDomain)
            if let items = try? fm.contentsOfDirectory(atPath: vorssaint.path) {
                _ = PrivateFileStore.createDirectory(at: container)
                for name in items where name != "Scratchpad.json" && !name.hasPrefix(".") {
                    let target = container.appendingPathComponent(name)
                    guard !fm.fileExists(atPath: target.path) else { continue }
                    if (try? fm.copyItem(at: vorssaint.appendingPathComponent(name), to: target)) != nil {
                        copied.append("EVERYTHING/\(name)")
                    }
                }
            }
        }
        return copied
    }
}
