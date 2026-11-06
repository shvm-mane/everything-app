// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

enum SwitcherAppIconCache {
    private static let lock = NSLock()
    private static var icons: [pid_t: NSImage]?

    static func beginSession() {
        lock.withLock { icons = [:] }
    }

    static func endSession() {
        lock.withLock { icons = nil }
    }

    static func icon(for pid: pid_t) -> NSImage? {
        if let cached = lock.withLock({ icons?[pid] }) { return cached }
        guard let resolved = stableBundleIcon(pid: pid,
                                              appearance: NSApplication.shared.effectiveAppearance)
        else { return nil }
        lock.withLock { icons?[pid] = resolved }
        return resolved
    }

    static func declaredDockIconURL(bundleURL: URL,
                                    resourceName: String?,
                                    darkMode: Bool) -> URL? {
        guard let resourceName = resourceName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !resourceName.isEmpty,
              !resourceName.hasPrefix("/") else { return nil }
        let replacements: [(String, String)] = darkMode
            ? [("-light.", "-dark-color."), ("-light.", "-dark.")]
            : [("-dark-color.", "-light."), ("-dark.", "-light.")]
        let names = replacements.compactMap { source, destination in
            resourceName.contains(source)
                ? resourceName.replacingOccurrences(of: source, with: destination)
                : nil
        } + [resourceName]

        let resources = bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        let bundle = bundleURL.resolvingSymlinksInPath().standardizedFileURL
        guard resources.path.hasPrefix(bundle.path + "/") else { return nil }
        for name in names {
            let candidate = resources.appendingPathComponent(name)
                .resolvingSymlinksInPath().standardizedFileURL
            guard candidate.path.hasPrefix(resources.path + "/") else { continue }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               !isDirectory.boolValue {
                return candidate
            }
        }
        return nil
    }

    private static func stableBundleIcon(pid: pid_t, appearance: NSAppearance) -> NSImage? {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        let darkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let declaredIcon = app.bundleURL.flatMap { bundleURL -> NSImage? in
            guard let bundleIdentifier = app.bundleIdentifier,
                  let resourceName = CFPreferencesCopyAppValue(
                      "DockIconResourceName" as CFString,
                      bundleIdentifier as CFString
                  ) as? String,
                  let resourceURL = declaredDockIconURL(bundleURL: bundleURL,
                                                        resourceName: resourceName,
                                                        darkMode: darkMode)
            else { return nil }
            return NSImage(contentsOf: resourceURL)
        }
        let source = declaredIcon
            ?? app.bundleURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? app.icon
        guard let source else { return nil }
        return NSImage(size: source.size, flipped: false) { rect in
            appearance.performAsCurrentDrawingAppearance { source.draw(in: rect) }
            return true
        }
    }
}

enum WindowSwitchMinimizedPlacement: String, CaseIterable {
    case normal
    case end
    case hidden
}

struct SwitcherItem: Identifiable, Equatable {
    let id: String
    let title: String
    let appName: String
    let pid: pid_t
    let windowOwnerPID: pid_t
    let windowID: CGWindowID?
    let isOnScreen: Bool
    let isAppHidden: Bool
    let isMinimized: Bool
    let isFullscreen: Bool
    let isOnHiddenSpace: Bool
    let frame: CGRect

    var previewWindowID: CGWindowID? { windowID }

    var displayTitle: String {
        title.isEmpty ? appName : title
    }

    func windowLabel(noOpenWindow: String) -> String {
        isAppEntry ? noOpenWindow : displayTitle
    }

    func windowDetail(noOpenWindow: String) -> String? {
        if isAppEntry { return noOpenWindow }
        return displaySubtitle == nil ? nil : displayTitle
    }

    var displaySubtitle: String? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAppName.isEmpty,
              !cleanTitle.isEmpty,
              cleanTitle.caseInsensitiveCompare(cleanAppName) != .orderedSame
        else { return nil }
        return cleanAppName
    }

    var accessibilityTitle: String {
        if let displaySubtitle {
            return "\(displayTitle), \(displaySubtitle)"
        }
        return displayTitle
    }

    var isAppEntry: Bool { windowID == nil }

    func isMinimizedForPlacement(treatHiddenAppsLikeMinimized: Bool) -> Bool {
        isMinimized || (treatHiddenAppsLikeMinimized && isAppHidden)
    }

    func spokenLabel(noOpenWindow: String,
                     hiddenApp: String,
                     otherDesktop: String) -> String {
        var label = isAppEntry ? "\(appName), \(noOpenWindow)" : accessibilityTitle
        if isAppHidden { label += ", \(hiddenApp)" }
        if isOnHiddenSpace { label += ", \(otherDesktop)" }
        return label
    }

    var appIcon: NSImage? {
        SwitcherAppIconCache.icon(for: pid)
    }

    func withMinimized(_ minimized: Bool) -> SwitcherItem {
        SwitcherItem(id: id,
                     title: title,
                     appName: appName,
                     pid: pid,
                     windowOwnerPID: windowOwnerPID,
                     windowID: windowID,
                     isOnScreen: minimized ? false : true,
                     isAppHidden: isAppHidden,
                     isMinimized: minimized,
                     isFullscreen: isFullscreen,
                     isOnHiddenSpace: isOnHiddenSpace,
                     frame: frame)
    }

    func withHiddenSpaceState(_ hidden: Bool) -> SwitcherItem {
        SwitcherItem(id: id,
                     title: title,
                     appName: appName,
                     pid: pid,
                     windowOwnerPID: windowOwnerPID,
                     windowID: windowID,
                     isOnScreen: isOnScreen,
                     isAppHidden: isAppHidden,
                     isMinimized: isMinimized,
                     isFullscreen: isFullscreen,
                     isOnHiddenSpace: hidden,
                     frame: frame)
    }

    static func window(id: CGWindowID, title: String, appName: String, pid: pid_t,
                       windowOwnerPID: pid_t? = nil,
                       isOnScreen: Bool, isAppHidden: Bool = false,
                       isMinimized: Bool = false,
                       isFullscreen: Bool = false, frame: CGRect) -> SwitcherItem {
        SwitcherItem(id: "w:\(id)", title: title, appName: appName,
                     pid: pid, windowOwnerPID: windowOwnerPID ?? pid,
                     windowID: id, isOnScreen: isOnScreen,
                     isAppHidden: isAppHidden,
                     isMinimized: isMinimized, isFullscreen: isFullscreen,
                     isOnHiddenSpace: false,
                     frame: frame)
    }

    static func appOnly(appName: String, pid: pid_t,
                        isAppHidden: Bool = false) -> SwitcherItem {
        SwitcherItem(id: "a:\(pid)", title: appName, appName: appName,
                     pid: pid, windowOwnerPID: pid, windowID: nil, isOnScreen: false,
                     isAppHidden: isAppHidden,
                     isMinimized: false, isFullscreen: false,
                     isOnHiddenSpace: false, frame: .zero)
    }
}
