// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum WindowMaximizerSupport {
    static func excludes(bundleIdentifier: String?, excludedBundleIdentifiers: [String]) -> Bool {
        guard let bundleIdentifier else { return false }
        return Defaults.sanitizedBundleIdentifierList(excludedBundleIdentifiers).contains(bundleIdentifier)
    }

    static func overshoots(_ actual: CGSize, target: CGSize) -> Bool {
        actual.width > target.width + 0.5 || actual.height > target.height + 0.5
    }

    static func approachOrigin(for target: CGPoint, tolerance: CGFloat) -> CGPoint {
        CGPoint(x: target.x - tolerance, y: target.y - tolerance)
    }
}
