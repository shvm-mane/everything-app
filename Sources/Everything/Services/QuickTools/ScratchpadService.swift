// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

final class ScratchpadService: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = ScratchpadService()

    @Published private(set) var shortcutRegistrationFailed = false
    @Published private(set) var isPinned = false
    @Published private(set) var isPreviewing = false
    @Published private(set) var marksExpanded = false
    @Published private(set) var pads: [ScratchpadPad] = []
    @Published private(set) var selectedPadID: UUID?
    @Published private(set) var saveFailed = false
    @Published private(set) var keyboardCloseSelectedPadSerial = 0
    @Published var text = "" {
        didSet {
            guard hasLoaded, !isReplacingText, var document else { return }
            document.updateSelectedText(text, modifiedAt: Date())
            self.document = document
            pads = document.pads
            scheduleSave()
        }
    }

    private let hotkey = QuickToolHotkey(id: 18)
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var outsideClickMonitor: Any?
    private weak var textView: NSTextView?
    private var pendingSave: DispatchWorkItem?
    private var document: ScratchpadDocument?
    private var store = ScratchpadStore(directoryURL: PrivateFileStore.containerURL,
                                        defaults: .standard)
    private var hasLoaded = false
    private var isReplacingText = false
    private(set) var modalInteractionActive = false

    private override init() {
        super.init()
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    func syncWithPreferences() {
        let available = AppFeature.scratchpad.isAvailable
        let enabled = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.scratchpadShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.scratchpadShortcut,
                                            fallback: .scratchpadDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut,
                                                  storageKey: DefaultsKey.scratchpadShortcut)
        if !available {
            hide()
            panel = nil
        }
    }

    func suspend() {
        hotkey.unregister()
        hide()
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func toggle() {
        guard !modalInteractionActive else { return }
        _ = NotchService.shared.showScratchpad(toggle: true)
        if isVisible { hide() }
        return ()
    }

    func show(allowsIsland: Bool = true) {
        guard AppFeature.scratchpad.isAvailable, !modalInteractionActive else { return }
        _ = NotchService.shared.showScratchpad()
        if isVisible { hide() }
        return ()
    }

    func loadForEmbedding() -> Bool {
        guard AppFeature.scratchpad.isAvailable else { return false }
        marksExpanded = false
        return loadApplyingRetention()
    }

    func commitEdits() {
        flushSave()
        if saveFailed {
            QuickToolHUD.show(
                icon: "exclamationmark.triangle",
                message: FeatureStrings.scratchpad(L10n.shared.language).saveFailed)
        }
    }

    func hide() {
        guard panel != nil else { return }
        commitEdits()
        removeMonitors()
        panel?.orderOut(nil)
        isPinned = false
        isPreviewing = false
        modalInteractionActive = false
    }

    // MARK: - Document

    @discardableResult
    private func loadApplyingRetention() -> Bool {
        if hasLoaded, let document, document != store.lastSavedDocument {
            flushSave()
            return true
        }
        let defaults = UserDefaults.standard
        let defaultName = FeatureStrings.scratchpad(L10n.shared.language).pageTitle
        let retention = ScratchpadRetention.sanitized(
            defaults.string(forKey: DefaultsKey.scratchpadRetention))
        do {
            let loaded = try store.load(defaultName: defaultName, retention: retention, now: Date())
            apply(loaded)
            hasLoaded = true
            return true
        } catch {
            hasLoaded = false
            return false
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushSave() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func flushSave() {
        pendingSave?.cancel()
        pendingSave = nil
        guard hasLoaded, let document else { return }
        _ = save(document)
    }

    private func save(_ next: ScratchpadDocument) -> Bool {
        saveFailed = !store.save(next)
        return !saveFailed
    }

    private func apply(_ document: ScratchpadDocument, focus: Bool = false) {
        self.document = document
        pads = document.pads
        selectedPadID = document.selectedID
        let selectedText = document.pads.first(where: { $0.id == document.selectedID })?.text ?? ""
        isReplacingText = true
        text = selectedText
        isReplacingText = false
        if text.isEmpty { isPreviewing = false }
        if focus { focusText() }
    }

    var canCreatePad: Bool { pads.count < ScratchpadDocument.maximumPadCount }
    var canClosePad: Bool { pads.count > 1 }
    var selectedPadName: String {
        pads.first(where: { $0.id == selectedPadID })?.name
            ?? FeatureStrings.scratchpad(L10n.shared.language).pageTitle
    }

    func createPad(defaultName: String) {
        guard let document, let next = document.addingPad(defaultName: defaultName), save(next) else { return }
        apply(next, focus: true)
    }

    func selectPad(_ id: UUID) {
        guard id != selectedPadID, let document, let next = document.selecting(id), save(next) else { return }
        apply(next, focus: true)
    }

    func renamePad(_ id: UUID, to name: String) {
        guard let document, let next = document.renaming(id, to: name), save(next) else { return }
        apply(next, focus: id == selectedPadID)
    }

    @discardableResult
    func closePad(_ id: UUID) -> Bool {
        guard let document, let next = document.removing(id), save(next) else { return false }
        apply(next, focus: true)
        return true
    }

    func setModalInteractionActive(_ active: Bool) {
        modalInteractionActive = active
    }

    func prepareForSettingsBackup() {
        if hasLoaded { flushSave() } else { loadApplyingRetention() }
    }

    func prepareForSettingsRestore() {
        pendingSave?.cancel()
        pendingSave = nil
        hasLoaded = false
        document = nil
        store = ScratchpadStore(directoryURL: PrivateFileStore.containerURL, defaults: .standard)
    }

    // MARK: - Actions

    func copyAll() {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareVorssaintSource()
        pasteboard.setString(text, forType: .string)
    }

    func clear(through editor: NSTextView? = nil) {
        guard !text.isEmpty else { return }
        if let textView = editor ?? textView.flatMap({ $0.window === panel ? $0 : nil }) {
            if textView.hasMarkedText() { textView.unmarkText() }
            let full = NSRange(location: 0, length: (textView.string as NSString).length)
            if textView.shouldChangeText(in: full, replacementString: "") {
                textView.replaceCharacters(in: full, with: "")
                textView.didChangeText()
            }
        } else {
            text = ""
        }
        if isPreviewing {
            isPreviewing = false
            focusText()
        }
        flushSave()
    }

    func toggleTask(box: Int, through editor: NSTextView? = nil) {
        if let textView = editor ?? textView.flatMap({ $0.window === panel ? $0 : nil }) {
            if textView.hasMarkedText() { textView.unmarkText() }
            guard let edit = ScratchpadSupport.taskToggleEdit(box: box, in: textView.string) else { return }
            textView.breakUndoCoalescing()
            guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
            textView.replaceCharacters(in: edit.range, with: edit.replacement)
            textView.didChangeText()
        } else {
            guard let edit = ScratchpadSupport.taskToggleEdit(box: box, in: text) else { return }
            text = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        }
        flushSave()
    }

    func apply(_ mark: ScratchpadMark, through editor: NSTextView? = nil) {
        guard !isPreviewing else { return }
        guard let textView = editor ?? textView.flatMap({ $0.window === panel ? $0 : nil }) else { return }
        if textView.hasMarkedText() { textView.unmarkText() }
        textView.window?.makeFirstResponder(textView)
        let edit = ScratchpadSupport.edit(applying: mark,
                                          to: textView.string,
                                          selection: textView.selectedRange())
        guard (textView.string as NSString).substring(with: edit.range) != edit.replacement else { return }
        guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textView.replaceCharacters(in: edit.range, with: edit.replacement)
        textView.didChangeText()
        textView.setSelectedRange(edit.selection)
        textView.scrollRangeToVisible(edit.selection)
        flushSave()
    }

    func toggleMarks() {
        marksExpanded.toggle()
    }

    func togglePreview() {
        guard !text.isEmpty else { return }
        isPreviewing.toggle()
        if isPreviewing { marksExpanded = false }
        if isPreviewing {
            if let textView = textView, textView.window === panel { hideFindBar(in: textView) }
            panel?.makeFirstResponder(nil)
        } else {
            focusText()
        }
    }

    func togglePin() {
        guard isVisible else { return }
        isPinned.toggle()
    }

    func outsideClickPreferenceDidChange() {
        guard isVisible else { return }
        isPinned = !closesOnClickOutside
    }

    func exportText(suggestedName: String, from window: NSWindow? = nil) {
        guard !text.isEmpty, !modalInteractionActive, let padID = selectedPadID,
              let sourceWindow = window ?? panel, sourceWindow.isVisible else { return }
        modalInteractionActive = true
        flushSave()
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.nameFieldStringValue = suggestedName
        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            self?.modalInteractionActive = false
            if response == .OK, let url = savePanel.url {
                do {
                    guard let content = self?.document?.pads.first(where: { $0.id == padID })?.text else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    try content.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    QuickToolHUD.show(
                        icon: "exclamationmark.triangle",
                        message: FeatureStrings.scratchpad(L10n.shared.language).exportFailed)
                }
            }
            DispatchQueue.main.async {
                if sourceWindow.isVisible { sourceWindow.makeKey() }
            }
        }
        if sourceWindow === NotchService.shared.presentationWindow {
            savePanel.level = NSWindow.Level(rawValue: sourceWindow.level.rawValue + 1)
            savePanel.hidesOnDeactivate = false
            savePanel.begin(completionHandler: complete)
            NSApp.activate(ignoringOtherApps: true)
            savePanel.makeKeyAndOrderFront(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async { complete(savePanel.runModal()) }
        }
    }

    // MARK: - Focus

    func registerTextView(_ view: NSTextView) {
        textView = view
    }

    private func focusText(requiresKeyWindow: Bool = true) {
        guard let panel, panel.isVisible, !requiresKeyWindow || panel.isKeyWindow else { return }
        panel.makeKey()
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible, panel.isKeyWindow,
                  let textView = self.textView else { return }
            panel.makeFirstResponder(textView)
            let end = NSRange(location: (textView.string as NSString).length, length: 0)
            textView.setSelectedRange(end)
            textView.scrollRangeToVisible(end)
        }
    }

    // MARK: - Panel

    private final class KeyableScratchpadPanel: OverlayPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyableScratchpadPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                                           styleMask: [.borderless, .nonactivatingPanel, .resizable],
                                           backing: .buffered,
                                           defer: false)
        panel.title = "EVERYTHING"
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentMinSize = NSSize(width: 280, height: 220)
        panel.minSize = NSSize(width: 280, height: 220)
        panel.delegate = self
        let host = NSHostingController(rootView: ScratchpadView())
        host.sizingOptions = []
        panel.contentViewController = host
        panel.setContentSize(NSSize(width: 380, height: 300))
        center(panel)
        self.panel = panel
        return panel
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(width: max(280, frameSize.width), height: max(220, frameSize.height))
    }

    private func center(_ panel: NSPanel) {
        let size = panel.frame.size
        let screen = NSScreen.pointerVisibleFrame
        let x = screen.midX - size.width / 2
        let y = screen.minY + (screen.height - size.height) * 0.58
        panel.setFrame(NSRect(x: max(screen.minX + 16, min(x, screen.maxX - size.width - 16)),
                              y: max(screen.minY + 16, min(y, screen.maxY - size.height - 16)),
                              width: size.width,
                              height: size.height),
                       display: true,
                       animate: false)
    }

    // MARK: - Monitors

    private var closesOnClickOutside: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.scratchpadCloseOnClickOutside)
    }

    private var dismissesOnOutsideClick: Bool {
        ScratchpadSupport.dismissesOnOutsideClick(isPinned: isPinned,
                                                  exportModalActive: modalInteractionActive)
    }

    private func performFocusedTabShortcut(_ action: ScratchpadFocusedShortcut.Action) {
        switch action {
        case .createPad:
            createPad(defaultName: FeatureStrings.scratchpad(L10n.shared.language).pageTitle)
        case .closeSelectedPad:
            keyboardCloseSelectedPadSerial += 1
        case .hidePad:
            hide()
        case .find:
            performFind(.showFindInterface)
        case .findNext:
            performFind(.nextMatch)
        case .findPrevious:
            performFind(.previousMatch)
        }
    }

    func performFind(_ action: NSTextFinder.Action, in editor: NSTextView? = nil) {
        guard let textView = editor ?? textView.flatMap({ $0.window === panel ? $0 : nil }) else { return }
        let leftPreview = isPreviewing
        if isPreviewing {
            isPreviewing = false
        }
        let sender = NSMenuItem()
        sender.tag = action.rawValue
        if action == .showFindInterface || leftPreview {
            textView.window?.makeFirstResponder(textView)
        }
        textView.performTextFinderAction(sender)
    }

    func hideFindBar(in editor: NSTextView) {
        guard editor.enclosingScrollView?.isFindBarVisible == true else { return }
        let sender = NSMenuItem()
        sender.tag = NSTextFinder.Action.hideFindInterface.rawValue
        editor.performTextFinderAction(sender)
    }

    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                if let textView = self.textView, textView.hasMarkedText() {
                    return event
                }
                if PlainTextEditor.findBarHasKeyboard(in: panel) { return event }
                self.hide()
                return nil
            }
            guard !self.modalInteractionActive else { return event }
            let commandOnly = event.modifierFlags
                .intersection([.command, .option, .control]) == .command
            let shift = event.modifierFlags.contains(.shift)
            if let action = ScratchpadFocusedShortcut.action(
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                commandOnly: commandOnly,
                shift: shift,
                canCreatePad: self.canCreatePad,
                canClosePad: self.canClosePad
            ) {
                self.performFocusedTabShortcut(action)
                return nil
            }
            if commandOnly, !shift, event.charactersIgnoringModifiers?.lowercased() == "t" {
                return nil
            }
            return event
        }
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, self.dismissesOnOutsideClick else { return event }
            if event.window !== panel, !Self.mouseIsInside(panel) {
                self.hide()
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, self.dismissesOnOutsideClick else { return }
            if event.windowNumber != panel.windowNumber, !Self.mouseIsInside(panel),
               !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) {
                self.hide()
            }
        }
    }

    private static func mouseIsInside(_ panel: NSPanel) -> Bool {
        panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
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
    }
}
