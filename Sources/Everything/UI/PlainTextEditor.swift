// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

struct PlainTextEditor: NSViewRepresentable {
    static let defaultFontSize: CGFloat = 13
    static let lineFragmentPadding: CGFloat = 5

    var fontSize: CGFloat = PlainTextEditor.defaultFontSize

    static func findBarHasKeyboard(in window: NSWindow?) -> Bool {
        guard let field = window?.firstResponder as? NSTextView, field.isFieldEditor,
              let control = field.delegate as? NSView else { return false }
        return sequence(first: control, next: \.superview).contains { view in
            guard let bar = (view as? NSScrollView)?.findBarView else { return false }
            return control.isDescendant(of: bar)
        }
    }

    @Binding var text: String
    var selectedRange: Binding<Range<Int>?>?
    var textColor: NSColor?
    var textContainerInset: NSSize?
    var usesFindBar = false
    var completesTaskBoxes = false
    var continuesLists = false
    var onCommandReturn: (() -> Void)?
    var isActive = true
    var onCreate: ((NSTextView) -> Void)?

    init(text: Binding<String>,
         fontSize: CGFloat = PlainTextEditor.defaultFontSize,
         selectedRange: Binding<Range<Int>?>? = nil,
         textColor: NSColor? = nil,
         textContainerInset: NSSize? = nil,
         usesFindBar: Bool = false,
         completesTaskBoxes: Bool = false,
         continuesLists: Bool = false,
         onCommandReturn: (() -> Void)? = nil,
         isActive: Bool = true,
         onCreate: ((NSTextView) -> Void)? = nil) {
        self._text = text
        self.fontSize = fontSize
        self.selectedRange = selectedRange
        self.textColor = textColor
        self.textContainerInset = textContainerInset
        self.usesFindBar = usesFindBar
        self.completesTaskBoxes = completesTaskBoxes
        self.continuesLists = continuesLists
        self.onCommandReturn = onCommandReturn
        self.isActive = isActive
        self.onCreate = onCreate
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: fontSize)
        textView.textContainer?.lineFragmentPadding = Self.lineFragmentPadding
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        if usesFindBar {
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
        }
        if let textColor {
            textView.textColor = textColor
        }
        if let textContainerInset {
            textView.textContainerInset = textContainerInset
        }
        textView.string = text
        textView.delegate = context.coordinator
        context.coordinator.completesTaskBoxes = completesTaskBoxes
        context.coordinator.continuesLists = continuesLists
        context.coordinator.onCommandReturn = onCommandReturn
        context.coordinator.installLineMoveMonitor(for: textView)
        onCreate?(textView)
        return scroll
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.removeLineMoveMonitor()
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.continuesLists = continuesLists
        context.coordinator.onCommandReturn = onCommandReturn
        if nsView.isHidden == isActive { nsView.isHidden = !isActive }
        if textView.font?.pointSize != fontSize {
            textView.font = .systemFont(ofSize: fontSize)
        }
        guard textView.string != text, !textView.hasMarkedText() else { return }
        context.coordinator.isApplyingExternalText = true
        textView.string = text
        context.coordinator.isApplyingExternalText = false
        textView.undoManager?.removeAllActions()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: selectedRange)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        private let selectedRange: Binding<Range<Int>?>?
        var isApplyingExternalText = false
        var completesTaskBoxes = false
        var continuesLists = false
        var onCommandReturn: (() -> Void)?
        private weak var textView: NSTextView?
        private var lineMoveMonitor: Any?

        init(text: Binding<String>, selectedRange: Binding<Range<Int>?>?) {
            self.text = text
            self.selectedRange = selectedRange
        }

        func installLineMoveMonitor(for textView: NSTextView) {
            self.textView = textView
            lineMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if let self, let textView = self.textView,
                   event.window === textView.window,
                   textView.window?.firstResponder === textView,
                   !textView.hasMarkedText(),
                   [kVK_Return, kVK_ANSI_KeypadEnter].contains(Int(event.keyCode)) {
                    let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
                    if flags == .shift, self.continuesLists {
                        self.continueList(in: textView)
                        return nil
                    }
                    if flags == .command, let onCommandReturn = self.onCommandReturn {
                        onCommandReturn()
                        return nil
                    }
                }
                guard let self, let textView = self.textView,
                      event.window === textView.window,
                      textView.window?.firstResponder === textView,
                      !textView.hasMarkedText(),
                      event.modifierFlags.intersection([.command, .option, .shift, .control]) == .option
                else { return event }
                let direction: PlainTextLineMover.Direction
                switch Int(event.keyCode) {
                case kVK_UpArrow: direction = .up
                case kVK_DownArrow: direction = .down
                default: return event
                }
                return self.moveLine(direction, in: textView) ? nil : event
            }
        }

        private func continueList(in textView: NSTextView) {
            let edit = ScratchpadSupport.lineBreakEdit(in: textView.string, selection: textView.selectedRange())
            textView.breakUndoCoalescing()
            textView.insertText(edit.replacement, replacementRange: edit.range)
            textView.setSelectedRange(NSRange(location: edit.caret, length: 0))
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        func removeLineMoveMonitor() {
            if let lineMoveMonitor {
                NSEvent.removeMonitor(lineMoveMonitor)
                self.lineMoveMonitor = nil
            }
        }

        private func moveLine(_ direction: PlainTextLineMover.Direction, in textView: NSTextView) -> Bool {
            let before = textView.selectedRange()
            guard let result = PlainTextLineMover.moving(direction, in: textView.string, selection: before)
            else { return false }
            let full = textView.string as NSString
            let block = full.lineRange(for: before)
            let span = direction == .up
                ? NSUnionRange(full.lineRange(for: NSRange(location: block.location - 1, length: 0)), block)
                : NSUnionRange(block, full.lineRange(for: NSRange(location: NSMaxRange(block), length: 0)))
            let replacement = (result.text as NSString).substring(with: span)
            if replacement != full.substring(with: span) {
                guard textView.isEditable else { return false }
                textView.breakUndoCoalescing()
                Self.keepSelection(before, whenUndoing: true, in: textView)
                guard textView.shouldChangeText(in: span, replacementString: replacement) else { return false }
                textView.textStorage?.replaceCharacters(in: span, with: replacement)
                textView.didChangeText()
                Self.keepSelection(result.selection, whenUndoing: false, in: textView)
            }
            textView.setSelectedRange(result.selection)
            textView.scrollRangeToVisible(result.selection)
            return true
        }

        private static func keepSelection(_ selection: NSRange, whenUndoing: Bool, in textView: NSTextView) {
            textView.undoManager?.registerUndo(withTarget: textView) { textView in
                if textView.undoManager?.isUndoing == whenUndoing { textView.setSelectedRange(selection) }
                keepSelection(selection, whenUndoing: whenUndoing, in: textView)
            }
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange,
                      replacementString: String?) -> Bool {
            guard completesTaskBoxes, replacementString == "]", range.length == 0,
                  !textView.hasMarkedText() else { return true }
            let full = textView.string as NSString
            guard range.location <= full.length else { return true }
            let line = full.lineRange(for: NSRange(location: range.location, length: 0))
            let before = full.substring(with: NSRange(location: line.location, length: range.location - line.location))
            guard ScratchpadSupport.completesEmptyTaskBox(before: before) else { return true }
            textView.insertText(" ]", replacementRange: range)
            return false
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalText, let textView = notification.object as? NSTextView else { return }
            let current = textView.string
            if text.wrappedValue != current { text.wrappedValue = current }
            publishSelection(of: textView, in: current)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingExternalText,
                  selectedRange != nil,
                  let textView = notification.object as? NSTextView else { return }
            publishSelection(of: textView, in: textView.string)
        }

        private func publishSelection(of textView: NSTextView, in current: String) {
            guard let selectedRange else { return }
            guard let converted = Range(textView.selectedRange(), in: current) else { return }
            selectedRange.wrappedValue =
                current.distance(from: current.startIndex, to: converted.lowerBound)
                    ..< current.distance(from: current.startIndex, to: converted.upperBound)
        }
    }
}
