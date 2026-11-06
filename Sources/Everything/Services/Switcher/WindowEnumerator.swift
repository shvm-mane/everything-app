// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics

enum WindowEnumerator {
    struct DisplayScope: Sendable {
        let bounds: [CGRect]
        let targetIndex: Int
    }

    struct WindowList {
        let items: [SwitcherItem]
        let sourceItems: [SwitcherItem]
    }

    struct AppSnapshot: Sendable {
        let pid: pid_t
        let bundleIdentifier: String?
        let localizedName: String?
        let isRegular: Bool
        let isHidden: Bool
        let bundlePath: String?
        let executablePath: String?
    }

    struct Snapshot: Sendable {
        let accessibilityGranted: Bool
        let runningApps: [AppSnapshot]
        let ownWindowTitles: [CGWindowID: String]
        let screenFrames: [CGRect]
        let displayIDsByUUID: [String: CGDirectDisplayID]
    }

    private static let minimumSize = CGSize(width: 80, height: 60)
    private static let maximumCount = 48
    private static let messagingTimeout: Float = 0.2
    private static let maximumConcurrentQueries = 24
    private static let accessibilityQueryQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInteractive
        queue.maxConcurrentOperationCount = maximumConcurrentQueries
        return queue
    }()
    private static let accessibilityBatchBudget: TimeInterval = 5.0

    static func snapshot() -> Snapshot {
        dispatchPrecondition(condition: .onQueue(.main))
        let runningApps = NSWorkspace.shared.runningApplications.compactMap { app -> AppSnapshot? in
            guard !app.isTerminated else { return nil }
            return AppSnapshot(pid: app.processIdentifier,
                               bundleIdentifier: app.bundleIdentifier,
                               localizedName: app.localizedName,
                               isRegular: app.activationPolicy == .regular,
                               isHidden: app.isHidden,
                               bundlePath: app.bundleURL?.path,
                               executablePath: app.executableURL?.path)
        }
        var ownWindowTitles: [CGWindowID: String] = [:]
        for window in NSApp.windows {
            guard window.windowNumber > 0,
                  let windowID = CGWindowID(exactly: window.windowNumber),
                  window.styleMask.contains(.titled),
                  window.canBecomeKey,
                  window.isVisible || window.isMiniaturized
            else { continue }
            guard ownWindowTitles[windowID] == nil else { continue }
            ownWindowTitles[windowID] = window.title.isEmpty ? AppInfo.name : window.title
        }
        return Snapshot(accessibilityGranted: Permissions.shared.accessibility,
                        runningApps: runningApps,
                        ownWindowTitles: ownWindowTitles,
                        screenFrames: NSScreen.screens.map(\.frame),
                        displayIDsByUUID: SpaceWindowBridge.displayIDsByUUID())
    }

    static func enumerateSwitcherWindows(groupByApp: Bool,
                                         preservingGroupedWindows: Bool,
                                         snapshot: Snapshot,
                                         windowsOnly: Bool = false,
                                         displayScope: DisplayScope? = nil,
                                         scopedToFrontmostPID: pid_t? = nil,
                                         resolveSource: (([SwitcherItem]) -> SwitcherItem?)? = nil,
                                         isCancelled: @escaping () -> Bool = { false }) -> WindowList {
        listWindows(
            appRules: SwitcherAppRule.rules(
                storedValue: UserDefaults.standard.dictionary(forKey: DefaultsKey.switcherAppRules)),
            groupByApp: groupByApp,
            preservingGroupedWindows: preservingGroupedWindows,
            marksHiddenSpaces: true,
            includesFullscreenAcrossSpaces: true,
            snapshot: snapshot,
            windowsOnly: windowsOnly,
            displayScope: displayScope,
            scopedToFrontmostPID: scopedToFrontmostPID,
            resolveSource: resolveSource,
            isCancelled: isCancelled
        )
    }

    static func listWindowsForCommandBar(snapshot: Snapshot) -> [SwitcherItem] {
        listWindows(appRules: [:], groupByApp: false,
                    preservingGroupedWindows: false, marksHiddenSpaces: false,
                    snapshot: snapshot).items
    }

    private static func listWindows(appRules: [String: SwitcherAppRule],
                                    groupByApp: Bool,
                                    preservingGroupedWindows: Bool,
                                    marksHiddenSpaces: Bool,
                                    includesFullscreenAcrossSpaces: Bool = false,
                                    snapshot: Snapshot,
                                    windowsOnly: Bool = false,
                                    displayScope: DisplayScope? = nil,
                                    scopedToFrontmostPID: pid_t? = nil,
                                    resolveSource: (([SwitcherItem]) -> SwitcherItem?)? = nil,
                                    isCancelled: @escaping () -> Bool = { false }) -> WindowList {
        let windowlessApps = SwitcherWindowlessApps.mode(
            storedValue: UserDefaults.standard.string(forKey: DefaultsKey.switcherWindowlessApps),
            takeOverSystemShortcuts: UserDefaults.standard.bool(
                forKey: DefaultsKey.switcherTakeOverSystemShortcuts))
        let currentSpaceOnly = UserDefaults.standard.bool(forKey: DefaultsKey.switcherCurrentSpaceOnly)
        let minimizedPlacement = WindowSwitchMinimizedPlacement(
            rawValue: UserDefaults.standard.string(forKey: DefaultsKey.switcherMinimizedPlacement) ?? ""
        ) ?? .normal
        let treatHiddenAppsLikeMinimized = UserDefaults.standard.bool(
            forKey: DefaultsKey.switcherTreatHiddenAppsLikeMinimized)
        let showFullscreenWindows = UserDefaults.standard.object(forKey: DefaultsKey.switcherShowFullscreenWindows) as? Bool ?? true
        return listWindows(filterPID: nil,
                           maximumCount: maximumCount,
                           windowlessApps: windowlessApps,
                           appRules: appRules,
                           groupByApp: groupByApp,
                           minimizedPlacement: minimizedPlacement,
                           treatHiddenAppsLikeMinimized: treatHiddenAppsLikeMinimized,
                           showFullscreenWindows: showFullscreenWindows,
                           preservingGroupedWindows: preservingGroupedWindows,
                           currentSpaceOnly: currentSpaceOnly,
                           includesFullscreenAcrossSpaces: includesFullscreenAcrossSpaces && showFullscreenWindows,
                           marksHiddenSpaces: marksHiddenSpaces,
                           snapshot: snapshot,
                           windowsOnly: windowsOnly,
                           scopedToFrontmostPID: scopedToFrontmostPID,
                           displayScope: displayScope,
                           resolveSource: resolveSource,
                           isCancelled: isCancelled)
    }

    static func listWindowsForDockPreview(for pid: pid_t, maximumCount: Int = 12) -> [SwitcherItem] {
        listWindows(for: pid, maximumCount: maximumCount,
                    currentSpaceOnly: UserDefaults.standard.bool(forKey: DefaultsKey.dockPreviewCurrentSpaceOnly),
                    marksHiddenSpaces: true)
    }

    static func dockPreviewMayActivate(_ item: SwitcherItem) -> Bool {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.dockPreviewCurrentSpaceOnly),
              let windowID = item.windowID else { return true }
        return !SpaceWindowBridge.isParkedOnHiddenSpace(windowID)
    }

    static func listWindows(for pid: pid_t, maximumCount: Int = 12,
                            currentSpaceOnly: Bool = false,
                            marksHiddenSpaces: Bool = false) -> [SwitcherItem] {
        listWindows(for: pid, maximumCount: maximumCount,
                    currentSpaceOnly: currentSpaceOnly,
                    marksHiddenSpaces: marksHiddenSpaces,
                    snapshot: snapshot())
    }

    static func listWindows(for pid: pid_t, maximumCount: Int = 12,
                            currentSpaceOnly: Bool = false,
                            marksHiddenSpaces: Bool = false,
                            snapshot: Snapshot) -> [SwitcherItem] {
        listWindows(filterPID: pid,
                    maximumCount: maximumCount,
                    windowlessApps: .off,
                    appRules: [:],
                    groupByApp: false,
                    minimizedPlacement: .normal,
                    treatHiddenAppsLikeMinimized: false,
                    showFullscreenWindows: true,
                    preservingGroupedWindows: false,
                    currentSpaceOnly: currentSpaceOnly,
                    marksHiddenSpaces: marksHiddenSpaces && !currentSpaceOnly,
                    snapshot: snapshot).items
    }

    private static func listWindows(filterPID: pid_t?,
                                    maximumCount: Int,
                                    windowlessApps: SwitcherWindowlessApps,
                                    appRules: [String: SwitcherAppRule],
                                    groupByApp: Bool,
                                    minimizedPlacement: WindowSwitchMinimizedPlacement,
                                    treatHiddenAppsLikeMinimized: Bool,
                                    showFullscreenWindows: Bool,
                                    preservingGroupedWindows: Bool,
                                    currentSpaceOnly: Bool,
                                    includesFullscreenAcrossSpaces: Bool = false,
                                    marksHiddenSpaces: Bool,
                                    snapshot: Snapshot,
                                    windowsOnly: Bool = false,
                                    scopedToFrontmostPID: pid_t? = nil,
                                    displayScope: DisplayScope? = nil,
                                    resolveSource: (([SwitcherItem]) -> SwitcherItem?)? = nil,
                                    isCancelled: @escaping () -> Bool = { false }) -> WindowList {
        guard !isCancelled() else { return WindowList(items: [], sourceItems: []) }
        let historyRevision = WindowUseTracker.shared.historyRevision
        let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []

        let ownPid = ProcessInfo.processInfo.processIdentifier
        let normalLevelWindowIDs = Set(raw.compactMap { info -> CGWindowID? in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else { return nil }
            return (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        })
        let windowOwnerPIDs = raw.compactMap { info -> pid_t? in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 else { return nil }
            return (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
        }
        let runningApps = SwitcherSupport.usableApps(
            snapshot.runningApps,
            windowOwnerPIDs: windowOwnerPIDs,
            pid: \.pid,
            isRegular: \.isRegular,
            resolve: { pid in
                guard let app = NSRunningApplication(processIdentifier: pid),
                      !app.isTerminated else { return nil }
                return AppSnapshot(pid: pid,
                                   bundleIdentifier: app.bundleIdentifier,
                                   localizedName: app.localizedName,
                                   isRegular: app.activationPolicy == .regular,
                                   isHidden: app.isHidden,
                                   bundlePath: app.bundleURL?.path,
                                   executablePath: app.executableURL?.path)
            })
        let hiddenAppPIDs = Set(runningApps.lazy
            .filter { $0.isHidden }
            .map(\.pid))
        let bundleIdentifiers = SwitcherSupport.firstValuesByPID(runningApps.compactMap { app in
            app.bundleIdentifier.map { (app.pid, $0) }
        })
        let frontToBack = WindowUseTracker.frontToBack()
        WindowUseTracker.shared.reconcile(
            existingWindows: Set(raw.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }),
            frontToBack: frontToBack,
            running: Set(runningApps.map(\.pid)), revision: historyRevision)
        var regularApps: [pid_t: String] = [:]
        var regularBundlePaths: [pid_t: String] = [:]
        for app in runningApps where app.isRegular {
            regularApps[app.pid] = app.localizedName ?? ""
            if let path = app.bundlePath {
                regularBundlePaths[app.pid] = path
            }
        }
        regularApps[pid_t(ownPid)] = AppInfo.name
        var compatibilityLayerPids: Set<pid_t> = []
        for app in runningApps where SwitcherSupport.isCompatibilityLayerApp(
            bundleIdentifier: app.bundleIdentifier,
            executablePath: app.executablePath,
            localizedName: app.localizedName) {
            compatibilityLayerPids.insert(app.pid)
            if regularApps[app.pid] == nil {
                regularApps[app.pid] = app.localizedName ?? ""
            }
        }
        let embeddedHostPairs: [(pid_t, pid_t)] = runningApps.compactMap { app in
            guard !app.isRegular,
                  let helperPath = app.bundlePath,
                  let hostPID = SwitcherSupport.embeddedHostPID(helperBundlePath: helperPath,
                                                               regularBundlePaths: regularBundlePaths)
            else { return nil }
            return (app.pid, hostPID)
        }
        let embeddedHostPIDs = SwitcherSupport.firstValuesByPID(embeddedHostPairs)
        let accessibilityPids = SwitcherSupport.accessibilityPIDs(
            regularAppPIDs: Set(regularApps.keys),
            embeddedHostPIDs: embeddedHostPIDs,
            ownPID: pid_t(ownPid),
            filterPID: filterPID)
        let accessibilityWindows = accessibilityWindows(for: accessibilityPids,
                                                        bundleIdentifiers: bundleIdentifiers,
                                                        undescribedSubrolePids: compatibilityLayerPids,
                                                        accessibilityGranted: snapshot.accessibilityGranted,
                                                        normalLevelWindowIDs: normalLevelWindowIDs,
                                                        screenFrames: snapshot.screenFrames,
                                                        isCancelled: isCancelled)
        guard !isCancelled() else { return WindowList(items: [], sourceItems: []) }

        var seen = Set<CGWindowID>()
        var windows: [SwitcherItem] = []
        var withheldPIDs = Set<pid_t>()

        var topologyResolved = false
        var topology: SpaceWindowBridge.Topology?
        var windowSpaces: [CGWindowID: [UInt64]] = [:]
        var hiddenSpaceVerdicts: [CGWindowID: Bool] = [:]
        var fullscreenSpaceVerdicts: [CGWindowID: Bool] = [:]
        func resolvedTopology() -> SpaceWindowBridge.Topology? {
            if !topologyResolved {
                topology = SpaceWindowBridge.topology(displayIDsByUUID: snapshot.displayIDsByUUID)
                topologyResolved = true
            }
            return topology
        }
        func spaces(of windowID: CGWindowID) -> [UInt64] {
            if let cached = windowSpaces[windowID] { return cached }
            let resolved = SpaceWindowBridge.spaces(of: windowID)
            windowSpaces[windowID] = resolved
            return resolved
        }
        func isOnHiddenSpace(_ windowID: CGWindowID) -> Bool {
            if let verdict = hiddenSpaceVerdicts[windowID] { return verdict }
            guard let visible = resolvedTopology()?.visibleSpaces, !visible.isEmpty else { return false }
            let verdict = SpaceHopSupport.isParkedOnHiddenSpace(
                windowSpaces: spaces(of: windowID),
                visibleSpaces: visible
            )
            hiddenSpaceVerdicts[windowID] = verdict
            return verdict
        }
        func isOnFullscreenSpace(_ windowID: CGWindowID) -> Bool {
            if let verdict = fullscreenSpaceVerdicts[windowID] { return verdict }
            guard let fullscreen = resolvedTopology()?.fullscreenSpaces, !fullscreen.isEmpty else {
                return false
            }
            let verdict = SpaceHopSupport.isOnFullscreenSpace(
                windowSpaces: spaces(of: windowID),
                fullscreenSpaces: fullscreen
            )
            fullscreenSpaceVerdicts[windowID] = verdict
            return verdict
        }
        var hiddenWithAppResolved = false
        var hiddenWithAppWindowIDs: Set<CGWindowID>?
        func isHiddenWithApp(_ windowID: CGWindowID) -> Bool? {
            if !hiddenWithAppResolved {
                hiddenWithAppWindowIDs = SpaceWindowBridge.windowsHiddenWithApp(among: Array(normalLevelWindowIDs))
                hiddenWithAppResolved = true
            }
            return hiddenWithAppWindowIDs.map { $0.contains(windowID) }
        }
        var hiddenSpaceTitles: [pid_t: [CGWindowID: String]] = [:]
        let hiddenSpaceTitleDeadline = ProcessInfo.processInfo.systemUptime + AXWindowResolver.remoteLookupBudget
        func hiddenSpaceTitle(of windowID: CGWindowID, ownerPID: pid_t) -> String {
            if hiddenSpaceTitles[ownerPID] == nil {
                hiddenSpaceTitles[ownerPID] = [:]
                guard !isCancelled(), ProcessInfo.processInfo.systemUptime < hiddenSpaceTitleDeadline else { return "" }
                let parked = Set(raw.compactMap { info -> CGWindowID? in
                    guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == ownerPID,
                          (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                          let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                          isOnHiddenSpace(CGWindowID(id)) else { return nil }
                    return CGWindowID(id)
                })
                let elements = AXWindowResolver
                    .elementsOnHiddenSpace(windowIDs: parked, pid: ownerPID,
                                           budget: hiddenSpaceTitleDeadline - ProcessInfo.processInfo.systemUptime,
                                           isCancelled: isCancelled)
                var titles: [CGWindowID: String] = [:]
                for (id, element) in elements {
                    guard !isCancelled(), ProcessInfo.processInfo.systemUptime < hiddenSpaceTitleDeadline else { break }
                    guard AXWindowResolver.prepareForRequest(element, deadline: hiddenSpaceTitleDeadline) else { continue }
                    titles[id] = accessibilityTitle(for: element)
                }
                hiddenSpaceTitles[ownerPID] = titles
            }
            return hiddenSpaceTitles[ownerPID]?[windowID] ?? ""
        }
        func excludeForSpaceScope(_ windowID: CGWindowID, appPID: pid_t,
                                  isNativeFullscreen: Bool) -> Bool {
            guard currentSpaceOnly, isOnHiddenSpace(windowID) else { return false }
            if includesFullscreenAcrossSpaces,
               isNativeFullscreen || isOnFullscreenSpace(windowID) { return false }
            withheldPIDs.insert(appPID)
            return true
        }

        for info in raw {
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0,
                  let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  !seen.contains(windowID),
                  let windowOwnerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any]
            else { continue }
            let appPID = regularApps[windowOwnerPID] != nil
                ? windowOwnerPID
                : embeddedHostPIDs[windowOwnerPID]
            guard let appPID else { continue }
            if let filterPID, appPID != filterPID { continue }
            if SwitcherSupport.hidesApp(bundleIdentifier: bundleIdentifiers[appPID],
                                        appRules: appRules) { continue }
            let axSnapshot = accessibilityWindows[windowOwnerPID]
            let axWindow = axSnapshot?.byID[CGWindowID(windowID)]
            if excludeForSpaceScope(windowID, appPID: appPID,
                                    isNativeFullscreen: axWindow?.isNativeFullscreen ?? false) { continue }
            let isAppHidden = hiddenAppPIDs.contains(appPID)
            let isOnScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue
                ?? (info[kCGWindowIsOnscreen as String] as? Bool)
                ?? false
            let isConfirmedHiddenAppWindow = isAppHidden
                && SwitcherSupport.isConfirmedHiddenAppWindow(
                    appIsHidden: isAppHidden,
                    windowSpaces: spaces(of: CGWindowID(windowID)),
                    isHiddenWithApp: isHiddenWithApp(CGWindowID(windowID)))
            let hiddenSpaceSurfaceIsWitnessed = isOnHiddenSpace(CGWindowID(windowID))
            let witness = axSnapshot.map {
                SwitcherSupport.accessibilityWitness(
                    isDescribed: axWindow != nil,
                    isUnanswered: $0.everyWindowUnanswered || $0.unansweredIDs.contains(CGWindowID(windowID)))
            }
            guard SwitcherSupport.keepsSurface(
                witness: witness,
                keepsUnmatched: {
                    SwitcherSupport.keepsUnmatchedWindow(
                        isOnHiddenSpace: hiddenSpaceSurfaceIsWitnessed,
                        isConfirmedHiddenAppWindow: isConfirmedHiddenAppWindow,
                        isExcludedFromWindowCycle: SpaceWindowBridge.isExcludedFromWindowCycle(CGWindowID(windowID)),
                        isOrderedIn: hiddenSpaceSurfaceIsWitnessed && !isConfirmedHiddenAppWindow
                            ? SpaceWindowBridge.isWindowOrderedIn(CGWindowID(windowID)) : nil,
                        allowsUnverifiedHiddenSpace: axSnapshot?.ordered.isEmpty == true
                            || isOnFullscreenSpace(CGWindowID(windowID)))
                },
                isExcludedFromWindowCycle: {
                    SpaceWindowBridge.isExcludedFromWindowCycle(CGWindowID(windowID))
                },
                isLeftover: {
                    SwitcherSupport.unwitnessedSurfaceIsLeftover(
                        isOnScreen: isOnScreen,
                        canResolveSpaces: SpaceWindowBridge.canResolveSpaces,
                        windowSpacesCount: spaces(of: CGWindowID(windowID)).count)
                }) else { continue }
            let cgFrame = CGRect(x: (boundsDict["X"] as? NSNumber)?.doubleValue ?? 0,
                                 y: (boundsDict["Y"] as? NSNumber)?.doubleValue ?? 0,
                                 width: (boundsDict["Width"] as? NSNumber)?.doubleValue ?? 0,
                                 height: (boundsDict["Height"] as? NSNumber)?.doubleValue ?? 0)
            let isMinimized = axWindow?.isMinimized ?? false
            let isFullscreen = (axWindow?.isFullscreen ?? false)
                || (axWindow == nil && isOnFullscreenSpace(CGWindowID(windowID)))
                || frameLooksFullscreen(cgFrame, screenFrames: snapshot.screenFrames)
            guard let frame = switchableFrame(cgFrame, fallback: axWindow?.frame, isMinimized: isMinimized) else {
                continue
            }

            if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
               alpha == 0, !isMinimized, !isConfirmedHiddenAppWindow {
                continue
            }

            let title = info[kCGWindowName as String] as? String ?? ""

            let appName: String
            let displayTitle: String
            if windowOwnerPID == ownPid {
                guard let title = snapshot.ownWindowTitles[windowID] else { continue }
                appName = AppInfo.name
                displayTitle = title
            } else {
                guard let name = regularApps[appPID] else { continue }
                appName = name
                if SwitcherSupport.looksUpHiddenSpaceTitle(windowServerTitle: title,
                                                           isDescribedByAccessibility: axWindow != nil,
                                                           accessibilityGranted: snapshot.accessibilityGranted,
                                                           isOnHiddenSpace: hiddenSpaceSurfaceIsWitnessed) {
                    displayTitle = hiddenSpaceTitle(of: CGWindowID(windowID), ownerPID: windowOwnerPID)
                } else {
                    displayTitle = title.isEmpty ? (axWindow?.title ?? "") : title
                }
            }

            if !isOnScreen && displayTitle.isEmpty && axWindow == nil
                && !hiddenSpaceSurfaceIsWitnessed && !isConfirmedHiddenAppWindow { continue }

            seen.insert(windowID)
            windows.append(.window(id: windowID,
                                   title: displayTitle,
                                   appName: appName,
                                   pid: appPID,
                                   windowOwnerPID: windowOwnerPID,
                                   isOnScreen: isOnScreen,
                                   isAppHidden: isAppHidden,
                                   isMinimized: isMinimized,
                                   isFullscreen: isFullscreen,
                                   frame: frame))
        }
        appendAccessibilityOnlyWindows(to: &windows,
                                       snapshots: accessibilityWindows,
                                       regularApps: regularApps,
                                       embeddedHostPIDs: embeddedHostPIDs,
                                       hiddenAppPIDs: hiddenAppPIDs,
                                       seen: &seen,
                                       filterPID: filterPID,
                                       excludeWindow: { windowID, appPID, isNativeFullscreen in
                                           if SwitcherSupport.hidesApp(
                                               bundleIdentifier: bundleIdentifiers[appPID],
                                               appRules: appRules) { return true }
                                           return excludeForSpaceScope(windowID, appPID: appPID,
                                                                       isNativeFullscreen: isNativeFullscreen)
                                       })
        appendWindowlessApps(to: &windows,
                             mode: windowlessApps,
                             runningApps: runningApps,
                             regularApps: regularApps,
                             accessibilityWindows: accessibilityWindows,
                             ownPID: pid_t(ownPid),
                             withheldPIDs: withheldPIDs,
                             appRules: appRules)
        let affectedByMinimizedPlacement = { (item: SwitcherItem) in
            item.isMinimizedForPlacement(treatHiddenAppsLikeMinimized: treatHiddenAppsLikeMinimized)
        }
        let filtered = windows.filter { item in
            if windowsOnly, item.isAppEntry { return false }
            if !showFullscreenWindows, item.isFullscreen { return false }
            if minimizedPlacement == .hidden, affectedByMinimizedPlacement(item) { return false }
            return true
        }
        let sourceItems = displayScope.map { _ in orderByUse(filtered, frontToBack: frontToBack) }
        let scoped = displayScope.map {
            SwitcherSupport.itemsOnDisplay(filtered, displayBounds: $0.bounds, targetIndex: $0.targetIndex)
        } ?? filtered
        let groupedBackingWindows = groupByApp && preservingGroupedWindows ? scoped : []
        func groupedByApp(_ items: [SwitcherItem]) -> [SwitcherItem] {
            SwitcherSupport.groupWindowsByApp(items, isOnHiddenSpace: { item in
                guard currentSpaceOnly, let windowID = item.windowID else { return false }
                return isOnHiddenSpace(windowID)
            })
        }
        var ordered: [SwitcherItem]
        if minimizedPlacement == .end {
            let primary = scoped.filter { !affectedByMinimizedPlacement($0) }
            let deferred = scoped.filter { affectedByMinimizedPlacement($0) }
            let orderedPrimary = orderByUse(primary, frontToBack: frontToBack)
            let orderedDeferred = orderByUse(deferred, frontToBack: frontToBack)
            let groupedPrimary = groupByApp ? groupedByApp(orderedPrimary) : orderedPrimary
            let groupedDeferred = groupByApp ? groupedByApp(orderedDeferred) : orderedDeferred
            ordered = groupedPrimary + groupedDeferred
        } else {
            let orderedRaw = orderByUse(scoped, frontToBack: frontToBack)
            ordered = groupByApp ? groupedByApp(orderedRaw) : orderedRaw
        }
        let backingOrdered: [SwitcherItem]
        if groupByApp, preservingGroupedWindows {
            if minimizedPlacement == .end {
                let primary = groupedBackingWindows.filter { !affectedByMinimizedPlacement($0) }
                let deferred = groupedBackingWindows.filter { affectedByMinimizedPlacement($0) }
                backingOrdered = orderByUse(primary, frontToBack: frontToBack) + orderByUse(deferred, frontToBack: frontToBack)
            } else {
                backingOrdered = orderByUse(groupedBackingWindows, frontToBack: frontToBack)
            }
        } else {
            backingOrdered = []
        }
        let sourceCandidates = sourceItems ?? (backingOrdered.isEmpty ? ordered
            : SwitcherSupport.expandGroupedWindows(orderedWindows: backingOrdered, representatives: ordered))
        guard !isCancelled() else { return WindowList(items: [], sourceItems: []) }
        let source = ordered.isEmpty ? nil : resolveSource?(sourceCandidates)
        guard !isCancelled() else { return WindowList(items: [], sourceItems: []) }
        ordered = SwitcherSupport.orderedForSession(ordered, currentID: source?.id)
        var result = ordered
        if ordered.count > maximumCount {
            result = SwitcherSupport
                .visibleSelectionIndices(items: ordered, limit: maximumCount,
                                         frontmostPID: scopedToFrontmostPID)
                .map { ordered[$0] }
            if windowlessApps == .finder,
               !result.contains(where: { $0.windowID == nil }),
               let desktopEntry = ordered.first(where: { $0.windowID == nil }) {
                result.append(desktopEntry)
            }
        }
        if groupByApp, preservingGroupedWindows {
            result = SwitcherSupport.expandGroupedWindows(
                orderedWindows: backingOrdered,
                representatives: result)
        }
        if marksHiddenSpaces {
            result = result.map { window in
                guard let windowID = window.windowID else { return window }
                return window.withHiddenSpaceState(isOnHiddenSpace(windowID))
            }
        }
        return WindowList(items: result, sourceItems: sourceCandidates)
    }

    private struct AccessibilityWindowSnapshot {
        let title: String
        let frame: CGRect?
        let isMinimized: Bool
        let isFullscreen: Bool
        let isNativeFullscreen: Bool
    }

    private struct AccessibilityWindowSnapshotList {
        let ordered: [(id: CGWindowID, snapshot: AccessibilityWindowSnapshot)]
        let byID: [CGWindowID: AccessibilityWindowSnapshot]
        var unansweredIDs: Set<CGWindowID> = []
        var everyWindowUnanswered = false
    }

    private struct AccessibilityWindowAttributes {
        enum Attribute: Int, CaseIterable {
            case role, subrole, fullscreen, minimized, position, size, title

            var name: String {
                switch self {
                case .role: return kAXRoleAttribute as String
                case .subrole: return kAXSubroleAttribute as String
                case .fullscreen: return "AXFullScreen"
                case .minimized: return kAXMinimizedAttribute as String
                case .position: return kAXPositionAttribute as String
                case .size: return kAXSizeAttribute as String
                case .title: return kAXTitleAttribute as String
                }
            }
        }

        let values: [Any]
        let result: AXError

        init(_ window: AXUIElement) {
            var values: CFArray?
            result = AXUIElementCopyMultipleAttributeValues(
                window, Attribute.allCases.map(\.name) as CFArray, [], &values)
            self.values = values as? [Any] ?? []
        }

        func error(for attribute: Attribute) -> AXError {
            guard result == .success else { return result }
            guard values.indices.contains(attribute.rawValue) else { return .noValue }
            let value = values[attribute.rawValue] as CFTypeRef
            if CFGetTypeID(value) == CFNullGetTypeID() { return .noValue }
            if CFGetTypeID(value) == AXValueGetTypeID() {
                let axValue = value as! AXValue
                if AXValueGetType(axValue) == .axError {
                    var error = AXError.failure
                    AXValueGetValue(axValue, .axError, &error)
                    return error
                }
            }
            return .success
        }

        func value(_ attribute: Attribute) -> Any? {
            guard error(for: attribute) == .success else { return nil }
            return values[attribute.rawValue]
        }

        func string(_ attribute: Attribute) -> String? {
            value(attribute) as? String
        }

        func bool(_ attribute: Attribute) -> Bool {
            value(attribute) as? Bool ?? false
        }

        var frame: CGRect? {
            guard let positionValue = value(.position), let sizeValue = value(.size),
                  CFGetTypeID(positionValue as CFTypeRef) == AXValueGetTypeID(),
                  CFGetTypeID(sizeValue as CFTypeRef) == AXValueGetTypeID()
            else { return nil }
            var position = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
                  AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            else { return nil }
            return CGRect(origin: position, size: size)
        }

        var isNativeFullscreen: Bool {
            bool(.fullscreen) || string(.subrole) == "AXFullScreenWindow"
        }
    }

    private enum WindowReading {
        case userFacing
        case notUserFacing
        case unanswered
    }

    private static func accessibilityWindows(for pids: Set<pid_t>,
                                             bundleIdentifiers: [pid_t: String] = [:],
                                             undescribedSubrolePids: Set<pid_t> = [],
                                             accessibilityGranted: Bool,
                                             normalLevelWindowIDs: Set<CGWindowID>,
                                             screenFrames: [CGRect],
                                             isCancelled: @escaping () -> Bool = { false }) -> [pid_t: AccessibilityWindowSnapshotList] {
        guard accessibilityGranted, !isCancelled() else { return [:] }

        let orderedPIDs = pids.sorted()
        guard !orderedPIDs.isEmpty else { return [:] }
        var result: [pid_t: AccessibilityWindowSnapshotList] = [:]
        var pendingQueries = orderedPIDs.count
        let resultLock = NSCondition()
        var operations: [BlockOperation] = []
        for pid in orderedPIDs {
            let operation = BlockOperation()
            operation.addExecutionBlock { [weak operation] in
                guard let operation, !operation.isCancelled else { return }
                defer {
                    resultLock.lock()
                    pendingQueries -= 1
                    if pendingQueries == 0 { resultLock.broadcast() }
                    resultLock.unlock()
                }
                let windows = accessibilityWindows(
                    for: pid,
                    bundleIdentifier: bundleIdentifiers[pid],
                    acceptsUndescribedSubroles: undescribedSubrolePids.contains(pid),
                    normalLevelWindowIDs: normalLevelWindowIDs,
                    screenFrames: screenFrames,
                    isCancelled: { operation.isCancelled || isCancelled() }
                )
                resultLock.lock()
                if let windows { result[pid] = windows }
                resultLock.unlock()
            }
            operations.append(operation)
            accessibilityQueryQueue.addOperation(operation)
        }
        let deadline = Date(timeIntervalSinceNow: accessibilityBatchBudget)
        resultLock.lock()
        while pendingQueries > 0, !isCancelled() {
            let nextCancellationCheck = min(deadline, Date(timeIntervalSinceNow: 0.01))
            guard resultLock.wait(until: nextCancellationCheck) else {
                if nextCancellationCheck >= deadline { break }
                continue
            }
        }
        let incompleteBatch = pendingQueries > 0
        let collected = result
        resultLock.unlock()
        if incompleteBatch {
            for operation in operations { operation.cancel() }
        }
        return collected
    }

    private static func accessibilityWindows(for pid: pid_t,
                                             bundleIdentifier: String? = nil,
                                             acceptsUndescribedSubroles: Bool = false,
                                             normalLevelWindowIDs: Set<CGWindowID>,
                                             screenFrames: [CGRect],
                                             isCancelled: () -> Bool) -> AccessibilityWindowSnapshotList? {
        guard !isCancelled() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        var axWindows: [AXUIElement] = []
        var value: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        guard !isCancelled() else { return nil }
        guard windowsResult != .cannotComplete else { return nil }
        var unansweredWindows: [AXUIElement] = []
        var readWindows: [AXUIElement] = []
        var byID: [CGWindowID: AccessibilityWindowSnapshot] = [:]
        var ordered: [(id: CGWindowID, snapshot: AccessibilityWindowSnapshot)] = []
        func read(_ window: AXUIElement) -> WindowReading {
            guard !contains(window, in: readWindows) else { return .notUserFacing }
            readWindows.append(window)
            AXUIElementSetMessagingTimeout(window, 0.35)
            let attributes = AccessibilityWindowAttributes(window)
            let reading = userFacingReading(of: window,
                                            attributes: attributes,
                                            bundleIdentifier: bundleIdentifier,
                                            acceptsUndescribedSubroles: acceptsUndescribedSubroles,
                                            normalLevelWindowIDs: normalLevelWindowIDs,
                                            screenFrames: screenFrames,
                                            isCancelled: isCancelled)
            if reading == .unanswered { appendUnique(window, to: &unansweredWindows) }
            if reading == .userFacing, !isCancelled(), let id = AXWindowResolver.windowID(for: window) {
                let frame = attributes.frame
                let isNativeFullscreen = attributes.isNativeFullscreen
                let snapshot = AccessibilityWindowSnapshot(
                    title: attributes.string(.title) ?? "",
                    frame: frame,
                    isMinimized: attributes.bool(.minimized),
                    isFullscreen: isNativeFullscreen || frameLooksFullscreen(frame, screenFrames: screenFrames),
                    isNativeFullscreen: isNativeFullscreen)
                byID[id] = snapshot
                ordered.append((id, snapshot))
            }
            return reading
        }
        if windowsResult == .success, let windows = value as? [AXUIElement] {
            for window in windows {
                guard !isCancelled() else { return nil }
                if read(window) == .userFacing {
                    appendUnique(window, to: &axWindows)
                }
            }
        }
        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            guard !isCancelled() else { return nil }
            if let window = accessibilityWindowAttribute(app, attribute as String) {
                guard !isCancelled() else { return nil }
                guard !contains(window, in: readWindows) else { continue }
                if read(window) == .userFacing {
                    axWindows.append(window)
                }
            }
        }

        guard !isCancelled() else { return nil }
        let unansweredIDs = Set(unansweredWindows.compactMap(AXWindowResolver.windowID(for:)))
        if axWindows.isEmpty {
            switch SwitcherSupport.emptyAccessibilityAnswer(
                acceptsUndescribedSubroles: acceptsUndescribedSubroles,
                unansweredWindowCount: unansweredWindows.count,
                resolvedUnansweredIDCount: unansweredIDs.count) {
            case .perWindow:
                return AccessibilityWindowSnapshotList(ordered: ordered, byID: byID, unansweredIDs: unansweredIDs)
            case .everyWindowUnanswered:
                return AccessibilityWindowSnapshotList(ordered: ordered, byID: byID,
                                                       unansweredIDs: unansweredIDs,
                                                       everyWindowUnanswered: true)
            case .noAnswer:
                return nil
            }
        }
        if !ordered.isEmpty {
            return AccessibilityWindowSnapshotList(ordered: ordered, byID: byID, unansweredIDs: unansweredIDs,
                everyWindowUnanswered: unansweredIDs.count != unansweredWindows.count)
        }
        return nil
    }

    private static func appendAccessibilityOnlyWindows(to windows: inout [SwitcherItem],
                                                       snapshots: [pid_t: AccessibilityWindowSnapshotList],
                                                       regularApps: [pid_t: String],
                                                       embeddedHostPIDs: [pid_t: pid_t],
                                                       hiddenAppPIDs: Set<pid_t>,
                                                       seen: inout Set<CGWindowID>,
                                                       filterPID: pid_t?,
                                                       excludeWindow: (CGWindowID, pid_t, Bool) -> Bool = { _, _, _ in false }) {
        let tracker = WindowUseTracker.shared
        let pids = snapshots.keys
            .filter { windowOwnerPID in
                guard windowOwnerPID != ProcessInfo.processInfo.processIdentifier else { return false }
                let appPID = regularApps[windowOwnerPID] != nil
                    ? windowOwnerPID
                    : embeddedHostPIDs[windowOwnerPID]
                guard let appPID, regularApps[appPID] != nil else { return false }
                return filterPID == nil || appPID == filterPID
            }
            .sorted { lhs, rhs in
                let rankL = tracker.rank(of: embeddedHostPIDs[lhs] ?? lhs)
                let rankR = tracker.rank(of: embeddedHostPIDs[rhs] ?? rhs)
                return rankL != rankR ? rankL < rankR : lhs < rhs
            }

        for windowOwnerPID in pids {
            let appPID = embeddedHostPIDs[windowOwnerPID] ?? windowOwnerPID
            guard let appName = regularApps[appPID],
                  let list = snapshots[windowOwnerPID] else { continue }
            for entry in list.ordered {
                guard !seen.contains(entry.id),
                      !excludeWindow(entry.id, appPID, entry.snapshot.isNativeFullscreen),
                      let frame = switchableFrame(entry.snapshot.frame,
                                                  fallback: nil,
                                                  isMinimized: entry.snapshot.isMinimized) else { continue }
                seen.insert(entry.id)
                windows.append(.window(id: entry.id,
                                       title: entry.snapshot.title,
                                       appName: appName,
                                       pid: appPID,
                                       windowOwnerPID: windowOwnerPID,
                                       isOnScreen: false,
                                       isAppHidden: hiddenAppPIDs.contains(appPID),
                                       isMinimized: entry.snapshot.isMinimized,
                                       isFullscreen: entry.snapshot.isFullscreen,
                                       frame: frame))
            }
        }
    }

    private static func accessibilityTitle(for window: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success else {
            return ""
        }
        return value as? String ?? ""
    }

    private static func frameIsSwitchable(_ frame: CGRect) -> Bool {
        frame.width >= minimumSize.width && frame.height >= minimumSize.height
    }

    private static func switchableFrame(_ frame: CGRect?,
                                        fallback: CGRect?,
                                        isMinimized: Bool) -> CGRect? {
        if let frame, frameIsSwitchable(frame) { return frame }
        if let fallback, frameIsSwitchable(fallback) { return fallback }
        guard isMinimized else { return nil }
        return CGRect(origin: .zero, size: minimumSize)
    }

    private static func frameLooksFullscreen(_ frame: CGRect?,
                                             screenFrames: [CGRect]) -> Bool {
        guard let frame else { return false }
        return screenFrames.contains { screenFrame in
            abs(frame.width - screenFrame.width) <= 2
                && abs(frame.height - screenFrame.height) <= 2
        }
    }

    private static func userFacingReading(of window: AXUIElement,
                                          attributes: AccessibilityWindowAttributes,
                                          bundleIdentifier: String? = nil,
                                          acceptsUndescribedSubroles: Bool = false,
                                          normalLevelWindowIDs: Set<CGWindowID>,
                                          screenFrames: [CGRect],
                                          isCancelled: () -> Bool) -> WindowReading {
        guard !isCancelled() else { return .notUserFacing }
        if attributes.isNativeFullscreen { return .userFacing }
        if attributes.bool(.minimized), attributes.string(.role) == (kAXWindowRole as String) {
            return .userFacing
        }
        guard !SwitcherSupport.isUnansweredAccessibilityRead(attributes.error(for: .subrole)) else {
            return .unanswered
        }
        if let subrole = attributes.string(.subrole) {
            if subrole == "AXStandardWindow" || subrole == "AXFullScreenWindow" { return .userFacing }
            if SwitcherSupport.isSupportedMediaFloatingWindow(bundleIdentifier: bundleIdentifier,
                                                              subrole: subrole) { return .userFacing }
            guard !SwitcherSupport.isUnansweredAccessibilityRead(attributes.error(for: .role)) else {
                return .unanswered
            }
            let role = attributes.string(.role)
            let canBePlaybackSurface = subrole == "AXUnknown" || subrole == "AXFloatingWindow"
            let fillsScreen = canBePlaybackSurface
                && frameLooksFullscreen(attributes.frame, screenFrames: screenFrames)
            let windowID = role == (kAXWindowRole as String)
                ? AXWindowResolver.windowID(for: window)
                : nil
            let hasNormalWindowLevel = (subrole == "AXUnknown" || subrole == "AXDialog")
                && (windowID.map(normalLevelWindowIDs.contains) ?? false)
            let canMinimize = subrole == "AXDialog" && hasNormalWindowLevel
                && !isCancelled()
                && hasWorkingMinimizeButton(window)
            return SwitcherSupport.isSwitchableNonstandardWindow(
                role: role,
                subrole: subrole,
                fillsScreen: fillsScreen,
                hasNormalWindowLevel: hasNormalWindowLevel,
                acceptsUndescribedSubroles: acceptsUndescribedSubroles,
                canMinimize: canMinimize,
                isExcludedFromWindowCycle: windowID
                    .map(SpaceWindowBridge.isExcludedFromWindowCycle) ?? false)
                ? .userFacing : .notUserFacing
        }
        guard !SwitcherSupport.isUnansweredAccessibilityRead(attributes.error(for: .role)) else {
            return .unanswered
        }
        return attributes.string(.role) == "AXWindow" ? .userFacing : .notUserFacing
    }

    private static func hasWorkingMinimizeButton(_ window: AXUIElement) -> Bool {
        guard let button = accessibilityWindowAttribute(window, kAXMinimizeButtonAttribute as String) else {
            return false
        }
        AXUIElementSetMessagingTimeout(button, 0.35)
        return boolAttribute(button, kAXEnabledAttribute as String)
    }

    private static func appendUnique(_ window: AXUIElement, to windows: inout [AXUIElement]) {
        guard !contains(window, in: windows) else { return }
        windows.append(window)
    }

    private static func contains(_ window: AXUIElement, in windows: [AXUIElement]) -> Bool {
        windows.contains { CFEqual($0, window) }
    }

    private static func accessibilityWindowAttribute(_ app: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return false }
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return (value as? Bool) ?? false
        }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    private static func appendWindowlessApps(to windows: inout [SwitcherItem],
                                             mode: SwitcherWindowlessApps,
                                             runningApps: [AppSnapshot],
                                             regularApps: [pid_t: String],
                                             accessibilityWindows: [pid_t: AccessibilityWindowSnapshotList],
                                             ownPID: pid_t,
                                             withheldPIDs: Set<pid_t>,
                                             appRules: [String: SwitcherAppRule]) {
        let candidates = runningApps.compactMap { app -> SwitcherAppCandidate? in
            let pid = app.pid
            guard app.isRegular,
                  pid != ownPID,
                  regularApps[pid]?.isEmpty == false,
                  let answer = accessibilityWindows[pid],
                  SwitcherSupport.accessibilityAnswerShowsNoWindow(
                      describedWindowCount: answer.ordered.count,
                      unansweredIDs: answer.unansweredIDs,
                      everyWindowUnanswered: answer.everyWindowUnanswered,
                      isExcludedFromWindowCycle: SpaceWindowBridge.isExcludedFromWindowCycle)
            else { return nil }
            return SwitcherAppCandidate(pid: pid, bundleIdentifier: app.bundleIdentifier)
        }
        let chosen = SwitcherSupport.windowlessAppPIDs(
            mode: mode,
            candidates: candidates,
            pidsWithWindows: Set(windows.map(\.pid)),
            pidsWithWithheldWindows: withheldPIDs,
            desktopAppBundleIdentifier: Defaults.finderBundleIdentifier,
            appRules: appRules)
        for pid in chosen {
            guard let name = regularApps[pid] else { continue }
            let isAppHidden = runningApps.first { $0.pid == pid }?.isHidden ?? false
            windows.append(.appOnly(appName: name, pid: pid, isAppHidden: isAppHidden))
        }
    }

    private static func orderByUse(_ windows: [SwitcherItem],
                                   frontToBack: WindowUseTracker.FrontToBack) -> [SwitcherItem] {
        let tracker = WindowUseTracker.shared
        let entries = windows.map { WindowUseOrder.Entry(windowID: $0.windowID, pid: $0.pid) }
        return tracker.order(entries, frontToBack: frontToBack.windows)
            .map { windows[$0] }
    }

}
