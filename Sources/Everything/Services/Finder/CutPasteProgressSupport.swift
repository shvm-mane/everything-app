// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CutPasteProgressSupport {
    static let pollInterval: TimeInterval = 0.3

    static func isCrossVolume(source: NSObject?, destination: NSObject?) -> Bool {
        guard let source, let destination else { return false }
        return !source.isEqual(destination)
    }

    static func fraction(finishedBytes: Int64, currentBytes: Int64, totalBytes: Int64) -> Double? {
        guard totalBytes > 0 else { return nil }
        let done = min(max(finishedBytes, 0) + max(currentBytes, 0), totalBytes)
        return Double(done) / Double(totalBytes)
    }

    static func displayPosition(completed: Int, total: Int) -> Int {
        min(max(completed, 0) + 1, max(total, 1))
    }
}
