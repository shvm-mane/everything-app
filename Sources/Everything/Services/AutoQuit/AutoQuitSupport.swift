// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import Foundation

enum AutoQuitWindowEvent: Equatable {
    case windowDestroyed
    case appHidden
    case appDeactivated
    case appActivated
    case mainWindowChanged
    case focusedWindowChanged
    case windowCreated
    case windowDeminiaturized
    case appShown
    case other
}

enum AutoQuitSupport {
    private static let hostBundleIdentifierKey = "CrBundleIdentifier"
    private static let guestWindowHostBundleIdentifier = "com.parallels.desktop.console"
    private static let guestWindowBundleIdentifierPrefix = "com.parallels.winapp."

    static let commandWKeyCode: Int64 = 13

    static func shouldScheduleWindowCheck(for event: AutoQuitWindowEvent,
                                          hasRecentCloseRequest: Bool) -> Bool {
        switch event {
        case .windowDestroyed:
            return true
        case .appHidden:
            return hasRecentCloseRequest
        case .appDeactivated,
             .appActivated,
             .mainWindowChanged,
             .focusedWindowChanged,
             .windowCreated,
             .windowDeminiaturized,
             .appShown,
             .other:
            return false
        }
    }

    static func needsWindowWatchRetry(registeredWindows: Int,
                                      listedWindows: Int,
                                      foundUserWindow: Bool,
                                      hadPriorWindows: Bool = false) -> Bool {
        if foundUserWindow {
            return registeredWindows < max(listedWindows, 1)
        }
        return !hadPriorWindows && registeredWindows == 0
    }

    static func isWindowNotificationRegistered(_ result: AXError) -> Bool {
        result == .success || result == .notificationAlreadyRegistered
    }

    static func shouldQuitAfterWindowCheck(hadWindows: Bool,
                                           appIsTerminated: Bool,
                                           appIsExcepted: Bool,
                                           appIsHidden: Bool,
                                           hiddenByCloseRequest: Bool,
                                           hasKnownMinimizedWindow: Bool,
                                           hasUserFacingWindow: Bool) -> Bool {
        guard hadWindows, !appIsTerminated, !appIsExcepted else { return false }
        if appIsHidden && !hiddenByCloseRequest { return false }
        if hasKnownMinimizedWindow { return false }
        return !hasUserFacingWindow
    }

    static func isExcepted(bundleIdentifier: String?,
                           bundleURL: URL?,
                           exceptions: [String]) -> Bool {
        if let bundleIdentifier, exceptions.contains(bundleIdentifier) { return true }
        if let bundleIdentifier,
           bundleIdentifier.hasPrefix(guestWindowBundleIdentifierPrefix),
           exceptions.contains(guestWindowHostBundleIdentifier) {
            return true
        }
        guard var url = bundleURL?.standardizedFileURL.deletingLastPathComponent() else { return false }

        while url.path != "/" {
            if url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
               let containingIdentifier = Bundle(url: url)?.bundleIdentifier,
               exceptions.contains(containingIdentifier) {
                return true
            }
            let parent = url.deletingLastPathComponent()
            guard parent != url else { break }
            url = parent
        }
        return false
    }

    static func hasDependentApplication(hostBundleIdentifier: String?,
                                        applicationBundleURLs: [URL]) -> Bool {
        guard let hostBundleIdentifier, !hostBundleIdentifier.isEmpty else { return false }
        return applicationBundleURLs.contains { bundleURL in
            Bundle(url: bundleURL)?.object(forInfoDictionaryKey: hostBundleIdentifierKey) as? String
                == hostBundleIdentifier
        }
    }

    static func isQuitExempt(bundleIdentifier: String?,
                             bundleURL: URL?,
                             isInDock: Bool,
                             exceptions: [String],
                             dockApps: [String]) -> Bool {
        if isExcepted(bundleIdentifier: bundleIdentifier,
                      bundleURL: bundleURL,
                      exceptions: Defaults.mandatoryAutoQuitExceptionBundleIDs + exceptions) {
            return true
        }
        let allowsMenuBarQuit = bundleIdentifier.map { dockApps.contains($0) } ?? false
        return isBackgroundApp(bundleURL: bundleURL,
                               isInDock: isInDock,
                               allowsMenuBarQuit: allowsMenuBarQuit)
    }

    static func isBackgroundApp(bundleURL: URL?,
                                isInDock: Bool,
                                allowsMenuBarQuit: Bool = false) -> Bool {
        guard let bundleURL, let bundle = Bundle(url: bundleURL) else { return false }
        return bundleFlag("LSBackgroundOnly", in: bundle)
            || (bundleFlag("LSUIElement", in: bundle) && (!allowsMenuBarQuit || !isInDock))
    }

    static func canAllowMenuBarQuit(bundleURL: URL?) -> Bool {
        guard let bundleURL, let bundle = Bundle(url: bundleURL) else { return false }
        return bundleFlag("LSUIElement", in: bundle) && !bundleFlag("LSBackgroundOnly", in: bundle)
    }

    private static func bundleFlag(_ key: String, in bundle: Bundle) -> Bool {
        (bundle.object(forInfoDictionaryKey: key) as? NSNumber)?.boolValue
            ?? (bundle.object(forInfoDictionaryKey: key) as? NSString)?.boolValue
            ?? false
    }

    static func isCommandW(keyCode: Int64, command: Bool, control: Bool) -> Bool {
        keyCode == commandWKeyCode && command && !control
    }

    static func isWindowButtonOtherThanClose(subrole: String?) -> Bool {
        guard let subrole else { return false }
        return [kAXMinimizeButtonSubrole, kAXZoomButtonSubrole, kAXFullScreenButtonSubrole].contains(subrole)
    }

    static func shouldDisplayException(bundleID: String, isInstalled: Bool) -> Bool {
        if bundleID == Defaults.phoneBundleIdentifier { return isInstalled }
        return true
    }

    static func visibleExceptions(_ bundleIDs: [String],
                                  isInstalled: (String) -> Bool) -> [String] {
        bundleIDs.filter { shouldDisplayException(bundleID: $0, isInstalled: isInstalled($0)) }
    }

    enum WindowServerWindowRole: Equatable {
        case shownOnScreen
        case normalWindowOffScreen
        case unrelated
    }

    static func windowServerWindowRole(layer: Int,
                                       alpha: Double,
                                       width: Double,
                                       height: Double,
                                       isOnScreen: Bool,
                                       isAppsOwnWindow: Bool,
                                       countsEverythingShown: Bool) -> WindowServerWindowRole {
        guard alpha > 0, width >= 80, height >= 80 else { return .unrelated }
        if isAppsOwnWindow, layer == 0 {
            return isOnScreen ? .shownOnScreen : .normalWindowOffScreen
        }
        guard countsEverythingShown, isOnScreen, layer >= 0 else { return .unrelated }
        return .shownOnScreen
    }

    static func offscreenWindowKeepsAppAlive(windowSpaces: [UInt64]?,
                                             visibleSpaces: Set<UInt64>?) -> Bool {
        guard let windowSpaces else { return true }
        guard !windowSpaces.isEmpty else { return false }
        guard let visibleSpaces, !visibleSpaces.isEmpty else { return true }
        return SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: windowSpaces,
                                                     visibleSpaces: visibleSpaces)
    }

    static func windowListHasUserWindow(_ windows: [[String: Any]],
                                        pid: pid_t,
                                        countsEverythingShown: Bool,
                                        processDrawsForApp: (pid_t) -> Bool,
                                        windowIsMinimized: (CGWindowID) -> Bool?,
                                        visibleSpaces: () -> Set<UInt64>?,
                                        windowSpaces: (CGWindowID) -> [UInt64]?) -> Bool {
        var shownSpaces: Set<UInt64>?
        var askedForVisibleSpaces = false
        var drawsForApp: [pid_t: Bool] = [:]

        for window in windows {
            guard let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == pid || countsEverythingShown,
                  let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue else { continue }
            let isOnScreen = (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue
                ?? (window[kCGWindowIsOnscreen as String] as? Bool)
                ?? false
            let role = windowServerWindowRole(
                layer: layer,
                alpha: (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                width: width,
                height: height,
                isOnScreen: isOnScreen,
                isAppsOwnWindow: ownerPID == pid,
                countsEverythingShown: countsEverythingShown)
            if role == .shownOnScreen {
                if ownerPID == pid { return true }
                if drawsForApp[ownerPID] == nil {
                    drawsForApp[ownerPID] = processDrawsForApp(ownerPID)
                }
                if drawsForApp[ownerPID] == true { return true }
                continue
            }
            guard role == .normalWindowOffScreen,
                  let windowID = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            if windowIsMinimized(CGWindowID(windowID)) != false { return true }
            if !askedForVisibleSpaces {
                shownSpaces = visibleSpaces()
                askedForVisibleSpaces = true
            }
            if offscreenWindowKeepsAppAlive(
                windowSpaces: windowSpaces(CGWindowID(windowID)),
                visibleSpaces: shownSpaces) {
                return true
            }
        }
        return false
    }
}
