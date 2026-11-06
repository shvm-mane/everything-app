// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum MouseExceptionScope: String, CaseIterable {
    case smoothScroll
    case linearScroll
    case scrollDirection
    case focusFollowsMouse
    case navigation
    case buttonShortcuts
    case middleClick
    case superKey

    var defaultsKey: String {
        switch self {
        case .smoothScroll: return DefaultsKey.smoothScrollExceptions
        case .linearScroll: return DefaultsKey.linearScrollExceptions
        case .scrollDirection: return DefaultsKey.scrollInverterExceptions
        case .focusFollowsMouse: return DefaultsKey.focusFollowsMouseExceptions
        case .navigation: return DefaultsKey.mouseNavigationExceptions
        case .buttonShortcuts: return DefaultsKey.mouseButtonExceptions
        case .middleClick: return DefaultsKey.middleClickExceptions
        case .superKey: return DefaultsKey.superKeyExceptions
        }
    }

    var feature: AppFeature {
        switch self {
        case .smoothScroll: return .smoothScroll
        case .linearScroll: return .linearScroll
        case .scrollDirection: return .scrollInverter
        case .focusFollowsMouse: return .focusFollowsMouse
        case .navigation: return .mouseNavigation
        case .buttonShortcuts: return .mouseButtonShortcuts
        case .middleClick: return .middleClick
        case .superKey: return .superKey
        }
    }
}

enum MouseAppExceptionSupport {
    struct Window: Equatable {
        let frame: CGRect
        let layer: Int
        let alpha: Double
        let processID: Int32
        let number: CGWindowID

        init(frame: CGRect, layer: Int, alpha: Double = 1, processID: Int32, number: CGWindowID = 0) {
            self.frame = frame
            self.layer = layer
            self.alpha = alpha
            self.processID = processID
            self.number = number
        }
    }

    static func windows(from descriptions: [[String: Any]]) -> [Window] {
        descriptions.compactMap { info in
            guard let raw = info[kCGWindowBounds as String] as? [String: Any],
                  let x = (raw["X"] as? NSNumber)?.doubleValue,
                  let y = (raw["Y"] as? NSNumber)?.doubleValue,
                  let width = (raw["Width"] as? NSNumber)?.doubleValue,
                  let height = (raw["Height"] as? NSNumber)?.doubleValue,
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            else { return nil }
            return Window(frame: CGRect(x: x, y: y, width: width, height: height),
                          layer: layer,
                          alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                          processID: pid,
                          number: (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0)
        }
    }

    static let appWindowLayers = 0...3

    static let resolveLifetime: TimeInterval = 0.5

    static func pointerWindow(in windows: [Window],
                              at point: CGPoint,
                              ownProcessID: Int32) -> Window? {
        windows.first { window in
            window.alpha > 0
                && appWindowLayers.contains(window.layer)
                && window.processID != ownProcessID
                && window.frame.contains(point)
        }
    }

    static func pointerSurface(in windows: [Window],
                               receivingWindowID: CGWindowID?,
                               ownProcessID: Int32) -> Window? {
        guard let receivingWindowID, receivingWindowID != 0 else { return nil }
        return windows.first { window in
            window.number == receivingWindowID
                && window.layer > appWindowLayers.upperBound
                && window.processID != ownProcessID
        }
    }

    static let dockBundleID = "com.apple.dock"
    static let launchpadBundleID = "com.apple.launchpad.launcher"

    static func surfaceIdentities(_ ownerIdentities: [String]) -> [String] {
        ownerIdentities.contains(dockBundleID) ? ownerIdentities + [launchpadBundleID] : ownerIdentities
    }

    static func cacheHolds(region: CGRect?,
                           resolvedPoint: CGPoint,
                           resolvedAt: TimeInterval,
                           point: CGPoint,
                           now: TimeInterval) -> Bool {
        guard now >= resolvedAt, now - resolvedAt < resolveLifetime else { return false }
        guard region != nil else { return point == resolvedPoint }
        return cacheNamesWindow(region: region, point: point)
    }

    static func cacheNamesWindow(region: CGRect?, point: CGPoint) -> Bool {
        guard let region else { return false }
        return region.contains(point)
    }

    static func isExcepted(_ bundleID: String?, exceptions: Set<String>) -> Bool {
        guard let bundleID, !exceptions.isEmpty else { return false }
        return exceptions.contains(bundleID)
    }

    static func isExecutablePathIdentity(_ identity: String) -> Bool {
        identity.hasPrefix("/")
    }

    static func executablePathIdentity(_ path: String?) -> String? {
        guard let path, isExecutablePathIdentity(path) else { return nil }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    static func identity(bundleID: String?, executablePath: @autoclosure () -> String?) -> String? {
        bundleID ?? executablePathIdentity(executablePath())
    }

    static func identities(bundleID: String?,
                           executablePath: @autoclosure () -> String?,
                           readsPath: Bool) -> [String] {
        var identities = bundleID.map { [$0] } ?? []
        if readsPath, let path = executablePathIdentity(executablePath()) {
            identities.append(path)
        }
        return identities
    }

    static func pickedIdentity(for url: URL) -> String? {
        if let bundle = Bundle(url: url) {
            return bundle.bundleIdentifier ?? executablePathIdentity(bundle.executableURL?.path)
        }
        let picked = executablePathIdentity(url.path)
        var candidate = url.deletingLastPathComponent()
        while candidate.path != "/" {
            if candidate.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
               let bundle = Bundle(url: candidate),
               executablePathIdentity(bundle.executableURL?.path) == picked {
                return bundle.bundleIdentifier ?? picked
            }
            let parent = candidate.deletingLastPathComponent()
            guard parent != candidate else { break }
            candidate = parent
        }
        return picked
    }

    static func sourceProcessID(_ rawValue: Int64) -> Int32? {
        guard rawValue > 0 else { return nil }
        return Int32(exactly: rawValue)
    }

    static func isExcepted(_ bundleIDs: [String], exceptions: Set<String>) -> Bool {
        bundleIDs.contains(where: exceptions.contains)
    }
}
