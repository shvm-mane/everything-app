// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import SwiftUI

@discardableResult
private func requestDockPreviewApplicationQuit(_ item: SwitcherItem) -> Bool {
    guard let app = NSRunningApplication(processIdentifier: item.pid),
          !app.isTerminated else { return false }
    return app.terminate()
}

final class DockPreviewService: ObservableObject {
    static let shared = DockPreviewService()

    @Published private(set) var isRunning = false
    @Published private(set) var blockedReason: DockPreviewBlockedReason?
    @Published private(set) var dockAutohide = false
    @Published private(set) var windows: [SwitcherItem] = []
    @Published private(set) var previews: [CGWindowID: CGImage] = [:]
    @Published private(set) var selectedWindowID: CGWindowID?
    @Published private(set) var currentAppName: String?
    @Published private(set) var isPinned = false
    @Published private(set) var orientation: DockPreviewOrientation = .bottom
    private var isDraggingWindow = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var settingsTimer: Timer?
    private let dockAutohideHold = DockAutohideHold()
    private var dockFrameRestoration: DockPreviewFrameRestoration?
    private var dockFrameRestorationGeneration = 0
    private var dockHoldObservers: [NSObjectProtocol] = []
    private var dockHoldInputTap: CFMachPort?
    private var dockHoldInputSource: CFRunLoopSource?
    private var pendingHover: PendingHover?
    private var pendingHide: DispatchWorkItem?
    private var lastMoveSampledAt: TimeInterval = 0
    private var pendingMove: DispatchWorkItem?
    private var pendingMovePoint: CGPoint?
    private var pointerEventGeneration = 0
    private var lastAXMousePoint: CGPoint?
    private var lastAppKitMousePoint: CGPoint?
    private var panel: NSPanel?
    private var currentSessionPID: pid_t?
    private var hasEnteredPanel = false
    private var activePanelFrame: CGRect?
    private var activeCorridor: HoverCorridor?
    private var activeIconFrame: CGRect?
    private var activeDockPreferences: DockPreviewPreferences?
    private var pendingMinimizeConfirmations: [CGWindowID: UUID] = [:]
    private var pinnedPanels: [UUID: DockPreviewPinnedPanel] = [:]
    private var pinnedPanelWindows: [UUID: NSPanel] = [:]
    private var dockPIDCache: pid_t?
    private var cachedPreferences: DockPreviewPreferences?
    private var currentSpaceOnly = false
    private var spaceChangeObserver: NSObjectProtocol?

    private init() {}

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func syncWithPreferences() {
        if !UserDefaults.standard.bool(forKey: DefaultsKey.dockPreviewKeepDockVisible),
           dockAutohideHold.isHolding {
            endSession()
        }
        let freshScope = UserDefaults.standard.bool(forKey: DefaultsKey.dockPreviewCurrentSpaceOnly)
        if freshScope != currentSpaceOnly {
            currentSpaceOnly = freshScope
            endSession()
        }
        let enabled = AppFeature.dockPreview.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.dockPreviewEnabled)
        cachedPreferences = readDockPreferences()
        dockAutohide = cachedPreferences?.autohide ?? false

        if enabled {
            startSettingsTimer()
        } else {
            stopSettingsTimer()
        }

        let availability = DockPreviewSupport.availability(
            enabled: enabled,
            hasAccessibility: Permissions.shared.accessibility,
            hasScreenRecording: Permissions.shared.screenRecording,
            preferences: cachedPreferences
        )
        blockedReason = availability.blockedReason

        guard availability.canRun else {
            stopTap()
            endSession()
            closeAllPinnedPanels()
            isRunning = false
            return
        }

        if dockProcessID() == nil {
            blockedReason = .dockUnavailable
            stopTap()
            endSession()
            closeAllPinnedPanels()
            isRunning = false
            return
        }

        startTap()
        syncSpaceObservation()
    }

    private func syncSpaceObservation() {
        guard isRunning, currentSpaceOnly else {
            stopSpaceObservation()
            return
        }
        guard spaceChangeObserver == nil else { return }
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isRunning, self.currentSpaceOnly,
                  !self.isDraggingWindow else { return }
            self.endSession()
        }
    }

    private func stopSpaceObservation() {
        if let spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceChangeObserver)
        }
        spaceChangeObserver = nil
    }

    func stop() {
        stopSettingsTimer()
        stopTap()
        endSession()
        closeAllPinnedPanels()
        isRunning = false
        blockedReason = nil
    }

    func preview(_ item: SwitcherItem) {
        guard isVisible, windows.contains(item) else { return }
        cancelPendingHide()
        selectedWindowID = item.windowID
    }

    func panelCovers(axPoint: CGPoint) -> Bool {
        let point = appKitPoint(fromAX: axPoint)
        if isVisible, activePanelFrame?.contains(point) == true { return true }
        return pinnedPanelWindows.values.contains { $0.isVisible && $0.frame.contains(point) }
    }

    func dockClickWasHandled() {
        cancelPendingHover()
        guard isVisible else { return }
        let decision = DockPreviewSupport.mouseDownDecision(isVisible: isVisible,
                                                            isPinned: isPinned,
                                                            isInsidePanel: false)
        if decision.shouldEndSession {
            endSession()
        } else {
            cancelPendingHide()
        }
    }

    func endPreview(_ item: SwitcherItem) {
        guard isVisible else { return }
        guard selectedWindowID == item.windowID else { return }
        selectedWindowID = nil
    }

    func commit(_ item: SwitcherItem) {
        guard windows.contains(item) else { return }
        let generation = dockFrameRestorationGeneration
        let restoreFrame = dockFrameRestoration?.restoration(for: item) { [weak self] in
            self?.isRunning == true && self?.dockFrameRestorationGeneration == generation
        }
        endSession()
        guard WindowEnumerator.dockPreviewMayActivate(item) else { return }
        WindowActivator.activate(
            item,
            handoffSourcePID: NSWorkspace.shared.frontmostApplication?.processIdentifier
        )
        restoreFrame?()
    }

    func closePreviewPanel() {
        guard isVisible else { return }
        endSession()
    }

    func closeWindow(_ item: SwitcherItem) {
        close(item, quitAppOnClose: false)
    }

    func close(_ item: SwitcherItem) {
        close(item, quitAppOnClose: UserDefaults.standard.bool(forKey: DefaultsKey.dockPreviewQuitAppOnClose))
    }

    private func close(_ item: SwitcherItem, quitAppOnClose: Bool) {
        guard isVisible,
              windows.contains(item),
              let windowID = item.windowID
        else { return }

        DockPreviewSupport.performCloseAction(
            quitAppOnClose: quitAppOnClose,
            requestQuit: { [weak self] in
                let accepted = requestDockPreviewApplicationQuit(item)
                if accepted { self?.endSession() }
                return accepted
            },
            closeWindow: {
                WindowActivator.closeWindowIncludingHiddenState(item) { [weak self] didClose in
                    guard didClose, let self else { return }
                    if self.selectedWindowID == windowID {
                        self.selectedWindowID = nil
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                        self?.finishClosing(item, windowID: windowID, attempt: 0)
                    }
                }
            }
        )
    }

    func toggleMinimized(_ item: SwitcherItem) {
        guard isVisible,
              windows.contains(item),
              let windowID = item.windowID,
              !item.isFullscreen
        else { return }

        let shouldMinimize = !item.isMinimized
        guard WindowActivator.setWindowMinimized(shouldMinimize,
                                                 windowID: windowID,
                                                 pid: item.windowOwnerPID) else { return }
        scheduleMinimizeConfirmation(windowID: windowID,
                                     pid: item.windowOwnerPID,
                                     minimized: shouldMinimize,
                                     attempt: 0)
    }

    // MARK: - Drag to place

    func beginWindowDrag(_ item: SwitcherItem) {
        guard isVisible,
              windows.contains(item),
              DockPreviewSupport.canDragToPlace(hasWindowID: item.windowID != nil,
                                                isFullscreen: item.isFullscreen),
              let image = item.previewWindowID.flatMap({ previews[$0] })
        else { return }

        isDraggingWindow = true
        releaseDockAutohideHold()
        cancelPendingHide()
        cancelPendingHover()
        DockPreviewDragGhost.shared.begin(image: image, at: NSEvent.mouseLocation)
    }

    func updateWindowDrag() {
        guard isDraggingWindow else { return }
        DockPreviewDragGhost.shared.move(to: NSEvent.mouseLocation)
    }

    func endWindowDrag(_ item: SwitcherItem) {
        guard isDraggingWindow else { return }
        isDraggingWindow = false
        DockPreviewDragGhost.shared.end()

        guard item.windowID != nil else {
            endSession()
            return
        }
        let pointer = NSEvent.mouseLocation
        let visibleFrame = (NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
            ?? NSScreen.withMouse)?.visibleFrame ?? .zero
        let origin = axPoint(fromAppKit: DockPreviewSupport.dragOrigin(
            pointer: pointer,
            windowSize: item.frame.size,
            visibleFrame: visibleFrame
        ))
        let moved = WindowActivator.place(item, origin: origin, pointer: pointer)
        endSession()
        if moved {
            WindowActivator.activate(
                item,
                handoffSourcePID: NSWorkspace.shared.frontmostApplication?.processIdentifier
            )
            WindowActivator.focusPlacedWindow(item)
        }
    }

    func togglePinned() {
        guard isVisible, let panel, !windows.isEmpty else { return }
        createPinnedPanel(from: panel.frame)
        endSession()
    }

    func selectPreviousWindow() {
        selectAdjacentWindow(offset: -1)
    }

    func selectNextWindow() {
        selectAdjacentWindow(offset: 1)
    }

    private func selectAdjacentWindow(offset: Int) {
        guard isVisible, windows.count > 1 else { return }
        let ids = windows.compactMap(\.windowID)
        guard let nextWindowID = DockPreviewSupport.adjacentWindowID(selectedWindowID: selectedWindowID,
                                                                     windowIDs: ids,
                                                                     offset: offset),
              let next = windows.first(where: { $0.windowID == nextWindowID })
        else { return }
        preview(next)
    }

    // MARK: - Event tap

    private func startTap() {
        guard tap == nil else {
            isRunning = true
            return
        }

        let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<DockPreviewService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isRunning = false
            blockedReason = .missingAccessibility
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    private func stopTap() {
        stopSpaceObservation()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
        cancelPendingHover()
        cancelPendingMove()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let point = event.location
        if type == .mouseMoved {
            if discardFarMouseMove(axPoint: point) {
                cancelPendingMove()
                return Unmanaged.passUnretained(event)
            }
            guard admitMouseMove(axPoint: point) else {
                return Unmanaged.passUnretained(event)
            }
        } else {
            cancelPendingMove()
        }
        let generation = pointerEventGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pointerEventGeneration == generation else { return }
            self.handleOnMain(type: type, axPoint: point)
        }
        return Unmanaged.passUnretained(event)
    }

    private func discardFarMouseMove(axPoint: CGPoint) -> Bool {
        guard !isVisible, pendingHover == nil else { return false }
        let point = appKitPoint(fromAX: axPoint)
        guard !isNearDock(point) else { return false }
        lastAXMousePoint = axPoint
        lastAppKitMousePoint = point
        return true
    }

    private func admitMouseMove(axPoint: CGPoint) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastMoveSampledAt < DockPreviewSupport.mouseMoveSampleInterval else {
            lastMoveSampledAt = now
            cancelPendingMove()
            return true
        }
        pendingMovePoint = axPoint
        guard pendingMove == nil else { return false }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingMove = nil
            self.lastMoveSampledAt = ProcessInfo.processInfo.systemUptime
            guard let point = self.pendingMovePoint else { return }
            self.pendingMovePoint = nil
            self.handleOnMain(type: .mouseMoved, axPoint: point)
        }
        pendingMove = work
        DispatchQueue.main.asyncAfter(deadline: .now() + DockPreviewSupport.mouseMoveSampleInterval,
                                      execute: work)
        return false
    }

    private func cancelPendingMove() {
        pendingMove?.cancel()
        pendingMove = nil
        pendingMovePoint = nil
    }

    private func handleOnMain(type: CGEventType, axPoint: CGPoint) {
        guard isRunning else { return }
        switch type {
        case .mouseMoved:
            handleMouseMoved(axPoint)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            handleMouseDown(axPoint)
        default:
            break
        }
    }

    private func handleMouseMoved(_ axPoint: CGPoint) {
        guard !isDraggingWindow else { return }
        lastAXMousePoint = axPoint
        let point = appKitPoint(fromAX: axPoint)
        lastAppKitMousePoint = point

        if isVisible {
            if isPinned {
                switch currentZone(point: point, axPoint: axPoint) {
                case .panel:
                    hasEnteredPanel = true
                case .openingPath, .ownIcon, .otherIcon, .outside:
                    break
                }
                cancelPendingHide()
                cancelPendingHover()
                return
            }
            switch currentZone(point: point, axPoint: axPoint) {
            case .panel:
                hasEnteredPanel = true
                cancelPendingHide()
                cancelPendingHover()
            case .openingPath:
                cancelPendingHide()
                cancelPendingHover()
            case .ownIcon:
                if hasEnteredPanel {
                    scheduleHideIfStillOutside()
                } else {
                    cancelPendingHide()
                    cancelPendingHover()
                }
            case .otherIcon(let hit):
                cancelPendingHide()
                scheduleHover(hit, delay: DockPreviewSupport.switchDelay)
            case .outside:
                scheduleHideIfStillOutside()
            }
            return
        }

        if let pendingHover,
           pendingHover.iconFrame.insetBy(dx: -6, dy: -6).contains(point) {
            return
        }

        guard isNearDock(point) else {
            cancelPendingHover()
            return
        }

        guard let hit = dockHit(at: axPoint) else {
            cancelPendingHover()
            return
        }
        scheduleHover(hit)
    }

    private func isNearDock(_ point: CGPoint) -> Bool {
        guard let preferences = cachedPreferences else { return true }
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.frame else { return true }
        let band = DockPreviewSupport.dockProximityBand(tileSize: preferences.hoverTileSize)
        switch preferences.orientation {
        case .bottom: return point.y <= frame.minY + band
        case .left: return point.x <= frame.minX + band
        case .right: return point.x >= frame.maxX - band
        }
    }

    private func currentZone(point: CGPoint, axPoint: CGPoint) -> Zone {
        if activePanelFrame?.insetBy(dx: -DockPreviewSupport.panelStayMargin,
                                     dy: -DockPreviewSupport.panelStayMargin).contains(point) == true {
            return .panel
        }
        if isNearDock(point), let hit = dockHit(at: axPoint) {
            return hit.app.processIdentifier == currentSessionPID ? .ownIcon : .otherIcon(hit)
        }
        if !hasEnteredPanel, activeCorridor?.contains(point) == true { return .openingPath }
        return .outside
    }

    private func handleMouseDown(_ axPoint: CGPoint) {
        guard isVisible else {
            cancelPendingHover()
            return
        }

        let point = appKitPoint(fromAX: axPoint)
        let isInsidePanel = activePanelFrame?.contains(point) == true
        let initialDecision = DockPreviewSupport.mouseDownDecision(isVisible: isVisible,
                                                                   isPinned: isPinned,
                                                                   isInsidePanel: isInsidePanel)
        if !initialDecision.shouldEndSession {
            cancelPendingHide()
            cancelPendingHover()
            return
        }
        endSession()
    }

    private func scheduleHideIfStillOutside() {
        guard !isPinned, !isDraggingWindow else { return }
        guard pendingHide == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingHide = nil
            guard let point = self.lastAppKitMousePoint,
                  let axPoint = self.lastAXMousePoint else {
                self.endSession()
                return
            }
            switch self.currentZone(point: point, axPoint: axPoint) {
            case .panel, .openingPath:
                return
            case .ownIcon:
                if self.hasEnteredPanel { self.endSession() }
            case .otherIcon(let hit):
                self.scheduleHover(hit, delay: DockPreviewSupport.switchDelay)
            case .outside:
                self.endSession()
            }
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + DockPreviewSupport.hideDelay, execute: work)
    }

    // MARK: - Sessions

    private var openDelay: TimeInterval {
        DockPreviewSupport.openDelay(
            milliseconds: UserDefaults.standard.integer(forKey: DefaultsKey.dockPreviewOpenDelay))
    }

    private func scheduleHover(_ hit: DockHit, delay: TimeInterval? = nil) {
        if let pendingHover,
           pendingHover.app.processIdentifier == hit.app.processIdentifier,
           pendingHover.iconFrame.insetBy(dx: -6, dy: -6).intersects(hit.iconFrame) {
            return
        }

        cancelPendingHover()
        let delay = delay ?? openDelay
        let token = UUID()
        let work = DispatchWorkItem { [weak self] in
            self?.beginHoverIfStillValid(token: token, initialHit: hit)
        }
        pendingHover = PendingHover(token: token, app: hit.app, iconFrame: hit.iconFrame, workItem: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        schedulePrefetch(token: token, pid: hit.app.processIdentifier, delay: delay)
    }

    private func schedulePrefetch(token: UUID, pid: pid_t, delay: TimeInterval) {
        guard !isVisible else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pendingHover?.token == token else { return }
            let list = Self.previewableWindows(for: pid)
            guard self.pendingHover?.token == token else { return }
            self.pendingHover?.windows = list
        }
        pendingHover?.prefetchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + DockPreviewSupport.prefetchDelay(openDelay: delay),
                                      execute: work)
    }

    private static func previewableWindows(for pid: pid_t) -> [SwitcherItem] {
        let windows = WindowEnumerator.listWindowsForDockPreview(for: pid, maximumCount: 12)
            .filter { $0.windowID != nil }
        let order = DockPreviewWindowOrder.fromDefaults(
            orderByCreation: UserDefaults.standard.bool(forKey: DefaultsKey.dockPreviewOrderByCreation))
        return DockPreviewSupport.orderedWindows(windows, order: order)
    }

    private func beginHoverIfStillValid(token: UUID, initialHit: DockHit) {
        guard pendingHover?.token == token else { return }
        let point = lastAXMousePoint ?? axPoint(fromAppKit: initialHit.iconFrame.center)
        guard let hit = dockHit(at: point),
              hit.app.processIdentifier == initialHit.app.processIdentifier
        else {
            cancelPendingHover()
            return
        }
        beginSession(hit)
    }

    private func beginSession(_ hit: DockHit) {
        guard !(isPinned && isVisible) else { return }
        let prefetched = pendingHover.flatMap {
            $0.app.processIdentifier == hit.app.processIdentifier ? $0.windows : nil
        }
        cancelPendingHover()
        cancelPendingHide()

        let list = prefetched ?? Self.previewableWindows(for: hit.app.processIdentifier)
        guard !list.isEmpty else {
            if isVisible { endSession() }
            return
        }

        if isVisible {
            tearDownVisuals()
        }

        currentSessionPID = hit.app.processIdentifier
        isPinned = false
        hasEnteredPanel = false
        currentAppName = hit.app.localizedName ?? hit.app.bundleIdentifier ?? ""
        windows = list
        previews = Dictionary(uniqueKeysWithValues: list.compactMap { item in
            item.previewWindowID.flatMap { id in
                WindowPreviewProvider.shared.cachedPreview(for: id).map { (id, $0) }
            }
        })
        selectedWindowID = nil

        WindowPreviewProvider.shared.refreshPreviews(for: list, maxPixelSize: 420 * PreviewSizing.scale,
                                                     excludedAppsKey: DefaultsKey.windowPreviewExcludedApps) { [weak self] windowID, image in
            guard let self, self.isVisible, self.windows.contains(where: { $0.previewWindowID == windowID }) else { return }
            self.previews[windowID] = image
        }

        if hit.preferences.autohide,
           UserDefaults.standard.bool(forKey: DefaultsKey.dockPreviewKeepDockVisible) {
            beginDockAutohideHold()
        }
        showPanel(for: hit, itemCount: list.count)
    }

    private func endSession() {
        isDraggingWindow = false
        DockPreviewDragGhost.shared.end()
        cancelPendingHover()
        cancelPendingHide()
        WindowPreviewProvider.shared.cancel()
        panel?.orderOut(nil)
        releaseDockAutohideHold()
        tearDownVisuals()
        isPinned = false
    }

    private func tearDownVisuals() {
        cancelPendingMinimizeConfirmations()

        windows = []
        previews = [:]
        selectedWindowID = nil
        currentAppName = nil
        currentSessionPID = nil
        isPinned = false
        activePanelFrame = nil
        activeCorridor = nil
        activeIconFrame = nil
        activeDockPreferences = nil
    }

    private func cancelPendingHover() {
        pendingHover?.workItem.cancel()
        pendingHover?.prefetchWorkItem?.cancel()
        pendingHover = nil
    }

    private func cancelPendingHide() {
        pendingHide?.cancel()
        pendingHide = nil
    }

    private func cancelPendingMinimizeConfirmations() {
        pendingMinimizeConfirmations.removeAll()
    }

    private func scheduleMinimizeConfirmation(windowID: CGWindowID,
                                              pid: pid_t,
                                              minimized: Bool,
                                              attempt: Int) {
        let token = pendingMinimizeConfirmations[windowID] ?? UUID()
        pendingMinimizeConfirmations[windowID] = token
        let delay = DockPreviewMinimizeConfirmation.delay(for: attempt)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.confirmMinimizedState(windowID: windowID,
                                        pid: pid,
                                        minimized: minimized,
                                        attempt: attempt,
                                        token: token)
        }
    }

    private func confirmMinimizedState(windowID: CGWindowID,
                                       pid: pid_t,
                                       minimized: Bool,
                                       attempt: Int,
                                       token: UUID) {
        guard isVisible,
              pendingMinimizeConfirmations[windowID] == token,
              windows.contains(where: { $0.windowID == windowID })
        else { return }

        let isMinimized = WindowActivator.windowIsMinimized(windowID: windowID, pid: pid)
        if isMinimized == minimized {
            pendingMinimizeConfirmations.removeValue(forKey: windowID)
            applyMinimizedState(windowID: windowID,
                                minimized: minimized)
            return
        }

        guard attempt + 1 < DockPreviewMinimizeConfirmation.delays.count else {
            pendingMinimizeConfirmations.removeValue(forKey: windowID)
            applyMinimizedState(windowID: windowID,
                                minimized: isMinimized)
            return
        }

        _ = WindowActivator.setWindowMinimized(minimized, windowID: windowID, pid: pid)
        scheduleMinimizeConfirmation(windowID: windowID,
                                     pid: pid,
                                     minimized: minimized,
                                     attempt: attempt + 1)
    }

    private func applyMinimizedState(windowID: CGWindowID,
                                     minimized: Bool) {
        windows = windows.map { candidate in
            candidate.windowID == windowID ? candidate.withMinimized(minimized) : candidate
        }

        if minimized {
            if selectedWindowID == windowID {
                selectedWindowID = nil
            }
        } else {
            selectedWindowID = windowID
        }
    }

    private func finishClosing(_ item: SwitcherItem, windowID: CGWindowID, attempt: Int) {
        guard isVisible,
              currentSessionPID == item.pid,
              windows.contains(where: { $0.windowID == windowID })
        else { return }

        let refreshed = WindowEnumerator.listWindows(for: item.pid, maximumCount: 12)
        guard !refreshed.contains(where: { $0.windowID == windowID }) else {
            guard attempt < 2 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.finishClosing(item, windowID: windowID, attempt: attempt + 1)
            }
            return
        }

        applyClosedWindowRemoval(windowID)
    }

    private func applyClosedWindowRemoval(_ closedWindowID: CGWindowID) {
        let state = DockPreviewSupport.closeState(
            afterRemoving: closedWindowID,
            windowIDs: windows.compactMap(\.windowID),
            selectedWindowID: selectedWindowID
        )
        let remaining = Set(state.remainingWindowIDs)

        windows = windows.filter { item in
            guard let windowID = item.windowID else { return false }
            return remaining.contains(windowID)
        }
        previews = previews.filter { remaining.contains($0.key) }
        selectedWindowID = state.selectedWindowID

        if state.shouldEndSession {
            endSession()
        } else {
            resizePanelForCurrentWindows()
        }
    }

    // MARK: - Panel

    private func showPanel(for hit: DockHit, itemCount: Int) {
        let panel = ensurePanel()
        let screenVisibleFrame = visibleFrameForScreen(containing: hit.iconFrame)
        let size = DockPreviewSupport.panelSize(itemCount: itemCount,
                                                screenVisibleFrame: screenVisibleFrame,
                                                isPinned: false,
                                                orientation: hit.preferences.orientation)
        let gap = hit.preferences.autohide ? DockPreviewSupport.autohidePanelGap : DockPreviewSupport.panelGap
        let frame = DockPreviewSupport.panelFrame(anchor: hit.iconFrame,
                                                  panelSize: size,
                                                  screenVisibleFrame: screenVisibleFrame,
                                                  orientation: hit.preferences.orientation,
                                                  gap: gap)
        activePanelFrame = frame
        activeCorridor = DockPreviewSupport.hoverCorridor(
            iconFrame: hit.iconFrame,
            panelFrame: frame,
            orientation: hit.preferences.orientation
        )
        activeIconFrame = hit.iconFrame
        activeDockPreferences = hit.preferences
        orientation = hit.preferences.orientation

        panel.setFrame(frame, display: true, animate: false)
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        panel.orderFrontRegardless()
    }

    private func resizePanelForCurrentWindows() {
        guard let panel,
              panel.isVisible,
              let iconFrame = activeIconFrame,
              let preferences = activeDockPreferences
        else { return }

        let screenVisibleFrame = visibleFrameForScreen(containing: iconFrame)
        let size = DockPreviewSupport.panelSize(itemCount: windows.count,
                                                screenVisibleFrame: screenVisibleFrame,
                                                isPinned: false,
                                                orientation: preferences.orientation)
        let gap = preferences.autohide ? DockPreviewSupport.autohidePanelGap : DockPreviewSupport.panelGap
        var frame = DockPreviewSupport.panelFrame(anchor: iconFrame,
                                                  panelSize: size,
                                                  screenVisibleFrame: screenVisibleFrame,
                                                  orientation: preferences.orientation,
                                                  gap: gap)
        switch preferences.orientation {
        case .bottom: frame.origin.y = panel.frame.minY
        case .left: frame.origin.x = panel.frame.minX
        case .right: frame.origin.x = panel.frame.maxX - frame.width
        }
        frame = clampedPanelFrame(frame)
        activePanelFrame = frame
        activeCorridor = DockPreviewSupport.hoverCorridor(
            iconFrame: iconFrame,
            panelFrame: frame,
            orientation: preferences.orientation
        )
        panel.setFrame(frame, display: true, animate: true)
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
    }

    private func beginDockAutohideHold() {
        guard dockHoldObservers.isEmpty, startDockHoldInputTap() else { return }
        dockFrameRestorationGeneration &+= 1
        let frameRestoration = DockPreviewFrameRestoration()
        guard dockAutohideHold.begin() else {
            stopDockHoldInputTap()
            return
        }
        dockFrameRestoration = frameRestoration
        let workspace = NSWorkspace.shared.notificationCenter
        let events = [NSWorkspace.activeSpaceDidChangeNotification,
                      NSWorkspace.willSleepNotification,
                      NSWorkspace.sessionDidResignActiveNotification]
        dockHoldObservers = events.map { name in
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.endSession()
            }
        }
    }

    private func startDockHoldInputTap() -> Bool {
        guard dockHoldInputTap == nil else { return true }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << CGEventType.keyDown.rawValue,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<DockPreviewService>.fromOpaque(userInfo).takeUnretainedValue()
                service.handleDockHoldInput(type: type)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        dockHoldInputTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        dockHoldInputSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handleDockHoldInput(type: CGEventType) {
        guard dockAutohideHold.isHolding else { return }
        if type == .keyDown || type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            pointerEventGeneration &+= 1
            cancelPendingMove()
            endSession()
        }
    }

    private func stopDockHoldInputTap() {
        if let tap = dockHoldInputTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = dockHoldInputSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        dockHoldInputTap = nil
        dockHoldInputSource = nil
    }

    private func releaseDockAutohideHold() {
        dockAutohideHold.end()
        dockFrameRestoration = nil
        stopDockHoldInputTap()
        for observer in dockHoldObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        dockHoldObservers.removeAll()
    }

    private func clampedPanelFrame(_ frame: CGRect) -> CGRect {
        let visibleFrame = visibleFrameForScreen(containing: frame)
        let padding = DockPreviewSupport.edgePadding
        let minX = visibleFrame.minX + padding
        let maxX = visibleFrame.maxX - frame.width - padding
        let minY = visibleFrame.minY + padding
        let maxY = visibleFrame.maxY - frame.height - padding

        func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
            min(max(value, lower), max(lower, upper))
        }

        return CGRect(x: clamped(frame.minX, lower: minX, upper: maxX),
                      y: clamped(frame.minY, lower: minY, upper: maxY),
                      width: frame.width,
                      height: frame.height)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = OverlayPanel(contentRect: .zero,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered,
                                 defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentViewController = NSHostingController(rootView: DockPreviewPanelView(service: self))
        self.panel = panel
        return panel
    }

    private func createPinnedPanel(from sourceFrame: CGRect) {
        let pinned = DockPreviewPinnedPanel(
            appPID: windows[0].pid,
            windows: windows,
            previews: previews,
            selectedWindowID: selectedWindowID,
            currentAppName: currentAppName,
            onClose: { [weak self] id in
                self?.closePinnedPanel(id)
            }
        )
        let panel = makePinnedPanel(for: pinned)
        pinned.panel = panel
        let frame = clampedPanelFrame(sourceFrame)

        pinnedPanels[pinned.id] = pinned
        pinnedPanelWindows[pinned.id] = panel

        panel.setFrame(frame, display: true, animate: false)
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        panel.orderFrontRegardless()
    }

    private func makePinnedPanel(for pinned: DockPreviewPinnedPanel) -> NSPanel {
        let panel = OverlayPanel(contentRect: .zero,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered,
                                 defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentViewController = NSHostingController(rootView: DockPreviewPinnedPanelView(panel: pinned))
        return panel
    }

    private func closePinnedPanel(_ id: UUID) {
        if let panel = pinnedPanelWindows.removeValue(forKey: id) {
            panel.orderOut(nil)
            panel.contentViewController = nil
        }
        pinnedPanels.removeValue(forKey: id)
    }

    private func closeAllPinnedPanels() {
        for id in Array(pinnedPanelWindows.keys) {
            closePinnedPanel(id)
        }
    }

    private func visibleFrameForScreen(containing rect: CGRect) -> CGRect {
        let point = rect.center
        return (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.withMouse)?.visibleFrame
            ?? NSScreen.pointerVisibleFrame
    }

    // MARK: - Dock hit testing

    private func dockHit(at axPoint: CGPoint) -> DockHit? {
        guard let preferences = cachedPreferences ?? readDockPreferences(),
              let dockPID = dockProcessID()
        else { return nil }

        var overlayHit: AXUIElement?
        func systemWideHitProcessID() -> pid_t? {
            guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),
                                                   Float(axPoint.x), Float(axPoint.y),
                                                   &overlayHit) == .success else { return nil }
            return overlayHit.flatMap { pid(of: $0) }
        }

        guard DockClickSupport.dockOwnsPoint(
            axPoint,
            windows: WindowServerSupport.onScreenWindows(),
            dockProcessID: dockPID,
            dockLayer: Int(CGWindowLevelForKey(.dockWindow)),
            ownProcessID: getpid(),
            accessibilityHitProcessID: systemWideHitProcessID
        ), let element = overlayHit ?? dockElement(at: axPoint, dockPID: dockPID) else { return nil }

        let chain = elementAndParents(from: element).filter { pid(of: $0) == dockPID }
        for candidate in chain {
            switch DockTileResolver.resolution(forTile: candidate) {
            case .instance(let app):
                guard let frame = appKitFrame(of: candidate) else { continue }
                return DockHit(app: app, iconFrame: frame, preferences: preferences)
            case .unpaired:
                return nil
            case .unknown:
                continue
            }
        }
        for candidate in chain {
            guard let frame = appKitFrame(of: candidate),
                  let app = applicationByLabel(forDockElement: candidate)
            else { continue }
            return DockHit(app: app, iconFrame: frame, preferences: preferences)
        }
        return nil
    }

    private func dockElement(at axPoint: CGPoint, dockPID: pid_t) -> AXUIElement? {
        let dock = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(dock, DockPreviewSupport.dockHitTimeout)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(dock, Float(axPoint.x), Float(axPoint.y),
                                               &element) == .success else { return nil }
        return element
    }

    private func applicationByLabel(forDockElement element: AXUIElement) -> NSRunningApplication? {
        let labels = labelCandidates(from: element)
        guard !labels.isEmpty else { return nil }
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
        }
        return running.first { app in
            let names = [
                app.localizedName,
                app.bundleURL?.deletingPathExtension().lastPathComponent,
                app.bundleURL?.lastPathComponent.replacingOccurrences(of: ".app", with: ""),
            ].compactMap { $0 }.map(normalizeLabel)
            return labels.contains { label in names.contains(normalizeLabel(label)) }
        }
    }

    private func labelCandidates(from element: AXUIElement) -> [String] {
        var result: [String] = []
        for candidate in elementAndParents(from: element) {
            for attribute in [kAXTitleAttribute as String,
                              kAXDescriptionAttribute as String,
                              kAXHelpAttribute as String,
                              kAXValueAttribute as String] {
                if let value = stringAttribute(candidate, attribute), !value.isEmpty {
                    result.append(value)
                }
            }
        }
        return result
    }

    private func elementAndParents(from element: AXUIElement) -> [AXUIElement] {
        var result = [element]
        var current = element
        for _ in 0..<8 {
            guard let parent = elementAttribute(current, kAXParentAttribute as String) else { break }
            result.append(parent)
            current = parent
        }
        return result
    }

    private func dockProcessID() -> pid_t? {
        if let dockPIDCache,
           NSRunningApplication(processIdentifier: dockPIDCache)?.isTerminated == false {
            return dockPIDCache
        }
        let pid = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == "com.apple.dock"
        }?.processIdentifier
        dockPIDCache = pid
        return pid
    }

    // MARK: - Dock preferences

    private func startSettingsTimer() {
        guard settingsTimer == nil else { return }
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            let fresh = self.readDockPreferences()
            if fresh != self.cachedPreferences || !self.isRunning {
                self.syncWithPreferences()
            }
        }
        timer.tolerance = 2.5
        RunLoop.main.add(timer, forMode: .common)
        settingsTimer = timer
    }

    private func stopSettingsTimer() {
        settingsTimer?.invalidate()
        settingsTimer = nil
    }

    private func readDockPreferences() -> DockPreviewPreferences? {
        let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.dock")
            ?? UserDefaults(suiteName: "com.apple.dock")?.dictionaryRepresentation()
        guard let domain, !domain.isEmpty else {
            return nil
        }
        return DockPreviewPreferences.sanitized(
            orientation: domain["orientation"] as? String,
            autohide: dockAutohideHold.isHolding ? true : boolValue(domain["autohide"]),
            tileSize: doubleValue(domain["tilesize"]),
            magnification: boolValue(domain["magnification"]),
            magnifiedTileSize: doubleValue(domain["largesize"])
        )
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no": return false
            default: return nil
            }
        }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? CGFloat { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    // MARK: - AX helpers

    private func pid(of element: AXUIElement) -> pid_t? {
        var pid = pid_t()
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }

    private func appKitFrame(of element: AXUIElement) -> CGRect? {
        guard let origin = pointAttribute(element, kAXPositionAttribute as String),
              let size = sizeAttribute(element, kAXSizeAttribute as String),
              size.width > 0,
              size.height > 0
        else { return nil }
        return appKitFrame(fromAX: CGRect(origin: origin, size: size))
    }

    private func pointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else { return nil }
        return value as? String
    }

    private func normalizeLabel(_ value: String) -> String {
        let firstLine = value.components(separatedBy: .newlines).first ?? value
        return firstLine
            .replacingOccurrences(of: ".app", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func appKitPoint(fromAX point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: menuBarScreenTopY - point.y)
    }

    private func axPoint(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: menuBarScreenTopY - point.y)
    }

    private func appKitFrame(fromAX rect: CGRect) -> CGRect {
        CGRect(x: rect.minX,
               y: menuBarScreenTopY - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    private var menuBarScreenTopY: CGFloat {
        let menuBarScreen = NSScreen.screens.first {
            abs($0.frame.minX) < 0.5 && abs($0.frame.minY) < 0.5
        }
        return (menuBarScreen ?? NSScreen.main ?? NSScreen.screens.first)?.frame.maxY ?? 0
    }
}

private struct DockHit {
    let app: NSRunningApplication
    let iconFrame: CGRect
    let preferences: DockPreviewPreferences
}

private enum Zone {
    case panel
    case openingPath
    case ownIcon
    case otherIcon(DockHit)
    case outside
}

private struct PendingHover {
    let token: UUID
    let app: NSRunningApplication
    let iconFrame: CGRect
    let workItem: DispatchWorkItem
    var prefetchWorkItem: DispatchWorkItem?
    var windows: [SwitcherItem]?
}

private enum DockPreviewMinimizeConfirmation {
    static let delays: [TimeInterval] = [0.04, 0.12, 0.28, 0.55]

    static func delay(for attempt: Int) -> TimeInterval {
        delays[min(max(0, attempt), delays.count - 1)]
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

final class DockPreviewPinnedPanel: ObservableObject, Identifiable {
    private static let refreshInterval: TimeInterval = 0.75
    private static let maximumWindowCount = 12

    let id = UUID()
    @Published private(set) var windows: [SwitcherItem]
    @Published private(set) var previews: [CGWindowID: CGImage]
    @Published private(set) var selectedWindowID: CGWindowID?
    let currentAppName: String?

    weak var panel: NSPanel?

    private let appPID: pid_t
    private let onClose: (UUID) -> Void
    private let previewProvider = WindowPreviewProvider()
    private var refreshTimer: Timer?
    private var pendingMinimizeConfirmations: [CGWindowID: UUID] = [:]

    init(appPID: pid_t,
         windows: [SwitcherItem],
         previews: [CGWindowID: CGImage],
         selectedWindowID: CGWindowID?,
         currentAppName: String?,
         onClose: @escaping (UUID) -> Void) {
        self.appPID = appPID
        self.windows = windows
        self.previews = previews
        self.selectedWindowID = selectedWindowID
        self.currentAppName = currentAppName
        self.onClose = onClose
        startRefreshTimer()
    }

    deinit {
        refreshTimer?.invalidate()
        pendingMinimizeConfirmations.removeAll()
        previewProvider.cancel()
    }

    func preview(_ item: SwitcherItem) {
        guard windows.contains(item) else { return }
        selectedWindowID = item.windowID
    }

    func endPreview(_ item: SwitcherItem) {
        guard selectedWindowID == item.windowID else { return }
    }

    func commit(_ item: SwitcherItem) {
        guard windows.contains(item) else { return }
        guard WindowEnumerator.dockPreviewMayActivate(item) else {
            refreshWindows()
            return
        }
        selectedWindowID = item.windowID
        WindowActivator.activate(
            item,
            handoffSourcePID: NSWorkspace.shared.frontmostApplication?.processIdentifier
        )
    }

    func closeWindow(_ item: SwitcherItem) {
        close(item, quitAppOnClose: false)
    }

    func close(_ item: SwitcherItem) {
        close(item, quitAppOnClose: UserDefaults.standard.bool(forKey: DefaultsKey.dockPreviewQuitAppOnClose))
    }

    private func close(_ item: SwitcherItem, quitAppOnClose: Bool) {
        guard windows.contains(item),
              let windowID = item.windowID
        else { return }

        DockPreviewSupport.performCloseAction(
            quitAppOnClose: quitAppOnClose,
            requestQuit: { [weak self] in
                let accepted = requestDockPreviewApplicationQuit(item)
                if accepted { self?.closePreviewPanel() }
                return accepted
            },
            closeWindow: {
                WindowActivator.closeWindowIncludingHiddenState(item) { [weak self] didClose in
                    guard didClose else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                        self?.finishClosing(item, windowID: windowID, attempt: 0)
                    }
                }
            }
        )
    }

    func toggleMinimized(_ item: SwitcherItem) {
        guard windows.contains(item),
              let windowID = item.windowID,
              !item.isFullscreen
        else { return }

        let shouldMinimize = !item.isMinimized
        guard WindowActivator.setWindowMinimized(shouldMinimize,
                                                 windowID: windowID,
                                                 pid: item.windowOwnerPID) else { return }
        scheduleMinimizeConfirmation(windowID: windowID,
                                     pid: item.windowOwnerPID,
                                     minimized: shouldMinimize,
                                     attempt: 0)
    }

    func closePreviewPanel() {
        refreshTimer?.invalidate()
        pendingMinimizeConfirmations.removeAll()
        previewProvider.cancel()
        onClose(id)
    }

    func selectPreviousWindow() {
        selectAdjacentWindow(offset: -1)
    }

    func selectNextWindow() {
        selectAdjacentWindow(offset: 1)
    }

    private func selectAdjacentWindow(offset: Int) {
        let ids = windows.compactMap(\.windowID)
        guard let nextWindowID = DockPreviewSupport.adjacentWindowID(selectedWindowID: selectedWindowID,
                                                                     windowIDs: ids,
                                                                     offset: offset)
        else { return }
        selectedWindowID = nextWindowID
    }

    private func scheduleMinimizeConfirmation(windowID: CGWindowID,
                                              pid: pid_t,
                                              minimized: Bool,
                                              attempt: Int) {
        let token = pendingMinimizeConfirmations[windowID] ?? UUID()
        pendingMinimizeConfirmations[windowID] = token
        let delay = DockPreviewMinimizeConfirmation.delay(for: attempt)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.confirmMinimizedState(windowID: windowID,
                                        pid: pid,
                                        minimized: minimized,
                                        attempt: attempt,
                                        token: token)
        }
    }

    private func confirmMinimizedState(windowID: CGWindowID,
                                       pid: pid_t,
                                       minimized: Bool,
                                       attempt: Int,
                                       token: UUID) {
        guard pendingMinimizeConfirmations[windowID] == token,
              windows.contains(where: { $0.windowID == windowID })
        else { return }

        let isMinimized = WindowActivator.windowIsMinimized(windowID: windowID, pid: pid)
        if isMinimized == minimized {
            pendingMinimizeConfirmations.removeValue(forKey: windowID)
            applyMinimizedState(windowID: windowID, minimized: minimized)
            return
        }

        guard attempt + 1 < DockPreviewMinimizeConfirmation.delays.count else {
            pendingMinimizeConfirmations.removeValue(forKey: windowID)
            applyMinimizedState(windowID: windowID, minimized: isMinimized)
            return
        }

        _ = WindowActivator.setWindowMinimized(minimized, windowID: windowID, pid: pid)
        scheduleMinimizeConfirmation(windowID: windowID,
                                     pid: pid,
                                     minimized: minimized,
                                     attempt: attempt + 1)
    }

    private func applyMinimizedState(windowID: CGWindowID, minimized: Bool) {
        windows = windows.map { candidate in
            candidate.windowID == windowID ? candidate.withMinimized(minimized) : candidate
        }
        selectedWindowID = minimized ? nil : windowID
    }

    private func startRefreshTimer() {
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.refreshWindows()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func refreshWindows() {
        let previousIDs = windows.compactMap(\.windowID)
        let refreshed = DockPreviewSupport.orderedWindows(
            WindowEnumerator.listWindowsForDockPreview(for: appPID, maximumCount: Self.maximumWindowCount)
                .filter { $0.windowID != nil },
            order: DockPreviewWindowOrder.fromDefaults(
                orderByCreation: UserDefaults.standard.bool(
                    forKey: DefaultsKey.dockPreviewOrderByCreation)))
        guard !refreshed.isEmpty else {
            closePreviewPanel()
            return
        }

        let refreshedIDs = refreshed.compactMap(\.windowID)
        let windowIDsChanged = refreshedIDs != previousIDs
        let windowsChanged = refreshed != windows
        let missingPreview = refreshed.contains { item in
            guard let windowID = item.previewWindowID else { return false }
            return previews[windowID] == nil
        }
        guard windowIDsChanged || windowsChanged || missingPreview else { return }

        windows = refreshed
        previews = previews.filter { refreshedIDs.contains($0.key) }
        for item in refreshed {
            guard let windowID = item.previewWindowID,
                  previews[windowID] == nil,
                  let cached = WindowPreviewProvider.shared.cachedPreview(for: windowID)
            else { continue }
            previews[windowID] = cached
        }

        if let selectedWindowID, !refreshedIDs.contains(selectedWindowID) {
            self.selectedWindowID = refreshedIDs.first
        } else if selectedWindowID == nil {
            selectedWindowID = refreshedIDs.first
        }

        if windowIDsChanged {
            resizePanel()
        }
        refreshMissingPreviews(for: refreshed,
                               windowIDsChanged: windowIDsChanged,
                               missingPreview: missingPreview)
    }

    private func refreshMissingPreviews(for items: [SwitcherItem],
                                        windowIDsChanged: Bool,
                                        missingPreview: Bool) {
        guard windowIDsChanged || missingPreview else { return }

        previewProvider.refreshPreviews(for: items, maxPixelSize: 420 * PreviewSizing.scale,
                                        excludedAppsKey: DefaultsKey.windowPreviewExcludedApps) { [weak self] windowID, image in
            guard let self, self.windows.contains(where: { $0.previewWindowID == windowID }) else { return }
            self.previews[windowID] = image
        }
    }

    private func finishClosing(_ item: SwitcherItem, windowID: CGWindowID, attempt: Int) {
        guard windows.contains(where: { $0.windowID == windowID }) else { return }

        let refreshed = WindowEnumerator.listWindows(for: item.pid, maximumCount: 12)
        guard !refreshed.contains(where: { $0.windowID == windowID }) else {
            guard attempt < 2 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.finishClosing(item, windowID: windowID, attempt: attempt + 1)
            }
            return
        }

        windows.removeAll { $0.windowID == windowID }
        previews.removeValue(forKey: windowID)
        if selectedWindowID == windowID {
            selectedWindowID = windows.first?.windowID
        }
        if windows.isEmpty {
            closePreviewPanel()
        } else {
            resizePanel()
        }
    }

    private func resizePanel() {
        guard let panel else { return }
        let size = DockPreviewSupport.panelSize(itemCount: windows.count,
                                                screenVisibleFrame: visibleFrameForScreen(containing: panel.frame),
                                                isPinned: true)
        var frame = panel.frame
        frame.size = size
        panel.setFrame(clampedPanelFrame(frame), display: true, animate: true)
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
    }

    private func clampedPanelFrame(_ frame: CGRect) -> CGRect {
        let visibleFrame = visibleFrameForScreen(containing: frame)
        let padding = DockPreviewSupport.edgePadding
        let minX = visibleFrame.minX + padding
        let maxX = visibleFrame.maxX - frame.width - padding
        let minY = visibleFrame.minY + padding
        let maxY = visibleFrame.maxY - frame.height - padding

        func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
            min(max(value, lower), max(lower, upper))
        }

        return CGRect(x: clamped(frame.minX, lower: minX, upper: maxX),
                      y: clamped(frame.minY, lower: minY, upper: maxY),
                      width: frame.width,
                      height: frame.height)
    }

    private func visibleFrameForScreen(containing rect: CGRect) -> CGRect {
        let point = rect.center
        return (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.withMouse)?.visibleFrame
            ?? NSScreen.pointerVisibleFrame
    }
}
