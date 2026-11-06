// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

struct GlobalShortcutModifiers: OptionSet, Hashable {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let control = GlobalShortcutModifiers(rawValue: 1 << 0)
    static let option = GlobalShortcutModifiers(rawValue: 1 << 1)
    static let shift = GlobalShortcutModifiers(rawValue: 1 << 2)
    static let command = GlobalShortcutModifiers(rawValue: 1 << 3)

    static let validMask: GlobalShortcutModifiers = [.control, .option, .shift, .command]

    var hasPrimaryModifier: Bool {
        contains(.control) || contains(.option) || contains(.command)
    }

    var cgFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.command) { flags.insert(.maskCommand) }
        return flags
    }

    var carbonFlags: UInt32 {
        var flags = UInt32(0)
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }

    var keyCaps: [String] {
        var caps: [String] = []
        if contains(.control) { caps.append("⌃") }
        if contains(.option) { caps.append("⌥") }
        if contains(.shift) { caps.append("⇧") }
        if contains(.command) { caps.append("⌘") }
        return caps
    }

    var storageTokens: [String] {
        var tokens: [String] = []
        if contains(.control) { tokens.append("control") }
        if contains(.option) { tokens.append("option") }
        if contains(.shift) { tokens.append("shift") }
        if contains(.command) { tokens.append("command") }
        return tokens
    }

    init(cgFlags: CGEventFlags) {
        var modifiers: GlobalShortcutModifiers = []
        if cgFlags.contains(.maskControl) { modifiers.insert(.control) }
        if cgFlags.contains(.maskAlternate) { modifiers.insert(.option) }
        if cgFlags.contains(.maskShift) { modifiers.insert(.shift) }
        if cgFlags.contains(.maskCommand) { modifiers.insert(.command) }
        self = modifiers
    }

    init(eventFlags: NSEvent.ModifierFlags) {
        var modifiers: GlobalShortcutModifiers = []
        if eventFlags.contains(.control) { modifiers.insert(.control) }
        if eventFlags.contains(.option) { modifiers.insert(.option) }
        if eventFlags.contains(.shift) { modifiers.insert(.shift) }
        if eventFlags.contains(.command) { modifiers.insert(.command) }
        self = modifiers
    }
}

struct GlobalShortcut: Equatable, Hashable {
    let keyCode: Int64
    let modifiers: GlobalShortcutModifiers

    init(keyCode: Int64, modifiers: GlobalShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.validMask)
    }

    init?(storageValue: String) {
        self.init(storageValue: storageValue, requiringModifier: true)
    }

    init?(storageValue: String, requiringModifier: Bool) {
        guard let separator = storageValue.firstIndex(of: ":"),
              let keyCode = Int64(storageValue[storageValue.index(after: separator)...])
        else { return nil }
        var modifiers: GlobalShortcutModifiers = []
        for token in storageValue[..<separator].split(separator: "+") {
            switch token {
            case "control": modifiers.insert(.control)
            case "option": modifiers.insert(.option)
            case "shift": modifiers.insert(.shift)
            case "command": modifiers.insert(.command)
            default: return nil
            }
        }
        self.init(keyCode: keyCode, modifiers: modifiers)
        guard requiringModifier ? isValid : hasPrintableKey else { return nil }
    }

    static func clearsShortcut(keyCode: Int64, modifiers: GlobalShortcutModifiers) -> Bool {
        guard keyCode == Int64(kVK_Delete) || keyCode == Int64(kVK_ForwardDelete)
        else { return false }
        return !modifiers.hasPrimaryModifier
    }

    static let keepAwakeDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_K),
                                                 modifiers: [.control, .option, .command])
    static let shelfDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_D),
                                             modifiers: [.control, .option, .command])
    static let switcherDefault = GlobalShortcut(keyCode: Int64(kVK_Tab),
                                                modifiers: [.command])
    static let switcherWindowDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_Grave),
                                                      modifiers: [.command])
    static let switcherAllWindowsDefault = GlobalShortcut(keyCode: Int64(kVK_Tab),
                                                          modifiers: [.option])
    static let clipboardDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_V),
                                                 modifiers: [.control, .option, .command])
    static let soundOutputSwitcherDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_S),
                                                           modifiers: [.control, .option, .command])
    static let displayBrightnessDecreaseDefault = GlobalShortcut(
        keyCode: Int64(kVK_ANSI_Minus), modifiers: [.shift, .command])
    static let displayBrightnessIncreaseDefault = GlobalShortcut(
        keyCode: Int64(kVK_ANSI_Equal), modifiers: [.shift, .command])
    static let keyboardBrightnessDecreaseDefault = GlobalShortcut(
        keyCode: Int64(kVK_ANSI_Minus), modifiers: [.option, .command])
    static let keyboardBrightnessIncreaseDefault = GlobalShortcut(
        keyCode: Int64(kVK_ANSI_Equal), modifiers: [.option, .command])
    static let windowLayoutLeftDefault = GlobalShortcut(keyCode: Int64(kVK_LeftArrow),
                                                        modifiers: [.control, .option])
    static let windowLayoutRightDefault = GlobalShortcut(keyCode: Int64(kVK_RightArrow),
                                                         modifiers: [.control, .option])
    static let windowLayoutTopDefault = GlobalShortcut(keyCode: Int64(kVK_UpArrow),
                                                       modifiers: [.control, .option])
    static let windowLayoutBottomDefault = GlobalShortcut(keyCode: Int64(kVK_DownArrow),
                                                          modifiers: [.control, .option])
    static let windowLayoutTopLeftDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_U),
                                                           modifiers: [.control, .option])
    static let windowLayoutTopRightDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_I),
                                                            modifiers: [.control, .option])
    static let windowLayoutBottomLeftDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_J),
                                                              modifiers: [.control, .option])
    static let windowLayoutBottomRightDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_K),
                                                               modifiers: [.control, .option])
    static let windowLayoutMaximizeDefault = GlobalShortcut(keyCode: Int64(kVK_Return),
                                                            modifiers: [.control, .option])
    static let windowLayoutCenterDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_C),
                                                          modifiers: [.control, .option])
    static let windowLayoutRestoreDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_R),
                                                           modifiers: [.control, .option])
    static let windowLayoutLeftThirdDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_D),
                                                             modifiers: [.control, .option])
    static let windowLayoutCenterThirdDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_F),
                                                               modifiers: [.control, .option])
    static let windowLayoutRightThirdDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_G),
                                                              modifiers: [.control, .option])
    static let windowLayoutLeftTwoThirdsDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_E),
                                                                 modifiers: [.control, .option])
    static let windowLayoutRightTwoThirdsDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_T),
                                                                  modifiers: [.control, .option])
    static let windowLayoutNextDisplayDefault = GlobalShortcut(keyCode: Int64(kVK_RightArrow),
                                                               modifiers: [.control, .option, .command])
    static let windowDirectionalDefault = GlobalShortcut(keyCode: Int64(kVK_Space),
                                                         modifiers: [.control, .option])
    static let pointerNextDisplayDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_Z),
                                                          modifiers: [.control, .option, .command])
    static let pastePlainDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_V),
                                                  modifiers: [.shift, .option, .command])
    static let finderRenameDefault = GlobalShortcut(keyCode: Int64(kVK_F2), modifiers: [])
    static let colorPickerDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_C),
                                                   modifiers: [.control, .option, .command])
    static let screenOCRDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_T),
                                                 modifiers: [.control, .option, .command])
    static let micMuteDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_M),
                                               modifiers: [.control, .option, .command])
    static let quitAllDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_Q),
                                                           modifiers: [.control, .option, .command])
    static let quitAllExceptFrontDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_O),
                                                              modifiers: [.control, .option, .command])
    static let cameraPreviewDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_W),
                                                     modifiers: [.control, .option, .command])
    static let quickLauncherDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_V),
                                                     modifiers: [.control, .command])
    static let screenshotDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_4),
                                                  modifiers: [.control, .option, .command])
    static let screenshotFullScreenDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_3),
                                                            modifiers: [.control, .option, .command])
    static let screenshotUploadDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_U),
                                                        modifiers: [.control, .option, .command])
    static let screenshotLastCaptureDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_E),
                                                             modifiers: [.control, .option, .command])
    static let recentCapturesDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_H),
                                                      modifiers: [.control, .option, .command])
    static let screenshotClipboardDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_P),
                                                           modifiers: [.control, .option, .command])
    static let radialMenuDefault = GlobalShortcut(keyCode: Int64(kVK_Space),
                                                  modifiers: [.control, .option, .command])
    static let scratchpadDefault = GlobalShortcut(keyCode: Int64(kVK_Space),
                                                  modifiers: [.option])
    static let notchDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_I),
                                             modifiers: [.control, .option, .command])
    static let snippetLibraryDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_L),
                                                      modifiers: [.control, .option, .command])
    static let commandBarDefault = GlobalShortcut(keyCode: Int64(kVK_Space),
                                                  modifiers: [.option])
    static let screenRecorderDefault = GlobalShortcut(keyCode: Int64(kVK_ANSI_5),
                                                      modifiers: [.control, .option, .command])

    static func saved(for key: String, fallback: GlobalShortcut) -> GlobalShortcut {
        if let raw = UserDefaults.standard.string(forKey: key),
           let shortcut = GlobalShortcut(storageValue: raw) {
            return shortcut
        }
        return fallback
    }

    var storageValue: String {
        "\(modifiers.storageTokens.joined(separator: "+")):\(keyCode)"
    }

    static let keyCodeRange: ClosedRange<Int64> = 0...0xFFFF

    var hasUsableKeyCode: Bool { Self.keyCodeRange.contains(keyCode) }

    var hasPrintableKey: Bool { hasUsableKeyCode && keyLabel != nil }

    var isValid: Bool {
        hasPrintableKey
            && (modifiers.hasPrimaryModifier || Self.standaloneFunctionKeys.contains(keyCode))
    }

    var displayString: String {
        let label = keyLabel ?? "Key \(keyCode)"
        let needsSeparator = label.count == 1
            && label.rangeOfCharacter(from: .alphanumerics) == nil
        return modifiers.keyCaps.joined() + (needsSeparator ? " " : "") + label
    }

    var keyCaps: [String] {
        modifiers.keyCaps + [keyLabel ?? "Key \(keyCode)"]
    }

    func superKeyAlternative(sourceLabel: String,
                             superKeyModifiers: GlobalShortcutModifiers) -> String? {
        guard superKeyModifiers.hasPrimaryModifier,
              modifiers == superKeyModifiers,
              let key = keyCaps.last else { return nil }
        return "\(sourceLabel) + \(key)"
    }

    var carbonKeyCode: UInt32 {
        UInt32(exactly: keyCode) ?? 0
    }

    var carbonModifiers: UInt32 {
        modifiers.carbonFlags
    }

    var syntheticEventFlags: CGEventFlags {
        var flags = modifiers.cgFlags
        if Self.functionKeys.contains(keyCode) { flags.insert(.maskSecondaryFn) }
        if Self.numericPadKeys.contains(keyCode) { flags.insert(.maskNumericPad) }
        return flags
    }

    private static let functionKeys: Set<Int64> = Set(([
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        kVK_Help, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete,
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
    ] as [Int]).map(Int64.init))

    private static let standaloneFunctionKeys: Set<Int64> = Set(([
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ] as [Int]).map(Int64.init))

    private static let numericPadKeys: Set<Int64> = Set(([
        kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4,
        kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9,
        kVK_ANSI_KeypadClear, kVK_ANSI_KeypadDecimal, kVK_ANSI_KeypadDivide, kVK_ANSI_KeypadEnter,
        kVK_ANSI_KeypadEquals, kVK_ANSI_KeypadMinus, kVK_ANSI_KeypadMultiply, kVK_ANSI_KeypadPlus,
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
    ] as [Int]).map(Int64.init))

    var isStandardPasteCommand: Bool {
        keyCode == Int64(kVK_ANSI_V) && modifiers == [.command]
    }

    func matches(event: CGEvent,
                 allowingExtraShift: Bool = false,
                 tolerating extra: GlobalShortcutModifiers = []) -> Bool {
        guard event.getIntegerValueField(.keyboardEventKeycode) == keyCode else { return false }
        return modifiersMatch(event: event, allowingExtraShift: allowingExtraShift, tolerating: extra)
    }

    func matches(keyCode: Int64, modifiers actual: GlobalShortcutModifiers) -> Bool {
        keyCode == self.keyCode && actual == modifiers
    }

    func matchesByCharacter(event: CGEvent,
                            tolerating extra: GlobalShortcutModifiers = []) -> Bool {
        let actual = GlobalShortcutModifiers(cgFlags: event.flags)
        guard actual.intersection(modifiers) == modifiers,
              actual.subtracting(modifiers).subtracting([.shift, .option])
                  .subtracting(extra).isEmpty
        else { return false }
        guard let label = keyLabel, label.count == 1 else { return false }
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: chars.count,
                                       actualStringLength: &length,
                                       unicodeString: &chars)
        guard length > 0 else { return false }
        let typed = String(utf16CodeUnits: chars, count: length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !typed.isEmpty && typed.uppercased() == label.uppercased()
    }

    private func modifiersMatch(event: CGEvent,
                                allowingExtraShift: Bool,
                                tolerating extra: GlobalShortcutModifiers = []) -> Bool {
        var actual = GlobalShortcutModifiers(cgFlags: event.flags)
        guard actual.intersection(modifiers) == modifiers else { return false }
        actual.subtract(extra.subtracting(modifiers))
        if allowingExtraShift, !modifiers.contains(.shift) {
            return actual.subtracting(.shift) == modifiers
        }
        return actual == modifiers
    }

    func requiredModifiersHeld(in flags: CGEventFlags) -> Bool {
        let actual = GlobalShortcutModifiers(cgFlags: flags)
        return actual.intersection(modifiers) == modifiers
    }

    func requiredModifiersHeld(in flags: NSEvent.ModifierFlags) -> Bool {
        let actual = GlobalShortcutModifiers(eventFlags: flags)
        return actual.intersection(modifiers) == modifiers
    }

    var shiftIsNavigationModifier: Bool {
        !modifiers.contains(.shift)
    }

    private var keyLabel: String? {
        switch Int(keyCode) {
        case kVK_Tab: return "Tab"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Escape: return "Esc"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_ANSI_KeypadEnter: return "⌤"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        default:
            if let label = Self.layoutKeyLabel(for: keyCode,
                                               usesCommand: modifiers.contains(.command)) {
                return label
            }
            return Self.fallbackAnsiKeyLabel(for: keyCode)
        }
    }

    private static func fallbackAnsiKeyLabel(for keyCode: Int64) -> String? {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"
        case kVK_ISO_Section: return "§"
        default: return nil
        }
    }

    static func layoutKeyLabel(for keyCode: Int64, usesCommand: Bool,
                               usesShift: Bool = false, capsLockOn: Bool = false) -> String? {
        let cacheKey = LayoutLabelKey(keyCode: keyCode, usesCommand: usesCommand,
                                      usesShift: usesShift, capsLockOn: capsLockOn)
        if let cached = (layoutLabelLock.withLock { layoutLabels[cacheKey] }) {
            return cached
        }
        if Thread.isMainThread {
            let label = derivedLayoutKeyLabel(for: keyCode, usesCommand: usesCommand,
                                              usesShift: usesShift, capsLockOn: capsLockOn)
            layoutLabelLock.withLock { layoutLabels[cacheKey] = label }
            return label
        }
        return nil
    }

    private struct LayoutLabelKey: Hashable {
        let keyCode: Int64
        let usesCommand: Bool
        let usesShift: Bool
        let capsLockOn: Bool
    }

    private static let layoutLabelLock = NSLock()
    private static var layoutLabels: [LayoutLabelKey: String] = [:]
    private static var keyboardLayoutObserver: AnyObject?
    static let keyboardLayoutDidChange = Notification.Name("VorssaintShortcutKeyboardLayoutDidChange")

    static func startObservingKeyboardLayout() {
        refreshLayoutLabels()
        guard keyboardLayoutObserver == nil else { return }
        keyboardLayoutObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in refreshLayoutLabels() }
    }

    static func refreshLayoutLabels(layoutData: Data? = currentLayoutData()) {
        defer { NotificationCenter.default.post(name: keyboardLayoutDidChange, object: nil) }
        guard let layoutData else {
            layoutLabelLock.withLock { layoutLabels.removeAll() }
            return
        }
        var labels: [LayoutLabelKey: String] = [:]
        for keyCode in UInt16(0)...127 {
            for usesCommand in [false, true] {
                for usesShift in [false, true] {
                    for capsLockOn in [false, true] {
                        if let label = derivedLayoutKeyLabel(for: keyCode,
                                                             layoutData: layoutData,
                                                             usesCommand: usesCommand,
                                                             usesShift: usesShift,
                                                             capsLockOn: capsLockOn) {
                            labels[LayoutLabelKey(keyCode: Int64(keyCode),
                                                  usesCommand: usesCommand,
                                                  usesShift: usesShift,
                                                  capsLockOn: capsLockOn)] = label
                        }
                    }
                }
            }
        }
        layoutLabelLock.withLock { layoutLabels = labels }
    }

    private static func derivedLayoutKeyLabel(for keyCode: Int64,
                                              usesCommand: Bool,
                                              usesShift: Bool, capsLockOn: Bool) -> String? {
        guard let code = UInt16(exactly: keyCode),
              let layoutData = currentLayoutData()
        else { return nil }
        return derivedLayoutKeyLabel(for: code, layoutData: layoutData,
                                     usesCommand: usesCommand, usesShift: usesShift,
                                     capsLockOn: capsLockOn)
    }

    private static func currentLayoutData() -> Data? {
        guard Thread.isMainThread else { return nil }
        let source = inputMethodIsActive
            ? TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
            : TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        guard let source,
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        return Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
    }

    private static var inputMethodIsActive: Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let type = TISGetInputSourceProperty(source, kTISPropertyInputSourceType)
        else { return false }
        let value = Unmanaged<CFString>.fromOpaque(type).takeUnretainedValue() as String
        return value != (kTISTypeKeyboardLayout as String)
    }

    private static func derivedLayoutKeyLabel(for code: UInt16,
                                              layoutData: Data,
                                              usesCommand: Bool,
                                              usesShift: Bool, capsLockOn: Bool) -> String? {
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let modifierState = (usesCommand ? UInt32((cmdKey >> 8) & 0xFF) : 0)
            | (usesShift ? UInt32((shiftKey >> 8) & 0xFF) : 0)
            | (capsLockOn ? UInt32((alphaLock >> 8) & 0xFF) : 0)
        let status = layoutData.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> OSStatus in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress
            else { return OSStatus(paramErr) }
            return UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), modifierState,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let label = String(utf16CodeUnits: chars, count: length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard label.count == 1,
              let scalar = label.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar)
        else { return nil }
        return label.uppercased()
    }
}

enum ShortcutRecordingCaption {
    static func text(_ strings: Strings, canClear: Bool) -> String {
        let parts = canClear
            ? [strings.shortcutRecording, strings.shortcutEscapeHint, strings.shortcutDeleteHint]
            : [strings.shortcutRecording, strings.shortcutEscapeHint]
        return parts.joined(separator: " ")
    }
}

enum GlobalShortcutRole: CaseIterable, Identifiable {
    case keepAwake
    case shelf
    case switcher
    case switcherWindow
    case switcherAllWindows
    case clipboard
    case soundOutputSwitcher
    case pastePlain
    case finderRename
    case colorPicker
    case screenOCR
    case micMute
    case quitAll
    case quitAllExceptFront
    case quickLauncher
    case screenshot
    case screenshotFullScreen
    case screenshotLastCapture
    case screenshotUpload
    case recentCaptures
    case screenshotClipboard
    case cameraPreview
    case radialMenu
    case scratchpad
    case snippetLibrary
    case commandBar
    case screenRecorder
    case displayBrightnessDecrease
    case displayBrightnessIncrease
    case keyboardBrightnessDecrease
    case keyboardBrightnessIncrease
    case pointerNextDisplay
    case notch

    var id: String { storageKey }

    var storageKey: String {
        switch self {
        case .keepAwake: return DefaultsKey.keepAwakeShortcut
        case .shelf: return DefaultsKey.shelfShortcut
        case .switcher: return DefaultsKey.switcherShortcut
        case .switcherWindow: return DefaultsKey.switcherWindowShortcut
        case .switcherAllWindows: return DefaultsKey.switcherAllWindowsShortcut
        case .clipboard: return DefaultsKey.clipboardHistoryShortcut
        case .soundOutputSwitcher: return DefaultsKey.soundOutputSwitcherShortcut
        case .pastePlain: return DefaultsKey.pastePlainShortcut
        case .finderRename: return DefaultsKey.finderRenameShortcut
        case .colorPicker: return DefaultsKey.colorPickerShortcut
        case .screenOCR: return DefaultsKey.screenOCRShortcut
        case .micMute: return DefaultsKey.micMuteShortcut
        case .quitAll: return DefaultsKey.quitAppsShortcut
        case .quitAllExceptFront: return DefaultsKey.quitAppsExceptFrontShortcut
        case .quickLauncher: return DefaultsKey.quickLauncherShortcut
        case .screenshot: return DefaultsKey.screenshotShortcut
        case .screenshotFullScreen: return DefaultsKey.screenshotFullScreenShortcut
        case .screenshotLastCapture: return DefaultsKey.screenshotLastCaptureShortcut
        case .screenshotUpload: return DefaultsKey.screenshotUploadShortcut
        case .recentCaptures: return DefaultsKey.recentCapturesShortcut
        case .screenshotClipboard: return DefaultsKey.screenshotClipboardShortcut
        case .cameraPreview: return DefaultsKey.cameraPreviewShortcut
        case .radialMenu: return DefaultsKey.radialMenuShortcut
        case .scratchpad: return DefaultsKey.scratchpadShortcut
        case .snippetLibrary: return DefaultsKey.snippetLibraryShortcut
        case .commandBar: return DefaultsKey.commandBarShortcut
        case .screenRecorder: return DefaultsKey.recorderShortcut
        case .displayBrightnessDecrease: return DefaultsKey.displayBrightnessDecreaseShortcut
        case .displayBrightnessIncrease: return DefaultsKey.displayBrightnessIncreaseShortcut
        case .keyboardBrightnessDecrease: return DefaultsKey.keyboardBrightnessDecreaseShortcut
        case .keyboardBrightnessIncrease: return DefaultsKey.keyboardBrightnessIncreaseShortcut
        case .pointerNextDisplay: return DefaultsKey.pointerDisplayShortcut
        case .notch: return DefaultsKey.notchShortcut
        }
    }

    var defaultShortcut: GlobalShortcut {
        switch self {
        case .keepAwake: return .keepAwakeDefault
        case .shelf: return .shelfDefault
        case .switcher: return .switcherDefault
        case .switcherWindow: return .switcherWindowDefault
        case .switcherAllWindows: return .switcherAllWindowsDefault
        case .clipboard: return .clipboardDefault
        case .soundOutputSwitcher: return .soundOutputSwitcherDefault
        case .pastePlain: return .pastePlainDefault
        case .finderRename: return .finderRenameDefault
        case .colorPicker: return .colorPickerDefault
        case .screenOCR: return .screenOCRDefault
        case .micMute: return .micMuteDefault
        case .quitAll: return .quitAllDefault
        case .quitAllExceptFront: return .quitAllExceptFrontDefault
        case .quickLauncher: return .quickLauncherDefault
        case .screenshot: return .screenshotDefault
        case .screenshotFullScreen: return .screenshotFullScreenDefault
        case .screenshotLastCapture: return .screenshotLastCaptureDefault
        case .screenshotUpload: return .screenshotUploadDefault
        case .recentCaptures: return .recentCapturesDefault
        case .screenshotClipboard: return .screenshotClipboardDefault
        case .cameraPreview: return .cameraPreviewDefault
        case .radialMenu: return .radialMenuDefault
        case .scratchpad: return .scratchpadDefault
        case .snippetLibrary: return .snippetLibraryDefault
        case .commandBar: return .commandBarDefault
        case .screenRecorder: return .screenRecorderDefault
        case .displayBrightnessDecrease: return .displayBrightnessDecreaseDefault
        case .displayBrightnessIncrease: return .displayBrightnessIncreaseDefault
        case .keyboardBrightnessDecrease: return .keyboardBrightnessDecreaseDefault
        case .keyboardBrightnessIncrease: return .keyboardBrightnessIncreaseDefault
        case .pointerNextDisplay: return .pointerNextDisplayDefault
        case .notch: return .notchDefault
        }
    }

    var savedShortcut: GlobalShortcut {
        GlobalShortcut.saved(for: storageKey, fallback: defaultShortcut)
    }

    var permittedSystemShortcutIDs: Set<Int32> {
        switch self {
        case .switcher:
            return [SwitcherNativeSymbolicHotKey.commandTab.rawValue,
                    SwitcherNativeSymbolicHotKey.commandShiftTab.rawValue]
        case .switcherWindow:
            return [SwitcherNativeSymbolicHotKey.nextWindow.rawValue,
                    SwitcherNativeSymbolicHotKey.previousWindow.rawValue]
        case .switcherAllWindows:
            return SwitcherNativeSymbolicHotKey.ids
        default:
            return []
        }
    }

    func title(_ strings: Strings) -> String {
        switch self {
        case .keepAwake: return strings.keepAwakeTitle
        case .shelf: return strings.shelfName
        case .switcher: return strings.switcherShortcutHintApps
        case .switcherWindow: return strings.switcherShortcutHintWindows
        case .switcherAllWindows: return FeatureStrings.switcherShortcuts(L10n.shared.language).allWindows
        case .clipboard: return FeatureStrings.clipboard(L10n.shared.language).title
        case .soundOutputSwitcher: return strings.soundOutputSwitcherTitle
        case .pastePlain: return strings.pastePlainName
        case .finderRename: return FeatureStrings.finderRename(L10n.shared.language).hubTitle
        case .colorPicker: return strings.colorPickerName
        case .screenOCR: return strings.ocrName
        case .micMute: return strings.micMuteName
        case .quitAll: return FeatureStrings.quickToggles(L10n.shared.language).quitAllTitle
        case .quitAllExceptFront:
            return FeatureStrings.quickToggles(L10n.shared.language).quitOthersTitle
        case .quickLauncher: return strings.launcherName
        case .screenshot:
            return FeatureStrings.screenshot(L10n.shared.language).pageTitle
        case .screenshotFullScreen:
            return FeatureStrings.screenshot(L10n.shared.language).fullScreenShortcutTitle
        case .screenshotUpload:
            return FeatureStrings.screenshot(L10n.shared.language).uploadLastCapture
        case .screenshotLastCapture:
            return FeatureStrings.screenshot(L10n.shared.language).editLastCapture
        case .recentCaptures:
            return FeatureStrings.recentCaptures(L10n.shared.language).title
        case .screenshotClipboard:
            return FeatureStrings.screenshot(L10n.shared.language).editClipboardImage
        case .cameraPreview: return FeatureStrings.cameraPreview(L10n.shared.language).pageTitle
        case .radialMenu: return FeatureStrings.radialMenu(L10n.shared.language).pageTitle
        case .scratchpad: return FeatureStrings.scratchpad(L10n.shared.language).pageTitle
        case .snippetLibrary: return FeatureStrings.snippets(L10n.shared.language).libraryTitle
        case .commandBar: return FeatureStrings.commandBar(L10n.shared.language).pageTitle
        case .screenRecorder: return FeatureStrings.recorder(L10n.shared.language).pageTitle
        case .displayBrightnessDecrease:
            return FeatureStrings.brightness(L10n.shared.language).displayBrightnessDecrease
        case .displayBrightnessIncrease:
            return FeatureStrings.brightness(L10n.shared.language).displayBrightnessIncrease
        case .keyboardBrightnessDecrease:
            return FeatureStrings.brightness(L10n.shared.language).keyboardBrightnessDecrease
        case .keyboardBrightnessIncrease:
            return FeatureStrings.brightness(L10n.shared.language).keyboardBrightnessIncrease
        case .pointerNextDisplay: return PointerDisplayStrings.localized(L10n.shared.language).title
        case .notch: return FeatureStrings.notch(L10n.shared.language).title
        }
    }

    static func conflict(for shortcut: GlobalShortcut,
                         excluding role: GlobalShortcutRole?,
                         isOn: (String) -> Bool = { UserDefaults.standard.bool(forKey: $0) },
                         isAvailable: (AppFeature) -> Bool = { $0.isAvailable },
                         includeInactive: Bool = false,
                         radialMenuShortcuts: () -> [GlobalShortcut] = { RadialMenuSupport.profileShortcuts() })
        -> GlobalShortcutRole? {
        let candidates = includeInactive
            ? availableRoles(isAvailable: isAvailable)
            : activeRoles(isOn: isOn, isAvailable: isAvailable)
        return candidates.first { candidate in
            guard candidate != role else { return false }
            if candidate == .radialMenu { return radialMenuShortcuts().contains(shortcut) }
            return candidate.savedShortcut == shortcut
        }
    }

    var requiredEnableKeys: [String] {
        switch self {
        case .keepAwake: return [DefaultsKey.hotkeyEnabled]
        case .shelf: return [DefaultsKey.shelfEnabled, DefaultsKey.shelfShortcutEnabled]
        case .switcher, .switcherWindow: return [DefaultsKey.switcherEnabled]
        case .switcherAllWindows:
            return [DefaultsKey.switcherEnabled, DefaultsKey.switcherAllWindowsShortcutEnabled]
        case .clipboard: return [DefaultsKey.clipboardHistoryEnabled,
                                 DefaultsKey.clipboardHistoryShortcutEnabled]
        case .soundOutputSwitcher: return [DefaultsKey.soundOutputSwitcherEnabled]
        case .pastePlain: return [DefaultsKey.pastePlainEnabled]
        case .finderRename: return [DefaultsKey.finderRenameEnabled]
        case .colorPicker: return [DefaultsKey.colorPickerShortcutEnabled]
        case .screenOCR: return [DefaultsKey.screenOCRShortcutEnabled]
        case .micMute: return [DefaultsKey.micMuteShortcutEnabled]
        case .quitAll: return [DefaultsKey.quitAppsShortcutEnabled]
        case .quitAllExceptFront: return [DefaultsKey.quitAppsExceptFrontShortcutEnabled]
        case .quickLauncher: return [DefaultsKey.quickLauncherShortcutEnabled]
        case .screenshot: return [DefaultsKey.screenshotShortcutEnabled]
        case .screenshotFullScreen: return [DefaultsKey.screenshotFullScreenShortcutEnabled]
        case .screenshotLastCapture: return [DefaultsKey.screenshotLastCaptureShortcutEnabled]
        case .screenshotUpload: return [DefaultsKey.screenshotUploadShortcutEnabled, DefaultsKey.screenshotSharingEnabled]
        case .recentCaptures: return [DefaultsKey.recentCapturesShortcutEnabled]
        case .screenshotClipboard: return [DefaultsKey.screenshotClipboardShortcutEnabled]
        case .cameraPreview: return [DefaultsKey.cameraPreviewShortcutEnabled]
        case .radialMenu: return [DefaultsKey.radialMenuEnabled]
        case .scratchpad: return [DefaultsKey.scratchpadShortcutEnabled]
        case .snippetLibrary: return [DefaultsKey.snippetLibraryEnabled]
        case .commandBar: return [DefaultsKey.commandBarShortcutEnabled]
        case .screenRecorder: return [DefaultsKey.recorderShortcutEnabled]
        case .displayBrightnessDecrease, .displayBrightnessIncrease:
            return [DefaultsKey.brightnessControlEnabled, DefaultsKey.displayBrightnessShortcutsEnabled]
        case .keyboardBrightnessDecrease, .keyboardBrightnessIncrease:
            return [DefaultsKey.keyboardBrightnessShortcutsEnabled]
        case .pointerNextDisplay: return [DefaultsKey.pointerDisplayEnabled]
        case .notch: return [DefaultsKey.notchEnabled, DefaultsKey.notchShortcutEnabled]
        }
    }

    var feature: AppFeature {
        switch self {
        case .keepAwake: return .keepAwake
        case .shelf: return .shelf
        case .switcher, .switcherWindow, .switcherAllWindows: return .switcher
        case .clipboard: return .clipboardHistory
        case .soundOutputSwitcher: return .soundOutputSwitcher
        case .pastePlain: return .pastePlain
        case .finderRename: return .finderRename
        case .colorPicker: return .colorPicker
        case .screenOCR: return .screenOCR
        case .micMute: return .micMute
        case .quitAll, .quitAllExceptFront: return .quitApps
        case .quickLauncher: return .quickLauncher
        case .screenshot, .screenshotFullScreen, .screenshotLastCapture, .recentCaptures,
             .screenshotClipboard, .screenshotUpload:
            return .screenshot
        case .cameraPreview: return .cameraPreview
        case .radialMenu: return .radialMenu
        case .scratchpad: return .scratchpad
        case .snippetLibrary: return .textSnippets
        case .commandBar: return .commandBar
        case .screenRecorder: return .screenRecorder
        case .displayBrightnessDecrease, .displayBrightnessIncrease: return .brightness
        case .keyboardBrightnessDecrease, .keyboardBrightnessIncrease: return .brightness
        case .pointerNextDisplay: return .windowLayout
        case .notch: return .notch
        }
    }

    var group: FeatureGroup {
        switch self {
        case .keyboardBrightnessDecrease, .keyboardBrightnessIncrease: return .mouseKeyboard
        default: return feature.group
        }
    }

    var supportsTakeOver: Bool {
        switch self {
        case .switcher, .switcherWindow, .switcherAllWindows, .radialMenu: return false
        default: return true
        }
    }

    var isKeyboardBrightness: Bool {
        self == .keyboardBrightnessDecrease || self == .keyboardBrightnessIncrease
    }

    var availabilityFeatures: [AppFeature] {
        switch self {
        case .recentCaptures: return [.screenshot, .screenRecorder]
        default: return [feature]
        }
    }

    func isAvailable(using isAvailable: (AppFeature) -> Bool) -> Bool {
        availabilityFeatures.contains(where: isAvailable)
    }

    static var featuresToSilenceWhileRecording: [AppFeature] {
        var seen: Set<AppFeature> = []
        var features = allCases.compactMap { seen.insert($0.feature).inserted ? $0.feature : nil }
        if seen.insert(.windowLayout).inserted { features.append(.windowLayout) }
        return features
    }

    static func activeRoles(isOn: (String) -> Bool,
                            isAvailable: (AppFeature) -> Bool = { _ in true }) -> [GlobalShortcutRole] {
        allCases.filter { role in
            role.isAvailable(using: isAvailable) && role.requiredEnableKeys.allSatisfy(isOn)
        }
    }

    static func availableRoles(isAvailable: (AppFeature) -> Bool = { $0.isAvailable })
        -> [GlobalShortcutRole] {
        allCases.filter { $0.isAvailable(using: isAvailable) }
    }

    static let captureFeatures: [AppFeature] =
        [.screenshot, .screenRecorder, .screenOCR, .colorPicker]

    static let captureDisplayOrder: [GlobalShortcutRole] = [
        .screenshot, .screenRecorder, .screenOCR, .colorPicker,
        .recentCaptures, .screenshotFullScreen, .screenshotLastCapture, .screenshotClipboard, .screenshotUpload,
    ]

    static func captureRoles(in roles: [GlobalShortcutRole]) -> [GlobalShortcutRole] {
        roles.filter { captureFeatures.contains($0.feature) }
            .enumerated()
            .sorted { lhs, rhs in
                (captureDisplayOrder.firstIndex(of: lhs.element) ?? .max, lhs.offset)
                    < (captureDisplayOrder.firstIndex(of: rhs.element) ?? .max, rhs.offset)
            }
            .map(\.element)
    }
}

extension GlobalShortcut {
    static var systemSymbolicHotKeys: [String: Any]? {
        UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys")
    }

    var conflictsWithSystemShortcut: Bool {
        conflictsWithSystemShortcut(for: nil)
    }

    func conflictsWithSystemShortcut(for role: GlobalShortcutRole?) -> Bool {
        Self.conflictsWithSystemShortcut(self,
                                         liveEntries: SymbolicHotKeys.liveEntries(),
                                         symbolicHotKeys: Self.systemSymbolicHotKeys,
                                         role: role)
    }

    static func conflictsWithSystemShortcut(_ shortcut: GlobalShortcut,
                                            liveEntries: [LiveSystemShortcut]?,
                                            symbolicHotKeys: @autoclosure () -> [String: Any]?,
                                            role: GlobalShortcutRole? = nil) -> Bool {
        let permittedIDs = role?.permittedSystemShortcutIDs ?? []
        if let liveEntries, !liveEntries.isEmpty {
            return matchesLiveSystemShortcut(shortcut, entries: liveEntries.filter {
                !permittedIDs.contains($0.id)
            })
        }
        return matchesSystemShortcut(shortcut, symbolicHotKeys: symbolicHotKeys()?.filter {
            !permittedIDs.contains(Int32($0.key) ?? -1)
        })
    }

    static func matchesLiveSystemShortcut(_ shortcut: GlobalShortcut,
                                          entries: [LiveSystemShortcut]) -> Bool {
        guard shortcut.keyCode != Self.noKeyCode else { return false }
        return entries.contains {
            $0.enabled && $0.shortcut == shortcut
                && (!$0.requiresFunctionKey || shortcut.syntheticEventFlags.contains(.maskSecondaryFn))
        }
    }

    static func matchesSystemShortcut(_ shortcut: GlobalShortcut,
                                      symbolicHotKeys: [String: Any]?) -> Bool {
        guard let symbolicHotKeys else { return false }
        return symbolicHotKeys.values.contains { entry in
            guard let entry = entry as? [String: Any],
                  (entry["enabled"] as? NSNumber)?.boolValue == true,
                  let value = entry["value"] as? [String: Any],
                  (value["type"] as? String) == "standard",
                  let parameters = value["parameters"] as? [NSNumber],
                  parameters.count >= 3
            else { return false }
            let keyCode = parameters[1].int64Value
            guard keyCode == shortcut.keyCode, keyCode != Self.noKeyCode else { return false }
            let flags = NSEvent.ModifierFlags(rawValue: UInt(parameters[2].uintValue))
            return GlobalShortcutModifiers(eventFlags: flags) == shortcut.modifiers
                && (!flags.contains(.function) || shortcut.syntheticEventFlags.contains(.maskSecondaryFn))
        }
    }

    private static let noKeyCode: Int64 = 0xFFFF
}

struct ModifierShortcutRecording {
    private var candidate: GlobalShortcutModifiers = []
    private var waitingForRelease = false

    mutating func keyPressed() {
        candidate = []
        waitingForRelease = true
    }

    mutating func flagsChanged(_ modifiers: GlobalShortcutModifiers,
                               hasUnsupportedModifier: Bool = false) -> GlobalShortcutModifiers? {
        if hasUnsupportedModifier {
            keyPressed()
            return nil
        }
        if modifiers.isEmpty {
            let captured = candidate
            candidate = []
            waitingForRelease = false
            return captured.isEmpty ? nil : captured
        }
        guard !waitingForRelease else { return nil }
        if modifiers.rawValue.nonzeroBitCount > candidate.rawValue.nonzeroBitCount {
            candidate = modifiers
        }
        return nil
    }
}
