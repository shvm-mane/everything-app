// SPDX-License-Identifier: GPL-3.0-or-later
// Imports settings from Vorssaint, Wisp and InstantSpaceSwitcher.

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

    private static func skipsVorssaintKey(_ key: String) -> Bool {
        let prefixes = ["NS", "featureAvailable.", "appUpdates", "update", "whatsNew", "lastUpdate",
                        "supportUpdate", "onboarding", "featuresOnboarding", "settingsWindow",
                        "commandBar", "startupDidNotFinish", "panelCollapsed"]
        return prefixes.contains { key.hasPrefix($0) }
    }

    @discardableResult
    static func run(defaults: UserDefaults = .standard) -> Report {
        var report = Report()

        if let domain = defaults.persistentDomain(forName: vorssaintDomain) {
            for (key, value) in domain where !skipsVorssaintKey(key) {
                defaults.set(value, forKey: key)
                report.vorssaintKeys += 1
            }
        }

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

    static func applyEverythingChoices(defaults: UserDefaults) {
        defaults.set(true, forKey: DefaultsKey.notchAgentsClaude)
        for key in [DefaultsKey.notchAgentsCodex, DefaultsKey.notchAgentsOpenCode, DefaultsKey.notchAgentsCopilot] {
            defaults.set(false, forKey: key)
        }
        defaults.set("", forKey: DefaultsKey.notchAgentsCodexProfiles)
        defaults.set(false, forKey: DefaultsKey.notchOpenOnHover)
        defaults.set(false, forKey: DefaultsKey.notchHoverExpands)
        defaults.set(true, forKey: DefaultsKey.notchHidesMenuBarIcon)
        defaults.set(true, forKey: DefaultsKey.hasOnboarded)
        defaults.set(true, forKey: DefaultsKey.notchScratchpad)
        defaults.set(true, forKey: DefaultsKey.notchLiquidGlassEnabled)
        defaults.set(true, forKey: DefaultsKey.liquidGlassEnabled)
        defaults.set(FontSize.fixed.rawValue, forKey: "wisp.FontSize")
        defaults.set(true, forKey: SpacesDefaults.swipeOverride)
        defaults.set(2000.0, forKey: SpacesDefaults.gestureSpeed)
        for identifier in HotkeyIdentifier.allCases where identifier != .left && identifier != .right {
            defaults.set(false, forKey: identifier.enabledKey)
        }
        defaults.set(NotchSize.spacious.rawValue, forKey: DefaultsKey.notchSize)
        defaults.set(true, forKey: DefaultsKey.notchHapticFeedback)
        defaults.set(true, forKey: DefaultsKey.notchKeepAwakeActivity)
        defaults.set(false, forKey: DefaultsKey.notchLockScreen)
        defaults.set(false, forKey: DefaultsKey.notchHideInFullscreen)
        defaults.set(false, forKey: DefaultsKey.notchTimerSoundEnabled)
        defaults.set(false, forKey: DefaultsKey.keepAwakeAutoStart)
        defaults.set(false, forKey: DefaultsKey.keepAwakeRightClickToggle)
        defaults.set(false, forKey: DefaultsKey.keepAwakeMouseJiggleEnabled)
        defaults.set(false, forKey: DefaultsKey.autoQuitEnabled)
        defaults.set(true, forKey: DefaultsKey.radialMenuAtPointer)
        defaults.set(true, forKey: DefaultsKey.notchBattery)
        defaults.set(false, forKey: DefaultsKey.notchTimerEnabled)
        defaults.set(false, forKey: DefaultsKey.notchKeepAwakeActivity)
        defaults.set(false, forKey: DefaultsKey.notchLiveEqualizer)
        defaults.set(false, forKey: DefaultsKey.colorPickerShortcutEnabled)
        defaults.set(false, forKey: DefaultsKey.screenshotShortcutEnabled)
        if let volumes = defaults.dictionary(forKey: DefaultsKey.appVolumes) as? [String: Double] {
            defaults.set(volumes.mapValues { min($0, 1) }, forKey: DefaultsKey.appVolumes)
        }
    }

    private static func copyFiles() -> [String] {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return [] }
        var copied: [String] = []

        let wisp = support.appendingPathComponent("Wisp")
        let pad = StorageLocation.defaultFolder
        try? fm.createDirectory(at: pad, withIntermediateDirectories: true)
        for name in ["scratchpad.md", "History"] {
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
