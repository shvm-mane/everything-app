// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

enum SpaceHopSupport {
    static let maximumArrowSteps = 16

    enum FirstStage: Equatable {
        case waitForActivationTravel
        case moveASpace
    }

    static func firstStage(appHasWindowOnVisibleSpace: Bool,
                           directRaiseSucceeded: Bool = false) -> FirstStage {
        if directRaiseSucceeded { return .waitForActivationTravel }
        return appHasWindowOnVisibleSpace ? .moveASpace : .waitForActivationTravel
    }

    static func arrivalPulseShouldFocus(isFirstPulse: Bool,
                                        targetSpaceIsVisible: @autoclosure () -> Bool,
                                        targetWindowID: CGWindowID,
                                        windowOwnerPID: pid_t,
                                        frontmostPID: pid_t?,
                                        focusedWindowID: @autoclosure () -> CGWindowID?) -> Bool {
        guard !isFirstPulse, targetSpaceIsVisible() else { return true }
        guard frontmostPID == windowOwnerPID else { return true }
        return focusedWindowID() != targetWindowID
    }

    static func isParkedOnHiddenSpace(windowSpaces: [UInt64], visibleSpaces: Set<UInt64>) -> Bool {
        guard !windowSpaces.isEmpty, !visibleSpaces.isEmpty else { return false }
        return !windowSpaces.contains { visibleSpaces.contains($0) }
    }

    static func isOnFullscreenSpace(windowSpaces: [UInt64],
                                    fullscreenSpaces: Set<UInt64>) -> Bool {
        windowSpaces.contains { fullscreenSpaces.contains($0) }
    }

    static func isExcludedFromWindowCycle(windowTags: UInt64) -> Bool {
        let ignoresCycleTag: UInt64 = 1 << 18
        return windowTags & ignoresCycleTag != 0
    }

    static func isHiddenWithApp(windowTags: UInt64) -> Bool {
        let hiddenWithAppTag: UInt64 = 1 << 39
        return windowTags & hiddenWithAppTag != 0
    }

    static func isMinimized(windowTags: UInt64) -> Bool {
        let minimizedTag: UInt64 = 1 << 60
        return windowTags & minimizedTag != 0
    }

    static func windowsHiddenWithApp(windowTags: [CGWindowID: UInt64]) -> Set<CGWindowID>? {
        guard windowTags.values.contains(where: { $0 != 0 }) else { return nil }
        return Set(windowTags.filter { isHiddenWithApp(windowTags: $0.value) }.keys)
    }

    static func arrowSteps(orderedSpacesPerDisplay: [[UInt64]],
                           visibleSpaces: Set<UInt64>,
                           target: UInt64) -> Int? {
        guard let row = orderedSpacesPerDisplay.first(where: { $0.contains(target) }) else { return nil }
        guard !visibleSpaces.contains(target) else { return nil }
        guard let targetIndex = row.firstIndex(of: target),
              let currentIndex = row.firstIndex(where: { visibleSpaces.contains($0) })
        else { return nil }
        let steps = targetIndex - currentIndex
        guard steps != 0, abs(steps) <= maximumArrowSteps else { return nil }
        return steps
    }

    static func eventFlags(fromCarbonModifiers modifiers: UInt32) -> CGEventFlags {
        var flags = CGEventFlags()
        if modifiers & 0x20000 != 0 { flags.insert(.maskShift) }
        if modifiers & 0x40000 != 0 { flags.insert(.maskControl) }
        if modifiers & 0x80000 != 0 { flags.insert(.maskAlternate) }
        if modifiers & 0x100000 != 0 { flags.insert(.maskCommand) }
        if modifiers & 0x800000 != 0 { flags.insert(.maskSecondaryFn) }
        return flags
    }
}
