// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MouseButtonShortcutSupport {
    static let buttonRange: ClosedRange<Int64> = 3...31

    static let backButtonNumber: Int64 = 3
    static let forwardButtonNumber: Int64 = 4
    static let sideWheelLeftInput: Int64 = -2
    static let sideWheelRightInput: Int64 = -1

    struct SideWheelGestureGate {
        static let quietNanoseconds: UInt64 = 250_000_000

        private var lastTimestamp: UInt64?
        private var firedDirections: UInt8 = 0

        mutating func shouldFire(_ input: Int64, at timestamp: UInt64) -> Bool {
            let bit: UInt8
            switch input {
            case MouseButtonShortcutSupport.sideWheelLeftInput: bit = 1
            case MouseButtonShortcutSupport.sideWheelRightInput: bit = 2
            default: return false
            }

            if let lastTimestamp,
               timestamp >= lastTimestamp,
               timestamp - lastTimestamp <= Self.quietNanoseconds {
                self.lastTimestamp = timestamp
            } else {
                lastTimestamp = timestamp
                firedDirections = 0
            }

            guard firedDirections & bit == 0 else { return false }
            firedDirections |= bit
            return true
        }

        mutating func reset() {
            lastTimestamp = nil
            firedDirections = 0
        }
    }

    static func canMap(_ input: Int64) -> Bool {
        input == sideWheelLeftInput
            || input == sideWheelRightInput
            || buttonRange.contains(input)
    }

    static func isPressed(_ button: Int64, pressedButtons: Int) -> Bool {
        guard button >= 0, button < Int64(Int.bitWidth) else { return false }
        return pressedButtons & (1 << Int(button)) != 0
    }

    static func sideWheelInput(isContinuous: Bool,
                               vertical: (line: Double, fixedPoint: Double, point: Double),
                               horizontal: (line: Double, fixedPoint: Double, point: Double)) -> Int64? {
        guard vertical.line.isFinite,
              vertical.fixedPoint.isFinite,
              vertical.point.isFinite,
              horizontal.line.isFinite,
              horizontal.fixedPoint.isFinite,
              horizontal.point.isFinite else { return nil }
        let verticalDelta: Double
        let horizontalDelta: Double
        if isContinuous {
            verticalDelta = vertical.point != 0
                ? vertical.point : (vertical.fixedPoint != 0 ? vertical.fixedPoint : vertical.line)
            horizontalDelta = horizontal.point != 0
                ? horizontal.point : (horizontal.fixedPoint != 0 ? horizontal.fixedPoint : horizontal.line)
        } else {
            verticalDelta = vertical.fixedPoint != 0
                ? vertical.fixedPoint : (vertical.line != 0 ? vertical.line : vertical.point)
            horizontalDelta = horizontal.fixedPoint != 0
                ? horizontal.fixedPoint : (horizontal.line != 0 ? horizontal.line : horizontal.point)
        }
        guard horizontalDelta != 0, abs(horizontalDelta) > abs(verticalDelta) else { return nil }
        return horizontalDelta > 0 ? sideWheelLeftInput : sideWheelRightInput
    }

    static func decode(_ raw: [String: String]?) -> [Int64: GlobalShortcut] {
        guard let raw else { return [:] }
        var mappings: [Int64: GlobalShortcut] = [:]
        for (key, value) in raw {
            guard let button = Int64(key), canMap(button),
                  let shortcut = GlobalShortcut(storageValue: value) else { continue }
            mappings[button] = shortcut
        }
        return mappings
    }

    static func encode(_ mappings: [Int64: GlobalShortcut]) -> [String: String] {
        var raw: [String: String] = [:]
        for (button, shortcut) in mappings where canMap(button) {
            raw[String(button)] = shortcut.storageValue
        }
        return raw
    }

    static func firesShortcut(for button: Int64,
                              isAvailable: Bool,
                              isEnabled: Bool,
                              mappings: [Int64: GlobalShortcut],
                              claimedByWheel: (Int64) -> Bool) -> GlobalShortcut? {
        guard isAvailable, isEnabled, !claimedByWheel(button) else { return nil }
        return mappings[button]
    }

    static func claimsButton(_ button: Int64, defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: AppFeature.mouseButtonShortcuts.availabilityKey),
              !RadialMenuSupport.claimsMouseButton(button, defaults: defaults) else { return false }
        return hasActiveShortcut(button, defaults) || spacesGestureButton(defaults) == button
    }

    static func spacesGestureButton(_ defaults: UserDefaults = .standard) -> Int64? {
        MouseSpacesGestureSupport.boundButton(
            isAvailable: defaults.bool(forKey: AppFeature.mouseButtonShortcuts.availabilityKey),
            isEnabled: defaults.bool(forKey: DefaultsKey.mouseSpacesGestureEnabled),
            button: Int64(defaults.integer(forKey: DefaultsKey.mouseSpacesGestureButton)),
            hasShortcut: { hasActiveShortcut($0, defaults) },
            claimedByWheel: { RadialMenuSupport.claimsMouseButton($0, defaults: defaults) })
    }

    private static func hasActiveShortcut(_ button: Int64, _ defaults: UserDefaults) -> Bool {
        guard canMap(button), defaults.bool(forKey: DefaultsKey.mouseButtonShortcutsEnabled) else { return false }
        let raw = defaults.dictionary(forKey: DefaultsKey.mouseButtonShortcuts) as? [String: String]
        guard let stored = raw?[String(button)] else { return false }
        return GlobalShortcut(storageValue: stored) != nil
    }

    static func sortedButtons(_ mappings: [Int64: GlobalShortcut]) -> [Int64] {
        mappings.keys.sorted()
    }

    static func buttonName(for button: Int64, strings: MouseButtonFeatureStrings) -> String {
        switch button {
        case 2: return strings.middleButtonName
        case sideWheelLeftInput: return strings.sideWheelLeftName
        case sideWheelRightInput: return strings.sideWheelRightName
        case backButtonNumber: return strings.backButtonName
        case forwardButtonNumber: return strings.forwardButtonName
        default: return String(format: strings.otherButtonFormat, Int(button) + 1)
        }
    }
}
