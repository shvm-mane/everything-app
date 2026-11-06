// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum QuitProtectionShortcut: String, CaseIterable, Identifiable {
    case quit
    case close

    var id: String { rawValue }
    var character: String { self == .quit ? "q" : "w" }
    var fallbackKeyCode: Int64 { self == .quit ? 12 : 13 }
    var symbol: String { self == .quit ? "⌘Q" : "⌘W" }
}

enum QuitProtectionMode: String, CaseIterable, Identifiable {
    case hold
    case doublePress
    case extraModifier

    var id: String { rawValue }
}

enum QuitProtectionExtraModifier: String, CaseIterable, Identifiable {
    case shift
    case option
    case control

    var id: String { rawValue }
}

enum QuitProtectionScope: String, CaseIterable, Identifiable {
    case all
    case selectedOnly
    case allExceptSelected

    var id: String { rawValue }
}

struct QuitProtectionConfiguration: Equatable {
    var enabled: Bool
    var mode: QuitProtectionMode
    var holdDurationMilliseconds: Double
    var doublePressIntervalMilliseconds: Double
    var extraModifier: QuitProtectionExtraModifier
    var scope: QuitProtectionScope
    var exceptions: [String]
    var showFeedback: Bool
}

enum QuitProtectionSupport {
    static let holdDurationRange = 250.0...2_000.0
    static let doublePressIntervalRange = 200.0...1_500.0
    static let defaultHoldDurationMilliseconds = 800.0
    static let defaultDoublePressIntervalMilliseconds = 600.0

    static func sanitizedHoldDuration(_ value: Double) -> Double {
        guard value.isFinite else { return defaultHoldDurationMilliseconds }
        return min(max(value, holdDurationRange.lowerBound), holdDurationRange.upperBound)
    }

    static func sanitizedDoublePressInterval(_ value: Double) -> Double {
        guard value.isFinite else { return defaultDoublePressIntervalMilliseconds }
        return min(max(value, doublePressIntervalRange.lowerBound), doublePressIntervalRange.upperBound)
    }

    static func isWithinDoublePressInterval(firstTimestamp: UInt64,
                                            secondTimestamp: UInt64,
                                            intervalMilliseconds: Double) -> Bool {
        guard secondTimestamp >= firstTimestamp else { return false }
        let allowedNanoseconds = UInt64(
            sanitizedDoublePressInterval(intervalMilliseconds) * 1_000_000
        )
        return secondTimestamp - firstTimestamp <= allowedNanoseconds
    }

    static func usesNativeQuitRequest(for shortcut: QuitProtectionShortcut,
                                      bundleIdentifier: String? = nil,
                                      confirmedWithExtraModifier: Bool = false) -> Bool {
        guard shortcut == .quit else { return false }
        guard let bundleIdentifier else { return true }
        if requiresSyntheticQuit(bundleIdentifier: bundleIdentifier) {
            return false
        }
        if keyForwardingBundleIdentifiers.contains(bundleIdentifier) {
            return confirmedWithExtraModifier
        }
        return true
    }

    static func requiresSyntheticQuit(bundleIdentifier: String) -> Bool {
        bundleIdentifier == "com.valvesoftware.steam"
    }

    static let keyForwardingBundleIdentifiers: Set<String> = [
        "com.apple.ScreenSharing",
        "com.apple.RemoteDesktop",
        "com.microsoft.rdc.macos",
        "com.p5sys.jump.mac.viewer",
        "com.p5sys.jump.mac.viewer.web",
        "com.edovia.screens.5",
        "com.realvnc.rvncconnect",
        "com.realvnc.vncviewer",
        "com.teamviewer.TeamViewer",
        "com.philandro.anydesk",
        "com.carriez.rustdesk",
        "com.splashtop.stb.macosx",
        "com.splashtop.stp.macosx",
        "com.2X.Client.Mac",
        "com.lemonmojo.RoyalTSX.App",
        "com.devolutions.remotedesktopmanager",
        "com.citrix.receiver.icaviewer.mac",
        "com.omnissa.horizon.client.mac",
        "com.vmware.horizon",
        "tv.parsec.www",
        "com.moonlight-stream.Moonlight",
        "com.parallels.desktop.console",
        "com.parallels.desktop.appstore",
        "com.vmware.fusion",
        "com.utmapp.UTM",
        "org.virtualbox.app.VirtualBoxVM",
        "codes.rambo.VirtualBuddy",
    ]

    static let nativeAppSwitcherIDs: Set<Int32> = [
        SwitcherNativeSymbolicHotKey.commandTab.rawValue,
        SwitcherNativeSymbolicHotKey.commandShiftTab.rawValue,
    ]

    static func opensNativeSwitcher(keyCode: Int64,
                                    flags: CGEventFlags,
                                    entries: [LiveSystemShortcut]?) -> Bool {
        let pressed = GlobalShortcut(keyCode: keyCode, modifiers: GlobalShortcutModifiers(cgFlags: flags))
        guard let entries else {
            return keyCode == 48
                && !pressed.modifiers.contains(.control) && !pressed.modifiers.contains(.option)
        }
        return entries.contains {
            nativeAppSwitcherIDs.contains($0.id) && $0.enabled && $0.shortcut == pressed
                && (!$0.requiresFunctionKey || flags.contains(.maskSecondaryFn))
        }
    }

    static func scopeAllows(_ scope: QuitProtectionScope,
                            bundleIdentifier: String?,
                            exceptions: [String]) -> Bool {
        let contains = bundleIdentifier.map { exceptions.contains($0) } ?? false
        switch scope {
        case .all: return true
        case .selectedOnly: return contains
        case .allExceptSelected: return !contains
        }
    }

    static func isBaseShortcut(keyCharacter: String?,
                               keyCode: Int64,
                               commandLabel: String?,
                               command: Bool,
                               control: Bool,
                               option: Bool,
                               shift: Bool,
                               shortcut: QuitProtectionShortcut) -> Bool {
        guard command, !control, !option, !shift else { return false }
        return matchesKey(keyCharacter: keyCharacter,
                          keyCode: keyCode,
                          commandLabel: commandLabel,
                          shortcut: shortcut)
    }

    static func isExtraShortcut(keyCharacter: String?,
                                keyCode: Int64,
                                commandLabel: String?,
                                command: Bool,
                                control: Bool,
                                option: Bool,
                                shift: Bool,
                                shortcut: QuitProtectionShortcut,
                                extraModifier: QuitProtectionExtraModifier) -> Bool {
        guard command else { return false }
        let hasExtra: Bool
        switch extraModifier {
        case .shift: hasExtra = shift && !option && !control
        case .option: hasExtra = option && !shift && !control
        case .control: hasExtra = control && !shift && !option
        }
        return hasExtra && matchesKey(keyCharacter: keyCharacter,
                                      keyCode: keyCode,
                                      commandLabel: commandLabel,
                                      shortcut: shortcut)
    }

    static func matchesKey(keyCharacter: String?,
                           keyCode: Int64,
                           commandLabel: String?,
                           shortcut: QuitProtectionShortcut) -> Bool {
        if let commandLabel {
            return commandLabel.lowercased() == shortcut.character
        }
        if let keyCharacter {
            return keyCharacter.lowercased() == shortcut.character
        }
        return keyCode == shortcut.fallbackKeyCode
    }

    static func modeFor(_ rawValue: String?) -> QuitProtectionMode {
        guard let rawValue, let value = QuitProtectionMode(rawValue: rawValue) else { return .hold }
        return value
    }

    static func extraModifierFor(_ rawValue: String?) -> QuitProtectionExtraModifier {
        guard let rawValue, let value = QuitProtectionExtraModifier(rawValue: rawValue) else { return .shift }
        return value
    }

    static func scopeFor(_ rawValue: String?) -> QuitProtectionScope {
        guard let rawValue, let value = QuitProtectionScope(rawValue: rawValue) else { return .all }
        return value
    }
}
