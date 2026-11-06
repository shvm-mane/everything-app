// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Darwin
import Foundation

enum TrafficLightButton {
    case close
    case zoom
}

struct TrafficLightCandidate {
    let pid: pid_t
    let windowID: CGWindowID
    let frame: CGRect
}

struct WindowServerWindowCandidate: Equatable {
    let pid: pid_t
    let windowID: CGWindowID
    let frame: CGRect
}

enum WindowServerSupport {
    static func onScreenWindowInfo() -> [[String: Any]] {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                   kCGNullWindowID) as? [[String: Any]] ?? []
    }

    static func onScreenWindows() -> [MouseAppExceptionSupport.Window] {
        MouseAppExceptionSupport.windows(from: onScreenWindowInfo())
    }

    static func receivingWindow(at point: CGPoint) -> CGWindowID? {
        guard let primary = NSScreen.screens.first else { return nil }
        let cocoaPoint = CGPoint(x: point.x, y: primary.frame.maxY - point.y)
        let number = NSWindow.windowNumber(at: cocoaPoint, belowWindowWithWindowNumber: 0)
        guard number > 0 else { return nil }
        return CGWindowID(exactly: number)
    }

    static func bounds(from window: [String: Any]) -> CGRect? {
        guard let raw = window[kCGWindowBounds as String] as? [String: Any],
              let x = (raw["X"] as? NSNumber)?.doubleValue,
              let y = (raw["Y"] as? NSNumber)?.doubleValue,
              let width = (raw["Width"] as? NSNumber)?.doubleValue,
              let height = (raw["Height"] as? NSNumber)?.doubleValue else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func frame(ofWindowID windowID: CGWindowID) -> CGRect? {
        guard let infos = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID)
                as? [[String: Any]] else { return nil }
        return frame(ofWindowID: windowID, in: infos)
    }

    static func frame(ofWindowID windowID: CGWindowID, in windows: [[String: Any]]) -> CGRect? {
        for window in windows
        where (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID {
            return bounds(from: window)
        }
        return nil
    }

    static func ownerProcessID(ofWindowID windowID: CGWindowID) -> pid_t? {
        guard let infos = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID)
                as? [[String: Any]] else { return nil }
        return ownerProcessID(ofWindowID: windowID, in: infos)
    }

    static func ownerProcessID(ofWindowID windowID: CGWindowID, in windows: [[String: Any]]) -> pid_t? {
        for window in windows
        where (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID {
            return (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
        }
        return nil
    }

    static func frontWindowOwner(in windows: [[String: Any]]) -> pid_t? {
        for window in windows {
            guard (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0
            else { continue }
            return (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
        }
        return nil
    }

    static func windowCandidate(in windows: [[String: Any]],
                                at point: CGPoint,
                                ownProcessID: pid_t,
                                pidIsEligible: (pid_t) -> Bool) -> WindowServerWindowCandidate? {
        for window in windows {
            guard let bounds = bounds(from: window),
                  bounds.width >= 80, bounds.height >= 80,
                  point.x >= bounds.minX, point.x <= bounds.maxX,
                  point.y >= bounds.minY, point.y <= bounds.maxY,
                  let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == 0,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != ownProcessID,
                  pidIsEligible(pid),
                  let number = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            else { continue }
            return WindowServerWindowCandidate(pid: pid,
                                               windowID: CGWindowID(number),
                                               frame: bounds)
        }
        return nil
    }

    static func trafficLightCandidate(in windows: [[String: Any]],
                                      at point: CGPoint,
                                      button: TrafficLightButton,
                                      ownProcessID: pid_t,
                                      pidIsEligible: (pid_t) -> Bool) -> TrafficLightCandidate? {
        for window in windows {
            guard let bounds = bounds(from: window),
                  bounds.width >= 80,
                  bounds.height >= 80,
                  bounds.contains(point) else {
                continue
            }

            guard let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == 0,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID != ownProcessID,
                  let number = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value else {
                continue
            }

            guard pidIsEligible(ownerPID),
                  contains(point, inTrafficLightAreaOf: bounds, button: button) else {
                return nil
            }
            return TrafficLightCandidate(pid: ownerPID, windowID: CGWindowID(number), frame: bounds)
        }
        return nil
    }

    static func contains(_ point: CGPoint,
                         inTrafficLightAreaOf bounds: CGRect,
                         button: TrafficLightButton) -> Bool {
        let dx = point.x - bounds.minX
        let dy = point.y - bounds.minY
        guard dy >= -6, dy <= 46 else { return false }

        switch button {
        case .close:
            return dx >= -6 && dx <= 52
        case .zoom:
            return dx >= 42 && dx <= 104
        }
    }

    static func contains(_ point: CGPoint, inCloseButtonOf bounds: CGRect) -> Bool {
        let dx = point.x - bounds.minX
        let dy = point.y - bounds.minY
        return dx >= 0 && dy >= 0 && max(dx, dy) <= 35 && abs(dx - dy) <= 9
    }
}
