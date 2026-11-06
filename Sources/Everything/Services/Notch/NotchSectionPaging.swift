// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchSectionPaging {
    static func rows(count: Int, columns: Int) -> Int {
        let columns = max(1, columns)
        return max(1, (max(0, count) + columns - 1) / columns)
    }

    static func positions(rows: Int, visible: Int) -> Int {
        max(1, max(1, rows) - max(1, visible) + 1)
    }

    static func clamped(_ row: Int, rows: Int, visible: Int) -> Int {
        min(max(0, row), positions(rows: rows, visible: visible) - 1)
    }

    static func revealing(row: Int, first: Int, rows: Int, visible: Int) -> Int {
        let visible = max(1, visible)
        var first = clamped(first, rows: rows, visible: visible)
        if row < first { first = row } else if row >= first + visible { first = row - visible + 1 }
        return clamped(first, rows: rows, visible: visible)
    }
}

struct NotchSectionScroll {
    static let firstStep = 24.0
    static let rowStep = Double(NotchLayout.sectionTileHeight + NotchLayout.sectionSpacing)
    static let sequenceGap = 0.35
    private var distance = 0.0
    private var direction = 0
    private var stepped = false
    private var lastTimestamp: TimeInterval?

    mutating func steps(deltaY: Double, timestamp: TimeInterval, precise: Bool, hasPhase: Bool,
                        began: Bool, ended: Bool, momentum: Bool) -> Int {
        guard deltaY.isFinite, timestamp.isFinite else { self = Self(); return 0 }
        if momentum { return 0 }
        if ended { self = Self(); return 0 }
        guard precise else {
            self = Self()
            return deltaY == 0 ? 0 : (deltaY < 0 ? 1 : -1)
        }
        if began || lastTimestamp.map({ timestamp < $0 || (!hasPhase && timestamp - $0 > Self.sequenceGap) }) == true {
            self = Self()
        }
        lastTimestamp = timestamp
        if deltaY != 0 {
            let incomingDirection = deltaY < 0 ? 1 : -1
            if direction != 0, direction != incomingDirection { distance = 0; stepped = false }
            direction = incomingDirection
        }
        distance += deltaY
        var steps = 0
        while abs(distance) >= (stepped ? Self.rowStep : Self.firstStep) {
            distance += Double(direction) * (stepped ? Self.rowStep : Self.firstStep)
            stepped = true
            steps += 1
        }
        return direction * steps
    }
}
