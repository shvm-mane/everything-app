// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum ExtraBrightnessSupport {
    static let engagementFactor: Double = 1.10

    static let headroomThreshold: Double = 1.05

    static let capabilityFloor: Double = 2.05

    static let xdrModelIdentifiers: Set<String> = [
        "MacBookPro18,1", "MacBookPro18,2", "MacBookPro18,3", "MacBookPro18,4",
        "Mac14,5", "Mac14,6", "Mac14,9", "Mac14,10",
        "Mac15,3", "Mac15,6", "Mac15,7", "Mac15,8", "Mac15,9", "Mac15,10", "Mac15,11",
        "Mac16,1", "Mac16,5", "Mac16,6", "Mac16,7", "Mac16,8",
        "Mac17,2", "Mac17,6", "Mac17,7", "Mac17,8", "Mac17,9",
    ]

    static func isXDRPanelName(_ localizedName: String) -> Bool {
        localizedName.localizedCaseInsensitiveContains("XDR")
    }

    static func isSupportedPanel(model: String?, localizedName: String,
                                 potentialEDR: Double) -> Bool {
        if let model, xdrModelIdentifiers.contains(model) { return true }
        return potentialEDR > capabilityFloor || isXDRPanelName(localizedName)
    }

    static let sdr500nitModels: Set<String> = [
        "MacBookPro18,1", "MacBookPro18,2", "MacBookPro18,3", "MacBookPro18,4",
        "Mac14,5", "Mac14,6", "Mac14,9", "Mac14,10",
    ]

    static func panelReference(model: String?) -> (referenceEDR: Double, bonus: Double) {
        if let model, sdr500nitModels.contains(model) { return (3.2, 0.58) }
        return (2.66, 0.48)
    }

    static func boostFactor(level: Double, maxEDR: Double,
                            reference: (referenceEDR: Double, bonus: Double)) -> Double {
        let clampedLevel = min(max(level, 0), 1)
        let granted = min(max(maxEDR, 0) / reference.referenceEDR, 1.0)
        return 1 + clampedLevel * reference.bonus * granted
    }

    static func renderFactor(level: Double, currentEDR: Double, potentialEDR: Double,
                             reference: (referenceEDR: Double, bonus: Double)) -> Double {
        guard potentialEDR > headroomThreshold else { return 1.0 }
        guard currentEDR > headroomThreshold else {
            return min(engagementFactor,
                       boostFactor(level: level, maxEDR: reference.referenceEDR, reference: reference))
        }
        return min(boostFactor(level: level, maxEDR: currentEDR, reference: reference),
                   max(currentEDR, 1.0))
    }

    // MARK: - Smoothing between poll ticks

    static let rampUpStep: Double = 0.03
    static let rampDownShare: Double = 0.25
    static let rampMinStep: Double = 0.01

    static let dropoutGraceTicks = 3

    static func rampedFactor(previous: Double, target: Double) -> Double {
        if target > previous { return min(previous + rampUpStep, target) }
        if target < previous {
            let step = max((previous - target) * rampDownShare, rampMinStep)
            return max(previous - step, target)
        }
        return previous
    }

    static func gracedTarget(instantaneous: Double, previous: Double,
                             engaged: Bool, disengagedTicks: Int) -> Double {
        guard !engaged, disengagedTicks <= dropoutGraceTicks else { return instantaneous }
        return max(instantaneous, previous)
    }

    static func canReuseSpaceWindows(sameDisplay: Bool,
                                     inOwnSpace: Bool,
                                     overlayOnActiveSpace: Bool,
                                     triggerOnActiveSpace: Bool) -> Bool {
        sameDisplay && (inOwnSpace || (overlayOnActiveSpace && triggerOnActiveSpace))
    }

    // MARK: - Overlay geometry

    static func overlayFrames(for screen: CGRect) -> [CGRect] {
        let lowerHeight = (screen.height / 2).rounded(.down)
        let lower = CGRect(x: screen.minX, y: screen.minY,
                           width: screen.width, height: lowerHeight)
        let upper = CGRect(x: screen.minX, y: screen.minY + lowerHeight,
                           width: screen.width, height: screen.height - lowerHeight)
        return [lower, upper]
    }
}
