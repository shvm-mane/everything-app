// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

struct WindowFocusHistory {
    struct Request: Equatable {
        let pid: pid_t
        let id = UUID()
    }

    private enum Use: Equatable {
        case app(Request)
        case window(CGWindowID, Request? = nil)
    }

    private var recent: [Use] = []
    private(set) var current: Request?
    private(set) var revision = UUID()

    mutating func activate(_ pid: pid_t, recording: Bool = true) -> Request? {
        if !recording, let current { invalidate(current.pid, keepingActivation: true) }
        invalidate(pid)
        current = recording ? Request(pid: pid) : nil
        if let current {
            promote(.app(current))
        }
        return current
    }

    @discardableResult
    mutating func focus(_ window: CGWindowID, for request: Request) -> Bool {
        if current == request {
            recent.removeAll { use in
                if case .app(let pending) = use { return pending.pid == request.pid }
                return false
            }
            promote(.window(window, request))
            return true
        }
        guard let anchor = recent.firstIndex(where: { use in
            switch use {
            case .app(let pending): return pending == request
            case .window(_, let pending): return pending == request
            }
        }) else { return false }
        recent.insert(.window(window, request), at: anchor)
        var seen = Set<CGWindowID>()
        recent = recent.filter { use in
            switch use {
            case .app(let pending): return pending != request
            case .window(let id, _): return seen.insert(id).inserted
            }
        }
        if recent.count > WindowUseOrder.limit { recent.removeLast() }
        revision = UUID()
        return true
    }

    mutating func switched(to window: CGWindowID?, pid: pid_t, previous: CGWindowID?) {
        if let current { invalidate(current.pid, keepingActivation: previous == nil) }
        invalidate(pid)
        let request = Request(pid: pid)
        current = request
        if let previous { promote(.window(previous)) }
        if let window { promote(.window(window, request)) }
        else { promote(.app(request)) }
    }

    mutating func reconcile(windows: Set<CGWindowID>, revision capturedRevision: UUID) {
        guard revision == capturedRevision else { return }
        recent.removeAll {
            switch $0 {
            case .window(let id, _): return !windows.contains(id)
            case .app: return false
            }
        }
    }

    mutating func terminated(_ pid: pid_t) {
        invalidate(pid)
        if current?.pid == pid { current = nil }
        revision = UUID()
    }

    func order(_ entries: [WindowUseOrder.Entry], baseline: [Int]) -> [Int] {
        var result: [Int] = []
        var seen = Set<Int>()
        for use in recent {
            let index = baseline.first { index in
                switch use {
                case .window(let id, _): return entries[index].windowID == id
                case .app(let request): return entries[index].pid == request.pid
                }
            }
            if let index, seen.insert(index).inserted { result.append(index) }
        }
        result += baseline.filter { seen.insert($0).inserted }
        return result
    }

    private mutating func invalidate(_ pid: pid_t, keepingActivation: Bool = false) {
        recent = recent.compactMap { use in
            switch use {
            case .app(let request):
                guard request.pid == pid else { return use }
                return keepingActivation ? .app(Request(pid: pid)) : nil
            case .window(let id, let request):
                return request?.pid == pid ? .window(id) : use
            }
        }
    }

    private mutating func promote(_ use: Use) {
        revision = UUID()
        recent.removeAll { existing in
            if case .window(let id, _) = use,
               case .window(let existingID, _) = existing { return id == existingID }
            return existing == use
        }
        recent.insert(use, at: 0)
        if recent.count > WindowUseOrder.limit { recent.removeLast() }
    }
}

enum WindowUseOrder {
    static let limit = 256

    struct Entry: Equatable {
        let windowID: CGWindowID?
        let pid: pid_t

        init(windowID: CGWindowID?, pid: pid_t) {
            self.windowID = windowID
            self.pid = pid
        }
    }

    static func order(_ entries: [Entry],
                      windowHistory: [CGWindowID],
                      appHistory: [pid_t],
                      frontToBack: [CGWindowID]) -> [Int] {
        let windowRank = rankMap(windowHistory)
        let appRank = rankMap(appHistory)
        let depthRank = rankMap(frontToBack)

        return entries.indices.sorted { lhs, rhs in
            key(entries[lhs], at: lhs, windowRank, appRank, depthRank)
                < key(entries[rhs], at: rhs, windowRank, appRank, depthRank)
        }
    }

    static func ordered(_ entries: [Entry],
                        windowHistory: [CGWindowID],
                        appHistory: [pid_t],
                        frontToBack: [CGWindowID]) -> [Entry] {
        order(entries, windowHistory: windowHistory, appHistory: appHistory, frontToBack: frontToBack)
            .map { entries[$0] }
    }

    private static func key(_ entry: Entry,
                            at index: Int,
                            _ windowRank: [CGWindowID: Int],
                            _ appRank: [pid_t: Int],
                            _ depthRank: [CGWindowID: Int]) -> SortKey {
        if let windowID = entry.windowID, let rank = windowRank[windowID] {
            return SortKey(tier: 0, primary: rank, secondary: 0, original: index)
        }
        let depth = entry.windowID.flatMap { depthRank[$0] } ?? Int.max
        return SortKey(tier: 1,
                       primary: appRank[entry.pid] ?? Int.max,
                       secondary: depth,
                       original: index)
    }

    private struct SortKey: Comparable {
        let tier: Int
        let primary: Int
        let secondary: Int
        let original: Int

        static func < (lhs: SortKey, rhs: SortKey) -> Bool {
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            if lhs.primary != rhs.primary { return lhs.primary < rhs.primary }
            if lhs.secondary != rhs.secondary { return lhs.secondary < rhs.secondary }
            return lhs.original < rhs.original
        }
    }

    private static func rankMap<T: Hashable>(_ list: [T]) -> [T: Int] {
        var map: [T: Int] = [:]
        map.reserveCapacity(list.count)
        for (index, value) in list.enumerated() where map[value] == nil {
            map[value] = index
        }
        return map
    }

    static func promoting(_ windowID: CGWindowID,
                          previous: CGWindowID? = nil,
                          in history: [CGWindowID],
                          limit: Int = limit) -> [CGWindowID] {
        var result = history
        result.removeAll { $0 == windowID }
        result.insert(windowID, at: 0)
        if let previous, previous != windowID {
            result.removeAll { $0 == previous }
            result.insert(previous, at: 1)
        }
        return capped(result, limit: limit)
    }

    static func promoting(target: CGWindowID?,
                          previous: CGWindowID?,
                          in history: [CGWindowID],
                          limit: Int = limit) -> [CGWindowID] {
        guard let target else {
            guard let previous else { return history }
            return promoting(previous, in: history, limit: limit)
        }
        return promoting(target, previous: previous, in: history, limit: limit)
    }

    static func promoting(_ pid: pid_t, in history: [pid_t], limit: Int = limit) -> [pid_t] {
        var result = history
        result.removeAll { $0 == pid }
        result.insert(pid, at: 0)
        return capped(result, limit: limit)
    }

    static func reconciled(_ history: [CGWindowID],
                           existing: Set<CGWindowID>,
                           frontToBack: [CGWindowID],
                           limit: Int = limit) -> [CGWindowID] {
        var result = history.filter { existing.contains($0) }
        var known = Set(result)
        for windowID in frontToBack where existing.contains(windowID) && !known.contains(windowID) {
            result.append(windowID)
            known.insert(windowID)
        }
        return capped(result, limit: limit)
    }

    static func reconciled(_ history: [pid_t],
                           running: Set<pid_t>,
                           frontToBack: [pid_t] = [],
                           limit: Int = limit) -> [pid_t] {
        var result = history.filter { running.contains($0) }
        var known = Set(result)
        for pid in frontToBack where running.contains(pid) && !known.contains(pid) {
            result.append(pid)
            known.insert(pid)
        }
        return capped(result, limit: limit)
    }

    private static func capped<T>(_ list: [T], limit: Int) -> [T] {
        guard list.count > limit else { return list }
        return Array(list.prefix(limit))
    }
}
