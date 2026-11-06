// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum DockClickAction: Equatable {
    case minimize
    case restore
    case hide
    case cycleWindows
    case passThrough
}

enum DockClickRepeatDecision: Equatable {
    case swallow
    case toggle(DockClickAction)
    case deriveFromState
}

struct DockAppInstance: Equatable {
    let pid: pid_t
    let launchTime: TimeInterval?
}

struct DockTilePairing<Tile> {
    let tile: Tile
    let pid: pid_t
    let launchTime: TimeInterval?
}

extension DockTilePairing: Equatable where Tile: Equatable {}

enum DockClickSupport {
    static func isOwnBundleIdentifier(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier == "com.vorssaint.utils"
            || bundleIdentifier == "com.vorssaint.utils.dev"
    }

    static func isVerifiedMinimizeAll(commandCharacter: String?,
                                      modifiers: Int?,
                                      identifier: String?) -> Bool {
        commandCharacter?.uppercased() == "M"
            && modifiers == 2
            && identifier == "miniaturizeAll:"
    }

    static let repeatClickGap: TimeInterval = 0.25

    static let toggleIntentWindow: TimeInterval = 1.5

    static let dragSlop: CGFloat = 6

    static func isDragMovement(from origin: CGPoint, to point: CGPoint) -> Bool {
        let dx = point.x - origin.x, dy = point.y - origin.y
        return (dx * dx + dy * dy).squareRoot() > dragSlop
    }

    static let minimizeSweepDelay: TimeInterval = 0.9

    static let minimizeMenuVerifyDelay: TimeInterval = 0.35

    static let restoreSweepDelay: TimeInterval = 0.6

    static func restoreSequence(ids: [CGWindowID?],
                                frontToBack: [CGWindowID],
                                preferredFront: CGWindowID? = nil) -> [Int] {
        var seen = Set<CGWindowID>()
        var candidates: [Int] = []
        for (index, id) in ids.enumerated() {
            if let id {
                guard !seen.contains(id) else { continue }
                seen.insert(id)
            }
            candidates.append(index)
        }

        guard !frontToBack.isEmpty else {
            guard let preferredFront,
                  let frontSlot = candidates.firstIndex(where: { ids[$0] == preferredFront })
            else { return candidates }
            candidates.append(candidates.remove(at: frontSlot))
            return candidates
        }

        func depth(_ index: Int) -> Int {
            guard let id = ids[index], let depth = frontToBack.firstIndex(of: id)
            else { return frontToBack.count }
            return depth
        }
        return candidates.sorted { first, second in
            let firstDepth = depth(first), secondDepth = depth(second)
            if firstDepth != secondDepth { return firstDepth > secondDepth }
            return first < second
        }
    }

    static func capturedMinimizeStillHolds(captured: [CGWindowID],
                                           stillMinimized: Set<CGWindowID>) -> Bool {
        captured.contains { stillMinimized.contains($0) }
    }

    static func repeatDecision(lastAction: DockClickAction?,
                               elapsed: TimeInterval?) -> DockClickRepeatDecision {
        guard let lastAction, let elapsed, elapsed < toggleIntentWindow else { return .deriveFromState }
        if elapsed < repeatClickGap { return .swallow }
        switch lastAction {
        case .minimize: return .toggle(.restore)
        case .restore: return .toggle(.minimize)
        case .hide, .cycleWindows: return .deriveFromState
        case .passThrough: return .deriveFromState
        }
    }

    static func effectiveHasUnminimized(unminimizedCount: Int,
                                        minimizedCount: Int,
                                        windowServerSeesWindows: Bool) -> Bool {
        unminimizedCount > 0 || (minimizedCount == 0 && windowServerSeesWindows)
    }

    static func cycleCandidateIndices(windowIDs: [CGWindowID?],
                                      onScreenFrontToBack: [CGWindowID]) -> [Int] {
        var depths: [(index: Int, depth: Int)] = []
        for (index, id) in windowIDs.enumerated() {
            guard let id, let depth = onScreenFrontToBack.firstIndex(of: id) else { continue }
            depths.append((index, depth))
        }
        return depths.sorted { $0.depth < $1.depth }.map(\.index)
    }

    static func action(appIsFrontmost: Bool,
                       hasUnminimizedWindows: Bool,
                       hasMinimizedWindows: Bool,
                       hasFullscreenWindows: Bool,
                       hasModifiers: Bool,
                       minimizeEnabled: Bool = true,
                       hideEnabled: Bool = false,
                       cycleWindowsEnabled: Bool = false,
                       cycleCandidateCount: Int = 0,
                       ownsMinimize: Bool = false) -> DockClickAction {
        guard !hasModifiers else { return .passThrough }
        if cycleWindowsEnabled, appIsFrontmost, !hasFullscreenWindows, cycleCandidateCount > 1 {
            return .cycleWindows
        }
        if hideEnabled, appIsFrontmost, hasUnminimizedWindows || hasMinimizedWindows { return .hide }
        guard !hasFullscreenWindows else { return .passThrough }
        if minimizeEnabled, appIsFrontmost, hasUnminimizedWindows { return .minimize }
        if minimizeEnabled, ownsMinimize, !hasUnminimizedWindows, hasMinimizedWindows { return .restore }
        return .passThrough
    }

    static func dockStripContains(_ point: CGPoint,
                                  screenFrame: CGRect,
                                  visibleFrame: CGRect,
                                  fallbackMargin: CGFloat = 120) -> Bool {
        guard screenFrame.insetBy(dx: -8, dy: -8).contains(point) else { return false }

        let bottomGap = screenFrame.maxY - visibleFrame.maxY
        let leftGap = visibleFrame.minX - screenFrame.minX
        let rightGap = screenFrame.maxX - visibleFrame.maxX
        let reserved: CGFloat = 8

        if bottomGap > reserved || leftGap > reserved || rightGap > reserved {
            if bottomGap > reserved, point.y >= visibleFrame.maxY - 2 { return true }
            if leftGap > reserved, point.x <= visibleFrame.minX + 2 { return true }
            if rightGap > reserved, point.x >= visibleFrame.maxX - 2 { return true }
            return false
        }

        return point.y >= screenFrame.maxY - fallbackMargin
            || point.x <= screenFrame.minX + fallbackMargin
            || point.x >= screenFrame.maxX - fallbackMargin
    }

    static func dockOwnsPoint(_ point: CGPoint,
                              windows: [MouseAppExceptionSupport.Window],
                              dockProcessID: pid_t,
                              dockLayer: Int,
                              ownProcessID: pid_t,
                              accessibilityHitProcessID: () -> pid_t?) -> Bool {
        var isCovered = false
        for window in windows where window.alpha > 0 {
            let isDockStrip = window.processID == dockProcessID && window.layer == dockLayer
            let contains = isDockStrip
                ? window.frame.insetBy(dx: -8, dy: -8).contains(point)
                : window.frame.contains(point)
            guard contains else { continue }
            if window.processID == ownProcessID { continue }
            if isDockStrip {
                return !isCovered || accessibilityHitProcessID() == dockProcessID
            }
            isCovered = true
        }
        return false
    }

    static func pairTiles<Tile: Equatable>(_ tiles: [Tile],
                                           instances: [DockAppInstance],
                                           previous: [DockTilePairing<Tile>],
                                           complete: Bool = true) -> [DockTilePairing<Tile>] {
        var pairings: [DockTilePairing<Tile>] = []
        for pairing in previous
        where instances.contains(where: { $0.pid == pairing.pid && $0.launchTime == pairing.launchTime })
            && tiles.contains(pairing.tile)
            && !pairings.contains(where: { $0.pid == pairing.pid || $0.tile == pairing.tile }) {
            pairings.append(pairing)
        }
        guard canPairByOrder(tileCount: tiles.count, instanceCount: instances.count, complete: complete)
        else { return pairings }
        let freeTiles = tiles.filter { tile in !pairings.contains { $0.tile == tile } }
        let freeInstances = instances
            .filter { instance in !pairings.contains { $0.pid == instance.pid } }
            .sorted { first, second in
                let firstTime = first.launchTime ?? -.infinity
                let secondTime = second.launchTime ?? -.infinity
                if firstTime != secondTime { return firstTime < secondTime }
                return first.pid < second.pid
            }
        for (tile, instance) in zip(freeTiles, freeInstances) {
            pairings.append(DockTilePairing(tile: tile, pid: instance.pid, launchTime: instance.launchTime))
        }
        return pairings
    }

    static func canPairByOrder(tileCount: Int, instanceCount: Int, complete: Bool) -> Bool {
        complete && tileCount == instanceCount
    }

    static func soleInstanceIsBehindTile(tileReadsRunning: Bool,
                                         anotherTileReadsRunning: () -> Bool) -> Bool {
        tileReadsRunning || !anotherTileReadsRunning()
    }

    static func launchTime(processStartMicroseconds: UInt64?, launchDate: Date?) -> TimeInterval? {
        if let processStartMicroseconds {
            return Date(timeIntervalSince1970: Double(processStartMicroseconds) / 1_000_000)
                .timeIntervalSinceReferenceDate
        }
        return launchDate?.timeIntervalSinceReferenceDate
    }
}
