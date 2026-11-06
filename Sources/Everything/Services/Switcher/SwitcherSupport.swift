// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

struct SwitcherScrollNavigation {
    static let gestureStep: Double = 30
    private var accumulated: Double = 0
    private var lastTimestamp: CGEventTimestamp?
    private var lastGesturePhaseTimestamp: CGEventTimestamp?
    private var wasMouseWheel: Bool?

    mutating func selectionDelta(for input: CGEvent, direction: ScrollDirectionPreferences? = nil) -> Int {
        guard input.getIntegerValueField(.eventSourceUserData) != ScrollWheelSupport.syntheticTag else {
            return 0
        }
        let traits = ScrollWheelEventTraits(
            isContinuous: input.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            momentumPhase: input.getIntegerValueField(.scrollWheelEventMomentumPhase),
            scrollPhase: input.getIntegerValueField(.scrollWheelEventScrollPhase),
            scrollCount: input.getIntegerValueField(.scrollWheelEventScrollCount)
        )
        let phase = CGScrollPhase(rawValue: UInt32(truncatingIfNeeded: traits.scrollPhase))
        let isMouseWheel = ScrollWheelSupport.isMouseWheel(traits, secondsSinceLastGesturePhase:
            lastGesturePhaseTimestamp.map { Double(input.timestamp &- $0) / 1_000_000_000 })
        var event = input
        if isMouseWheel, let direction, direction.invertVertical || direction.invertHorizontal,
           let turned = input.copy() {
            ScrollWheelSupport.applyDirection(to: turned, isContinuous: traits.isContinuous,
                                              invertVertical: direction.invertVertical,
                                              invertHorizontal: direction.invertHorizontal,
                                              horizontalModifier: nil)
            event = turned
        }
        if traits.scrollPhase != 0 || traits.momentumPhase != 0 {
            lastGesturePhaseTimestamp = event.timestamp
        }
        if wasMouseWheel != isMouseWheel || phase == .began
            || (!isMouseWheel && lastTimestamp.map({ event.timestamp &- $0 > 250_000_000 }) == true) {
            accumulated = 0
        }
        wasMouseWheel = isMouseWheel
        lastTimestamp = event.timestamp
        guard traits.momentumPhase == 0,
              phase != .ended, phase != .cancelled else {
            accumulated = 0
            return 0
        }
        func movement(line: CGEventField, fixed: CGEventField, point: CGEventField) -> Double {
            guard isMouseWheel else { return event.getDoubleValueField(point) }
            let lines = event.getDoubleValueField(line)
            if lines != 0 { return lines }
            let fraction = event.getDoubleValueField(fixed)
            if fraction != 0 { return fraction }
            return traits.isContinuous ? event.getDoubleValueField(point) / ScrollWheelSupport.pointsPerLine : 0
        }
        let vertical = movement(line: .scrollWheelEventDeltaAxis1, fixed: .scrollWheelEventFixedPtDeltaAxis1,
                                point: .scrollWheelEventPointDeltaAxis1)
        let horizontal = movement(line: .scrollWheelEventDeltaAxis2, fixed: .scrollWheelEventFixedPtDeltaAxis2,
                                  point: .scrollWheelEventPointDeltaAxis2)
        let delta = abs(horizontal) > abs(vertical) ? horizontal : vertical
        guard delta.isFinite, delta != 0 else { return 0 }
        if accumulated * delta < 0 { accumulated = 0 }
        accumulated += delta
        let step = isMouseWheel ? 1 : Self.gestureStep
        guard abs(accumulated) >= step else { return 0 }
        accumulated = isMouseWheel ? accumulated.truncatingRemainder(dividingBy: step) : 0
        return delta < 0 ? 1 : -1
    }
}

struct SwitcherCloseState: Equatable {
    let remainingItemIDs: [String]
    let selectedIndex: Int
    let didRemove: Bool
    let shouldEndSession: Bool
}

struct SwitcherActivationPlan: Equatable {
    let activateAllWindows: Bool
    let makeAppFrontmostAfterActivation: Bool
    let restoreSourceWhenTargetMinimizes: Bool
}

enum SwitcherAppActivationRoute: Equatable {
    case exactWindow(CGWindowID)
    case wholeApp
}

final class SwitcherWindowFocusRetryState {
    let targetStartedMinimized: Bool
    let knownWindowIDs: Set<CGWindowID>
    private(set) var targetWasObservedRestored: Bool
    private(set) var isActive = true

    init(targetWindowID: CGWindowID, targetStartedMinimized: Bool, knownWindowIDs: Set<CGWindowID>) {
        self.targetStartedMinimized = targetStartedMinimized
        self.knownWindowIDs = knownWindowIDs.isEmpty ? [] : knownWindowIDs.union([targetWindowID])
        self.targetWasObservedRestored = !targetStartedMinimized
    }

    func observe(targetMinimizedState: Bool?) {
        if targetMinimizedState == false {
            targetWasObservedRestored = true
        }
    }

    func shouldContinue(targetPID: pid_t,
                        sourcePID: pid_t?,
                        frontmostPID: @autoclosure () -> pid_t?,
                        targetMinimizedState: Bool?,
                        targetAppWindowIDs: @autoclosure () -> Set<CGWindowID>,
                        targetAppFocusedWindowID: @autoclosure () -> CGWindowID?,
                        targetWindowIsFocused: @autoclosure () -> Bool = false,
                        stopsWhenTargetFocused: Bool = false,
                        ignoresForeground: Bool = false,
                        ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> Bool {
        guard isActive else { return false }
        let observedFrontmostPID = frontmostPID()
        if stopsWhenTargetFocused,
           !ignoresForeground,
           !targetStartedMinimized,
           observedFrontmostPID == targetPID,
           targetWindowIsFocused() {
            isActive = false
            return false
        }
        isActive = SwitcherSupport.shouldContinueFocusRetry(
            targetPID: targetPID,
            sourcePID: sourcePID,
            frontmostPID: frontmostPID(),
            targetIsMinimized: targetMinimizedState == true,
            targetStartedMinimized: targetStartedMinimized,
            targetWasObservedRestored: targetWasObservedRestored,
            knownWindowIDs: knownWindowIDs,
            targetAppWindowIDs: targetAppWindowIDs(),
            targetAppFocusedWindowID: targetAppFocusedWindowID(),
            ignoresForeground: ignoresForeground,
            ownPID: ownPID
        )
        observe(targetMinimizedState: targetMinimizedState)
        return isActive
    }
}

struct SwitcherSearchRecord: Equatable {
    let id: String
    let title: String
    let appName: String
}

enum SwitcherLetterAction: Equatable {
    case closeWindow
    case quitApp
    case pinSearch
}

enum SwitcherSessionScope: Equatable {
    case allApps
    case frontmostApp
    case allWindows
}

enum SwitcherPendingKeyDecision: Equatable {
    case handleActiveSession
    case routeShortcut
    case swallow
    case cancelAndSwallow
}

enum SwitcherNativeSymbolicHotKey: Int32, CaseIterable, Hashable {
    case commandTab = 1
    case commandShiftTab = 2
    case nextWindow = 27
    case previousWindow = 220

    static let ids = Set(allCases.map(\.rawValue))
}

enum SwitcherWindowlessApps: String, CaseIterable, Equatable {
    case off
    case finder
    case all

    static let fallback = SwitcherWindowlessApps.finder

    static func mode(storedValue: String?,
                     takeOverSystemShortcuts: Bool) -> SwitcherWindowlessApps {
        if takeOverSystemShortcuts { return .all }
        guard let storedValue, let mode = SwitcherWindowlessApps(rawValue: storedValue) else {
            return fallback
        }
        return mode
    }

    static func migrated(showsWindowlessFinder: Bool) -> SwitcherWindowlessApps {
        showsWindowlessFinder ? .finder : .off
    }
}

enum SwitcherScreenPlacement: String, CaseIterable, Equatable {
    case pointer
    case menuBar
    case activeWindow

    static let fallback = SwitcherScreenPlacement.pointer

    static func placement(storedValue: String?) -> SwitcherScreenPlacement {
        guard let storedValue, let placement = SwitcherScreenPlacement(rawValue: storedValue) else {
            return fallback
        }
        return placement
    }
}

enum SwitcherAppRule: String, CaseIterable, Equatable {
    case showWithoutWindows
    case windowsOnly
    case hidden

    static func rules(storedValue: [String: Any]?) -> [String: SwitcherAppRule] {
        guard let storedValue else { return [:] }
        var rules: [String: SwitcherAppRule] = [:]
        for rawBundleID in storedValue.keys.sorted() {
            let bundleID = rawBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty,
                  let rawRule = storedValue[rawBundleID] as? String,
                  let rule = SwitcherAppRule(rawValue: rawRule)
            else { continue }
            rules[bundleID] = rule
        }
        return rules
    }

    static func storedValue(_ rules: [String: SwitcherAppRule]) -> [String: String] {
        var stored: [String: String] = [:]
        for (rawBundleID, rule) in rules {
            let bundleID = rawBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty else { continue }
            stored[bundleID] = rule.rawValue
        }
        return stored
    }
}

struct SwitcherAppCandidate: Equatable {
    let pid: pid_t
    let bundleIdentifier: String?
}

struct SwitcherAppGroup: Identifiable, Equatable {
    let pid: pid_t
    let appName: String
    let representativeIndex: Int
    let itemIDs: [String]

    var id: pid_t { pid }
    var windowCount: Int { itemIDs.count }
}

enum SwitcherGridCard {
    static var width: CGFloat { 288 * PreviewSizing.switcherScale }
    static var height: CGFloat { 214 * PreviewSizing.switcherScale }
    static let padding: CGFloat = 10
    static let titleSpacing: CGFloat = 7
    static let titleHeight: CGFloat = 31
    static var thumbnailWidth: CGFloat { width - padding * 2 }
    static var thumbnailHeight: CGFloat { height - padding * 2 - titleSpacing - titleHeight }
    static var titleWidth: CGFloat { thumbnailWidth - 8 }
    static var fallbackIconSize: CGFloat { 80 * PreviewSizing.switcherScale }
}

enum SwitcherSearchLayout {
    static let chipHeight: CGFloat = 28
    static let edgeInset: CGFloat = 12
    static let contentGap: CGFloat = 8

    static func topInset(query: String, isPinned: Bool, contentPadding: CGFloat) -> CGFloat {
        guard !query.isEmpty || isPinned else { return 0 }
        return max(0, edgeInset + chipHeight + contentGap - contentPadding)
    }
}

struct SwitcherIconRowLayout: Equatable {
    let visibleIconCount: Int
    let appRowContentWidth: CGFloat
    let appRowSurfaceWidth: CGFloat
    let previewContentWidth: CGFloat
    let previewSurfaceWidth: CGFloat
    let simpleTitleSurfaceWidth: CGFloat
    let panelSize: CGSize
    let showsShortcutHints: Bool
    let columns: Int
    let rows: Int
    let visibleRows: Int

    var isWrapped: Bool { rows > 1 }

    var iconAreaHeight: CGFloat { Self.iconAreaHeight(visibleRows: visibleRows) }

    static func iconAreaHeight(visibleRows: Int) -> CGFloat { CGFloat(max(1, visibleRows)) * rowHeight }

    static var scale: CGFloat { min(PreviewSizing.switcherScale, 1.15) }
    static var iconSize: CGFloat { 68 * scale }
    static var selectedIconSize: CGFloat { 78 * scale }
    static let iconTileSpacing: CGFloat = 5
    static let iconTitleHeight: CGFloat = 14
    static let iconTileVerticalPadding: CGFloat = 5
    static let iconTileVerticalMargin: CGFloat = 3
    static var iconLabelWidth: CGFloat { max(selectedIconSize + 12, 86 * scale) }
    static var rowHeight: CGFloat {
        selectedIconSize + iconTileSpacing + iconTitleHeight
            + 2 * (iconTileVerticalPadding + iconTileVerticalMargin)
    }
    static var appTileWidth: CGFloat { iconLabelWidth + 12 }
    static var windowLabelWidth: CGFloat { 120 * scale }
    static var windowTileWidth: CGFloat { windowLabelWidth + 12 }
    static var previewCardWidth: CGFloat { 220 * scale }
    static var previewCardHeight: CGFloat { 164 * scale }
    static var appEntryIconSize: CGFloat { 66 * scale }
    static var previewHeight: CGFloat { previewCardHeight + 76 * scale }
    static var hintHeight: CGFloat { 28 * scale }
    static var hintGap: CGFloat { 8 * scale }
    static var hintBarWidth: CGFloat { 300 * scale }
    static var rowHorizontalPadding: CGFloat { 8 * scale }
    static var previewPanelPadding: CGFloat { 12 * scale }
    static var padding: CGFloat { 20 * scale }
    static var spacing: CGFloat { 12 * scale }
    static var previewGap: CGFloat { 10 * scale }
    static var simpleTitleHeight: CGFloat { 66 * scale }
    static var simpleTitleGap: CGFloat { 10 * scale }
    static var simpleTitleChipMaxWidth: CGFloat { 180 * scale }
    static var simpleTitlePanelPadding: CGFloat { 10 * scale }
    static let simpleTitleSpacing: CGFloat = 6
    static let simpleTitleScrollPadding: CGFloat = 1

    static func naturalPreviewWidth(cardCount: Int) -> CGFloat {
        let count = max(0, cardCount)
        return CGFloat(count) * previewCardWidth + CGFloat(max(0, count - 1)) * spacing
    }

    func previewFitsWithoutScrolling(cardCount: Int) -> Bool {
        Self.naturalPreviewWidth(cardCount: cardCount) <= previewContentWidth
    }

    func contentWidth(simpleMode: Bool, windowRow: Bool) -> CGFloat {
        let hintWidth = showsShortcutHints ? Self.hintBarWidth : 0
        guard simpleMode else {
            return max(0, panelSize.width - Self.padding * 2)
        }
        return max(appRowSurfaceWidth,
                   windowRow ? 0 : simpleTitleSurfaceWidth,
                   hintWidth)
    }

    var simplePanelSize: CGSize {
        CGSize(width: contentWidth(simpleMode: true, windowRow: false) + Self.padding * 2,
               height: Self.simpleTitleHeight + Self.simpleTitleGap
                        + iconAreaHeight + shortcutHintHeight
                        + Self.padding * 2)
    }

    var simpleWindowPanelSize: CGSize {
        CGSize(width: contentWidth(simpleMode: true, windowRow: true) + Self.padding * 2,
               height: iconAreaHeight + shortcutHintHeight + Self.padding * 2)
    }

    private var shortcutHintHeight: CGFloat {
        showsShortcutHints ? Self.hintGap + Self.hintHeight : 0
    }

    static let empty = SwitcherIconRowLayout(visibleIconCount: 1,
                                             appRowContentWidth: 0,
                                             appRowSurfaceWidth: 0,
                                             previewContentWidth: 0,
                                             previewSurfaceWidth: 0,
                                             simpleTitleSurfaceWidth: 0,
                                             panelSize: .zero,
                                             showsShortcutHints: true,
                                             columns: 1,
                                             rows: 1,
                                             visibleRows: 1)

    static func compute(appCount rawAppCount: Int,
                        selectedWindowCount rawWindowCount: Int,
                        maximumWindowCount: Int = 1,
                        sessionScope: SwitcherSessionScope = .allApps,
                        screenVisibleFrame: CGRect,
                        showsShortcutHints: Bool = true,
                        tileWidth: CGFloat = appTileWidth,
                        maxColumns userMax: Int? = nil,
                        searchTopInset: CGFloat = 0) -> SwitcherIconRowLayout {
        let appCount = max(1, rawAppCount)
        let windowCount = max(1, rawWindowCount)
        let usableWidth = max(320, screenVisibleFrame.width * 0.96)
        let maxContentWidth = max(tileWidth, usableWidth - padding * 2)
        let maxAppContentWidth = max(tileWidth, maxContentWidth - rowHorizontalPadding * 2)
        let fitByWidth = max(1, Int((maxAppContentWidth + spacing) / (tileWidth + spacing)))
        let cap = SwitcherSupport.cappedColumnCount(fitByWidth: fitByWidth, userMax: userMax)
        let wraps = userMax != nil && appCount > cap
        let columns = wraps ? cap : appCount
        let rows = wraps ? (appCount + columns - 1) / columns : 1
        let rowIcons = wraps ? columns : appCount
        let naturalAppRowWidth = CGFloat(rowIcons) * tileWidth + CGFloat(max(0, rowIcons - 1)) * spacing
        let naturalPreviewWidth = Self.naturalPreviewWidth(cardCount: windowCount)
        let maxPreviewContentWidth = max(previewCardWidth, maxContentWidth - previewPanelPadding * 2)
        let appRowWidth = min(naturalAppRowWidth, maxAppContentWidth)
        let appRowSurfaceWidth = min(appRowWidth + rowHorizontalPadding * 2, maxContentWidth)
        let reservedCardCount = sessionScope == .frontmostApp
            ? max(windowCount, maximumWindowCount)
            : min(2, max(windowCount, maximumWindowCount))
        let previewCeiling = min(maxPreviewContentWidth,
                                 max(Self.naturalPreviewWidth(cardCount: reservedCardCount),
                                     appRowSurfaceWidth - previewPanelPadding * 2))
        let previewWidth = min(naturalPreviewWidth, previewCeiling)
        let previewSurfaceWidth = min(previewWidth + previewPanelPadding * 2, maxContentWidth)
        let naturalSimpleTitleWidth = CGFloat(windowCount) * simpleTitleChipMaxWidth
            + CGFloat(max(0, windowCount - 1)) * simpleTitleSpacing
            + simpleTitleScrollPadding * 2
            + simpleTitlePanelPadding * 2
        let simpleTitleSurfaceWidth = min(naturalSimpleTitleWidth, maxContentWidth)
        let hintWidth = showsShortcutHints ? min(hintBarWidth, maxContentWidth) : 0
        let contentWidth = min(max(appRowSurfaceWidth,
                                   previewCeiling + previewPanelPadding * 2,
                                   hintWidth), maxContentWidth)
        let visibleIconCount = wraps ? appCount : min(appCount, fitByWidth)
        let width = contentWidth + padding * 2
        let shortcutHintHeight = showsShortcutHints ? hintGap + hintHeight : 0
        let aboveIcons = max(previewHeight + previewGap, simpleTitleHeight + simpleTitleGap)
        let rowBudget = screenVisibleFrame.height * 0.85 - aboveIcons - shortcutHintHeight - padding * 2
            - searchTopInset
        let visibleRows = max(1, min(rows, Int(rowBudget / rowHeight)))
        let height = previewHeight + previewGap + Self.iconAreaHeight(visibleRows: visibleRows)
            + shortcutHintHeight + padding * 2
        return SwitcherIconRowLayout(visibleIconCount: visibleIconCount,
                                     appRowContentWidth: appRowWidth,
                                     appRowSurfaceWidth: appRowSurfaceWidth,
                                     previewContentWidth: previewWidth,
                                     previewSurfaceWidth: previewSurfaceWidth,
                                     simpleTitleSurfaceWidth: simpleTitleSurfaceWidth,
                                     panelSize: CGSize(width: width, height: height),
                                     showsShortcutHints: showsShortcutHints,
                                     columns: wraps ? columns : visibleIconCount,
                                     rows: rows,
                                     visibleRows: visibleRows)
    }

    static func compute(count rawCount: Int, screenVisibleFrame: CGRect) -> SwitcherIconRowLayout {
        compute(appCount: rawCount, selectedWindowCount: 1, screenVisibleFrame: screenVisibleFrame)
    }
}

struct SwitcherIconRowPreviewPlacement: Equatable {
    let contentWidth: CGFloat
    let leading: CGFloat
}

struct SwitcherShortcutHints: Equatable {
    let apps: String
    let windows: String
}

enum SwitcherSupport {
    static func screenIsInView(session: [String: Any]?, displaysAsleep: Bool) -> Bool {
        SessionActivitySupport.isOnConsole(session)
            && !KeepAwakeAutomationSupport.isScreenLocked(sessionDictionary: session)
            && !displaysAsleep
    }

    static let defaultAppearanceDelayMilliseconds = 100
    static let appearanceDelayMillisecondsRange: ClosedRange<Int> = 0 ... 500

    static func sanitizedAppearanceDelay(milliseconds: Int) -> Int {
        min(max(milliseconds, appearanceDelayMillisecondsRange.lowerBound),
            appearanceDelayMillisecondsRange.upperBound)
    }

    static func appearanceDelay(milliseconds: Int) -> TimeInterval {
        TimeInterval(sanitizedAppearanceDelay(milliseconds: milliseconds)) / 1000
    }

    static let maxColumnsRange: ClosedRange<Int> = 2 ... 10

    static func sanitizedMaxColumns(_ value: Int) -> Int? {
        guard value > 0 else { return nil }
        return min(max(value, maxColumnsRange.lowerBound), maxColumnsRange.upperBound)
    }

    static var userMaxColumns: Int? {
        sanitizedMaxColumns(UserDefaults.standard.integer(forKey: DefaultsKey.switcherMaxColumns))
    }

    static func cappedColumnCount(fitByWidth: Int, userMax: Int?) -> Int {
        max(1, min(fitByWidth, userMax ?? fitByWidth))
    }

    static func wrappingColumnCount(itemCount: Int, fitByWidth: Int, userMax: Int?) -> Int {
        let auto = gridColumnCount(itemCount: itemCount, maxColumns: fitByWidth)
        guard let userMax else { return auto }
        return max(1, min(auto, userMax))
    }

    static func titleWidth(_ title: String,
                           fontSize: CGFloat = 13,
                           weight: NSFont.Weight = .regular) -> CGFloat {
        guard !title.isEmpty else { return 0 }
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        return (title as NSString).size(withAttributes: [.font: font]).width
    }

    static func titleOverflows(_ title: String,
                               width: CGFloat,
                               fontSize: CGFloat = 13,
                               weight: NSFont.Weight = .regular) -> Bool {
        guard width > 0 else { return false }
        return titleWidth(title, fontSize: fontSize, weight: weight) > width
    }

    static let captureAlphaGridSize = 8

    static let iconRowEdgeHoverInterval: TimeInterval = 0.24

    static let iconRowEdgeHoverRepeatInterval: TimeInterval = 0.20

    static let iconRowEdgeHoverAnimationDuration: TimeInterval = 0.18

    static func firstValuesByPID<Value>(_ pairs: [(pid_t, Value)]) -> [pid_t: Value] {
        Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    static func usableApps<App>(_ apps: [App],
                                windowOwnerPIDs: [pid_t],
                                pid: (App) -> pid_t,
                                isRegular: (App) -> Bool,
                                resolve: (pid_t) -> App?) -> [App] {
        var usable = apps.filter { pid($0) > 0 }
        var known = Set(usable.map(pid))
        for owner in windowOwnerPIDs where owner > 0 && !known.contains(owner) {
            known.insert(owner)
            if let app = resolve(owner), pid(app) == owner, isRegular(app) {
                usable.append(app)
            }
        }
        return usable
    }

    static func usesIconRowLayout(iconRowMode: Bool, simpleMode: Bool) -> Bool {
        iconRowMode || simpleMode
    }

    static func capturesPreviews(simpleMode: Bool) -> Bool {
        !simpleMode
    }

    static func usesWindowRow(simpleMode: Bool,
                              mergeWindowsByApp: Bool,
                              sessionScope: SwitcherSessionScope) -> Bool {
        simpleMode && (!mergeWindowsByApp || sessionScope != .allApps)
    }

    static func usesAppGroupsForMainShortcut(iconRowLayout: Bool,
                                              windowRow: Bool) -> Bool {
        iconRowLayout && !windowRow
    }

    static func preservesGroupedWindowsDuringEnumeration(allApps: Bool,
                                                         mergeWindowsByApp: Bool,
                                                         simpleMode: Bool) -> Bool {
        allApps && mergeWindowsByApp && simpleMode
    }

    static func expandGroupedWindows(orderedWindows: [SwitcherItem],
                                     representatives: [SwitcherItem]) -> [SwitcherItem] {
        let windowsByPID = Dictionary(grouping: orderedWindows, by: \.pid)
        return representatives.flatMap { representative in
            [representative] + (windowsByPID[representative.pid] ?? []).filter {
                $0.id != representative.id
            }
        }
    }

    static func shouldPausePreviewCapture(frontmostBundleIdentifier: String?,
                                          frontmostExecutablePath: @autoclosure () -> String? = nil,
                                          excludedBundleIdentifiers: [String]) -> Bool {
        MouseAppExceptionSupport.identities(
            bundleID: frontmostBundleIdentifier,
            executablePath: frontmostExecutablePath(),
            readsPath: excludedBundleIdentifiers.contains(where: MouseAppExceptionSupport.isExecutablePathIdentity))
            .contains(where: excludedBundleIdentifiers.contains)
    }

    static func needsScreenRecording(switcherEnabled: Bool,
                                     simpleMode: Bool,
                                     dockPreviewEnabled: Bool) -> Bool {
        dockPreviewEnabled || (switcherEnabled && capturesPreviews(simpleMode: simpleMode))
    }

    static func sessionSourceItem(frontmostPID: pid_t?,
                                  focusedWindowID: CGWindowID?,
                                  items: [SwitcherItem]) -> SwitcherItem? {
        guard let frontmostPID else { return nil }
        let appPID = appPID(forFrontmost: frontmostPID, items: items)
        let candidates = items.filter { $0.pid == appPID }
        if let focusedWindowID,
           let focused = candidates.first(where: { $0.windowID == focusedWindowID }) {
            return focused
        }
        return candidates.first(where: { $0.isOnScreen && !$0.isMinimized })
            ?? candidates.first(where: { $0.windowID == nil })
    }

    static func orderedForSession(_ items: [SwitcherItem], currentID: String?) -> [SwitcherItem] {
        guard let currentID, let index = items.firstIndex(where: { $0.id == currentID }) else { return items }
        var ordered = items
        ordered.insert(ordered.remove(at: index), at: 0)
        return ordered
    }

    static func needsFocusedWindowLookup(frontmostPID: pid_t,
                                         items: [SwitcherItem]) -> Bool {
        let appPID = appPID(forFrontmost: frontmostPID, items: items)
        return items.lazy.filter {
            $0.pid == appPID && $0.windowID != nil && $0.isOnScreen && !$0.isMinimized
        }.prefix(2).count != 1
    }

    static func appPID(forFrontmost frontmostPID: pid_t, items: [SwitcherItem]) -> pid_t {
        items.first(where: { $0.windowOwnerPID == frontmostPID })?.pid ?? frontmostPID
    }

    static func frontmostAppWindows(allItems: [SwitcherItem], frontmostPID: pid_t) -> [SwitcherItem] {
        let appPID = appPID(forFrontmost: frontmostPID, items: allItems)
        return allItems.filter { $0.pid == appPID }
    }

    static func windowsForSession(_ items: [SwitcherItem], scope: SwitcherSessionScope,
                                  frontmostPID: pid_t) -> [SwitcherItem] {
        switch scope {
        case .allApps: return items
        case .frontmostApp: return frontmostAppWindows(allItems: items, frontmostPID: frontmostPID)
        case .allWindows: return items.filter { !$0.isAppEntry }
        }
    }

    static func shortcutMatch(event: CGEvent,
                               appsShortcut: GlobalShortcut,
                               windowShortcut: GlobalShortcut,
                               allWindowsShortcut: GlobalShortcut? = nil)
        -> (shortcut: GlobalShortcut, scope: SwitcherSessionScope, reversed: Bool)? {
        if appsShortcut.matches(event: event, allowingExtraShift: true) {
            return (appsShortcut, .allApps,
                    appsShortcut.shiftIsNavigationModifier && event.flags.contains(.maskShift))
        }
        let positional = windowShortcut.matches(event: event, allowingExtraShift: true)
        if positional || windowShortcut.matchesByCharacter(event: event) {
            return (windowShortcut, .frontmostApp,
                    windowNavigationDelta(positionalMatch: positional,
                                          shiftIsNavigationModifier: windowShortcut.shiftIsNavigationModifier,
                                          shiftHeld: event.flags.contains(.maskShift)) < 0)
        }
        if let allWindowsShortcut,
           allWindowsShortcut.matches(event: event, allowingExtraShift: true) {
            return (allWindowsShortcut, .allWindows,
                    allWindowsShortcut.shiftIsNavigationModifier && event.flags.contains(.maskShift))
        }
        return nil
    }

    static func initialWindowScopedSelectionIndex(itemCount: Int,
                                                  hasForegroundItem: Bool,
                                                  reversed: Bool) -> Int {
        guard itemCount > 0 else { return 0 }
        if reversed { return itemCount - 1 }
        guard hasForegroundItem else { return 0 }
        return itemCount > 1 ? 1 : 0
    }

    static func windowNavigationDelta(positionalMatch: Bool,
                                      shiftIsNavigationModifier: Bool,
                                      shiftHeld: Bool) -> Int {
        positionalMatch && shiftIsNavigationModifier && shiftHeld ? -1 : 1
    }

    static func isCompatibilityLayerApp(bundleIdentifier: String?,
                                        executablePath: String?,
                                        localizedName: String?) -> Bool {
        guard bundleIdentifier == nil else { return false }
        if let executablePath, !executablePath.isEmpty {
            let components = executablePath.split(separator: "/")
            guard let leaf = components.last else { return false }
            return leaf.hasPrefix("wine")
                || components.contains { $0.hasPrefix("winetemp-") }
        }
        guard let localizedName else { return false }
        return localizedName.hasPrefix("wine")
    }

    static func usesActivationClick(executablePath: String?, localizedName: String?) -> Bool {
        !isCompatibilityLayerApp(bundleIdentifier: nil,
                                 executablePath: executablePath,
                                 localizedName: localizedName)
    }

    static func isSupportedMediaFloatingWindow(bundleIdentifier: String?, subrole: String?) -> Bool {
        guard let subrole, subrole == "AXFloatingWindow" || subrole == "AXUnknown",
              let bundleIdentifier else { return false }
        let lower = bundleIdentifier.lowercased()
        return lower.hasPrefix("com.adobe.audition")
            || lower.hasPrefix("com.adobe.aftereffects")
            || lower.hasPrefix("com.adobe.premiere")
            || lower.hasPrefix("com.adobe.mediaencoder")
            || lower.hasPrefix("com.adobe.characteranimator")
    }

    static func isSwitchableNonstandardWindow(role: String?,
                                              subrole: String?,
                                              fillsScreen: Bool,
                                              hasNormalWindowLevel: Bool,
                                              acceptsUndescribedSubroles: Bool,
                                              canMinimize: Bool = false,
                                              isExcludedFromWindowCycle: Bool = false) -> Bool {
        guard role == "AXWindow", !isExcludedFromWindowCycle else { return false }
        if subrole == "AXUnknown" {
            return hasNormalWindowLevel || acceptsUndescribedSubroles || fillsScreen
        }
        if subrole == "AXDialog" {
            return hasNormalWindowLevel && canMinimize
        }
        return fillsScreen && subrole == "AXFloatingWindow"
    }

    static func visibleSelectionIndices(appPIDs: [pid_t], limit: Int) -> [Int] {
        guard limit > 0 else { return [] }
        guard appPIDs.count > limit else { return Array(appPIDs.indices) }
        var chosen = Set<Int>()
        var representedApps = Set<pid_t>()
        for index in appPIDs.indices.prefix(min(2, limit)) {
            chosen.insert(index)
            representedApps.insert(appPIDs[index])
        }
        for (index, pid) in appPIDs.enumerated() {
            guard chosen.count < limit else { break }
            guard representedApps.insert(pid).inserted else { continue }
            chosen.insert(index)
        }
        for index in appPIDs.indices {
            guard chosen.count < limit else { break }
            chosen.insert(index)
        }
        return chosen.sorted()
    }

    static func visibleSelectionIndices(items: [SwitcherItem],
                                        limit: Int,
                                        frontmostPID: pid_t?) -> [Int] {
        guard let frontmostPID else {
            return visibleSelectionIndices(appPIDs: items.map(\.pid), limit: limit)
        }
        let appPID = appPID(forFrontmost: frontmostPID, items: items)
        return Array(items.indices.filter { items[$0].pid == appPID }.prefix(max(0, limit)))
    }

    static func embeddedHostPID(helperBundlePath: String,
                                regularBundlePaths: [pid_t: String]) -> pid_t? {
        let helperPath = URL(fileURLWithPath: helperBundlePath).standardizedFileURL.path
        return regularBundlePaths
            .filter { _, hostPath in
                let normalizedHost = URL(fileURLWithPath: hostPath).standardizedFileURL.path
                return helperPath.hasPrefix(normalizedHost + "/")
            }
            .max { lhs, rhs in lhs.value.count < rhs.value.count }?
            .key
    }

    static func accessibilityPIDs(regularAppPIDs: Set<pid_t>,
                                  embeddedHostPIDs: [pid_t: pid_t],
                                  ownPID: pid_t,
                                  filterPID: pid_t?) -> Set<pid_t> {
        if let filterPID {
            let embeddedPIDs = embeddedHostPIDs.compactMap { ownerPID, hostPID in
                hostPID == filterPID ? ownerPID : nil
            }
            return Set([filterPID] + embeddedPIDs)
        }
        return regularAppPIDs.union(embeddedHostPIDs.keys).subtracting([ownPID])
    }

    static func windowlessAppPIDs(mode: SwitcherWindowlessApps,
                                  candidates: [SwitcherAppCandidate],
                                  pidsWithWindows: Set<pid_t>,
                                  pidsWithWithheldWindows: Set<pid_t>,
                                  desktopAppBundleIdentifier: String,
                                  appRules: [String: SwitcherAppRule] = [:]) -> [pid_t] {
        return candidates.compactMap { candidate in
            guard !pidsWithWindows.contains(candidate.pid),
                  !pidsWithWithheldWindows.contains(candidate.pid)
            else { return nil }
            if let bundleIdentifier = candidate.bundleIdentifier,
               let rule = appRules[bundleIdentifier] {
                switch rule {
                case .showWithoutWindows:
                    return candidate.pid
                case .windowsOnly, .hidden:
                    return nil
                }
            }
            switch mode {
            case .off:
                return nil
            case .finder:
                return candidate.bundleIdentifier == desktopAppBundleIdentifier ? candidate.pid : nil
            case .all:
                return candidate.pid
            }
        }
    }

    static func displayIndex(showingMostOf windowFrame: CGRect, displayBounds: [CGRect]) -> Int? {
        guard !windowFrame.isNull, !windowFrame.isEmpty else { return nil }
        var best: (index: Int, area: CGFloat)?
        for (index, bounds) in displayBounds.enumerated() {
            let overlap = bounds.intersection(windowFrame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            guard area > 0, area > (best?.area ?? 0) else { continue }
            best = (index, area)
        }
        return best?.index
    }

    static func groupWindowsByApp(_ windows: [SwitcherItem],
                                  isOnHiddenSpace: (SwitcherItem) -> Bool = { _ in false }) -> [SwitcherItem] {
        var indexByPid: [pid_t: Int] = [:]
        var grouped: [SwitcherItem] = []
        for window in windows {
            if let index = indexByPid[window.pid] {
                let keptIsElsewhere = isOnHiddenSpace(grouped[index])
                if isOnHiddenSpace(window) != keptIsElsewhere {
                    if keptIsElsewhere { grouped[index] = window }
                    continue
                }
                if (window.isOnScreen && !grouped[index].isOnScreen)
                    || (window.isFullscreen && !grouped[index].isFullscreen) {
                    grouped[index] = window
                }
            } else {
                indexByPid[window.pid] = grouped.count
                grouped.append(window)
            }
        }
        return grouped
    }

    static func itemsOnDisplay(_ items: [SwitcherItem],
                               displayBounds: [CGRect],
                               targetIndex: Int) -> [SwitcherItem] {
        guard displayBounds.indices.contains(targetIndex) else { return [] }
        return items.filter { item in
            guard !item.isAppEntry,
                  let index = displayIndex(showingMostOf: item.frame,
                                           displayBounds: displayBounds) else { return false }
            return index == targetIndex
        }
    }

    static func hidesApp(bundleIdentifier: String?,
                         appRules: [String: SwitcherAppRule]) -> Bool {
        guard let bundleIdentifier else { return false }
        return appRules[bundleIdentifier] == .hidden
    }

    static func isConfirmedHiddenAppWindow(appIsHidden: Bool,
                                           windowSpaces: [UInt64],
                                           isHiddenWithApp: Bool?) -> Bool {
        appIsHidden && !windowSpaces.isEmpty && isHiddenWithApp != false
    }

    static func looksUpHiddenSpaceTitle(windowServerTitle: String,
                                        isDescribedByAccessibility: Bool,
                                        accessibilityGranted: Bool,
                                        isOnHiddenSpace: Bool) -> Bool {
        windowServerTitle.isEmpty && !isDescribedByAccessibility && accessibilityGranted && isOnHiddenSpace
    }

    static func keepsUnmatchedWindow(isOnHiddenSpace: Bool,
                                     isConfirmedHiddenAppWindow: Bool,
                                     isExcludedFromWindowCycle: Bool,
                                     isOrderedIn: Bool?,
                                     allowsUnverifiedHiddenSpace: Bool) -> Bool {
        guard !isExcludedFromWindowCycle else { return false }
        if isConfirmedHiddenAppWindow { return true }
        guard isOnHiddenSpace else { return false }
        return allowsUnverifiedHiddenSpace || isOrderedIn == true
    }

    static func unwitnessedSurfaceIsLeftover(isOnScreen: Bool,
                                             canResolveSpaces: Bool,
                                             windowSpacesCount: Int) -> Bool {
        guard !isOnScreen, canResolveSpaces else { return false }
        return windowSpacesCount == 0
    }

    static func isUnansweredAccessibilityRead(_ error: AXError) -> Bool {
        error == .cannotComplete
    }

    enum AccessibilityWitness: Equatable {
        case described
        case rejected
        case unanswered
    }

    static func accessibilityWitness(isDescribed: Bool, isUnanswered: Bool) -> AccessibilityWitness {
        if isDescribed { return .described }
        return isUnanswered ? .unanswered : .rejected
    }

    static func keepsSurface(witness: AccessibilityWitness?,
                             keepsUnmatched: () -> Bool,
                             isExcludedFromWindowCycle: () -> Bool,
                             isLeftover: () -> Bool) -> Bool {
        switch witness {
        case .described: return true
        case .rejected: return keepsUnmatched()
        case .unanswered: return !isExcludedFromWindowCycle() && !isLeftover()
        case nil: return !isLeftover()
        }
    }

    static func accessibilityAnswerShowsNoWindow(describedWindowCount: Int,
                                                 unansweredIDs: Set<CGWindowID>,
                                                 everyWindowUnanswered: Bool,
                                                 isExcludedFromWindowCycle: (CGWindowID) -> Bool) -> Bool {
        describedWindowCount == 0
            && !everyWindowUnanswered
            && unansweredIDs.allSatisfy(isExcludedFromWindowCycle)
    }

    enum EmptyAccessibilityAnswer: Equatable {
        case perWindow
        case everyWindowUnanswered
        case noAnswer
    }

    static func emptyAccessibilityAnswer(acceptsUndescribedSubroles: Bool,
                                         unansweredWindowCount: Int,
                                         resolvedUnansweredIDCount: Int) -> EmptyAccessibilityAnswer {
        if acceptsUndescribedSubroles { return .noAnswer }
        return resolvedUnansweredIDCount == unansweredWindowCount ? .perWindow : .everyWindowUnanswered
    }

    static func alphaGrid(of image: CGImage, gridSize: Int = captureAlphaGridSize) -> [Double]? {
        guard gridSize > 0 else { return nil }
        let bytesPerPixel = 4
        var data = [UInt8](repeating: 0, count: gridSize * gridSize * bytesPerPixel)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress,
                                          width: gridSize,
                                          height: gridSize,
                                          bitsPerComponent: 8,
                                          bytesPerRow: gridSize * bytesPerPixel,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(gridSize), height: CGFloat(gridSize)))
            return true
        }
        guard drawn else { return nil }
        return (0..<(gridSize * gridSize)).map { Double(data[$0 * bytesPerPixel + 3]) / 255.0 }
    }

    static func captureLooksTransformed(alphaGrid: [Double],
                                        gridSize: Int = captureAlphaGridSize) -> Bool {
        guard gridSize >= 4, alphaGrid.count == gridSize * gridSize else { return false }
        let last = gridSize - 1
        let mid = gridSize / 2
        let probes = [
            (0, 0), (0, last), (last, 0), (last, last),
            (0, mid), (last, mid), (mid, 0), (mid, last),
        ]
        let transparent = probes.filter { alphaGrid[$0.0 * gridSize + $0.1] < 0.05 }.count
        return transparent >= 2
    }

    static let captureCoverageTolerance = 0.08

    static func captureCoversWindow(imageWidth: Int,
                                    imageHeight: Int,
                                    windowSize: CGSize,
                                    tolerance: Double = captureCoverageTolerance) -> Bool {
        guard windowSize.width.isFinite, windowSize.height.isFinite,
              windowSize.width > 1, windowSize.height > 1
        else { return true }
        let horizontal = Double(imageWidth) / Double(windowSize.width)
        let vertical = Double(imageHeight) / Double(windowSize.height)
        guard horizontal > 0, vertical > 0 else { return true }
        return max(horizontal, vertical) / min(horizontal, vertical) <= 1 + tolerance
    }

    struct CaptureQuadCorners: Equatable {
        var topLeft: CGPoint
        var topRight: CGPoint
        var bottomRight: CGPoint
        var bottomLeft: CGPoint
    }

    static func opaqueQuadCorners(alpha: [UInt8],
                                  width: Int,
                                  height: Int,
                                  threshold: UInt8 = 250) -> CaptureQuadCorners? {
        guard width > 16, height > 16, alpha.count == width * height else { return nil }
        var topLeft = (score: Int.max, x: 0, y: 0)
        var topRight = (score: Int.min, x: 0, y: 0)
        var bottomRight = (score: Int.min, x: 0, y: 0)
        var bottomLeft = (score: Int.max, x: 0, y: 0)
        var opaqueCount = 0
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where alpha[row + x] >= threshold {
                opaqueCount += 1
                let sum = x + y
                let diff = x - y
                if sum < topLeft.score { topLeft = (sum, x, y) }
                if diff > topRight.score { topRight = (diff, x, y) }
                if sum > bottomRight.score { bottomRight = (sum, x, y) }
                if diff < bottomLeft.score { bottomLeft = (diff, x, y) }
            }
        }
        guard opaqueCount >= (width * height) / 10 else { return nil }
        let spanX = max(topRight.x, bottomRight.x) - min(topLeft.x, bottomLeft.x)
        let spanY = max(bottomLeft.y, bottomRight.y) - min(topLeft.y, topRight.y)
        guard spanX >= width / 2, spanY >= height / 2 else { return nil }
        return CaptureQuadCorners(topLeft: CGPoint(x: topLeft.x, y: topLeft.y),
                                  topRight: CGPoint(x: topRight.x, y: topRight.y),
                                  bottomRight: CGPoint(x: bottomRight.x, y: bottomRight.y),
                                  bottomLeft: CGPoint(x: bottomLeft.x, y: bottomLeft.y))
    }

    static func staleCacheVictims(ids: Set<CGWindowID>,
                                  active: Set<CGWindowID>,
                                  lastTouched: [CGWindowID: TimeInterval],
                                  limit: Int) -> [CGWindowID] {
        let overflow = ids.count - limit
        guard overflow > 0 else { return [] }
        return ids.filter { !active.contains($0) }
            .sorted { (lastTouched[$0] ?? 0) < (lastTouched[$1] ?? 0) }
            .prefix(overflow)
            .map { $0 }
    }

    static func cacheByteBudgetVictims(sizes: [CGWindowID: Int],
                                       active: Set<CGWindowID>,
                                       lastTouched: [CGWindowID: TimeInterval],
                                       budget: Int) -> [CGWindowID] {
        var total = sizes.values.reduce(0, +)
        guard total > budget else { return [] }
        var victims: [CGWindowID] = []
        let evictable = sizes.keys.filter { !active.contains($0) }
            .sorted { (lastTouched[$0] ?? 0) < (lastTouched[$1] ?? 0) }
        for id in evictable {
            guard total > budget else { break }
            total -= sizes[id] ?? 0
            victims.append(id)
        }
        return victims
    }

    static func shouldNavigateBackwardOnShiftPress(shiftIsNavigationModifier: Bool,
                                                   wasShiftHeld: Bool,
                                                   isShiftHeld: Bool) -> Bool {
        shiftIsNavigationModifier && isShiftHeld && !wasShiftHeld
    }

    static func clampedIconRowFirstVisibleIndex(itemCount: Int,
                                                visibleCount: Int,
                                                firstVisibleIndex: Int) -> Int {
        let visible = max(1, visibleCount)
        guard itemCount > visible else { return 0 }
        return min(max(0, firstVisibleIndex), itemCount - visible)
    }

    static func iconRowFirstVisibleIndex(revealing selectedIndex: Int,
                                         itemCount: Int,
                                         visibleCount: Int,
                                         currentFirstVisibleIndex: Int) -> Int {
        let visible = max(1, visibleCount)
        let first = clampedIconRowFirstVisibleIndex(itemCount: itemCount,
                                                    visibleCount: visible,
                                                    firstVisibleIndex: currentFirstVisibleIndex)
        guard itemCount > 0 else { return 0 }
        let selected = min(max(0, selectedIndex), itemCount - 1)
        if selected < first { return selected }
        let lastVisible = first + min(visible, itemCount) - 1
        if selected > lastVisible { return selected - min(visible, itemCount) + 1 }
        return first
    }

    static func iconRowEdgeHoverDelta(hoveredIndex: Int,
                                      firstVisibleIndex: Int,
                                      visibleCount: Int,
                                      itemCount: Int) -> Int? {
        let visible = max(1, visibleCount)
        guard itemCount > visible else { return nil }
        let first = clampedIconRowFirstVisibleIndex(itemCount: itemCount,
                                                    visibleCount: visible,
                                                    firstVisibleIndex: firstVisibleIndex)
        let lastVisible = first + visible - 1
        let hovered = min(max(0, hoveredIndex), itemCount - 1)
        if hovered == lastVisible, lastVisible < itemCount - 1 { return 1 }
        if hovered == first, first > 0 { return -1 }
        return nil
    }

    static func iconRowIndexAfterEdgeHoverStep(firstVisibleIndex: Int,
                                               visibleCount: Int,
                                               itemCount: Int,
                                               delta: Int) -> Int {
        let visible = max(1, visibleCount)
        let first = clampedIconRowFirstVisibleIndex(itemCount: itemCount,
                                                    visibleCount: visible,
                                                    firstVisibleIndex: firstVisibleIndex)
        guard itemCount > 0 else { return 0 }
        if delta < 0 { return first }
        return min(itemCount - 1, first + min(visible, itemCount) - 1)
    }

    static let shiftBackChordWindow: TimeInterval = 0.35

    static func selectedPreviewPlacement(appCount rawAppCount: Int,
                                         selectedAppIndex rawSelectedAppIndex: Int,
                                         selectedWindowIndex _: Int,
                                         selectedWindowCount _: Int,
                                         visibleIconCount rawVisibleIconCount: Int,
                                         appRowContentWidth: CGFloat,
                                         appRowSurfaceWidth: CGFloat,
                                         previewContentWidth _: CGFloat,
                                         previewSurfaceWidth: CGFloat,
                                         columns rawColumns: Int? = nil) -> SwitcherIconRowPreviewPlacement {
        let appCount = max(1, rawAppCount)
        let visibleIconCount = max(1, rawVisibleIconCount)
        let selectedAppIndex = min(max(0, rawSelectedAppIndex), appCount - 1)
        let contentWidth = max(appRowSurfaceWidth, previewSurfaceWidth)
        guard previewSurfaceWidth < contentWidth else {
            return SwitcherIconRowPreviewPlacement(contentWidth: contentWidth, leading: 0)
        }

        let rowLeading = max(0, (contentWidth - appRowSurfaceWidth) / 2) + SwitcherIconRowLayout.rowHorizontalPadding
        let selectedCenterInRow: CGFloat
        if appCount > visibleIconCount {
            selectedCenterInRow = rowLeading + appRowContentWidth / 2
        } else {
            let column = rawColumns.map { selectedAppIndex % max(1, $0) } ?? selectedAppIndex
            selectedCenterInRow = rowLeading + SwitcherIconRowLayout.appTileWidth / 2
                + CGFloat(column) * (SwitcherIconRowLayout.appTileWidth + SwitcherIconRowLayout.spacing)
        }

        let rawLeading = selectedCenterInRow - previewSurfaceWidth / 2
        let clampedLeading = min(max(0, rawLeading), contentWidth - previewSurfaceWidth)
        return SwitcherIconRowPreviewPlacement(contentWidth: contentWidth, leading: clampedLeading)
    }

    static func shortcutHints(for switcherShortcut: GlobalShortcut,
                              windowShortcut: GlobalShortcut) -> SwitcherShortcutHints {
        return SwitcherShortcutHints(apps: switcherShortcut.displayString,
                                     windows: windowShortcut.displayString)
    }

    static func appGroups(items: [SwitcherItem], currentSpaceOnly: Bool = false) -> [SwitcherAppGroup] {
        var seen: Set<pid_t> = []
        var groups: [SwitcherAppGroup] = []
        for (index, item) in items.enumerated() where !seen.contains(item.pid) {
            seen.insert(item.pid)
            var representativeIndex = index
            if currentSpaceOnly, item.isOnHiddenSpace,
               let here = items[index...].firstIndex(where: { $0.pid == item.pid && !$0.isOnHiddenSpace }) {
                representativeIndex = here
            }
            groups.append(SwitcherAppGroup(pid: item.pid,
                                           appName: item.appName,
                                           representativeIndex: representativeIndex,
                                           itemIDs: items.filter { $0.pid == item.pid }.map(\.id)))
        }
        return groups
    }

    static func windowlessAppDividerPIDs(items: [SwitcherItem]) -> Set<pid_t> {
        let groups = appGroups(items: items)
        let windowedPIDs = Set(items.filter { !$0.isAppEntry }.map(\.pid))
        var dividers: Set<pid_t> = []
        for (previous, current) in zip(groups, groups.dropFirst()) {
            if windowedPIDs.contains(previous.pid) != windowedPIDs.contains(current.pid) {
                dividers.insert(current.pid)
            }
        }
        return dividers
    }

    static func initialSelectionPosition(pids: [pid_t],
                                         hasForegroundEntry: Bool,
                                         frontmostPID: pid_t?,
                                         reversed: Bool) -> Int {
        guard !pids.isEmpty else { return 0 }
        if reversed { return pids.count - 1 }
        guard hasForegroundEntry else {
            return pids.firstIndex { $0 != frontmostPID } ?? 0
        }
        return pids.count > 1 ? 1 : 0
    }

    static func gridColumnCount(itemCount: Int, maxColumns: Int) -> Int {
        let count = max(itemCount, 1)
        let packed = min(count, max(maxColumns, 1))
        let rows = (count + packed - 1) / packed
        return min(packed, (count + rows - 1) / rows)
    }

    static func gridSelectionIndex(after selectedIndex: Int,
                                   itemCount: Int,
                                   columns: Int,
                                   movingDown: Bool) -> Int {
        guard itemCount > 0 else { return 0 }
        let current = min(max(0, selectedIndex), itemCount - 1)
        let safeColumns = max(1, columns)

        guard movingDown else {
            let target = current - safeColumns
            return target >= 0 ? target : current
        }

        let nextRowStart = (current / safeColumns + 1) * safeColumns
        guard nextRowStart < itemCount else { return current }
        return min(current + safeColumns, itemCount - 1)
    }

    static func iconRowSelectionIndex(after selectedIndex: Int,
                                      items: [SwitcherItem],
                                      windowRow: Bool,
                                      columns: Int,
                                      movingDown: Bool,
                                      currentSpaceOnly: Bool = false) -> Int? {
        guard items.indices.contains(selectedIndex) else { return nil }
        let groups = windowRow ? [] : appGroups(items: items, currentSpaceOnly: currentSpaceOnly)
        let selectedPID = items[selectedIndex].pid
        guard let iconIndex = windowRow ? selectedIndex : groups.firstIndex(where: { $0.pid == selectedPID })
        else { return nil }
        let target = gridSelectionIndex(after: iconIndex,
                                        itemCount: windowRow ? items.count : groups.count,
                                        columns: columns,
                                        movingDown: movingDown)
        guard target != iconIndex else { return nil }
        return windowRow ? target : groups[target].representativeIndex
    }

    static func iconRowScrollID(items: [SwitcherItem],
                                selectedIndex: Int,
                                windowRow: Bool) -> AnyHashable? {
        guard items.indices.contains(selectedIndex) else { return nil }
        let selected = items[selectedIndex]
        return windowRow ? AnyHashable(selected.id) : AnyHashable(selected.pid)
    }

    static func nextAppSelectionIndex(items: [SwitcherItem],
                                      selectedIndex: Int,
                                      delta: Int,
                                      wrapping: Bool = true,
                                      currentSpaceOnly: Bool = false) -> Int {
        let groups = appGroups(items: items, currentSpaceOnly: currentSpaceOnly)
        guard !groups.isEmpty else { return 0 }
        guard items.indices.contains(selectedIndex) else {
            return groups[0].representativeIndex
        }

        let selectedID = items[selectedIndex].id
        let currentGroupIndex = groups.firstIndex { $0.itemIDs.contains(selectedID) } ?? 0
        let unwrapped = currentGroupIndex + delta
        if !wrapping, !groups.indices.contains(unwrapped) {
            return groups[currentGroupIndex].representativeIndex
        }
        let targetGroupIndex = (unwrapped + groups.count) % groups.count
        return groups[targetGroupIndex].representativeIndex
    }

    static func nextWindowSelectionIndexWithinApp(items: [SwitcherItem],
                                                  selectedIndex: Int,
                                                  delta: Int) -> Int {
        guard items.indices.contains(selectedIndex) else { return 0 }
        let pid = items[selectedIndex].pid
        let indices = items.indices.filter { items[$0].pid == pid }
        guard !indices.isEmpty,
              let current = indices.firstIndex(of: selectedIndex)
        else { return selectedIndex }

        let target = (current + delta + indices.count) % indices.count
        return indices[target]
    }

    static func activationPlan(targetsSpecificWindow: Bool) -> SwitcherActivationPlan {
        SwitcherActivationPlan(
            activateAllWindows: !targetsSpecificWindow,
            makeAppFrontmostAfterActivation: !targetsSpecificWindow,
            restoreSourceWhenTargetMinimizes: targetsSpecificWindow
        )
    }

    static func shouldActivateAllWindows(targetsSpecificWindow: Bool) -> Bool {
        activationPlan(targetsSpecificWindow: targetsSpecificWindow).activateAllWindows
    }

    static func appActivationRoute(plan: SwitcherActivationPlan,
                                   windowID: CGWindowID?) -> SwitcherAppActivationRoute {
        if !plan.activateAllWindows, let windowID {
            return .exactWindow(windowID)
        }
        return .wholeApp
    }

    static func shouldRestoreSourceAfterTargetMinimize(targetPID: pid_t,
                                                       sourcePID: pid_t?,
                                                       frontmostPID: pid_t?,
                                                       targetIsMinimized: Bool,
                                                       ownPID: pid_t = ProcessInfo.processInfo.processIdentifier,
                                                       frontmostMatchesTargetBundle: Bool = false,
                                                       frontmostCanBeSystemPromotion: Bool = false) -> Bool {
        guard targetIsMinimized,
              let sourcePID,
              let frontmostPID,
              sourcePID != targetPID else { return false }
        if frontmostPID == sourcePID { return false }
        return frontmostPID == targetPID
            || frontmostPID == ownPID
            || frontmostMatchesTargetBundle
            || frontmostCanBeSystemPromotion
    }

    static func shouldRestoreSourceAfterTargetMinimizeIntent(targetPID: pid_t,
                                                             sourcePID: pid_t?,
                                                             frontmostPID: pid_t?,
                                                             focusedWindowID: @autoclosure () -> UInt32?,
                                                             targetWindowID: UInt32,
                                                             targetIsMinimized: @autoclosure () -> Bool,
                                                             ownPID: pid_t = ProcessInfo.processInfo.processIdentifier,
                                                             frontmostMatchesTargetBundle: @autoclosure () -> Bool = false,
                                                             frontmostCanBeSystemPromotion: Bool = false) -> Bool {
        guard let sourcePID,
              sourcePID != targetPID else { return false }
        if frontmostPID == sourcePID { return false }
        let frontmostIsForeign = frontmostPID != nil
            && frontmostPID != targetPID
            && frontmostPID != ownPID
            && !frontmostMatchesTargetBundle()
        if frontmostIsForeign, !frontmostCanBeSystemPromotion { return false }
        let targetIsMinimized = targetIsMinimized()
        if frontmostIsForeign, !targetIsMinimized { return false }
        if targetIsMinimized { return true }
        guard let focusedWindowID = focusedWindowID() else { return false }
        return focusedWindowID != targetWindowID
    }

    static func shouldStageSourceBehindTarget(targetPID: pid_t,
                                              sourcePID: pid_t?,
                                              sourceWindowID: UInt32?,
                                              ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> Bool {
        guard let sourcePID,
              sourcePID != targetPID,
              sourcePID != ownPID,
              sourceWindowID != nil else { return false }
        return true
    }

    static func focusRetryWindowIDs(in windows: [[String: Any]], ownerPID: pid_t) -> Set<CGWindowID> {
        Set(windows.compactMap { info -> CGWindowID? in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == ownerPID else { return nil }
            return (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        })
    }

    static func focusRetrySourcePID(sessionSourcePID: pid_t?,
                                    handoffSourcePID: pid_t?,
                                    targetPID: pid_t,
                                    ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> pid_t? {
        if let sessionSourcePID { return sessionSourcePID }
        guard let handoffSourcePID,
              handoffSourcePID != targetPID,
              handoffSourcePID != ownPID else { return nil }
        return handoffSourcePID
    }

    static func shouldContinueFocusRetry(targetPID: pid_t,
                                         sourcePID: pid_t?,
                                         frontmostPID: @autoclosure () -> pid_t?,
                                         targetIsMinimized: Bool,
                                         targetStartedMinimized: Bool,
                                         targetWasObservedRestored: Bool = false,
                                         knownWindowIDs: Set<CGWindowID> = [],
                                         targetAppWindowIDs: @autoclosure () -> Set<CGWindowID> = [],
                                         targetAppFocusedWindowID: @autoclosure () -> CGWindowID? = nil,
                                         ignoresForeground: Bool = false,
                                         ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> Bool {
        guard !targetIsMinimized
                || (targetStartedMinimized && !targetWasObservedRestored)
        else { return false }
        let initialFrontmostPID = frontmostPID()
        let waitingForInitialMinimizedRestore = targetStartedMinimized
            && targetIsMinimized
            && (sourcePID == nil || initialFrontmostPID == sourcePID)
        if !ignoresForeground,
           let initialFrontmostPID,
           initialFrontmostPID != targetPID,
           initialFrontmostPID != ownPID,
           initialFrontmostPID != sourcePID,
           !waitingForInitialMinimizedRestore {
            return false
        }
        guard ignoresForeground || initialFrontmostPID == targetPID,
              !knownWindowIDs.isEmpty,
              !targetAppWindowIDs().isSubset(of: knownWindowIDs) else { return true }
        let focusedWindowID = targetAppFocusedWindowID()
        if !ignoresForeground, frontmostPID() != targetPID { return false }
        guard let focusedWindowID else { return true }
        return knownWindowIDs.contains(focusedWindowID)
    }

    static func isCurrentSessionStart(generation: UInt64,
                                      pendingGeneration: UInt64?) -> Bool {
        pendingGeneration == generation
    }

    static func pendingKeyDecision(sessionIsActive: Bool,
                                   hasPendingStart: Bool,
                                   commitWhenReady: Bool,
                                   matchesShortcut: Bool) -> SwitcherPendingKeyDecision {
        if sessionIsActive { return .handleActiveSession }
        guard hasPendingStart, !matchesShortcut else { return .routeShortcut }
        return commitWhenReady ? .cancelAndSwallow : .swallow
    }

    static func nativeHotkeysToSuppress(takeOverSystemShortcuts: Bool,
                                        appsShortcut: GlobalShortcut,
                                        windowShortcut: GlobalShortcut,
                                        allWindowsShortcut: GlobalShortcut? = nil,
                                        nativeShortcuts: [SwitcherNativeSymbolicHotKey: GlobalShortcut])
        -> Set<SwitcherNativeSymbolicHotKey> {
        guard takeOverSystemShortcuts else { return [] }
        let ownedShortcuts = [appsShortcut, windowShortcut] + [allWindowsShortcut].compactMap { $0 }
        return Set(nativeShortcuts.compactMap { id, nativeShortcut in
            ownedShortcuts.contains { switcherShortcut($0, owns: nativeShortcut) } ? id : nil
        })
    }

    static func nativeHotkeyIDs(takeOverSystemShortcuts: Bool,
                                secureInputEnabled: Bool,
                                appsShortcut: GlobalShortcut,
                                windowShortcut: GlobalShortcut,
                                allWindowsShortcut: GlobalShortcut? = nil,
                                liveEntries: [LiveSystemShortcut]) -> Set<Int32> {
        guard !secureInputEnabled else { return [] }
        let nativeShortcuts = Dictionary(
            liveEntries.compactMap { entry -> (SwitcherNativeSymbolicHotKey, GlobalShortcut)? in
                SwitcherNativeSymbolicHotKey(rawValue: entry.id).map { ($0, entry.shortcut) }
            },
            uniquingKeysWith: { first, _ in first })
        return Set(nativeHotkeysToSuppress(takeOverSystemShortcuts: takeOverSystemShortcuts,
                                           appsShortcut: appsShortcut,
                                           windowShortcut: windowShortcut,
                                           allWindowsShortcut: allWindowsShortcut,
                                           nativeShortcuts: nativeShortcuts).map(\.rawValue))
    }

    private static func switcherShortcut(_ shortcut: GlobalShortcut,
                                         owns nativeShortcut: GlobalShortcut) -> Bool {
        guard shortcut.keyCode == nativeShortcut.keyCode else { return false }
        if shortcut.modifiers.contains(.shift) {
            return shortcut.modifiers == nativeShortcut.modifiers
        }
        return nativeShortcut.modifiers.subtracting(.shift) == shortcut.modifiers
    }

    static func isCurrentActivationGeneration(_ scheduled: UInt64,
                                              current: UInt64) -> Bool {
        scheduled == current
    }

    static func shouldRestoreHiddenApp(revealGeneration: UInt64,
                                       currentGeneration: UInt64,
                                       appWasReactivated: Bool) -> Bool {
        revealGeneration == currentGeneration && !appWasReactivated
    }

    static func shouldContinueAppActivationRetry(targetPID: pid_t,
                                                 sourcePID: pid_t?,
                                                 frontmostPID: pid_t?,
                                                 targetWasObservedFrontmost: Bool,
                                                 ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> Bool {
        if frontmostPID == targetPID { return true }
        guard !targetWasObservedFrontmost else { return false }
        guard let frontmostPID else { return true }
        return frontmostPID == sourcePID || frontmostPID == ownPID
    }

    static func shouldKeepMinimizeRestoreObserver(targetPID: pid_t,
                                                  sourcePID: pid_t,
                                                  activatedPID: pid_t,
                                                  ownPID: pid_t = ProcessInfo.processInfo.processIdentifier,
                                                  activatedMatchesTargetBundle: Bool = false) -> Bool {
        activatedPID == targetPID || activatedPID == sourcePID || activatedPID == ownPID || activatedMatchesTargetBundle
    }

    static func closeState(afterRemoving closedItemID: String,
                           itemIDs: [String],
                           selectedIndex: Int) -> SwitcherCloseState {
        guard let removedIndex = itemIDs.firstIndex(of: closedItemID) else {
            return SwitcherCloseState(
                remainingItemIDs: itemIDs,
                selectedIndex: clampedSelection(selectedIndex, count: itemIDs.count),
                didRemove: false,
                shouldEndSession: itemIDs.isEmpty
            )
        }

        let currentIndex = clampedSelection(selectedIndex, count: itemIDs.count)
        let remaining = itemIDs.filter { $0 != closedItemID }
        guard !remaining.isEmpty else {
            return SwitcherCloseState(remainingItemIDs: [],
                                      selectedIndex: 0,
                                      didRemove: true,
                                      shouldEndSession: true)
        }

        let nextIndex: Int
        if removedIndex < currentIndex {
            nextIndex = currentIndex - 1
        } else if removedIndex == currentIndex {
            nextIndex = min(currentIndex, remaining.count - 1)
        } else {
            nextIndex = currentIndex
        }

        return SwitcherCloseState(remainingItemIDs: remaining,
                                  selectedIndex: clampedSelection(nextIndex, count: remaining.count),
                                  didRemove: true,
                                  shouldEndSession: false)
    }

    static func commitTargetID(itemIDs: [String],
                               selectedIndex: Int,
                               closingItemIDs: Set<String>) -> String? {
        guard itemIDs.indices.contains(selectedIndex) else { return nil }
        let selected = itemIDs[selectedIndex]
        guard closingItemIDs.contains(selected) else { return selected }
        let remaining = itemIDs.filter { !closingItemIDs.contains($0) }
        guard !remaining.isEmpty else { return nil }
        let position = itemIDs[..<selectedIndex].filter { !closingItemIDs.contains($0) }.count
        return remaining[clampedSelection(position, count: remaining.count)]
    }

    static func shouldDismissForClick(panelIsVisible: Bool,
                                      panelFrame: CGRect,
                                      location: CGPoint) -> Bool {
        panelIsVisible && !panelFrame.contains(location)
    }

    static func isMiddleClickInsidePanel(eventType: CGEventType,
                                         buttonNumber: Int64,
                                         panelIsVisible: Bool,
                                         panelFrame: CGRect,
                                         location: CGPoint,
                                         itemIsHovered: Bool) -> Bool {
        eventType == .otherMouseDown
            && buttonNumber == 2
            && panelIsVisible
            && panelFrame.contains(location)
            && itemIsHovered
    }

    static func shouldSwallowMiddleMouseUp(eventType: CGEventType,
                                           buttonNumber: Int64,
                                           swallowedMouseDown: Bool) -> Bool {
        eventType == .otherMouseUp
            && buttonNumber == 2
            && swallowedMouseDown
    }

    static func letterAction(typedCharacter: String?, keyCode: Int64, pinSearchEnabled: Bool) -> SwitcherLetterAction? {
        guard let letter = latinLetter(in: typedCharacter) else {
            switch keyCode {
            case USKeyPosition.w: return .closeWindow
            case USKeyPosition.q: return .quitApp
            case USKeyPosition.s where pinSearchEnabled: return .pinSearch
            default: return nil
            }
        }
        switch letter {
        case "w": return .closeWindow
        case "q": return .quitApp
        case "s" where pinSearchEnabled: return .pinSearch
        default:
            if pinSearchEnabled,
               keyCode == USKeyPosition.s,
               let typed = typedCharacter,
               !typed.unicodeScalars.allSatisfy({ $0.isASCII }) {
                return .pinSearch
            }
            return nil
        }
    }

    private enum USKeyPosition {
        static let q: Int64 = 12
        static let w: Int64 = 13
        static let s: Int64 = 1
    }

    private static func latinLetter(in text: String?) -> Character? {
        guard let folded = text?.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                         locale: nil),
              folded.count == 1,
              let letter = folded.first,
              letter.isASCII,
              letter.isLetter
        else { return nil }
        return letter
    }

    static func filteredSearchIDs(records: [SwitcherSearchRecord], query: String) -> [String] {
        let tokens = normalizedSearchTokens(query)
        guard !tokens.isEmpty else { return records.map(\.id) }
        return records.compactMap { record in
            let haystack = normalizedSearchText([record.title, record.appName])
            return tokens.allSatisfy { haystack.contains($0) } ? record.id : nil
        }
    }

    static func searchSelectionIndex(itemIDs: [String],
                                     preferredID: String?,
                                     previousIndex: Int) -> Int {
        guard !itemIDs.isEmpty else { return 0 }
        if let preferredID,
           let index = itemIDs.firstIndex(of: preferredID) {
            return index
        }
        return clampedSelection(previousIndex, count: itemIDs.count)
    }

    private static func clampedSelection(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(0, index), count - 1)
    }

    private static func normalizedSearchTokens(_ query: String) -> [String] {
        normalizedSearchText([query])
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private static func normalizedSearchText(_ parts: [String]) -> String {
        parts.joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
