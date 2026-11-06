// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import UniformTypeIdentifiers

final class ShelfService: ObservableObject {
    static let shared = ShelfService()

    struct Item: Identifiable, Equatable {
        let id: UUID
        indirect enum Payload: Equatable {
            case file(URL)
            case text(String)
            case link(URL)
            case batch([Item])
        }
        let payload: Payload
        let title: String
        let icon: NSImage
        let isImage: Bool
        let hasContentThumbnail: Bool
        let bookmark: Data?

        init(id: UUID = UUID(), payload: Payload, title: String, icon: NSImage,
             isImage: Bool, hasContentThumbnail: Bool = false, bookmark: Data? = nil) {
            self.id = id
            self.payload = payload
            self.title = title
            self.icon = icon
            self.isImage = isImage
            self.hasContentThumbnail = hasContentThumbnail
            self.bookmark = bookmark
        }

        static func == (lhs: Item, rhs: Item) -> Bool { lhs.id == rhs.id }

        func hasSameContent(as other: Item) -> Bool {
            guard id == other.id, title == other.title, isImage == other.isImage,
                  hasContentThumbnail == other.hasContentThumbnail,
                  icon === other.icon else { return false }
            switch (payload, other.payload) {
            case let (.file(lhs), .file(rhs)): return lhs == rhs
            case let (.text(lhs), .text(rhs)): return lhs == rhs
            case let (.link(lhs), .link(rhs)): return lhs == rhs
            case let (.batch(lhs), .batch(rhs)):
                return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.hasSameContent(as: $1) }
            default: return false
            }
        }

        var isBatch: Bool {
            if case .batch = payload { return true }
            return false
        }

        var batchItems: [Item] {
            if case let .batch(items) = payload { return items }
            return []
        }

        var leafCount: Int {
            switch payload {
            case .file, .text, .link: return 1
            case let .batch(items): return items.reduce(0) { $0 + $1.leafCount }
            }
        }

        var tooltipLeafKinds: [ShelfTooltipLeafKind] {
            switch payload {
            case .file: return [isImage ? .image : .file]
            case .text: return [.note]
            case .link: return [.link]
            case let .batch(items): return items.flatMap { $0.tooltipLeafKinds }
            }
        }

        var holdsFile: Bool {
            switch payload {
            case .file: return true
            case .text, .link: return false
            case let .batch(items): return items.contains(where: \.holdsFile)
            }
        }
    }

    @Published private(set) var items: [Item] = [] {
        didSet {
            contentRevision &+= 1
            scheduleRefit()
            schedulePersist()
            if items.isEmpty { dockedForcedOpen = false }
            scheduleDockedSync()
        }
    }
    @Published private(set) var selection: Set<UUID> = []
    private var selectionAnchor: UUID?
    @Published private(set) var expandedBatches: Set<UUID> = []
    @Published private(set) var pinnedIDs: Set<UUID> = [] {
        didSet { schedulePersist() }
    }
    @Published private var lastAddedID: UUID?
    @Published private(set) var contentRevision = 0
    @Published private(set) var addSerial = 0
    @Published private(set) var isPinned = false
    @Published private(set) var automaticExclusions: [String] = []

    private var panel: NSPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var registeredShortcut: GlobalShortcut?
    private var mouseMonitor: Any?
    private var shakeSamples: [(t: TimeInterval, x: CGFloat)] = []
    private var lastSummon: TimeInterval = 0
    var statusItemFrameProvider: (() -> NSRect?)?
    private var dockedPanel: NSPanel?
    @Published private(set) var dockedCollapsed = true
    @Published private(set) var dockedDragActive = false
    @Published private(set) var dockedProximate = false
    @Published private(set) var dockedPlacement = ShelfDockPlacement.menuBar
    @Published private(set) var dockedJustCaught = false
    private var dockedFlashWork: DispatchWorkItem?
    private var dockedEndWork: DispatchWorkItem?
    private var dockDwellStart: TimeInterval?
    private var dockedWatchdog: Timer?
    private var dockedForcedOpen = false
    private let autoHideDelay: TimeInterval = 5
    private let autoHideFadeDuration: TimeInterval = 0.22
    private var autoHideTimer: Timer?
    private var autoHideFadeTimer: Timer?
    private var autoHideFadeStart: Date?
    private var pointerInsidePanel = false
    @Published private(set) var dropTargeted = false
    @Published private(set) var hotkeyRegistrationFailed = false
    private var shortcutSelectionRequests = ShelfShortcutSelectionRequests()
    private var interactionDepth = 0
    private var dragBaselineChangeCount = 0
    private var dragRestingChangeCount = 0
    private var sawGestureStart = false
    private var dragBeganInDock = false
    private var dragSourceBundleIdentifier: String?
    private var activeInternalDragIDs: [UUID] = []
    private var internalDragHoldsPackageContent = false
    private weak var internalDragWindow: NSWindow?
    private var internalDragWasMerged = false
    private var edgeDwellMatch: ShelfEdgeMatch?
    private var edgeDwellStart: TimeInterval?
    private var edgePeekMatch: ShelfEdgeMatch?
    private var edgePeekEndWork: DispatchWorkItem?
    private var promiseTransfers: [UUID: (target: UUID?, transfer: ShelfFilePromiseTransfer, additions: [Item])] = [:]

    private let tempDir: URL = {
        let id = Bundle.main.bundleIdentifier ?? "com.vorssaint.utils"
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VorssaintShelf", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let storeDirectory: URL? = PrivateFileStore.containerURL?
        .appendingPathComponent("ShelfFiles", isDirectory: true)

    private static let persistQueue = DispatchQueue(label: "com.vorssaint.utils.shelf-persist",
                                                    qos: .utility)

    private var persistScheduled = false
    private var restoreCompleted = false

    private init() {
        automaticExclusions = Defaults.sanitizedBundleIdentifierList(
            UserDefaults.standard.stringArray(forKey: DefaultsKey.shelfAutomaticExclusions) ?? [])
        restoreItems()
    }

    var isVisible: Bool { panel?.isVisible == true }
    var itemCount: Int { items.reduce(0) { $0 + $1.leafCount } }
    var visibleItems: [Item] { visibleItems(in: items) }

    var revealTargetID: UUID? {
        guard let lastAddedID else { return nil }
        return ShelfRevealSupport.visibleAncestorID(of: lastAddedID,
                                                    in: revealNodes(for: items),
                                                    expanded: expandedBatches)
    }

    private func revealNodes(for items: [Item]) -> [ShelfRevealNode] {
        items.map { item in
            guard case let .batch(children) = item.payload else {
                return ShelfRevealNode(id: item.id)
            }
            return ShelfRevealNode(id: item.id, children: revealNodes(for: children))
        }
    }

    static let tileDropTypes: [NSPasteboard.PasteboardType] = {
        var types: [NSPasteboard.PasteboardType] = [
            .fileURL,
            .URL,
            .string,
            .tiff,
            .png,
            NSPasteboard.PasteboardType(UTType.gif.identifier),
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
            NSPasteboard.PasteboardType("NSURLPboardType"),
            NSPasteboard.PasteboardType(UTType.fileURL.identifier),
            NSPasteboard.PasteboardType(UTType.image.identifier),
            NSPasteboard.PasteboardType(UTType.url.identifier),
            NSPasteboard.PasteboardType(UTType.text.identifier),
            NSPasteboard.PasteboardType(UTType.plainText.identifier),
            NSPasteboard.PasteboardType("Apple files promise pasteboard type"),
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type"),
        ]
        types.append(contentsOf: NSFilePromiseReceiver.readableDraggedTypes.map {
            NSPasteboard.PasteboardType($0)
        })
        return types
    }()

    // MARK: - Lifecycle

    func syncWithPreferences() {
        reloadAutomaticExclusions()
        if NotchSupport.routesShelf() { hide(); hideDocked(); retractEdgePeek() }
        if AppFeature.shelf.isAvailable, UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled) {
            syncHotkey()
            syncDragMonitor()
        } else {
            shortcutSelectionRequests.invalidate()
            cancelPendingPromiseDeliveries()
            unregisterHotkey()
            stopDragMonitor()
            hide()
            hideDocked()
        }
        syncDockedShelf()
    }

    func addAutomaticExclusion(_ bundleIdentifier: String) {
        let updated = Defaults.sanitizedBundleIdentifierList(automaticExclusions + [bundleIdentifier])
        guard updated != automaticExclusions else { return }
        automaticExclusions = updated
        UserDefaults.standard.set(updated, forKey: DefaultsKey.shelfAutomaticExclusions)
    }

    func removeAutomaticExclusion(_ bundleIdentifier: String) {
        let updated = automaticExclusions.filter { $0 != bundleIdentifier }
        guard updated != automaticExclusions else { return }
        automaticExclusions = updated
        UserDefaults.standard.set(updated, forKey: DefaultsKey.shelfAutomaticExclusions)
    }

    private func reloadAutomaticExclusions() {
        let stored = UserDefaults.standard.stringArray(forKey: DefaultsKey.shelfAutomaticExclusions) ?? []
        let sanitized = Defaults.sanitizedBundleIdentifierList(stored)
        if stored != sanitized {
            UserDefaults.standard.set(sanitized, forKey: DefaultsKey.shelfAutomaticExclusions)
        }
        if automaticExclusions != sanitized { automaticExclusions = sanitized }
    }

    func syncDragMonitor() {
        let defaults = UserDefaults.standard
        let wanted = defaults.bool(forKey: DefaultsKey.shelfEnabled)
            && (defaults.bool(forKey: DefaultsKey.shelfShakeToOpen)
                || defaults.bool(forKey: DefaultsKey.shelfDropZoneEnabled)
                || defaults.bool(forKey: DefaultsKey.shelfEdgeDragEnabled)
                || NotchSupport.revealsShelfDrag())
        if wanted { startDragMonitor() } else { stopDragMonitor() }
        syncDockedShelf()
    }

    // MARK: - Triggers

    func syncHotkey() {
        let wanted = UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled)
            && UserDefaults.standard.bool(forKey: DefaultsKey.shelfShortcutEnabled)
        if wanted { registerHotkey() } else { unregisterHotkey() }
    }

    private func registerHotkey() {
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.shelfShortcut,
                                            fallback: .shelfDefault)
        if hotKeyRef != nil, registeredShortcut == shortcut { return }
        unregisterHotkey()
        if hotKeyHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                if let event {
                    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                      EventParamType(typeEventHotKeyID), nil,
                                      MemoryLayout<EventHotKeyID>.size, nil, &id)
                }
                guard id.signature == 0x5655_5348, id.id == 2
                else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<ShelfService>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { service.handleShortcut() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        }
        let id = EventHotKeyID(signature: 0x5655_5348, id: 2)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.carbonKeyCode,
                                         shortcut.carbonModifiers,
                                         id, GetEventDispatcherTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRef = ref
            registeredShortcut = shortcut
            hotkeyRegistrationFailed = false
            SystemShortcutTakeover.claim(DefaultsKey.shelfShortcut, shortcut: shortcut)
        } else {
            hotKeyRef = nil
            registeredShortcut = nil
            hotkeyRegistrationFailed = true
        }
    }

    func suspendShortcut() { unregisterHotkey() }

    private func unregisterHotkey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            SystemShortcutTakeover.release(DefaultsKey.shelfShortcut)
        }
        hotKeyRef = nil
        registeredShortcut = nil
        hotkeyRegistrationFailed = false
    }

    private func startDragMonitor() {
        guard mouseMonitor == nil else { return }
        closeDragGesture()
        dragBeganInDock = false
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return }
            switch event.type {
            case .leftMouseDown:
                self.beginDragGesture(with: event)
                self.shakeSamples.removeAll()
            case .leftMouseUp:
                self.closeDragGesture()
                self.endDockedDrag()
                self.endEdgePeekDrag()
            default:
                if !self.sawGestureStart {
                    self.beginDragGesture(with: event)
                }
                self.dragBeganInDock = self.dragBeganInDock || self.eventBelongsToDock(event)
                if NotchSupport.routesShelf() {
                    if self.automaticOpenAllowed, self.isContentDragActive() {
                        NotchService.shared.fileDragChanged(true)
                    }
                    self.startDockedWatchdog()
                    return
                }
                let defaults = UserDefaults.standard
                if defaults.bool(forKey: DefaultsKey.shelfShakeToOpen) {
                    self.handleDrag(event)
                }
                if defaults.bool(forKey: DefaultsKey.shelfDropZoneEnabled) {
                    self.handleDragForDock(event)
                }
                if defaults.bool(forKey: DefaultsKey.shelfEdgeDragEnabled) {
                    self.handleDragForEdge(at: event.timestamp)
                }
                self.startDockedWatchdog()
            }
        }
    }

    private func stopDragMonitor() {
        NotchService.shared.fileDragChanged(false)
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        shakeSamples.removeAll()
        dragSourceBundleIdentifier = nil
        dockedWatchdog?.invalidate()
        dockedWatchdog = nil
        dockedEndWork?.cancel()
        dockedEndWork = nil
        dockDwellStart = nil
        dockedDragActive = false
        dockedProximate = false
        edgeDwellMatch = nil
        edgeDwellStart = nil
        retractEdgePeek()
    }

    private func handleDrag(_ event: NSEvent) {
        let t = event.timestamp
        shakeSamples.append((t, NSEvent.mouseLocation.x))
        shakeSamples.removeAll { t - $0.t > 0.5 }
        guard shakeSamples.count >= 5 else { return }

        var reversals = 0
        var travel: CGFloat = 0
        var lastDirection = 0
        for i in 1..<shakeSamples.count {
            let dx = shakeSamples[i].x - shakeSamples[i - 1].x
            travel += abs(dx)
            let direction = dx > 6 ? 1 : (dx < -6 ? -1 : 0)
            if direction != 0 {
                if lastDirection != 0, direction != lastDirection { reversals += 1 }
                lastDirection = direction
            }
        }
        if reversals >= 3, travel > 220, t - lastSummon > 1.0 {
            guard isContentDragActive() else { return }
            guard automaticOpenAllowed else { return }
            lastSummon = t
            shakeSamples.removeAll()
            DispatchQueue.main.async { [weak self] in self?.summon() }
        }
    }

    private func isContentDragActive() -> Bool {
        let pasteboard = NSPasteboard(name: .drag)
        return ShelfInteractionSupport.isContentDrag(
            gestureChangeCount: dragBaselineChangeCount,
            restingChangeCount: dragRestingChangeCount,
            changeCount: pasteboard.changeCount,
            beganInDock: dragBeganInDock,
            hasDroppableContent: { pasteboardHasDroppableContent(pasteboard) })
    }

    private func beginDragGesture(with event: NSEvent) {
        sawGestureStart = true
        dragBaselineChangeCount = NSPasteboard(name: .drag).changeCount
        dragBeganInDock = eventBelongsToDock(event)
        dragSourceBundleIdentifier = sourceBundleIdentifier(for: event)
    }

    private func closeDragGesture() {
        if !isInternalDragActive { NotchService.shared.fileDragChanged(false) }
        sawGestureStart = false
        dragBaselineChangeCount = NSPasteboard(name: .drag).changeCount
        dragRestingChangeCount = dragBaselineChangeCount
    }

    func absorbOwnDrag() {
        dragRestingChangeCount = NSPasteboard(name: .drag).changeCount
    }

    private func pasteboardHasDroppableContent(_ pasteboard: NSPasteboard) -> Bool {
        (pasteboard.types ?? []).contains {
            ShelfPasteboardSupport.isDroppablePasteboardType($0.rawValue)
        }
    }

    private func eventBelongsToDock(_ event: NSEvent) -> Bool {
        if let cgEvent = event.cgEvent {
            let pid = pid_t(cgEvent.getIntegerValueField(.eventSourceUnixProcessID))
            if isDockProcess(pid) { return true }
        }

        guard event.windowNumber > 0 else { return false }
        guard let infos = CGWindowListCopyWindowInfo(.optionIncludingWindow,
                                                     CGWindowID(event.windowNumber)) as? [[String: Any]],
              let info = infos.first else { return false }
        if let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
           isDockProcess(pid_t(pidNumber.int32Value)) {
            return true
        }
        return (info[kCGWindowOwnerName as String] as? String) == "Dock"
    }

    private func isDockProcess(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.dock"
    }

    private var automaticOpenAllowed: Bool {
        ShelfInteractionSupport.allowsAutomaticOpen(
            sourceBundleIdentifier: dragSourceBundleIdentifier,
            excludedBundleIdentifiers: Set(automaticExclusions))
    }

    private func sourceBundleIdentifier(for event: NSEvent) -> String? {
        if event.windowNumber > 0,
           let infos = CGWindowListCopyWindowInfo(.optionIncludingWindow,
                                                  CGWindowID(event.windowNumber)) as? [[String: Any]],
           let pidNumber = infos.first?[kCGWindowOwnerPID as String] as? NSNumber,
           let bundleID = NSRunningApplication(processIdentifier: pid_t(pidNumber.int32Value))?.bundleIdentifier {
            return bundleID
        }
        if dragBeganInDock { return "com.apple.dock" }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    // MARK: - Docked shelf (under the menu bar icon)

    var dockedExpanded: Bool {
        dockedDragActive ? dockedProximate : !dockedCollapsed
    }
    var dockedVisible: Bool { dockedPanel?.isVisible == true }

    private var dockedFeatureOn: Bool {
        !NotchSupport.routesShelf() && AppFeature.shelf.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled)
            && UserDefaults.standard.bool(forKey: DefaultsKey.shelfDropZoneEnabled)
    }

    private var edgeFeatureOn: Bool {
        !NotchSupport.routesShelf() && AppFeature.shelf.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled)
            && UserDefaults.standard.bool(forKey: DefaultsKey.shelfEdgeDragEnabled)
    }

    private func handleDragForDock(_ event: NSEvent) {
        guard dockedFeatureOn, automaticOpenAllowed, !isVisible,
              !isInternalDragActive, isContentDragActive() else { return }
        dockedEndWork?.cancel()
        dockedEndWork = nil
        var changed = false
        if !dockedDragActive { dockedDragActive = true; changed = true }
        if updateDockedProximity(at: event.timestamp) { changed = true }

        startDockedWatchdog()
        if changed { scheduleDockedSync() }
    }

    private func updateDockedProximity(at now: TimeInterval) -> Bool {
        var changed = false
        let mouse = NSEvent.mouseLocation
        let anchor = statusItemFrameProvider?()
        let screen = anchor.flatMap { rect in
            NSScreen.screens.first { $0.frame.intersects(rect) }
        }?.frame ?? NSScreen.main?.frame

        let near = ShelfDockDragSupport.isPointNearDock(
            point: mouse,
            isProximate: dockedProximate,
            panelFrame: dockedPanel?.frame,
            anchorFrame: dockedPlacement == .menuBar ? anchor : nil,
            screenFrame: screen)

        if dockedProximate {
            if !near {
                dockedProximate = false
                dockDwellStart = nil
                changed = true
            }
        } else {
            if near {
                if dockDwellStart == nil {
                    dockDwellStart = now
                }
                if let start = dockDwellStart, ShelfDockDragSupport.hasDwelled(since: start, now: now) {
                    dockedProximate = true
                    changed = true
                }
            } else {
                dockDwellStart = nil
            }
        }
        return changed
    }

    private func endDockedDrag() {
        dockDwellStart = nil
        guard dockedDragActive, dockedEndWork == nil else { return }
        dockedWatchdog?.invalidate()
        dockedWatchdog = nil
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.dockedEndWork = nil
            self.dockedDragActive = false
            self.dockedProximate = false
            if !self.dockedJustCaught { self.dockedCollapsed = true }
            self.syncDockedShelf()
        }
        dockedEndWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func startDockedWatchdog() {
        guard dockedWatchdog == nil else { return }
        dockedWatchdog = Timer.scheduledTimer(
            withTimeInterval: min(ShelfDockDragSupport.dwell, ShelfEdgeDragSupport.dwell),
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            guard self.dockedDragActive || self.sawGestureStart else {
                self.dockedWatchdog?.invalidate()
                self.dockedWatchdog = nil
                return
            }
            guard CGEventSource.buttonState(.combinedSessionState, button: .left) else {
                self.closeDragGesture()
                self.endDockedDrag()
                self.endEdgePeekDrag()
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            if self.dockedDragActive, self.updateDockedProximity(at: now) {
                self.scheduleDockedSync()
            }
            self.handleDragForEdge(at: now)
        }
        dockedWatchdog?.tolerance = 0.05
    }

    private func handleDragForEdge(at now: TimeInterval) {
        guard edgeFeatureOn, automaticOpenAllowed, !isInternalDragActive, isContentDragActive()
        else { return }
        let mouse = NSEvent.mouseLocation
        if let edgePeekMatch {
            guard !ShelfEdgeDragSupport.stillNear(edgePeekMatch, point: mouse,
                                                  distance: ShelfEdgeDragSupport.retreatDistance)
            else { return }
            retractEdgePeek()
            return
        }
        guard !isVisible else { return }
        let screens = NSScreen.screens.map { ShelfEdgeScreen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        guard let matched = ShelfEdgeDragSupport.match(at: mouse, screens: screens,
                                                       distance: ShelfEdgeDragSupport.triggerDistance)
        else {
            edgeDwellMatch = nil
            edgeDwellStart = nil
            return
        }
        if edgeDwellMatch != matched {
            edgeDwellMatch = matched
            edgeDwellStart = now
        }
        guard let edgeDwellStart, ShelfEdgeDragSupport.hasDwelled(since: edgeDwellStart, now: now)
        else { return }
        summonEdgePeek(matched, mouse: mouse)
    }

    private func summonEdgePeek(_ match: ShelfEdgeMatch, mouse: CGPoint) {
        guard AppFeature.shelf.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled) else { return }
        edgePeekMatch = match
        edgeDwellMatch = nil
        edgeDwellStart = nil
        let panel = ensurePanel()
        cancelAutoHide()
        positionEdgePeek(panel, match: match, mouse: mouse)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        updatePointerInsidePanel()
        scheduleDockedSync()
    }

    private func positionEdgePeek(_ panel: NSPanel, match: ShelfEdgeMatch, mouse: CGPoint) {
        let view = panel.contentViewController!.view
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        let visible = visibleFrame(for: match.screen)
        let onScreenWidth = (size.width / 3).rounded()
        let x: CGFloat
        switch match.edge {
        case .left: x = visible.minX - size.width + onScreenWidth
        case .right: x = visible.maxX - onScreenWidth
        }
        var y = mouse.y - size.height / 2
        y = min(max(visible.minY + 8, y), visible.maxY - size.height - 8)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func revealEdgePeek(_ panel: NSPanel, match: ShelfEdgeMatch) {
        let size = panel.frame.size
        let visible = visibleFrame(for: match.screen)
        let x: CGFloat
        switch match.edge {
        case .left: x = visible.minX + 8
        case .right: x = visible.maxX - size.width - 8
        }
        let y = min(max(visible.minY + 8, panel.frame.minY), visible.maxY - size.height - 8)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true, animate: true)
    }

    private func visibleFrame(for screenFrame: CGRect) -> CGRect {
        NSScreen.screens.first { $0.frame == screenFrame }?.visibleFrame ?? screenFrame
    }

    private func endEdgePeekDrag() {
        guard edgePeekMatch != nil, edgePeekEndWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.edgePeekEndWork = nil
            self.retractEdgePeek()
        }
        edgePeekEndWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func retractEdgePeek() {
        edgePeekEndWork?.cancel()
        edgePeekEndWork = nil
        guard edgePeekMatch != nil else { return }
        resetAutoHide()
        panel?.orderOut(nil)
        ShelfTooltipPopover.shared.hide()
        scheduleDockedSync()
    }

    func dockDidAccept() {
        dockDwellStart = nil
        dockedJustCaught = true
        dockedCollapsed = true
        dockedForcedOpen = false
        dockedFlashWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.dockedJustCaught = false
            self.scheduleDockedSync()
        }
        dockedFlashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
        scheduleDockedSync()
    }

    func expandDocked() {
        guard dockedFeatureOn else { summon(); return }
        if isVisible { hide() }
        if itemCount == 0 { dockedForcedOpen = true }
        dockedCollapsed = false
        scheduleDockedSync()
    }

    func collapseDocked() {
        ShelfTooltipPopover.shared.hide()
        dockedCollapsed = true
        if itemCount == 0 { dockedForcedOpen = false }
        scheduleDockedSync()
    }

    func toggleDocked() {
        if dockedVisible, dockedExpanded {
            collapseDocked()
        } else {
            expandDocked()
        }
    }

    func syncDockedShelf() {
        let wanted = dockedFeatureOn && !isVisible
            && (itemCount > 0 || dockedDragActive || dockedForcedOpen)
        guard wanted else { hideDocked(); return }
        let placement = ShelfDockPlacement.current()
        if dockedPlacement != placement {
            dockedPlacement = placement
            scheduleDockedSync()
        }
        let panel = ensureDockedPanel()
        if panel.contentViewController == nil {
            let host = NSHostingController(rootView: DockedShelfView().environmentObject(self))
            host.sizingOptions = .preferredContentSize
            panel.contentViewController = host
        }
        positionDocked(panel)
    }

    private func hideDocked() {
        dockedForcedOpen = false
        guard let dockedPanel, dockedPanel.isVisible else { return }
        ShelfTooltipPopover.shared.hide()
        dockedPanel.orderOut(nil)
    }

    private func positionDocked(_ panel: NSPanel) {
        let view = panel.contentViewController!.view
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        let anchor = statusItemFrameProvider?()
        let screen = anchor.flatMap { rect in
            NSScreen.screens.first { $0.frame.intersects(rect) }
        } ?? NSScreen.withMouse
        let visible = screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
        let safeTop = screen.map { $0.frame.maxY - $0.safeAreaInsets.top } ?? visible.maxY
        panel.setFrame(dockedPlacement.frame(size: size, visible: visible, safeTop: safeTop, anchor: anchor),
                       display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private final class KeyableShelfPanel: OverlayPanel, NSDraggingDestination {
        func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            let shelf = ShelfService.shared
            let accepts = !shelf.isInternalDragActive && shelf.canAcceptPasteboard(sender.draggingPasteboard)
            shelf.setDropTargeted(accepts)
            return accepts ? .copy : []
        }

        func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }

        func draggingExited(_ sender: NSDraggingInfo?) { ShelfService.shared.setDropTargeted(false) }

        func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { draggingEntered(sender) != [] }

        func concludeDragOperation(_ sender: NSDraggingInfo?) { ShelfService.shared.setDropTargeted(false) }

        func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            defer { ShelfService.shared.setDropTargeted(false) }
            return ShelfService.shared.accept(draggingInfo: sender)
        }

        override var canBecomeKey: Bool { true }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
            if ShelfSelectionSupport.isClearSelectionShortcut(
                keyCode: event.keyCode,
                hasSelectionModifiers: !modifiers.isEmpty
            ) {
                ShelfService.shared.clearSelection()
                return true
            }
            if modifiers == [.command], event.charactersIgnoringModifiers?.lowercased() == "a" {
                ShelfService.shared.selectAllVisibleItems()
                return true
            }
            return super.performKeyEquivalent(with: event)
        }

        override func cancelOperation(_ sender: Any?) {
            ShelfService.shared.clearSelection()
        }
    }

    private func ensureDockedPanel() -> NSPanel {
        if let dockedPanel { return dockedPanel }
        let panel = KeyableShelfPanel(contentRect: .zero,
                                      styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.becomesKeyOnlyIfNeeded = true
        panel.registerForDraggedTypes(Self.tileDropTypes)
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        dockedPanel = panel
        return panel
    }

    // MARK: - Items

    func removeItem(_ id: UUID) {
        var removed: [Item] = []
        removeItems(Set([id]), from: &items, removed: &removed)
        cleanSelectionState()
        retireOwnedPayloads(in: removed)
        noteInteraction()
        ShelfTooltipPopover.shared.hide()
    }

    func removeItems(_ ids: [UUID]) {
        let set = Set(ids)
        var removed: [Item] = []
        removeItems(set, from: &items, removed: &removed)
        cleanSelectionState()
        retireOwnedPayloads(in: removed)
        noteInteraction()
        ShelfTooltipPopover.shared.hide()
    }

    func clear() {
        shortcutSelectionRequests.invalidate()
        cancelPendingPromiseDeliveries()
        let protected = protectedIDs
        guard !protected.isEmpty else {
            let removed = items
            items = []
            selection = []
            selectionAnchor = nil
            expandedBatches = []
            retireOwnedPayloads(in: removed)
            noteInteraction()
            ShelfTooltipPopover.shared.hide()
            return
        }
        let removable = leafIDs(in: items).subtracting(protected)
        guard !removable.isEmpty else { return }
        removeItems(Array(removable))
    }

    func toggleItemPin(_ id: UUID) {
        guard item(withID: id) != nil else { return }
        if pinnedIDs.contains(id) { pinnedIDs.remove(id) } else { pinnedIDs.insert(id) }
        noteInteraction()
    }

    private var protectedIDs: Set<UUID> {
        guard !pinnedIDs.isEmpty else { return [] }
        return items(withIDs: pinnedIDs, in: items).reduce(into: pinnedIDs) { ids, item in
            ids.formUnion(allIDs(in: item.batchItems))
        }
    }

    func toggleSelection(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        selectionAnchor = id
        noteInteraction()
    }

    func extendSelection(to id: UUID) {
        let visibleIDs = visibleItems.map(\.id)
        let range = ShelfSelectionSupport.rangeSelectionIDs(allIDs: visibleIDs,
                                                            anchorID: selectionAnchor,
                                                            targetID: id)
        guard !range.isEmpty else { return }
        selection.formUnion(range)
        selectionAnchor = id
        noteInteraction()
    }

    func selectAllVisibleItems() {
        let visibleIDs = visibleItems.map(\.id)
        guard !visibleIDs.isEmpty else { return }
        selection.formUnion(visibleIDs)
        noteInteraction()
    }

    func clearSelection() {
        guard !selection.isEmpty || selectionAnchor != nil else { return }
        selection.removeAll()
        selectionAnchor = nil
        noteInteraction()
    }

    func toggleBatchExpansion(_ id: UUID) {
        guard let batch = item(withID: id), batch.isBatch else { return }
        if expandedBatches.contains(id) {
            expandedBatches.remove(id)
            selection.subtract(allIDs(in: batch.batchItems))
        } else {
            expandedBatches.insert(id)
        }
        noteInteraction()
    }

    func selectedItems() -> [Item] {
        selectedItems(in: items)
    }

    func dragItems(for item: Item) -> [Item] {
        dragItems(for: [item])
    }

    func dragItems(for items: [Item]) -> [Item] {
        var result: [Item] = []
        var seen = Set<UUID>()
        for item in items {
            appendDragLeaves(from: item, to: &result, seen: &seen)
        }
        return result
    }

    func livingDragItems(in items: [Item]) -> [Item] {
        items.compactMap { item in
            guard case let .file(url) = item.payload else { return item }
            if FileManager.default.fileExists(atPath: url.path) { return item }
            guard let healed = rebookedItem(item) else { return nil }
            DispatchQueue.main.async { [weak self] in self?.replaceItem(healed) }
            return healed
        }
    }

    private static func resolvedBookmarkPath(_ bookmark: Data) -> String? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark,
                                 options: [.withoutUI, .withoutMounting],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        return url.path
    }

    private func rebookedItem(_ item: Item) -> Item? {
        guard case .file = item.payload, let bookmark = item.bookmark,
              let path = Self.resolvedBookmarkPath(bookmark),
              FileManager.default.fileExists(atPath: path) else { return nil }
        let resolved = URL(fileURLWithPath: path)
        return Item(id: item.id, payload: .file(resolved),
                    title: resolved.lastPathComponent,
                    icon: item.icon, isImage: item.isImage,
                    hasContentThumbnail: item.hasContentThumbnail,
                    bookmark: (try? resolved.bookmarkData()) ?? bookmark)
    }

    private func replaceItem(_ replacement: Item) {
        func replace(in items: inout [Item]) -> Bool {
            for index in items.indices {
                if items[index].id == replacement.id {
                    items[index] = replacement
                    return true
                }
                if case let .batch(children) = items[index].payload {
                    var mutable = children
                    if replace(in: &mutable) {
                        let face = Self.batchFace(of: mutable)
                        items[index] = Item(id: items[index].id, payload: .batch(mutable),
                                            title: items[index].title,
                                            icon: face.icon ?? symbol("doc.on.doc"),
                                            isImage: items[index].isImage,
                                            hasContentThumbnail: face.hasContentThumbnail)
                        return true
                    }
                }
            }
            return false
        }
        var current = items
        if replace(in: &current) { items = current }
    }

    func handleDeadDrag(_ items: [Item]) {
        QuickToolHUD.show(icon: "tray.full", message: L10n.shared.s.shelfFileMissing)
        let goneForever = items.filter { item in
            guard case let .file(url) = item.payload else { return false }
            let path = url.standardizedFileURL.path
            guard let volumeRoot = ShelfPersistenceSupport.unmountedVolumeRoot(of: path) else {
                return true
            }
            return FileManager.default.fileExists(atPath: volumeRoot)
        }
        guard !goneForever.isEmpty else { return }
        removeItems(goneForever.map(\.id))
    }

    func fileURLsForActions(startingAt item: Item) -> [URL] {
        fileURLs(in: selection.contains(item.id) ? selectedItems() : [item])
    }

    func fileURLsForActions() -> [URL] {
        let candidates = selectionOrEverything
        let urls = fileURLs(in: candidates)
        guard urls.isEmpty else { return urls }
        let leaves = dragItems(for: candidates)
        if leaves.contains(where: \.holdsFile) {
            handleDeadDrag(leaves)
        }
        return []
    }

    var hasFilesForActions: Bool {
        selectionOrEverything.contains(where: \.holdsFile)
    }

    private var selectionOrEverything: [Item] {
        selection.isEmpty ? items : selectedItems()
    }

    private func fileURLs(in candidates: [Item]) -> [URL] {
        livingDragItems(in: dragItems(for: candidates)).compactMap { entry in
            guard case let .file(url) = entry.payload else { return nil }
            return url
        }
    }

    func beginInternalDrag(items draggedItems: [Item], from window: NSWindow?) {
        internalDragWindow = window
        if let window, window === NotchService.shared.presentationWindow {
            NotchService.shared.fileDragChanged(true, internalDrag: true)
        }
        activeInternalDragIDs = draggedItems.map(\.id)
        internalDragWasMerged = false
        internalDragHoldsPackageContent = draggedItems.contains { item in
            guard case let .file(url) = item.payload else { return false }
            return ShelfInteractionSupport.isInsidePackage(url) {
                (try? $0.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
            }
        }
    }

    func internalDragMoved(to screenPoint: CGPoint) {
        guard !activeInternalDragIDs.isEmpty, let window = internalDragWindow,
              window === NotchService.shared.presentationWindow else { return }
        NotchService.shared.shelfDragMoved(to: screenPoint)
    }

    func finishInternalDrag(dropAccepted: Bool) -> [UUID] {
        defer {
            activeInternalDragIDs = []
            internalDragHoldsPackageContent = false
            internalDragWasMerged = false
            if let window = internalDragWindow, window === NotchService.shared.presentationWindow {
                NotchService.shared.fileDragChanged(false, internalDrag: true)
            }
            internalDragWindow = nil
        }
        guard dropAccepted, !internalDragWasMerged else { return [] }
        return activeInternalDragIDs
    }

    func completeInternalDrag(dropAccepted: Bool) {
        let notch = NotchService.shared
        let source = internalDragWindow
        let fromNotch = source != nil && source === notch.presentationWindow
        let draggedIDs = finishInternalDrag(dropAccepted: dropAccepted)
        endInteraction()
        guard !draggedIDs.isEmpty else { return }

        let defaults = UserDefaults.standard
        let removableIDs = ShelfInteractionSupport.removableAfterDrag(draggedIDs, protectedIDs: protectedIDs)
        if ShelfInteractionSupport.shouldRemoveAfterDrag(
            dropAccepted: dropAccepted,
            draggedItemCount: removableIDs.count,
            removeAfterDrop: defaults.bool(forKey: DefaultsKey.shelfRemoveAfterDrop)) {
            removeItems(removableIDs)
        }
        if ShelfInteractionSupport.shouldCloseAfterDrag(
            dropAccepted: dropAccepted,
            draggedItemCount: draggedIDs.count,
            closeAfterDrop: defaults.bool(forKey: DefaultsKey.shelfCloseAfterDrop),
            pinned: fromNotch ? notch.pinned : isPinned) {
            if fromNotch {
                if notch.expanded, notch.selected == .files, !notch.showingAppPanel, !notch.showingSections {
                    notch.collapse()
                }
            } else if isVisible, let source, source === panel {
                hide()
            } else if dockedVisible, let source, source === dockedPanel {
                collapseDocked()
            }
        }
    }

    func sourceOperationMask(for context: NSDraggingContext) -> NSDragOperation {
        if context == .withinApplication { return .move }
        let protected = protectedIDs
        return ShelfInteractionSupport.offersMoveOutside(
            removeAfterDrop: UserDefaults.standard.bool(forKey: DefaultsKey.shelfRemoveAfterDrop),
            dragIncludesPinned: activeInternalDragIDs.contains(where: protected.contains),
            dragIncludesPackageContent: internalDragHoldsPackageContent)
            ? [.copy, .move]
            : .copy
    }

    var isInternalDragActive: Bool {
        !activeInternalDragIDs.isEmpty
    }

    func canMergePasteboard(_ pasteboard: NSPasteboard, into targetID: UUID) -> Bool {
        if !activeInternalDragIDs.isEmpty {
            return canMergeInternalDrag(into: targetID)
        }
        return pasteboardCanCreateItem(pasteboard)
    }

    func mergePasteboard(_ pasteboard: NSPasteboard, into targetID: UUID) -> Bool {
        if !activeInternalDragIDs.isEmpty {
            return mergeInternalDrag(into: targetID)
        }
        return mergeExternalItems(items(from: pasteboard), into: targetID)
    }

    private func mergeExternalItems(_ additions: [Item], into targetID: UUID) -> Bool {
        guard !additions.isEmpty else { return false }
        guard merge(additions, into: targetID) else {
            discardOwnedPayloads(in: additions)
            return false
        }
        startContentThumbnails(for: additions)
        lastAddedID = dragItems(for: additions).last?.id
        addSerial &+= 1
        return true
    }

    func canAcceptPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        AppFeature.shelf.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled)
            && pasteboardCanCreateItem(pasteboard)
    }

    func accept(pasteboard: NSPasteboard) -> Bool {
        let additions = items(from: pasteboard)
        guard !additions.isEmpty else { return false }
        return append(additions.count == 1 ? additions[0] : batchItem(children: additions))
    }

    func acceptDrop(pasteboard: NSPasteboard) -> Bool {
        guard AppFeature.shelf.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled) else { return false }
        let receivers = filePromiseReceivers(from: pasteboard)
        return receivers.isEmpty
            ? accept(pasteboard: pasteboard)
            : beginPromisedFileReceive(receivers, additions: nonPromisedItems(from: pasteboard), mergeInto: nil)
    }

    func accept(draggingInfo: NSDraggingInfo) -> Bool {
        let accepted = acceptDrop(pasteboard: draggingInfo.draggingPasteboard)
        if accepted { noteAcceptedDrop(draggingInfo) }
        return accepted
    }

    func merge(draggingInfo: NSDraggingInfo, into targetID: UUID) -> Bool {
        guard AppFeature.shelf.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled) else { return false }
        let pasteboard = draggingInfo.draggingPasteboard
        let receivers = filePromiseReceivers(from: pasteboard)
        let accepted = receivers.isEmpty
            ? mergePasteboard(pasteboard, into: targetID)
            : beginPromisedFileReceive(receivers, additions: nonPromisedItems(from: pasteboard), mergeInto: targetID)
        if accepted { noteAcceptedDrop(draggingInfo) }
        return accepted
    }

    private func noteAcceptedDrop(_ draggingInfo: NSDraggingInfo) {
        if draggingInfo.draggingDestinationWindow === dockedPanel { dockDidAccept() }
        noteInteraction()
    }

    private func filePromiseReceivers(from pasteboard: NSPasteboard) -> [NSFilePromiseReceiver] {
        pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil)
            as? [NSFilePromiseReceiver] ?? []
    }

    private func beginPromisedFileReceive(_ receivers: [NSFilePromiseReceiver],
                                          additions companions: (items: [Item], positions: [Int], promises: [Int]),
                                          mergeInto targetID: UUID?) -> Bool {
        let additions = companions.items
        let available = ShelfPersistenceSupport.maxLeaves - itemCount - additions.reduce(0) { $0 + $1.leafCount }
        guard !receivers.isEmpty, receivers.count <= available,
              targetID.map({ item(withID: $0) != nil }) ?? true else {
            discardOwnedPayloads(in: additions)
            return false
        }
        let store = Self.storeDirectory ?? tempDir
        let id = UUID()
        guard let transfer = ShelfFilePromiseTransfer(temporaryDirectory: tempDir,
                                                      storeDirectory: store, maximumFiles: available,
                                                      completion: { [weak self] result in
            guard let self, self.promiseTransfers.removeValue(forKey: id) != nil else {
                ShelfFilePromiseTransfer.discard(result.urls, in: store)
                return
            }
            guard AppFeature.shelf.isAvailable,
                  UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled) else {
                ShelfFilePromiseTransfer.discard(result.urls, in: store)
                self.discardOwnedPayloads(in: additions)
                return
            }
            if let targetID, self.item(withID: targetID) == nil {
                ShelfFilePromiseTransfer.discard(result.urls, in: store)
                self.discardOwnedPayloads(in: additions)
                return
            }
            guard ShelfPersistenceSupport.canAdd(existingLeaves: self.itemCount,
                newLeaves: result.urls.count + additions.reduce(0) { $0 + $1.leafCount })
                || (result.urls.isEmpty && additions.isEmpty) else {
                ShelfFilePromiseTransfer.discard(result.urls, in: store)
                self.discardOwnedPayloads(in: additions)
                let strings = ShelfPromiseDeliveryStrings.localized(L10n.shared.language)
                self.reportPromiseDeliveryProblem(title: strings.fullTitle, body: strings.fullBody)
                return
            }
            let combined = additions + result.urls.map { self.fileItem(for: $0, deferImageThumbnail: true) }
            let receivedItems = ShelfPasteboardSupport.mergedItemIndices(
                companionPositions: companions.positions, receiverIndices: result.receiverIndices,
                promisePositions: companions.promises).map { combined[$0] }
            let added: Bool
            if receivedItems.isEmpty {
                added = true
            } else if let targetID {
                added = self.mergeExternalItems(receivedItems, into: targetID)
            } else {
                added = self.append(receivedItems.count == 1 ? receivedItems[0] : self.batchItem(children: receivedItems))
            }
            if !added { ShelfFilePromiseTransfer.discard(result.urls, in: store) }
            let strings = ShelfPromiseDeliveryStrings.localized(L10n.shared.language)
            if !added {
                self.reportPromiseDeliveryProblem(title: strings.fullTitle, body: strings.fullBody)
            } else if result.failed {
                self.reportPromiseDeliveryProblem(title: strings.failedTitle, body: strings.failedBody)
            }
        }) else {
            discardOwnedPayloads(in: additions)
            let strings = ShelfPromiseDeliveryStrings.localized(L10n.shared.language)
            reportPromiseDeliveryProblem(title: strings.failedTitle, body: strings.failedBody)
            return false
        }
        promiseTransfers[id] = (targetID, transfer, additions)
        guard transfer.receive(receivers) else {
            promiseTransfers.removeValue(forKey: id)
            discardOwnedPayloads(in: additions)
            return false
        }
        return true
    }

    private func cancelPendingPromiseDeliveries() {
        for entry in promiseTransfers.values {
            entry.transfer.cancel()
            discardOwnedPayloads(in: entry.additions)
        }
        promiseTransfers.removeAll()
    }

    private func cancelRemovedPromiseTargets() {
        let removed = promiseTransfers.filter { entry in
            entry.value.target.map { item(withID: $0) == nil } ?? false
        }
        for (id, entry) in removed {
            promiseTransfers.removeValue(forKey: id)
            entry.transfer.cancel()
            discardOwnedPayloads(in: entry.additions)
        }
    }

    private func reportPromiseDeliveryProblem(title: String, body: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: ShelfPromiseDeliveryStrings.localized(L10n.shared.language).okButton)
        if let window = panel, window.isVisible {
            alert.beginSheetModal(for: window)
        } else if let window = dockedPanel, window.isVisible {
            alert.beginSheetModal(for: window)
        } else if let window = NotchService.shared.presentationWindow, window.isVisible {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    @discardableResult
    func addFiles(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty, urls.allSatisfy(\.isFileURL) else { return false }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        return accept(pasteboard: pasteboard)
    }

    func shelveGeneratedFile(_ data: Data, named name: String) -> UUID? {
        guard AppFeature.shelf.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled),
              ShelfPersistenceSupport.canAdd(existingLeaves: itemCount, newLeaves: 1) else { return nil }
        let store = Self.storeDirectory ?? tempDir
        guard let url = ShelfPersistenceSupport.writeGeneratedFile(data, named: name, in: store) else {
            return nil
        }
        let item = fileItem(for: url, deferImageThumbnail: true)
        guard append(item) else {
            ShelfFilePromiseTransfer.discard([url], in: store)
            return nil
        }
        return item.id
    }

    func pasteboardWriter(for item: Item) -> NSPasteboardWriting {
        switch item.payload {
        case let .file(url): return url as NSURL
        case let .text(text): return text as NSString
        case let .link(url): return url as NSURL
        case let .batch(items):
            guard let first = dragItems(for: items).first else { return item.title as NSString }
            return pasteboardWriter(for: first)
        }
    }

    private static let contentThumbnailPointSize: CGFloat = 64

    private enum ContentThumbnailKind {
        case image
        case video
    }

    private func fileItem(for url: URL, id: UUID = UUID(), title: String? = nil,
                          bookmark: Data? = nil, deferImageThumbnail: Bool = false) -> Item {
        let isImage = Self.contentThumbnailKind(for: url) == .image
        let fallbackIcon = NSWorkspace.shared.icon(forFile: url.path)
        let inlineThumbnail = isImage && !deferImageThumbnail && Self.decodesCheaplyInline(url)
            ? ImageThumbnailer.thumbnail(for: url, pointSize: Self.contentThumbnailPointSize)
            : nil
        let icon = inlineThumbnail
            ?? ImageThumbnailer.thumbnail(for: fallbackIcon)
            ?? fallbackIcon
        return Item(id: id, payload: .file(url), title: title ?? url.lastPathComponent,
                    icon: icon, isImage: isImage, hasContentThumbnail: inlineThumbnail != nil,
                    bookmark: bookmark ?? (try? url.bookmarkData()))
    }

    private func startContentThumbnails(for newItems: [Item]) {
        for item in newItems {
            switch item.payload {
            case let .batch(children):
                startContentThumbnails(for: children)
            case let .file(url):
                guard !item.hasContentThumbnail,
                      let kind = Self.contentThumbnailKind(for: url) else { continue }
                patchContentThumbnail(for: url, id: item.id, kind: kind)
            default:
                continue
            }
        }
    }

    private static func contentThumbnailKind(for url: URL) -> ContentThumbnailKind? {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return nil }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        return nil
    }

    private static func decodesCheaplyInline(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return !type.conforms(to: .rawImage)
    }

    private func patchContentThumbnail(for url: URL, id: UUID, kind: ContentThumbnailKind) {
        Task { @MainActor [weak self] in
            let size = Self.contentThumbnailPointSize
            let decoded: NSImage?
            switch kind {
            case .image: decoded = await ImageThumbnailer.thumbnail(for: url, pointSize: size)
            case .video: decoded = await VideoThumbnailer.thumbnail(for: url, pointSize: size)
            }
            guard let decoded, let self, let current = self.item(withID: id) else { return }
            self.replaceItem(Item(id: current.id, payload: current.payload,
                                  title: current.title, icon: decoded,
                                  isImage: current.isImage, hasContentThumbnail: true,
                                  bookmark: current.bookmark))
        }
    }

    private func imageItem(for image: NSImage) -> Item? {
        let icon = ImageThumbnailer.thumbnail(for: image, pointSize: Self.contentThumbnailPointSize)
            ?? symbol("photo")
        if let png = autoreleasepool(invoking: { () -> Data? in
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else { return nil }
            return rep.representation(using: .png, properties: [:])
        }), let url = storePayloadData(png, fileExtension: "png") {
            return Item(payload: .file(url), title: L10n.shared.s.shelfItemImage, icon: icon,
                       isImage: true, hasContentThumbnail: true)
        }
        return nil
    }

    private func gifItem(for data: Data) -> Item? {
        guard let url = storePayloadData(data, fileExtension: "gif") else { return nil }
        let icon = ImageThumbnailer.thumbnail(for: url, pointSize: Self.contentThumbnailPointSize)
            ?? symbol("photo")
        return Item(payload: .file(url), title: "GIF", icon: icon, isImage: true, hasContentThumbnail: true)
    }

    private func storePayloadData(_ data: Data, fileExtension: String) -> URL? {
        let directory: URL
        if let store = Self.storeDirectory {
            PrivateFileStore.createDirectory(at: store)
            directory = store
        } else {
            directory = tempDir
        }
        let url = directory.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
        guard PrivateFileStore.write(data, to: url) else { return nil }
        return url
    }

    private func textItem(for string: String) -> Item? {
        guard let bounded = ShelfPersistenceSupport.boundedLiveText(string) else { return nil }
        let trimmed = bounded.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
        let icon = symbol("doc.plaintext")
        return Item(payload: .text(bounded), title: String(firstLine.prefix(48)),
                    icon: icon, isImage: false)
    }

    private func linkItem(for url: URL) -> Item {
        Item(payload: .link(url), title: url.host ?? url.absoluteString, icon: symbol("link"), isImage: false)
    }

    @discardableResult
    private func append(_ item: Item) -> Bool {
        guard ShelfPersistenceSupport.canAdd(existingLeaves: itemCount,
                                             newLeaves: item.leafCount) else {
            discardOwnedPayloads(in: [item])
            return false
        }
        items.append(item)
        startContentThumbnails(for: [item])
        lastAddedID = item.id
        addSerial &+= 1
        noteInteraction()
        return true
    }

    private static func batchFace(of children: [Item]) -> (icon: NSImage?, hasContentThumbnail: Bool) {
        (children.first?.icon, children.first?.hasContentThumbnail ?? false)
    }

    private func batchItem(id: UUID = UUID(), children: [Item]) -> Item {
        let total = children.reduce(0) { $0 + $1.leafCount }
        let title = children.first.map { "\($0.title) +\(max(0, total - 1))" } ?? ""
        let face = Self.batchFace(of: children)
        return Item(id: id, payload: .batch(children), title: title,
                    icon: face.icon ?? symbol("doc.on.doc"), isImage: false,
                    hasContentThumbnail: face.hasContentThumbnail)
    }

    private func items(from pasteboard: NSPasteboard) -> [Item] {
        guard let entries = pasteboard.pasteboardItems, entries.count > 1 else {
            return singlePasteboardItems(from: pasteboard)
        }
        return entries.flatMap { items(from: $0) }
    }

    private func nonPromisedItems(from pasteboard: NSPasteboard) -> (items: [Item], positions: [Int], promises: [Int]) {
        var result: (items: [Item], positions: [Int], promises: [Int]) = ([], [], [])
        for (index, entry) in (pasteboard.pasteboardItems ?? []).enumerated() {
            if entry.types.contains(where: { ShelfPasteboardSupport.isFilePromiseType($0.rawValue) }) {
                result.promises.append(index)
            } else {
                let found = items(from: entry)
                result.items += found
                result.positions += Array(repeating: index, count: found.count)
            }
        }
        return result
    }

    private func items(from item: NSPasteboardItem) -> [Item] {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let copy = NSPasteboardItem()
        for type in item.types where ShelfPasteboardSupport.isDroppablePasteboardType(type.rawValue)
            && !ShelfPasteboardSupport.isFilePromiseType(type.rawValue) {
            if let data = item.data(forType: type) { copy.setData(data, forType: type) }
        }
        guard !copy.types.isEmpty, board.writeObjects([copy]) else { return [] }
        return singlePasteboardItems(from: board)
    }

    private func singlePasteboardItems(from pasteboard: NSPasteboard) -> [Item] {
        let fileURLs = fileURLs(from: pasteboard)
        if !fileURLs.isEmpty {
            return fileURLs.map { fileItem(for: $0) }
        }
        if let gif = gifData(from: pasteboard),
           let item = gifItem(for: gif) {
            return [item]
        }
        if let image = NSImage(pasteboard: pasteboard),
           let item = imageItem(for: image) {
            return [item]
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL],
           let url = urls.map({ $0 as URL }).first(where: { !$0.isFileURL }) {
            return [linkItem(for: url)]
        }
        if let string = pasteboard.string(forType: .string),
           let item = textItem(for: string) {
            return [item]
        }
        return []
    }

    func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [NSURL],
           !urls.isEmpty {
            return unique(urls.map { $0 as URL }.filter(\.isFileURL))
        }
        if let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String],
           !paths.isEmpty {
            return unique(paths.map { URL(fileURLWithPath: $0) })
        }
        return []
    }

    private func pasteboardCanCreateItem(_ pasteboard: NSPasteboard) -> Bool {
        if pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil) {
            return ShelfPersistenceSupport.canAdd(existingLeaves: itemCount, newLeaves: 1)
        }
        if !fileURLs(from: pasteboard).isEmpty {
            return true
        }
        if pasteboardHasGIF(pasteboard) {
            return true
        }
        if pasteboardHasImage(pasteboard) {
            return true
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL],
           urls.contains(where: { !($0 as URL).isFileURL }) {
            return true
        }
        if let string = pasteboard.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        return false
    }

    private func gifData(from pasteboard: NSPasteboard) -> Data? {
        for type in pasteboard.types ?? [] {
            guard pasteboardTypeIsGIF(type),
                  let data = pasteboard.data(forType: type),
                  !data.isEmpty else {
                continue
            }
            return data
        }
        return nil
    }

    private func pasteboardHasGIF(_ pasteboard: NSPasteboard) -> Bool {
        (pasteboard.types ?? []).contains(where: pasteboardTypeIsGIF)
    }

    private func pasteboardHasImage(_ pasteboard: NSPasteboard) -> Bool {
        for type in pasteboard.types ?? [] {
            if pasteboardTypeIsGIF(type) { continue }
            if type == .png || type == .tiff { return true }
            if UTType(type.rawValue)?.conforms(to: .image) == true { return true }
        }
        return false
    }

    private func pasteboardTypeIsGIF(_ type: NSPasteboard.PasteboardType) -> Bool {
        type.rawValue == UTType.gif.identifier
            || UTType(type.rawValue)?.conforms(to: .gif) == true
    }

    private func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func canMergeInternalDrag(into targetID: UUID) -> Bool {
        guard !activeInternalDragIDs.isEmpty,
              !activeInternalDragIDs.contains(targetID),
              let target = item(withID: targetID)
        else { return false }
        let active = Set(activeInternalDragIDs)
        guard allIDs(in: target.batchItems).isDisjoint(with: active) else { return false }
        return !items(withIDs: active, in: items).isEmpty
    }

    private func mergeInternalDrag(into targetID: UUID) -> Bool {
        guard canMergeInternalDrag(into: targetID) else { return false }
        let sourceIDs = Set(activeInternalDragIDs)
        let additions = dragItems(for: items(withIDs: sourceIDs, in: items))
        guard !additions.isEmpty else { return false }

        var moved: [Item] = []
        removeItems(sourceIDs, from: &items, removed: &moved)
        guard merge(additions, into: targetID) else { return false }
        internalDragWasMerged = true
        ShelfTooltipPopover.shared.hide()
        return true
    }

    private func merge(_ additions: [Item], into targetID: UUID) -> Bool {
        let leaves = dragItems(for: additions)
        guard !leaves.isEmpty,
              ShelfPersistenceSupport.canAdd(existingLeaves: itemCount,
                                             newLeaves: leaves.count),
              leaves.allSatisfy({ $0.id != targetID }),
              merge(leaves, into: targetID, in: &items)
        else { return false }
        cleanSelectionState()
        noteInteraction()
        return true
    }

    private func merge(_ additions: [Item], into targetID: UUID, in items: inout [Item]) -> Bool {
        for index in items.indices {
            if items[index].id == targetID {
                switch items[index].payload {
                case let .batch(children):
                    items[index] = batchItem(id: items[index].id, children: children + additions)
                case .file, .text, .link:
                    items[index] = batchItem(id: items[index].id, children: [items[index]] + additions)
                }
                return true
            }

            guard case var .batch(children) = items[index].payload else { continue }
            if merge(additions, into: targetID, in: &children) {
                items[index] = batchItem(id: items[index].id, children: children)
                return true
            }
        }
        return false
    }

    private func retireOwnedPayloads(in removed: [Item]) {
        let urls = removed.flatMap { ownedPayloadURLs(in: $0) }
        guard !urls.isEmpty else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .seconds(10 * 60)) {
            let fm = FileManager.default
            for url in urls where self.isShelfOwnedFile(url) {
                try? fm.removeItem(at: url)
            }
        }
    }

    private func discardOwnedPayloads(in removed: [Item]) {
        let candidates = removed.flatMap { ownedPayloadURLs(in: $0) }
        let referencedPaths = Set(items.flatMap { ownedPayloadURLs(in: $0) }
            .map { $0.standardizedFileURL.path })
        let discardablePaths = ShelfPersistenceSupport.discardablePayloadPaths(
            candidatePaths: candidates.map { $0.standardizedFileURL.path },
            referencedPaths: referencedPaths)
        for url in candidates where discardablePaths.contains(url.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func ownedPayloadURLs(in item: Item) -> [URL] {
        switch item.payload {
        case let .file(url):
            return isShelfOwnedFile(url) ? [url] : []
        case .text, .link:
            return []
        case let .batch(items):
            return items.flatMap { ownedPayloadURLs(in: $0) }
        }
    }

    private func removeItems(_ ids: Set<UUID>, from items: inout [Item], removed: inout [Item]) {
        var kept: [Item] = []
        for item in items {
            if ids.contains(item.id) {
                removed.append(item)
                continue
            }

            guard case var .batch(children) = item.payload else {
                kept.append(item)
                continue
            }

            removeItems(ids, from: &children, removed: &removed)
            if children.isEmpty {
                expandedBatches.remove(item.id)
            } else if children.count == 1 {
                expandedBatches.remove(item.id)
                if pinnedIDs.contains(item.id) { pinnedIDs.insert(children[0].id) }
                kept.append(children[0])
            } else {
                kept.append(batchItem(id: item.id, children: children))
            }
        }
        items = kept
    }

    private func visibleItems(in items: [Item]) -> [Item] {
        var result: [Item] = []
        for item in items {
            result.append(item)
            if expandedBatches.contains(item.id), case let .batch(children) = item.payload {
                result.append(contentsOf: visibleItems(in: children))
            }
        }
        return result
    }

    private func selectedItems(in items: [Item]) -> [Item] {
        var result: [Item] = []
        for item in items {
            if selection.contains(item.id) { result.append(item) }
            if case let .batch(children) = item.payload {
                result.append(contentsOf: selectedItems(in: children))
            }
        }
        return result
    }

    private func appendDragLeaves(from item: Item, to result: inout [Item], seen: inout Set<UUID>) {
        switch item.payload {
        case .file, .text, .link:
            guard seen.insert(item.id).inserted else { return }
            result.append(item)
        case let .batch(items):
            for child in items {
                appendDragLeaves(from: child, to: &result, seen: &seen)
            }
        }
    }

    private func item(withID id: UUID) -> Item? {
        item(withID: id, in: items)
    }

    private func item(withID id: UUID, in items: [Item]) -> Item? {
        for item in items {
            if item.id == id { return item }
            if case let .batch(children) = item.payload,
               let found = self.item(withID: id, in: children) {
                return found
            }
        }
        return nil
    }

    private func items(withIDs ids: Set<UUID>, in items: [Item]) -> [Item] {
        var result: [Item] = []
        for item in items {
            if ids.contains(item.id) { result.append(item) }
            if case let .batch(children) = item.payload {
                result.append(contentsOf: self.items(withIDs: ids, in: children))
            }
        }
        return result
    }

    private func allIDs(in items: [Item]) -> Set<UUID> {
        var ids = Set<UUID>()
        for item in items {
            ids.insert(item.id)
            if case let .batch(children) = item.payload {
                ids.formUnion(allIDs(in: children))
            }
        }
        return ids
    }

    private func batchIDs(in items: [Item]) -> Set<UUID> {
        var ids = Set<UUID>()
        for item in items {
            if case let .batch(children) = item.payload {
                ids.insert(item.id)
                ids.formUnion(batchIDs(in: children))
            }
        }
        return ids
    }

    private func cleanSelectionState() {
        cancelRemovedPromiseTargets()
        let survivingIDs = allIDs(in: items)
        selection.formIntersection(survivingIDs)
        if let selectionAnchor, !survivingIDs.contains(selectionAnchor) {
            self.selectionAnchor = nil
        }
        expandedBatches.formIntersection(batchIDs(in: items))
        let survivingPins = pinnedIDs.intersection(survivingIDs)
        if survivingPins != pinnedIDs { pinnedIDs = survivingPins }
    }

    private func leafIDs(in items: [Item]) -> Set<UUID> {
        var ids = Set<UUID>()
        for item in items {
            if case let .batch(children) = item.payload {
                ids.formUnion(leafIDs(in: children))
            } else {
                ids.insert(item.id)
            }
        }
        return ids
    }

    private func cleanTemporaryFiles(keeping keptPaths: Set<String>, writtenBefore cutoff: Date) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: tempDir,
                                                        includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for url in entries where isShelfOwnedFile(url)
            && !ShelfPersistenceSupport.containsKeptFile(under: url.path, keptPaths: keptPaths) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if modified < cutoff { try? fm.removeItem(at: url) }
        }
    }

    private func cleanLegacyTemporaryFiles() {
        let legacyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VorssaintShelf", isDirectory: true)
        guard legacyDir != tempDir,
              let entries = try? FileManager.default.contentsOfDirectory(at: legacyDir,
                                                                         includingPropertiesForKeys: nil)
        else { return }
        for url in entries where url.pathExtension.lowercased() == "png" {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func isShelfOwnedFile(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if path.hasPrefix(tempDir.standardizedFileURL.path + "/") { return true }
        guard let store = Self.storeDirectory else { return false }
        return path.hasPrefix(store.standardizedFileURL.path + "/")
    }

    private func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }

    // MARK: - Persistence

    private func schedulePersist() {
        guard restoreCompleted, !persistScheduled else { return }
        persistScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.persistScheduled = false
            self.persistItems()
        }
    }

    private func persistItems() {
        let pinned = pinnedIDs
        let persisted = items.map { Self.persistedItem(from: $0, pinnedIDs: pinned) }
        Self.persistQueue.async {
            guard let data = try? JSONEncoder().encode(persisted) else { return }
            UserDefaults.standard.set(data, forKey: DefaultsKey.shelfItems)
        }
    }

    private func restoreItems() {
        let sweepCutoff = Date()
        let data = UserDefaults.standard.data(forKey: DefaultsKey.shelfItems)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            var sanitized: [ShelfPersistedItem] = []
            let store = ShelfPersistenceSupport.load(data)
            switch store {
            case let .items(decoded), let .partial(decoded):
                sanitized = ShelfPersistenceSupport.sanitized(decoded, fileExists: { path in
                    if FileManager.default.fileExists(atPath: path) { return true }
                    if let volumeRoot = ShelfPersistenceSupport.unmountedVolumeRoot(of: path) {
                        return !FileManager.default.fileExists(atPath: volumeRoot)
                    }
                    return false
                }, resolveBookmark: Self.resolvedBookmarkPath)
            case .unreadable:
                break
            }
            DispatchQueue.main.async {
                let restored = sanitized.compactMap { self.restoredItem(from: $0) }
                let liveItemCount = self.itemCount
                self.restoreCompleted = true
                if !restored.isEmpty {
                    var remaining = max(0, ShelfPersistenceSupport.maxLeaves - self.itemCount)
                    let keptRestored = restored.filter { item in
                        guard item.leafCount <= remaining else { return false }
                        remaining -= item.leafCount
                        return true
                    }
                    self.items = keptRestored + self.items
                    let restoredPins = Self.pinnedIDs(in: sanitized)
                        .intersection(self.allIDs(in: keptRestored))
                    if !restoredPins.isEmpty { self.pinnedIDs.formUnion(restoredPins) }
                    self.startContentThumbnails(for: keptRestored)
                }
                guard case .items = store else { return }
                if ShelfPersistenceSupport.needsPersistAfterRestore(
                    restoredIsEmpty: restored.isEmpty,
                    liveItemCount: liveItemCount) {
                    self.schedulePersist()
                }
                let keptPaths = Set(self.items.flatMap { self.ownedPayloadURLs(in: $0) }
                    .map(\.standardizedFileURL.path))
                DispatchQueue.global(qos: .utility).async {
                    self.sweepOwnedFiles(keeping: keptPaths, writtenBefore: sweepCutoff)
                }
            }
        }
    }

    private static func persistedItem(from item: Item, pinnedIDs: Set<UUID>) -> ShelfPersistedItem {
        let pinned = pinnedIDs.contains(item.id)
        switch item.payload {
        case let .file(url):
            return ShelfPersistedItem(id: item.id, kind: .file, title: item.title,
                                      path: url.path, bookmark: item.bookmark, pinned: pinned)
        case let .text(text):
            return ShelfPersistedItem(id: item.id, kind: .text, title: item.title, text: text,
                                      pinned: pinned)
        case let .link(url):
            return ShelfPersistedItem(id: item.id, kind: .link, title: item.title,
                                      url: url.absoluteString, pinned: pinned)
        case let .batch(children):
            return ShelfPersistedItem(id: item.id, kind: .batch, title: item.title,
                                      children: children.map { persistedItem(from: $0, pinnedIDs: pinnedIDs) },
                                      pinned: pinned)
        }
    }

    private static func pinnedIDs(in persisted: [ShelfPersistedItem]) -> Set<UUID> {
        persisted.reduce(into: Set<UUID>()) { ids, item in
            if item.pinned == true { ids.insert(item.id) }
            ids.formUnion(pinnedIDs(in: item.children ?? []))
        }
    }

    private func restoredItem(from persisted: ShelfPersistedItem) -> Item? {
        switch persisted.kind {
        case .file:
            guard let path = persisted.path else { return nil }
            return fileItem(for: URL(fileURLWithPath: path), id: persisted.id,
                            title: persisted.title.isEmpty ? nil : persisted.title,
                            bookmark: persisted.bookmark,
                            deferImageThumbnail: true)
        case .text:
            guard let text = persisted.text else { return nil }
            let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
            let title = persisted.title.isEmpty ? String(firstLine.prefix(48)) : persisted.title
            return Item(id: persisted.id, payload: .text(text), title: title,
                        icon: symbol("doc.plaintext"), isImage: false)
        case .link:
            guard let raw = persisted.url, let url = URL(string: raw) else { return nil }
            let title = persisted.title.isEmpty ? (url.host ?? url.absoluteString) : persisted.title
            return Item(id: persisted.id, payload: .link(url), title: title,
                        icon: symbol("link"), isImage: false)
        case .batch:
            let children = (persisted.children ?? []).compactMap { restoredItem(from: $0) }
            guard !children.isEmpty else { return nil }
            guard children.count > 1 else { return children[0] }
            return batchItem(id: persisted.id, children: children)
        }
    }

    private func sweepOwnedFiles(keeping keptPaths: Set<String>, writtenBefore cutoff: Date) {
        let fm = FileManager.default
        if let store = Self.storeDirectory,
           let entries = try? fm.contentsOfDirectory(at: store,
                                                     includingPropertiesForKeys: [.contentModificationDateKey]) {
            for url in entries where !ShelfPersistenceSupport.containsKeptFile(under: url.path, keptPaths: keptPaths) {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if modified < cutoff {
                    try? fm.removeItem(at: url)
                }
            }
        }
        cleanTemporaryFiles(keeping: keptPaths, writtenBefore: cutoff)
        cleanLegacyTemporaryFiles()
    }

    // MARK: - Panel

    func toggle() {
        if NotchService.shared.openShelf(toggle: true) { return }
        isVisible ? hide() : summon()
    }

    func handleShortcut() {
        guard shortcutMayAddFinderSelection,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        else {
            shortcutSelectionRequests.invalidate()
            toggle()
            return
        }
        let ticket = shortcutSelectionRequests.begin()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let urls = FinderBridge.selectionURLs()
            DispatchQueue.main.async {
                guard let self else { return }
                switch self.shortcutSelectionRequests.resolve(
                    ticket, urls: urls, stillAllowed: self.shortcutMayAddFinderSelection,
                    shelvedPaths: self.shelvedFilePaths) {
                case .discard:
                    return
                case .toggle:
                    self.toggle()
                case let .add(urls):
                    guard ShelfPersistenceSupport.canAdd(existingLeaves: self.itemCount,
                                                         newLeaves: urls.count) else {
                        NSSound.beep()
                        self.toggle()
                        return
                    }
                    if self.addFiles(urls) { self.summon() } else { self.toggle() }
                }
            }
        }
    }

    private var shelvedFilePaths: Set<String> {
        Set(dragItems(for: items).compactMap { item -> String? in
            guard case let .file(url) = item.payload else { return nil }
            return url.standardizedFileURL.path
        })
    }

    private var shortcutMayAddFinderSelection: Bool {
        let defaults = UserDefaults.standard
        return AppFeature.shelf.isAvailable
            && defaults.bool(forKey: DefaultsKey.shelfEnabled)
            && defaults.bool(forKey: DefaultsKey.shelfShortcutEnabled)
            && defaults.bool(forKey: DefaultsKey.shelfShortcutAddsFinderSelection)
    }

    func togglePin() {
        guard isVisible else { return }
        isPinned.toggle()
        if isPinned {
            cancelAutoHide()
        } else {
            scheduleAutoHideIfIdle()
        }
    }

    func summon() {
        guard AppFeature.shelf.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled) else { return }
        if NotchService.shared.openShelf() { return }
        let panel = ensurePanel()
        cancelAutoHide()
        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        updatePointerInsidePanel()
        scheduleAutoHideIfIdle()
        scheduleDockedSync()
    }

    func hide() {
        resetAutoHide()
        isPinned = false
        panel?.orderOut(nil)
        ShelfTooltipPopover.shared.hide()
        scheduleDockedSync()
    }

    func close() {
        if UserDefaults.standard.bool(forKey: DefaultsKey.shelfClearOnClose) {
            clear()
        }
        hide()
    }

    func noteInteraction() {
        guard panel?.isVisible == true else { return }
        cancelAutoHideFade()
        edgePeekEndWork?.cancel()
        edgePeekEndWork = nil
        if let match = edgePeekMatch, let panel {
            edgePeekMatch = nil
            revealEdgePeek(panel, match: match)
        }
        scheduleAutoHideIfIdle()
    }

    func setPointerInsidePanel(_ inside: Bool) {
        pointerInsidePanel = inside
        if inside {
            cancelAutoHide()
        } else {
            scheduleAutoHideIfIdle()
        }
    }

    func setDropTargeted(_ targeted: Bool) {
        guard dropTargeted != targeted else { return }
        dropTargeted = targeted
        if targeted {
            cancelAutoHide()
        } else {
            scheduleAutoHideIfIdle()
        }
    }

    func beginInteraction() {
        interactionDepth += 1
        cancelAutoHide()
    }

    func endInteraction() {
        interactionDepth = max(0, interactionDepth - 1)
        scheduleAutoHideIfIdle()
    }

    private func resetAutoHide() {
        cancelAutoHide()
        pointerInsidePanel = false
        dropTargeted = false
        interactionDepth = 0
        edgePeekEndWork?.cancel()
        edgePeekEndWork = nil
        edgePeekMatch = nil
    }

    private func cancelAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        cancelAutoHideFade()
    }

    private func cancelAutoHideFade() {
        autoHideFadeTimer?.invalidate()
        autoHideFadeTimer = nil
        autoHideFadeStart = nil
        panel?.alphaValue = 1
    }

    private var shouldHoldOpen: Bool {
        isPinned || !items.isEmpty || pointerInsidePanel || dropTargeted || interactionDepth > 0
            || edgePeekMatch != nil
    }

    private func scheduleAutoHideIfIdle() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        guard panel?.isVisible == true, !shouldHoldOpen else { return }

        autoHideTimer = Timer.scheduledTimer(withTimeInterval: autoHideDelay, repeats: false) { [weak self] _ in
            self?.autoHideIfIdle()
        }
        autoHideTimer?.tolerance = 0.5
    }

    private func autoHideIfIdle() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        updatePointerInsidePanel()
        guard panel?.isVisible == true else { return }
        guard !shouldHoldOpen else {
            scheduleAutoHideIfIdle()
            return
        }
        fadeOutAndHide()
    }

    private func updatePointerInsidePanel() {
        guard let panel, panel.isVisible else {
            pointerInsidePanel = false
            return
        }
        pointerInsidePanel = panel.frame.contains(NSEvent.mouseLocation)
    }

    private func fadeOutAndHide() {
        guard let panel, panel.isVisible else { return }
        autoHideFadeTimer?.invalidate()
        autoHideFadeStart = Date()
        panel.alphaValue = 1

        autoHideFadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self, let panel = self.panel, panel.isVisible else {
                timer.invalidate()
                return
            }
            self.updatePointerInsidePanel()
            guard !self.shouldHoldOpen else {
                timer.invalidate()
                self.autoHideFadeTimer = nil
                self.autoHideFadeStart = nil
                panel.alphaValue = 1
                self.scheduleAutoHideIfIdle()
                return
            }
            let elapsed = Date().timeIntervalSince(self.autoHideFadeStart ?? Date())
            let progress = min(1, elapsed / self.autoHideFadeDuration)
            panel.alphaValue = 1 - CGFloat(progress)
            guard progress >= 1 else { return }
            timer.invalidate()
            self.autoHideFadeTimer = nil
            self.autoHideFadeStart = nil
            panel.orderOut(nil)
            ShelfTooltipPopover.shared.hide()
            panel.alphaValue = 1
            self.pointerInsidePanel = false
            self.dropTargeted = false
            self.interactionDepth = 0
            self.edgePeekEndWork?.cancel()
            self.edgePeekEndWork = nil
            self.edgePeekMatch = nil
            self.scheduleDockedSync()
        }
        autoHideFadeTimer?.tolerance = 0.02
    }

    private func scheduleRefit() {
        DispatchQueue.main.async { [weak self] in self?.refitIfVisible() }
    }

    private func scheduleDockedSync() {
        DispatchQueue.main.async { [weak self] in self?.syncDockedShelf() }
    }

    private func refitIfVisible() {
        guard let panel, panel.isVisible else { return }
        let view = panel.contentViewController!.view
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        let top = panel.frame.maxY
        panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height),
                       display: true, animate: false)
    }

    private func position(_ panel: NSPanel) {
        let view = panel.contentViewController!.view
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.pointerVisibleFrame
        var x = mouse.x - size.width / 2
        var y = mouse.y - size.height - 16
        x = min(max(screen.minX + 8, x), screen.maxX - size.width - 8)
        y = min(max(screen.minY + 8, y), screen.maxY - size.height - 8)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyableShelfPanel(contentRect: .zero,
                                      styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.becomesKeyOnlyIfNeeded = true
        panel.registerForDraggedTypes(Self.tileDropTypes)
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: ShelfView().environmentObject(self))
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }
}
