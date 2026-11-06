// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

enum QuickLauncherItem: String, PanelOrderItem, Identifiable {
    case keepAwake, cleaner, toggles, micMute, screenOCR, colorPicker, clipboard, windowLayout,
         cleaning, homebrew, media, urlCleaner, uninstaller, screenshot, screenRecorder,
         cameraPreview, scratchpad

    var id: String { rawValue }

    var feature: AppFeature {
        switch self {
        case .keepAwake: return .keepAwake
        case .cleaner: return .cleaner
        case .toggles: return .quickToggles
        case .micMute: return .micMute
        case .screenOCR: return .screenOCR
        case .colorPicker: return .colorPicker
        case .clipboard: return .clipboardHistory
        case .windowLayout: return .windowLayout
        case .cleaning: return .cleaningMode
        case .homebrew: return .homebrew
        case .media: return .mediaTools
        case .urlCleaner: return .urlCleaner
        case .uninstaller: return .uninstaller
        case .screenshot: return .screenshot
        case .screenRecorder: return .screenRecorder
        case .cameraPreview: return .cameraPreview
        case .scratchpad: return .scratchpad
        }
    }
}

final class QuickLauncherService: ObservableObject {
    static let shared = QuickLauncherService()

    static let columns = 3

    @Published private(set) var shortcutRegistrationFailed = false
    @Published var isEditing = false
    @Published var editingOptionsItem: QuickLauncherItem?
    @Published private(set) var activeUtility: QuickLauncherItem?
    @Published private(set) var selectedIndex: Int?
    @Published private(set) var keyboardIndex: Int?
    @Published private(set) var presentationID = UUID()
    @Published private(set) var hiddenItemsRaw: String = UserDefaults.standard.string(
        forKey: DefaultsKey.quickLauncherHiddenItems) ?? ""

    private let hotkey = QuickToolHotkey(id: 14)
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var outsideClickMonitor: Any?
    private var activationObserver: NSObjectProtocol?

    private init() {
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    func syncWithPreferences() {
        let enabled = AppFeature.quickLauncher.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.quickLauncherShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.quickLauncherShortcut,
                                            fallback: .quickLauncherDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut,
                                                  storageKey: DefaultsKey.quickLauncherShortcut)
    }

    func suspend() {
        hotkey.unregister()
        hide()
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    // MARK: - Items

    var visibleItems: [QuickLauncherItem] {
        let hidden = QuickToolsSupport.hiddenIDs(from: hiddenItemsRaw)
        return orderedItems.filter { !hidden.contains($0.rawValue) }
    }

    var hiddenItems: [QuickLauncherItem] {
        let hidden = QuickToolsSupport.hiddenIDs(from: hiddenItemsRaw)
        return orderedItems.filter { hidden.contains($0.rawValue) }
    }

    private var orderedItems: [QuickLauncherItem] {
        PanelLayout.itemOrder(QuickLauncherItem.self, key: DefaultsKey.quickLauncherItemOrder)
            .filter { $0.feature.isAvailable }
    }

    var itemOrderBinding: Binding<[QuickLauncherItem]> {
        Binding {
            self.orderedItems
        } set: { newValue in
            PanelLayout.setItemOrder(newValue, key: DefaultsKey.quickLauncherItemOrder)
            self.objectWillChange.send()
        }
    }

    func setHidden(_ item: QuickLauncherItem, _ hidden: Bool) {
        var ids = QuickToolsSupport.hiddenIDs(from: hiddenItemsRaw)
        if hidden {
            ids.insert(item.rawValue)
            if editingOptionsItem == item { editingOptionsItem = nil }
        } else {
            ids.remove(item.rawValue)
        }
        hiddenItemsRaw = QuickToolsSupport.serializeHiddenIDs(ids)
        UserDefaults.standard.set(hiddenItemsRaw, forKey: DefaultsKey.quickLauncherHiddenItems)
        clampSelection()
    }

    // MARK: - Presentation

    func toggle() {
        if NotchService.shared.openQuickPanel(toggle: true) { return }
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if NotchService.shared.openQuickPanel() { return }
        let panel = ensurePanel()
        prepareForPresentation()
        position(panel)
        installMonitors(for: panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            panel.animator().alphaValue = 1
        }
    }

    func prepareForPresentation() {
        refreshAvailability()
        presentationID = UUID()
        isEditing = false
        editingOptionsItem = nil
        selectedIndex = visibleItems.isEmpty ? nil : 0
        keyboardIndex = selectedIndex
    }

    func refreshAvailability() {
        if let activeUtility, !activeUtility.feature.isAvailable { self.activeUtility = nil }
        if let editingOptionsItem, !editingOptionsItem.feature.isAvailable { self.editingOptionsItem = nil }
        clampSelection()
    }

    func hide() {
        if NotchService.shared.expanded, NotchService.shared.selected == .tools { NotchService.shared.collapse() }
        removeMonitors()
        isEditing = false
        editingOptionsItem = nil
        activeUtility = nil
        panel?.orderOut(nil)
    }

    func closeUtility() {
        activeUtility = nil
    }

    func refocusAfterModal() {
        if NotchService.shared.expanded, NotchService.shared.selected == .tools {
            NotchService.shared.presentationWindow?.makeKey(); return
        }
        guard let panel, panel.isVisible else { return }
        panel.makeKey()
    }

    private var dismissesOnOutsideInteraction: Bool {
        activeUtility == nil && !isEditing
    }

    func refreshPanelLayout() {
        guard let panel, panel.isVisible else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            panel.contentViewController?.view.layoutSubtreeIfNeeded()
            let size = panel.contentViewController?.view.fittingSize ?? panel.frame.size
            let screen = NSScreen.pointerVisibleFrame
            var frame = panel.frame
            frame.origin.x = frame.midX - size.width / 2
            frame.origin.y = frame.maxY - size.height
            frame.size = size
            frame.origin.x = max(screen.minX + 16, min(frame.origin.x, screen.maxX - size.width - 16))
            frame.origin.y = max(screen.minY + 16, frame.origin.y)
            panel.setFrame(frame, display: true, animate: true)
        }
    }

    // MARK: - Actions

    func activateSelection() {
        guard let selectedIndex, visibleItems.indices.contains(selectedIndex) else { return }
        run(visibleItems[selectedIndex])
    }

    func activate(at index: Int) {
        guard visibleItems.indices.contains(index) else { return }
        run(visibleItems[index])
    }

    func moveSelection(_ direction: QuickToolsSupport.GridDirection,
                       flow: QuickToolsSupport.GridFlow = .rows(columns: QuickLauncherService.columns)) {
        let count = visibleItems.count
        guard count > 0 else { return }
        selectedIndex = QuickToolsSupport.gridIndex(after: selectedIndex ?? 0,
                                                    count: count,
                                                    flow: flow,
                                                    direction: direction)
        keyboardIndex = selectedIndex
    }

    func select(_ item: QuickLauncherItem) {
        selectedIndex = visibleItems.firstIndex(of: item)
        keyboardIndex = nil
    }

    func run(_ item: QuickLauncherItem) {
        guard !isEditing, item.feature.isAvailable else { return }
        switch item {
        case .keepAwake:
            KeepAwakeManager.shared.toggle()
        case .micMute:
            MicMuteService.shared.toggle()
        case .screenOCR:
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                ScreenTextService.shared.capture()
            }
        case .screenshot:
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                ScreenshotService.shared.capture()
            }
        case .screenRecorder:
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                ScreenRecorderService.shared.toggle()
            }
        case .colorPicker:
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                ColorSamplerService.shared.pick()
            }
        case .cameraPreview:
            let embedded = CameraPreviewService.shared.showInNotchIfEnabled()
            hide()
            if !embedded {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    CameraPreviewService.shared.show()
                }
            }
        case .scratchpad:
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                ScratchpadService.shared.show()
            }
        case .clipboard:
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                ClipboardHistoryService.shared.showHistoryWindow()
            }
        case .cleaning:
            hide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                _ = 0
            }
        case .windowLayout, .homebrew, .media, .urlCleaner, .uninstaller, .cleaner, .toggles:
            activeUtility = item
        }
    }

    private func clampSelection() {
        let count = visibleItems.count
        guard count > 0 else {
            selectedIndex = nil
            return
        }
        selectedIndex = min(selectedIndex ?? 0, count - 1)
    }

    // MARK: - Panel

    private final class KeyableLauncherPanel: OverlayPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyableLauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
                                         styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered,
                                         defer: false)
        panel.title = "EVERYTHING"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: QuickLauncherView())
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? NSSize(width: 420, height: 380)
        let screen = NSScreen.pointerVisibleFrame
        let x = screen.midX - size.width / 2
        let y = screen.minY + (screen.height - size.height) * 0.62
        panel.setFrame(NSRect(x: max(screen.minX + 16, min(x, screen.maxX - size.width - 16)),
                              y: max(screen.minY + 16, y),
                              width: size.width,
                              height: size.height),
                       display: true,
                       animate: false)
    }

    // MARK: - Monitors

    func handlePanelKey(_ event: NSEvent,
                        flow: QuickToolsSupport.GridFlow = .rows(columns: QuickLauncherService.columns)) -> NSEvent? {
        if event.keyCode == UInt16(kVK_Escape) {
            if (event.window?.firstResponder as? NSTextView)?.hasMarkedText() == true { return event }
            if activeUtility != nil {
                activeUtility = nil
            } else if editingOptionsItem != nil {
                editingOptionsItem = nil
            } else if isEditing {
                isEditing = false
            } else {
                hide()
            }
            return nil
        }
        guard !isEditing, activeUtility == nil,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            activateSelection()
            return nil
        case kVK_LeftArrow:
            moveSelection(.left, flow: flow)
            return nil
        case kVK_RightArrow:
            moveSelection(.right, flow: flow)
            return nil
        case kVK_UpArrow:
            moveSelection(.up, flow: flow)
            return nil
        case kVK_DownArrow:
            moveSelection(.down, flow: flow)
            return nil
        default:
            if let index = Self.digitIndex(for: event.keyCode) {
                activate(at: index)
                return nil
            }
            return event
        }
    }

    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            return self.handlePanelKey(event)
        }
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, self.dismissesOnOutsideInteraction else { return event }
            if event.window !== panel, !Self.mouseIsInside(panel) {
                self.hide()
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, self.dismissesOnOutsideInteraction else { return }
            if event.windowNumber != panel.windowNumber, !Self.mouseIsInside(panel),
               !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) {
                self.hide()
            }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  self.dismissesOnOutsideInteraction,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier,
                  app.bundleIdentifier != AssistiveKeyboard.bundleID
            else { return }
            self.hide()
        }
    }

    private func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    private static func mouseIsInside(_ panel: NSPanel) -> Bool {
        panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    private static func digitIndex(for keyCode: UInt16) -> Int? {
        switch Int(keyCode) {
        case kVK_ANSI_1, kVK_ANSI_Keypad1: return 0
        case kVK_ANSI_2, kVK_ANSI_Keypad2: return 1
        case kVK_ANSI_3, kVK_ANSI_Keypad3: return 2
        case kVK_ANSI_4, kVK_ANSI_Keypad4: return 3
        case kVK_ANSI_5, kVK_ANSI_Keypad5: return 4
        case kVK_ANSI_6, kVK_ANSI_Keypad6: return 5
        case kVK_ANSI_7, kVK_ANSI_Keypad7: return 6
        case kVK_ANSI_8, kVK_ANSI_Keypad8: return 7
        case kVK_ANSI_9, kVK_ANSI_Keypad9: return 8
        default: return nil
        }
    }
}
