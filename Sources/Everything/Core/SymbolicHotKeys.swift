// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation

struct LiveSystemShortcut: Equatable {
    let id: Int32
    let shortcut: GlobalShortcut
    let enabled: Bool
    let requiresFunctionKey: Bool

    init(id: Int32, shortcut: GlobalShortcut, enabled: Bool,
         requiresFunctionKey: Bool = false) {
        self.id = id
        self.shortcut = shortcut
        self.enabled = enabled
        self.requiresFunctionKey = requiresFunctionKey
    }

    init(id: Int32, keyCode: Int64, flags: CGEventFlags, enabled: Bool) {
        self.init(id: id, shortcut: GlobalShortcut(keyCode: keyCode,
                                                   modifiers: GlobalShortcutModifiers(cgFlags: flags)),
                  enabled: enabled, requiresFunctionKey: flags.contains(.maskSecondaryFn))
    }
}

enum SymbolicHotKeys {
    typealias SetEnabledFunction = @convention(c) (Int32, Bool) -> CGError
    typealias IsEnabledFunction = @convention(c) (Int32) -> Bool
    typealias GetValueFunction =
        @convention(c) (Int32, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>) -> CGError

    static let setEnabled: SetEnabledFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSSetSymbolicHotKeyEnabled") else {
            return nil
        }
        return unsafeBitCast(symbol, to: SetEnabledFunction.self)
    }()
    static let isEnabled: IsEnabledFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSIsSymbolicHotKeyEnabled") else {
            return nil
        }
        return unsafeBitCast(symbol, to: IsEnabledFunction.self)
    }()
    static let getValue: GetValueFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSGetSymbolicHotKeyValue") else {
            return nil
        }
        return unsafeBitCast(symbol, to: GetValueFunction.self)
    }()

    static let scanRange: Range<Int32> = 0..<512

    static let unassignedKeyCode: UInt32 = 0xFFFF

    static func liveEntries() -> [LiveSystemShortcut]? {
        guard let getValue, let isEnabled else { return nil }
        return scanRange.compactMap { entry(id: $0, getValue: getValue, isEnabled: isEnabled) }
    }

    static func entries(for ids: Set<Int32>) -> [LiveSystemShortcut]? {
        guard let getValue, let isEnabled else { return nil }
        return ids.sorted().compactMap { entry(id: $0, getValue: getValue, isEnabled: isEnabled) }
    }

    private static func entry(id: Int32, getValue: GetValueFunction,
                              isEnabled: IsEnabledFunction) -> LiveSystemShortcut? {
        var character: UInt32 = 0
        var keyCode: UInt32 = 0
        var modifiers: UInt32 = 0
        guard getValue(id, &character, &keyCode, &modifiers) == .success,
              keyCode != unassignedKeyCode else { return nil }
        let flags = SpaceHopSupport.eventFlags(fromCarbonModifiers: modifiers)
        return LiveSystemShortcut(
            id: id, keyCode: Int64(keyCode), flags: flags, enabled: isEnabled(id))
    }
}
