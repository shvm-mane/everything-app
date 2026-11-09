// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

final class RadialMenuService: ObservableObject {
    static let shared = RadialMenuService()

    @Published private(set) var stack: [[RadialMenuItem]] = []
    @Published private(set) var activeProfile: RadialMenuProfile?
    @Published private(set) var trail: [String] = []
    @Published private(set) var highlightedIndex: Int?
    @Published private(set) var nowPlayingState = RadialNowPlayingState.nothingPlaying
    @Published private(set) var holdPhase = false
    @Published private(set) var registrationFailed = false
    @Published private(set) var isWatchingMouseButton = false
    @Published private(set) var lastMouseButtonSeen: Int?
    private var isReportingMouseButtons = false

    func setReportingMouseButtons(_ reporting: Bool) {
        isReportingMouseButtons = reporting
        if !reporting, lastMouseButtonSeen != nil { lastMouseButtonSeen = nil }
        if reporting { syncMouseTap() }
    }

    @Published private(set) var visible = false

    private var hotkeys: [UUID: QuickToolHotkey] = [:]
    private var panel: NSPanel?
    private var wheelCenter: CGPoint = .zero
    private var openPointerLocation: CGPoint = .zero
    private var pointerActivated = false
    private var sessionShortcut: GlobalShortcut?
    private var sessionActivationMode = RadialMenuActivationMode.pressOrHold
    private var sessionUsesSuperKey = false
    private var sessionID = 0
    private var holdButton: Int64?
    private var mouseTap: CFMachPort?
    private var mouseTapSource: CFRunLoopSource?
    private var eventMonitors: [Any] = []
    private var activationObserver: NSObjectProtocol?
    private var promptedForAccessibility = false
    private let dismissal = PanelDismissal()

    private init() {
        SessionActivity.shared.onChange { [weak self] active in
            if !active { self?.endSession() }
            self?.syncMouseTap()
        }
    }

    var sessionActive: Bool { !stack.isEmpty && !dismissal.isActive }

    private var currentItems: [RadialMenuItem] { stack.last ?? [] }

    // MARK: - Lifecycle

    func syncWithPreferences() {
        defer { MiddleClickService.shared.syncWithPreferences() }
        let defaults = UserDefaults.standard
        let enabled = AppFeature.radialMenu.isAvailable
            && defaults.bool(forKey: DefaultsKey.radialMenuEnabled)
        guard enabled else {
            suspend()
            registrationFailed = false
            return
        }
        fillMissingLinkIcons()

        let profiles = RadialMenuSupport.decodeProfiles(
            defaults.data(forKey: DefaultsKey.radialMenuProfiles),
            defaults: defaults
        )

        for hotkey in hotkeys.values { hotkey.unregister() }
        hotkeys.removeAll()

        var anyFailed = false
        for (index, profile) in profiles.enumerated() {
            guard !profile.shortcut.isEmpty,
                  let shortcut = GlobalShortcut(storageValue: profile.shortcut) else { continue }
            let hotkey = QuickToolHotkey(id: 1700 + UInt32(index))
            hotkey.onPress = { [weak self] in self?.hotkeyPressed(for: profile) }
            let registered = hotkey.sync(
                enabled: true, shortcut: shortcut,
                storageKey: "\(DefaultsKey.radialMenuProfiles).\(profile.id.uuidString)")
            if !registered { anyFailed = true }
            hotkeys[profile.id] = hotkey
        }
        registrationFailed = anyFailed

        syncMouseTap(profiles: profiles)
        ensurePanel().contentView?.layoutSubtreeIfNeeded()
    }

    func suspend() {
        for hotkey in hotkeys.values { hotkey.unregister() }
        hotkeys.removeAll()
        tearDownMouseTap()
        endSession()
        panel = nil
    }

    // MARK: - Mouse button trigger (a tap so the click never also reaches the

    private func mouseTapWanted(profiles: [RadialMenuProfile]?) -> Bool {
        let defaults = UserDefaults.standard
        let hasAnyButton = profiles.map { list in
            list.contains { RadialMenuMouseTrigger.sanitized($0.mouseButton).buttonNumber != nil }
        } ?? !RadialMenuSupport.claimedMouseButtons(
            defaults.data(forKey: DefaultsKey.radialMenuProfiles),
            defaults: defaults
        ).isEmpty
        let enabled = AppFeature.radialMenu.isAvailable
            && defaults.bool(forKey: DefaultsKey.radialMenuEnabled)
        return (hasAnyButton && enabled) || isReportingMouseButtons
    }

    private func syncMouseTap(profiles: [RadialMenuProfile]? = nil) {
        guard SessionActivitySupport.tapShouldRun(
            featureWanted: mouseTapWanted(profiles: profiles),
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive
        ) else {
            tearDownMouseTap()
            return
        }
        if let mouseTap, !CGEvent.tapIsEnabled(tap: mouseTap) {
            tearDownMouseTap()
        }
        guard mouseTap == nil else { return }
        let mask = (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<RadialMenuService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handleMouseTap(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        mouseTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        mouseTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        if !isWatchingMouseButton { isWatchingMouseButton = true }
    }

    private func tearDownMouseTap() {
        if let mouseTap {
            CGEvent.tapEnable(tap: mouseTap, enable: false)
            CFMachPortInvalidate(mouseTap)
        }
        if let mouseTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), mouseTapSource, .commonModes)
        }
        mouseTap = nil
        mouseTapSource = nil
        if isWatchingMouseButton { isWatchingMouseButton = false }
    }

    private func handleMouseTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if SessionActivitySupport.tapShouldRun(
                featureWanted: mouseTapWanted(profiles: nil),
                accessibilityGranted: AXIsProcessTrusted(),
                sessionIsActive: SessionActivity.shared.isActive
            ), let mouseTap {
                CGEvent.tapEnable(tap: mouseTap, enable: true)
            } else {
                DispatchQueue.main.async { [weak self] in self?.syncMouseTap() }
            }
            return Unmanaged.passUnretained(event)
        }
        let pressed = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        if MouseButtonShortcutService.isCaptureActive {
            return Unmanaged.passUnretained(event)
        }
        if isReportingMouseButtons, type == .otherMouseDown {
            lastMouseButtonSeen = pressed
        }
        let defaults = UserDefaults.standard
        let button = Int64(pressed)
        guard RadialMenuSupport.claimedMouseButtons(
            defaults.data(forKey: DefaultsKey.radialMenuProfiles),
            defaults: defaults
        ).contains(button) else {
            return Unmanaged.passUnretained(event)
        }

        if type == .otherMouseDown {
            if !sessionActive {
                let profiles = RadialMenuSupport.decodeProfiles(
                    defaults.data(forKey: DefaultsKey.radialMenuProfiles),
                    defaults: defaults
                )
                if let matchingProfile = profiles.first(where: {
                    RadialMenuMouseTrigger.sanitized($0.mouseButton).buttonNumber == button
                }) {
                    beginSession(for: matchingProfile, hold: false, heldButton: button)
                }
            } else if !holdPhase {
                endSession()
            }
        } else if holdPhase, holdButton == button {
            endHoldPhase()
        }
        return nil
    }

    // MARK: - Session

    private func hotkeyPressed(for profile: RadialMenuProfile) {
        if sessionActive {
            if activeProfile?.id == profile.id {
                endSession()
                return
            }
            endSession()
        }
        beginSession(for: profile, hold: true)
    }

    func toggleFromTrackpad() {
        let defaults = UserDefaults.standard
        guard AppFeature.radialMenu.isAvailable,
              defaults.bool(forKey: DefaultsKey.radialMenuEnabled),
              let profile = RadialMenuSupport.decodeProfiles(
                  defaults.data(forKey: DefaultsKey.radialMenuProfiles), defaults: defaults
              ).first(where: \.trackpadTap) else { return }
        if sessionActive {
            let sameWheel = activeProfile?.id == profile.id
            endSession()
            if sameWheel { return }
        }
        beginSession(for: profile, hold: false)
    }

    func presentPreview(for profile: RadialMenuProfile? = nil) {
        endSession()
        let defaults = UserDefaults.standard
        let profiles = RadialMenuSupport.decodeProfiles(
            defaults.data(forKey: DefaultsKey.radialMenuProfiles),
            defaults: defaults
        )
        let targetProfile = profile ?? profiles.first ?? RadialMenuProfilePreset.general.createProfile()
        beginSession(for: targetProfile, hold: false)
    }

    private func beginSession(for profile: RadialMenuProfile, hold: Bool, heldButton: Int64? = nil) {
        let defaults = UserDefaults.standard
        let items = availableItems(profile.items)
        guard !items.isEmpty else {
            NSSound.beep()
            return
        }
        dismissal.cancel { forgetSession() }
        visible = false
        activeProfile = profile
        if RadialMenuSupport.containsNowPlaying(items) {
            let nowPlaying = RadialNowPlayingService.shared
            nowPlaying.dismissDetails()
            nowPlaying.refresh { [weak self] state in self?.nowPlayingState = state }
        } else {
            nowPlayingState = .nothingPlaying
        }

        let shortcut = GlobalShortcut(storageValue: profile.shortcut) ?? .radialMenuDefault
        let activationMode = RadialMenuActivationMode.sanitized(
            defaults.string(forKey: DefaultsKey.radialMenuActivationMode))
        let startsHeld = activationMode.startsHeld(
            requestedHold: hold,
            hasHeldButton: heldButton != nil,
            shortcutHasModifiers: !shortcut.modifiers.isEmpty)
        sessionActivationMode = activationMode
        sessionShortcut = startsHeld && heldButton == nil ? shortcut : nil
        sessionUsesSuperKey = startsHeld && heldButton == nil
            && SuperKeyService.isEngaged && SuperKeyService.shared.isHeld
        holdButton = startsHeld ? heldButton : nil
        holdPhase = startsHeld
        sessionID &+= 1
        let activeSessionID = sessionID
        if sessionUsesSuperKey {
            SuperKeyService.shared.onHoldEnded = { [weak self] released in
                guard let self,
                      self.sessionUsesSuperKey,
                      self.sessionID == activeSessionID else { return }
                self.sessionShortcut = nil
                DispatchQueue.main.async {
                    guard self.sessionUsesSuperKey,
                          self.sessionID == activeSessionID else { return }
                    if released {
                        self.endHoldPhase()
                    } else {
                        self.endSession()
                    }
                }
            }
        }
        stack = [items]
        trail = []
        highlightedIndex = nil
        pointerActivated = false
        openPointerLocation = NSEvent.mouseLocation

        let atPointer = defaults.bool(forKey: DefaultsKey.radialMenuAtPointer)
        let visibleFrame = NSScreen.pointerVisibleFrame
        let wanted = atPointer ? NSEvent.mouseLocation
                               : CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        wheelCenter = clampedCenter(wanted, in: visibleFrame)

        let panel = ensurePanel()
        let half = RadialMenuLayout.panelSize / 2
        panel.setFrame(NSRect(x: wheelCenter.x - half, y: wheelCenter.y - half,
                              width: RadialMenuLayout.panelSize, height: RadialMenuLayout.panelSize),
                       display: false)
        WheelMotion.present(panel)
        installMonitors(for: panel)
        refreshHighlight()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.sessionActive, self.sessionID == activeSessionID else { return }
            self.visible = true
        }
    }

    private func endSession() {
        if dismissal.isActive { return }
        removeMonitors()
        stopTrackingSuperKeyHold()
        guard let panel, panel.isVisible, !stack.isEmpty else {
            forgetSession()
            return
        }
        visible = false
        dismissal.begin(panel) { [weak self] in self?.forgetSession() }
    }

    private func forgetSession() {
        visible = false
        panel?.orderOut(nil)
        stack = []
        activeProfile = nil
        trail = []
        highlightedIndex = nil
        holdPhase = false
        holdButton = nil
        sessionShortcut = nil
        sessionActivationMode = .pressOrHold
        if !AppFeature.radialMenu.isAvailable
            || !UserDefaults.standard.bool(forKey: DefaultsKey.radialMenuEnabled) {
            panel = nil
        }
    }

    private func availableItems(_ items: [RadialMenuItem]) -> [RadialMenuItem] {
        items.compactMap { item in
            var item = item
            if let tool = item.tool, !tool.isRunnable() { return nil }
            if item.kind == .quickToggle,
               !(item.quickToggle?.feature ?? .quickToggles).isAvailable { return nil }
            if item.kind == .windowLayout, !AppFeature.windowLayout.isAvailable { return nil }
            if item.kind == .submenu {
                item.children = availableItems(item.children)
                if item.children.isEmpty { return nil }
            }
            return item
        }
    }

    private func clampedCenter(_ wanted: CGPoint, in frame: NSRect) -> CGPoint {
        let half = RadialMenuLayout.panelSize / 2
        guard frame.width > RadialMenuLayout.panelSize,
              frame.height > RadialMenuLayout.panelSize else { return wanted }
        return CGPoint(x: min(max(wanted.x, frame.minX + half), frame.maxX - half),
                       y: min(max(wanted.y, frame.minY + half), frame.maxY - half))
    }

    // MARK: - Selection

    private func refreshHighlight() {
        let pointer = NSEvent.mouseLocation
        if !pointerActivated {
            let dx = pointer.x - openPointerLocation.x
            let dy = pointer.y - openPointerLocation.y
            guard (dx * dx + dy * dy).squareRoot() >= RadialMenuLayout.moveActivationDistance else {
                return
            }
            pointerActivated = true
        }
        let index = RadialMenuGeometry.highlightedIndex(dx: pointer.x - wheelCenter.x,
                                                        dyUp: pointer.y - wheelCenter.y,
                                                        deadZoneRadius: RadialMenuLayout.deadZoneRadius,
                                                        itemCount: currentItems.count)
        if index != highlightedIndex {
            highlightedIndex = index
            if index != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        }
    }

    func activatePointer() {
        guard sessionActive else { return }
        let pointer = NSEvent.mouseLocation
        let dx = pointer.x - wheelCenter.x
        let dyUp = pointer.y - wheelCenter.y
        let distance = (dx * dx + dyUp * dyUp).squareRoot()
        if distance > RadialMenuLayout.wheelDiameter / 2 {
            endSession()
        } else if distance < RadialMenuLayout.deadZoneRadius {
            stepBack()
        } else if let index = highlightedIndex {
            select(index)
        }
    }

    func select(_ index: Int) {
        guard sessionActive, currentItems.indices.contains(index) else { return }
        let item = currentItems[index]
        if item.kind == .submenu {
            stack.append(item.children)
            trail.append(item.name)
            highlightedIndex = nil
            enterStickyPhase()
            pointerActivated = false
            openPointerLocation = NSEvent.mouseLocation
            return
        }
        endSession()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        run(item)
    }

    func stepBack() {
        guard sessionActive else { return }
        if stack.count > 1 {
            stack.removeLast()
            trail.removeLast()
            highlightedIndex = nil
            refreshHighlight()
        } else {
            endSession()
        }
    }

    private func rotateHighlight(by delta: Int) {
        let count = currentItems.count
        guard count > 0 else { return }
        let current = highlightedIndex ?? (delta > 0 ? -1 : 0)
        highlightedIndex = ((current + delta) % count + count) % count
    }

    // MARK: - Monitors (session-scoped, removed the moment the wheel closes)

    private func installMonitors(for panel: NSPanel) {
        removeMonitors()

        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            return self.handleKeyDown(event) ? nil : event
        }) { eventMonitors.append(monitor) }

        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            self?.handleFlagsChanged(event.modifierFlags)
            return event
        }) { eventMonitors.append(monitor) }

        if let monitor = NSEvent.addLocalMonitorForEvents(matching: RadialMenuSupport.sessionMoveMask,
                                                          handler: { [weak self] event in
            self?.pointerMoved()
            return event
        }) { eventMonitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: RadialMenuSupport.sessionMoveMask,
                                                           handler: { [weak self] _ in
            self?.pointerMoved()
        }) { eventMonitors.append(monitor) }

        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return event }
            if event.window !== panel, !Self.pointerInside(panel) {
                self.endSession()
            }
            return event
        }) { eventMonitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return }
            if event.windowNumber != panel.windowNumber, !Self.pointerInside(panel) {
                self.endSession()
            }
        }) { eventMonitors.append(monitor) }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier
            else { return }
            self.endSession()
        }
    }

    private func removeMonitors() {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors = []
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    private static func pointerInside(_ panel: NSPanel) -> Bool {
        panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    private func pointerMoved() {
        guard sessionActive else { return }
        if holdPhase, holdButton == nil { handleFlagsChanged(NSEvent.modifierFlags) }
        refreshHighlight()
    }

    private func handleFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        guard sessionActive, holdPhase, let shortcut = sessionShortcut else { return }
        guard !RadialMenuSupport.shortcutIsStillHeld(
            modifiersHeld: shortcut.requiredModifiersHeld(in: flags),
            superKeyHeld: sessionUsesSuperKey && SuperKeyService.isEngaged
                && SuperKeyService.shared.isHeld
        ) else { return }
        endHoldPhase()
    }

    private func endHoldPhase() {
        guard sessionActive, holdPhase else { return }
        switch sessionActivationMode.releaseAction(hasSelection: highlightedIndex != nil) {
        case .stayOpen:
            enterStickyPhase()
        case .dismiss:
            endSession()
        case .select:
            guard let index = highlightedIndex else { return }
            select(index)
        }
    }

    private func enterStickyPhase() {
        holdPhase = false
        holdButton = nil
        stopTrackingSuperKeyHold()
    }

    private func stopTrackingSuperKeyHold() {
        guard sessionUsesSuperKey else { return }
        sessionUsesSuperKey = false
        SuperKeyService.shared.onHoldEnded = nil
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_Escape:
            stepBack()
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let index = highlightedIndex { select(index) }
            return true
        case kVK_LeftArrow, kVK_UpArrow:
            if sessionActivationMode != .hold { enterStickyPhase() }
            rotateHighlight(by: -1)
            return true
        case kVK_RightArrow, kVK_DownArrow:
            if sessionActivationMode != .hold { enterStickyPhase() }
            rotateHighlight(by: 1)
            return true
        default:
            if let character = event.charactersIgnoringModifiers?.first,
               let digit = character.wholeNumberValue, (1...9).contains(digit),
               currentItems.indices.contains(digit - 1) {
                select(digit - 1)
                return true
            }
            return false
        }
    }

    // MARK: - Actions

    private func run(_ item: RadialMenuItem) {
        switch item.kind {
        case .app:
            let url = URL(fileURLWithPath: (item.payload as NSString).expandingTildeInPath)
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if error != nil { DispatchQueue.main.async { NSSound.beep() } }
            }
        case .file:
            let path = (item.payload as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else {
                NSSound.beep()
                return
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .url:
            if let normalized = RadialMenuSupport.normalizedURL(item.payload),
               let url = URL(string: normalized) {
                NSWorkspace.shared.open(url)
            }
        case .shortcut:
            if let shortcut = GlobalShortcut(storageValue: item.payload) {
                postWhenModifiersReleased(attempt: 0) { Self.postShortcut(shortcut) }
            }
        case .media:
            if let key = item.mediaKey {
                if key == .nowPlaying {
                    RadialNowPlayingService.shared.presentDetails(at: wheelCenter)
                } else {
                    postWhenModifiersReleased(attempt: 0) { Self.postMediaKey(key) }
                }
            }
        case .tool:
            if let tool = item.tool { run(tool) }
        case .quickToggle:
            if let action = item.quickToggle { run(action) }
        case .windowLayout:
            if let action = item.windowLayoutAction { run(action) }
        case .submenu:
            break
        }
    }

    private func run(_ tool: RadialMenuTool) {
        guard tool.isRunnable() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            switch tool {
            case .screenshot: ScreenshotService.shared.capture()
            case .screenRecorder: ScreenRecorderService.shared.toggle()
            case .colorPicker: ColorSamplerService.shared.pick()
            case .screenOCR: ScreenTextService.shared.capture()
            case .micMute: MicMuteService.shared.toggle()
            case .clipboardHistory: ClipboardHistoryService.shared.showHistoryWindow()
            case .quickLauncher: QuickLauncherService.shared.show()
            case .cameraPreview: CameraPreviewService.shared.show()
            case .scratchpad: ScratchpadService.shared.show()
            case .shelf: ShelfService.shared.summon()
            case .cleaner: Self.openSettings(at: ())
            case .uninstaller: Self.openSettings(at: ())
            case .appUpdates:
                AppUpdatesService.shared.check()
                Self.openSettings(at: ())
            case .cleaningMode: break
            case .keepAwake: KeepAwakeManager.shared.toggle()
            }
        }
    }

    private static func openSettings(at page: Any) {
        appDelegate()?.openSettingsWindow()
    }

    private func run(_ action: RadialMenuQuickToggle) {
        guard action.feature.isAvailable else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let toggles = QuickTogglesService.shared
            switch action {
            case .darkMode: toggles.toggleDarkMode()
            case .emptyTrash: toggles.emptyTrash()
            case .quitAllApps: toggles.showQuitApps()
            case .ejectDisks: toggles.ejectAllDisks()
            case .hiddenFiles: toggles.toggleHiddenFiles()
            case .desktopIcons: toggles.toggleDesktopIcons()
            case .lockScreen: toggles.lockScreen()
            case .displayOff: toggles.turnDisplayOff()
            case .screenSaver: toggles.startScreenSaver()
            }
        }
    }

    private func run(_ action: WindowLayoutAction) {
        guard AppFeature.windowLayout.isAvailable, ensureAccessibilityPermission() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if case .failure = WindowLayoutService.shared.apply(action) { NSSound.beep() }
        }
    }

    // MARK: - Accessibility-gated actions (asked once and in context)

    private func ensureAccessibilityPermission() -> Bool {
        guard AXIsProcessTrusted() else {
            if promptedForAccessibility {
                NSSound.beep()
            } else {
                promptedForAccessibility = true
                Permissions.shared.requestAccessibility()
            }
            return false
        }
        return true
    }

    private func postWhenModifiersReleased(attempt: Int, then post: @escaping () -> Void) {
        guard ensureAccessibilityPermission() else { return }
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
        if held.isEmpty || attempt >= 100 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: post)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
            self?.postWhenModifiersReleased(attempt: attempt + 1, then: post)
        }
    }

    private static func postShortcut(_ shortcut: GlobalShortcut) {
        guard let keyDown = CGEvent(keyboardEventSource: nil,
                                    virtualKey: CGKeyCode(shortcut.keyCode), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil,
                                  virtualKey: CGKeyCode(shortcut.keyCode), keyDown: false)
        else { return }
        keyDown.flags = shortcut.syntheticEventFlags
        keyUp.flags = shortcut.syntheticEventFlags
        keyDown.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private static func postMediaKey(_ key: RadialMenuMediaKey) {
        guard let auxKeyType = key.auxKeyType else { return }
        postAuxKey(auxKeyType, down: true)
        postAuxKey(auxKeyType, down: false)
    }

    private static func postAuxKey(_ type: Int32, down: Bool) {
        let stateFlags: NSEvent.ModifierFlags = down
            ? NSEvent.ModifierFlags(rawValue: 0xA00)
            : NSEvent.ModifierFlags(rawValue: 0xB00)
        let data1 = (Int(type) << 16) | ((down ? 0xA : 0xB) << 8)
        guard let event = NSEvent.otherEvent(with: .systemDefined,
                                             location: .zero,
                                             modifierFlags: stateFlags,
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: 0,
                                             context: nil,
                                             subtype: 8,
                                             data1: data1,
                                             data2: -1)
        else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }

    // MARK: - Panel

    private final class KeyableWheelPanel: OverlayPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let size = RadialMenuLayout.panelSize
        let panel = KeyableWheelPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                                      styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered,
                                      defer: false)
        panel.title = "EVERYTHING"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentViewController = NSHostingController(rootView: RadialMenuView().transaction {
            $0.animation = $0.animation?.speed(PerformanceMode.motionSpeed)
        })
        self.panel = panel
        return panel
    }
}

private enum WheelMotion {
    static var isEnabled: Bool { !PerformanceMode.reduceMotion }

    static func present(_ panel: NSPanel) {
        panel.ignoresMouseEvents = false
        guard isEnabled else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            panel.makeKey()
            return
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.126
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    static func dismiss(_ panel: NSPanel, completion: @escaping () -> Void) {
        guard isEnabled, panel.isVisible else {
            completion()
            return
        }
        if panel.isKeyWindow {
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        panel.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.09
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { completion() }
    }
}

final class PanelDismissal {
    private(set) var isActive = false
    private var token = 0

    func begin(_ panel: NSPanel, finish: @escaping () -> Void) {
        isActive = true
        token &+= 1
        let started = token
        WheelMotion.dismiss(panel) { [weak self] in
            guard let self, self.isActive, self.token == started else { return }
            self.isActive = false
            panel.orderOut(nil)
            finish()
        }
    }

    func cancel(finish: () -> Void) {
        guard isActive else { return }
        isActive = false
        token &+= 1
        finish()
    }
}

extension RadialMenuService {
    func fillMissingLinkIcons() {
        let defaults = UserDefaults.standard
        guard !Self.fillingIcons else { return }
        let profiles = RadialMenuSupport.decodeProfiles(defaults.data(forKey: DefaultsKey.radialMenuProfiles), defaults: defaults)
        var all: [RadialMenuItem] = []
        for profile in profiles {
            all += profile.items
            for parent in profile.items { all += parent.children }
        }
        let missing = all.first { candidate in
            guard candidate.kind == .url, candidate.customIconData == nil, candidate.symbolName.isEmpty else { return false }
            return !Self.triedIcons.contains(candidate.id)
        }
        guard let item = missing else { return }
        Self.fillingIcons = true
        Self.triedIcons.insert(item.id)
        RadialMenuFaviconFetcher.fetchFavicon(for: item.payload) { [weak self] result in
            Self.fillingIcons = false
            if case let .success(data) = result {
                var stored = RadialMenuSupport.decodeProfiles(defaults.data(forKey: DefaultsKey.radialMenuProfiles), defaults: defaults)
                for p in stored.indices {
                    for i in stored[p].items.indices {
                        if stored[p].items[i].id == item.id { stored[p].items[i].customIconData = data }
                        for c in stored[p].items[i].children.indices where stored[p].items[i].children[c].id == item.id {
                            stored[p].items[i].children[c].customIconData = data
                        }
                    }
                }
                if let encoded = RadialMenuSupport.encodeProfiles(stored) {
                    defaults.set(encoded, forKey: DefaultsKey.radialMenuProfiles)
                }
            }
            self?.fillMissingLinkIcons()
        }
    }

    private static var fillingIcons = false
    private static var triedIcons = Set<UUID>()
}

