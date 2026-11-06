// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

enum WindowStageManagerSupport {
    private static let windowManagerDefaults = UserDefaults(suiteName: "com.apple.WindowManager")
    private static let dockDefaults = UserDefaults(suiteName: "com.apple.dock")
    private static var sampledAt: TimeInterval = -.infinity
    private static var sampledFrames: [CGRect] = []

    static func visibleFrame(for screen: NSScreen) -> CGRect {
        adjustedFrame(
            visibleFrame: screen.visibleFrame,
            screenFrame: screen.frame,
            enabled: UserDefaults.standard.bool(forKey: DefaultsKey.windowReserveStageManagerSpace),
            stageManagerEnabled: windowManagerDefaults?.bool(forKey: "GloballyEnabled") == true,
            autoHide: windowManagerDefaults?.object(forKey: "AutoHide") as? Bool,
            dockPosition: dockDefaults?.string(forKey: "orientation"),
            rightToLeft: Locale.current.language.characterDirection == .rightToLeft,
            stripFrames: currentStripFrames())
    }

    static func adjustedFrame(visibleFrame: CGRect,
                              screenFrame: CGRect,
                              enabled: Bool,
                              stageManagerEnabled: Bool,
                              autoHide: Bool?,
                              dockPosition: String?,
                              rightToLeft: Bool = false,
                              stripFrames: @autoclosure () -> [CGRect]) -> CGRect {
        guard enabled, stageManagerEnabled, autoHide == false,
              visibleFrame.width > 80, visibleFrame.height > 0 else { return visibleFrame }
        let onRight = dockPosition == "left" || (dockPosition != "right" && rightToLeft)
        let candidates = stripFrames().filter { frame in
            guard !frame.isNull, !frame.isInfinite,
                  frame.width >= 16, frame.height >= 32,
                  frame.width <= screenFrame.width / 4,
                  frame.minY >= screenFrame.minY, frame.maxY <= screenFrame.maxY else { return false }
            let distance = onRight ? screenFrame.maxX - frame.maxX : frame.minX - screenFrame.minX
            return distance >= -1 && distance <= 24
        }
        let boundary: CGFloat
        if onRight {
            boundary = candidates.map(\.minX).min().map { $0 - 8 } ?? (screenFrame.maxX - 75)
        } else {
            boundary = candidates.map(\.maxX).max().map { $0 + 8 } ?? (screenFrame.minX + 75)
        }
        let inset = min(max(0, onRight ? visibleFrame.maxX - boundary : boundary - visibleFrame.minX),
                        visibleFrame.width - 80)
        return CGRect(x: visibleFrame.minX + (onRight ? 0 : inset), y: visibleFrame.minY,
                      width: visibleFrame.width - inset, height: visibleFrame.height)
    }

    static func stripFrames(from windows: [[String: Any]], screenTop: CGFloat) -> [CGRect] {
        windows.compactMap { window in
            guard window[kCGWindowOwnerName as String] as? String == "WindowManager",
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return CGRect(x: frame.minX, y: screenTop - frame.maxY,
                          width: frame.width, height: frame.height)
        }
    }

    private static func currentStripFrames() -> [CGRect] {
        let now = ProcessInfo.processInfo.systemUptime
        if now - sampledAt >= 0.25 {
            sampledAt = now
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                     kCGNullWindowID) as? [[String: Any]] ?? []
            sampledFrames = stripFrames(from: windows, screenTop: NSScreen.screens.first?.frame.maxY ?? 0)
        }
        return sampledFrames
    }
}

extension NSScreen {
    var windowLayoutVisibleFrame: CGRect { WindowStageManagerSupport.visibleFrame(for: self) }
}
