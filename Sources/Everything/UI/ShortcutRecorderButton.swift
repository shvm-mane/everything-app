// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderButton: NSViewRepresentable {
    let shortcut: GlobalShortcut
    let isEnabled: Bool
    let waitingTitle: String
    var requiresModifier = true
    var emptyTitle: String? = nil
    var clearAction: (() -> Void)? = nil
    var notCapturedAction: (() -> Void)? = nil
    var recordingChanged: ((Bool) -> Void)? = nil
    var captureWithFlagsAction: ((GlobalShortcut, CGEventFlags) -> Void)? = nil
    var captureModifiersAction: ((GlobalShortcutModifiers) -> Void)? = nil
    let invalidAction: () -> Void
    let captureAction: (GlobalShortcut) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.cell?.lineBreakMode = .byTruncatingTail
        button.target = button
        button.action = #selector(RecorderButton.beginRecording)
        apply(to: button)
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        apply(to: nsView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize,
                      nsView: RecorderButton,
                      context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        return CGSize(width: proposal.width ?? intrinsic.width, height: intrinsic.height)
    }

    static func dismantleNSView(_ nsView: RecorderButton, coordinator: ()) {
        nsView.recordingChanged = nil
        nsView.stopRecording()
    }

    private func apply(to button: RecorderButton) {
        button.requiresModifier = requiresModifier
        button.shortcut = shortcut
        button.waitingTitle = waitingTitle
        button.emptyTitle = emptyTitle
        button.clearAction = clearAction
        button.notCapturedAction = notCapturedAction
        button.recordingChanged = recordingChanged
        button.captureWithFlagsAction = captureWithFlagsAction
        button.captureModifiersAction = captureModifiersAction
        button.invalidAction = invalidAction
        button.captureAction = captureAction
        button.isEnabled = isEnabled
        button.refreshTitle()
    }
}

final class RecorderButton: NSButton {
    var requiresModifier = true
    var shortcut = GlobalShortcut.keepAwakeDefault
    var waitingTitle = ""
    var emptyTitle: String?
    var clearAction: (() -> Void)?
    var notCapturedAction: (() -> Void)?
    var recordingChanged: ((Bool) -> Void)?
    var captureWithFlagsAction: ((GlobalShortcut, CGEventFlags) -> Void)?
    var captureModifiersAction: ((GlobalShortcutModifiers) -> Void)?
    private var modifierRecording = ModifierShortcutRecording()
    var invalidAction: (() -> Void)?
    var captureAction: ((GlobalShortcut) -> Void)?
    private var isRecording = false
    private var awaitingKeyForHeldModifiers = false
    private var observers: [NSObjectProtocol] = []

    override var acceptsFirstResponder: Bool { true }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        guard isRecording else { return }
        if Thread.isMainThread {
            ShortcutRecordingTap.end()
            ShortcutCapture.end()
        } else {
            DispatchQueue.main.async {
                ShortcutRecordingTap.end()
                ShortcutCapture.end()
            }
        }
    }

    @objc func beginRecording() {
        guard isEnabled, !isRecording else { return }
        if window?.firstResponder !== self {
            guard window?.makeFirstResponder(self) == true else { return }
        }
        isRecording = true
        awaitingKeyForHeldModifiers = false
        modifierRecording = ModifierShortcutRecording()
        ShortcutCapture.begin()
        ShortcutRecordingTap.begin { [weak self] keyCode, modifiers, flags in
            guard let self, self.isRecording else { return }
            self.handleRecordingKey(keyCode: keyCode, modifiers: modifiers, flags: flags)
        }
        observeExits()
        refreshTitle()
        recordingChanged?(true)
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        awaitingKeyForHeldModifiers = false
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        ShortcutRecordingTap.end()
        ShortcutCapture.end()
        refreshTitle()
        recordingChanged?(false)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        handleRecordingKey(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        handleRecordingKey(event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        let modifiers = GlobalShortcutModifiers(eventFlags: event.modifierFlags)
        if let captureModifiersAction {
            let unsupported = event.modifierFlags.contains(.function)
            let captured = modifierRecording.flagsChanged(modifiers, hasUnsupportedModifier: unsupported)
            if unsupported {
                invalidAction?()
                return
            }
            if let captured {
                guard captured.isValidWindowDirectionalTrigger else {
                    invalidAction?()
                    return
                }
                stopRecording()
                captureModifiersAction(captured)
            }
            return
        }
        if modifiers.hasPrimaryModifier {
            awaitingKeyForHeldModifiers = true
        } else if modifiers.isEmpty, awaitingKeyForHeldModifiers {
            awaitingKeyForHeldModifiers = false
            notCapturedAction?()
        }
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopRecording() }
    }

    private func handleRecordingKey(_ event: NSEvent) {
        handleRecordingKey(keyCode: Int64(event.keyCode),
                           modifiers: GlobalShortcutModifiers(eventFlags: event.modifierFlags),
                           flags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)))
    }

    private func handleRecordingKey(keyCode: Int64, modifiers: GlobalShortcutModifiers,
                                    flags: CGEventFlags) {
        awaitingKeyForHeldModifiers = false
        modifierRecording.keyPressed()

        if keyCode == Int64(kVK_Escape), !modifiers.hasPrimaryModifier {
            stopRecording()
            return
        }
        if GlobalShortcut.clearsShortcut(keyCode: keyCode, modifiers: modifiers) {
            guard let clearAction else { return }
            stopRecording()
            clearAction()
            return
        }
        let captured = GlobalShortcut(keyCode: keyCode, modifiers: modifiers)
        if !requiresModifier, flags.contains(.maskSecondaryFn),
           !captured.syntheticEventFlags.contains(.maskSecondaryFn) {
            invalidAction?()
            return
        }
        guard requiresModifier ? captured.isValid : captured.hasPrintableKey else {
            NSSound.beep()
            invalidAction?()
            return
        }
        shortcut = captured
        stopRecording()
        if let captureWithFlagsAction {
            captureWithFlagsAction(captured, flags)
        } else {
            captureAction?(captured)
        }
    }

    private func observeExits() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.stopRecording()
        })
        if let window {
            observers.append(center.addObserver(forName: NSWindow.willCloseNotification,
                                                object: window, queue: .main) { [weak self] _ in
                self?.stopRecording()
            })
        }
    }

    func refreshTitle() {
        if isRecording {
            title = waitingTitle
        } else {
            title = emptyTitle ?? shortcut.displayString
        }
    }
}

