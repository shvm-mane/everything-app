import SwiftUI
import AppKit

struct MinimalTextEditor: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int
    var scrollToken: Int
    var scrollTarget: Int
    var findHighlightToken: Int
    var findHighlightRange: NSRange
    var reminderFlashToken: Int
    var reminderFlashRange: NSRange
    var fontSize: FontSize
    var fontFace: FontFace
    var theme: WispTheme
    var transparency: Transparency
    var connect: (NoteEditor) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = CaretTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.contentView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        if let textContainer = textView.textContainer {
            textContainer.replaceLayoutManager(HorizontalRuleLayoutManager())
        }

        let font = Self.makeFont(face: fontFace, size: fontSize.pointSize)
        let paragraph = MarkdownStyler.bodyParagraph()

        let click = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleCheckboxClick(_:))
        )
        click.delegate = context.coordinator
        click.delaysPrimaryMouseButtonEvents = true
        textView.addGestureRecognizer(click)

        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = font
        textView.defaultParagraphStyle = paragraph
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.setAccessibilityLabel("Scratchpad")
        textView.string = text
        textView.textStorage?.delegate = context.coordinator
        context.coordinator.observeWidth(of: scrollView, textView: textView)
        context.coordinator.textView = textView
        context.coordinator.observeReminders(in: textView)
        connect(context.coordinator)

        Self.applyPalette(
            to: textView, face: fontFace, size: fontSize,
            theme: theme, transparency: transparency
        )

        context.coordinator.lastFontSize = fontSize
        context.coordinator.lastFontFace = fontFace
        context.coordinator.lastTheme = theme
        context.coordinator.lastTransparency = transparency
        context.coordinator.updateColumn(textView: textView, in: scrollView)
        if let saved = Self.savedCaret {
            DispatchQueue.main.async {
                let length = (textView.string as NSString).length
                let location = min(saved.selection.location, length)
                let selection = NSRange(location: location,
                                        length: min(saved.selection.length, length - location))
                textView.setSelectedRange(selection)
                scrollView.contentView.scroll(to: saved.scroll)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                textView.window?.makeFirstResponder(textView)
            }
        }
        return scrollView
    }

    static var savedCaret: (selection: NSRange, scroll: NSPoint)?

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        if let textView = scrollView.documentView as? NSTextView {
            savedCaret = (textView.selectedRange(), scrollView.contentView.bounds.origin)
            textView.breakUndoCoalescing()
            if let undo = textView.undoManager {
                undo.removeAllActions(withTarget: textView)
                if let storage = textView.textStorage { undo.removeAllActions(withTarget: storage) }
                undo.removeAllActions()
            }
        }
        coordinator.stopObservingWidth()
        coordinator.stopObservingReminders()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.forgetDrafts()
            context.coordinator.pendingEdit = nil
            context.coordinator.lastHighlight = nil
            if let storage = textView.textStorage {
                Self.restyle(
                    storage, face: fontFace, size: fontSize,
                    theme: theme, transparency: transparency
                )
            }
        }
        if context.coordinator.lastFontSize != fontSize {
            context.coordinator.lastFontSize = fontSize
            applyFont(to: textView)
            context.coordinator.updateColumn(textView: textView, in: scrollView)
        }
        if context.coordinator.lastFontFace != fontFace {
            context.coordinator.lastFontFace = fontFace
            applyFont(to: textView)
        }
        if context.coordinator.lastTheme != theme
            || context.coordinator.lastTransparency != transparency {
            context.coordinator.lastTheme = theme
            context.coordinator.lastTransparency = transparency
            Self.applyPalette(
                to: textView, face: fontFace, size: fontSize,
                theme: theme, transparency: transparency
            )
        }
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
            // Focused while the island was still opening, the caret was
            // scrolled into a smaller view; once open, a note that fits sits
            // at the top again.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak scrollView] in
                guard let scrollView, let document = scrollView.documentView else { return }
                if document.frame.height <= scrollView.contentView.bounds.height + 1 {
                    scrollView.contentView.scroll(to: .zero)
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
            }
        }
        if context.coordinator.lastScrollToken != scrollToken {
            context.coordinator.lastScrollToken = scrollToken
            let target = scrollTarget
            DispatchQueue.main.async {
                let length = (textView.string as NSString).length
                let safe = max(0, min(target, length))
                let range = NSRange(location: safe, length: 0)
                textView.scrollRangeToVisible(range)
                textView.setSelectedRange(range)
                textView.window?.makeFirstResponder(textView)
            }
        }
        if context.coordinator.lastReminderFlashToken != reminderFlashToken {
            context.coordinator.lastReminderFlashToken = reminderFlashToken
            let range = reminderFlashRange
            DispatchQueue.main.async {
                context.coordinator.flash(range, in: textView)
            }
        }
        if context.coordinator.lastFindHighlightToken != findHighlightToken {
            context.coordinator.lastFindHighlightToken = findHighlightToken
            let range = findHighlightRange
            let color = WispPalette.for(theme).findHighlight
            if let storage = textView.textStorage {
                if let previous = context.coordinator.lastHighlight {
                    Self.restyle(
                        storage, face: fontFace, size: fontSize,
                        theme: theme, transparency: transparency, edited: previous
                    )
                }
                context.coordinator.lastHighlight = nil
                if range.length > 0, NSMaxRange(range) <= storage.length {
                    storage.addAttribute(.backgroundColor, value: color, range: range)
                    context.coordinator.lastHighlight = range
                    textView.scrollRangeToVisible(range)
                }
            }
        }
    }

    static func restyle(
        _ storage: NSTextStorage,
        face: FontFace,
        size: FontSize,
        theme: WispTheme,
        transparency: Transparency,
        edited: NSRange? = nil
    ) {
        MarkdownStyler.restyle(
            storage, face: face, size: size, theme: theme,
            transparency: transparency, edited: edited
        )
    }

    private func applyFont(to textView: NSTextView) {
        let font = Self.makeFont(face: fontFace, size: fontSize.pointSize)
        textView.font = font
        (textView as? CaretTextView)?.labelFont = font
        var attrs = textView.typingAttributes
        attrs[.font] = font
        textView.typingAttributes = attrs
        if let storage = textView.textStorage {
            Self.restyle(
                storage, face: fontFace, size: fontSize,
                theme: theme, transparency: transparency
            )
        }
    }

    private static func applyPalette(
        to textView: NSTextView,
        face: FontFace,
        size: FontSize,
        theme: WispTheme,
        transparency: Transparency
    ) {
        let palette = WispPalette.for(theme)
        let font = makeFont(face: face, size: size.pointSize)
        let paragraph = MarkdownStyler.bodyParagraph()
        textView.textColor = palette.text
        textView.insertionPointColor = palette.cursor
        textView.selectedTextAttributes = [
            .backgroundColor: palette.selection
        ]
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: palette.text,
            .paragraphStyle: paragraph,
        ]
        if let lm = textView.layoutManager as? HorizontalRuleLayoutManager {
            lm.ruleColor = palette.divider
            lm.codeBlockColor = WispPalette.codeBackground(for: theme, transparency: transparency)
        }
        (textView as? CaretTextView)?.answerColor = palette.text.withAlphaComponent(0.5)
        (textView as? CaretTextView)?.labelFont = font
        if let storage = textView.textStorage {
            restyle(storage, face: face, size: size, theme: theme, transparency: transparency)
        }
    }

    static func makeFont(face: FontFace, size: CGFloat) -> NSFont {
        if let font = face.font(size: size) {
            return font
        }
        for fallback in ["Charter", "Iowan Old Style", "New York"] {
            if let font = NSFont(name: fallback, size: size) {
                return font
            }
        }
        let baseDescriptor = NSFont.systemFont(ofSize: size).fontDescriptor
        let serifDescriptor = baseDescriptor.withDesign(.serif) ?? baseDescriptor
        return NSFont(descriptor: serifDescriptor, size: size) ?? NSFont.systemFont(ofSize: size)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject, NoteEditor, NSTextViewDelegate, NSTextStorageDelegate, NSGestureRecognizerDelegate {
        var text: Binding<String>
        var lastFocusToken: Int = 0
        var lastScrollToken: Int = 0
        var lastFindHighlightToken: Int = 0
        var lastFontSize: FontSize = .medium
        var lastFontFace: FontFace = .charter
        var lastTheme: WispTheme = .dark
        var lastTransparency: Transparency = .subtle
        var pendingEdit: NSRange?
        var lastHighlight: NSRange?
        private var typedSingleCharacter = false
        private var widthObserver: NSObjectProtocol?
        var lastReminderFlashToken = 0
        private var draftReminders: Set<String> = []
        private var draftOrigins: [String: String] = [:] {
            didSet { if draftOrigins != oldValue { reminderStore.editing = draftOrigins } }
        }
        private var restoredDrafts: Set<String> = []
        private var editIsUndo = false
        private var editInserts = ""
        private var lineBeforeEdit: String?
        weak var textView: NSTextView?
        private var inTextDidChange = false
        lazy var reminderStore: ReminderStore = .shared
        private var reminderObservers: [NSObjectProtocol] = []
        private var flashTimer: Timer?
        private var flashStep = 0
        private weak var flashLayoutManager: NSLayoutManager?
        private var flashRange = NSRange(location: 0, length: 0)
        private var flashHoldsStill = false

        init(text: Binding<String>) {
            self.text = text
        }

        nonisolated func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters) else { return }
            MainActor.assumeIsolated {
                pendingEdit = Self.merge(pendingEdit, editedRange, delta: delta)
            }
        }

        nonisolated static func merge(_ earlier: NSRange?, _ edit: NSRange, delta: Int) -> NSRange {
            guard let earlier else { return edit }
            let start = min(earlier.location, edit.location)
            let earlierEnd = NSMaxRange(earlier) + (edit.location <= NSMaxRange(earlier) ? delta : 0)
            let end = max(earlierEnd, NSMaxRange(edit))
            return NSRange(location: start, length: max(0, end - start))
        }

        // MARK: Column width

        func updateColumn(textView: NSTextView, in scrollView: NSScrollView) {
            let width = scrollView.contentView.bounds.width
            let measure = lastFontSize.pointSize * 34
            let inset = max(0, ((width - measure) / 2).rounded(.down))
            if textView.textContainerInset.width != inset {
                textView.textContainerInset = NSSize(width: inset, height: 0)
            }
        }

        func observeWidth(of scrollView: NSScrollView, textView: NSTextView) {
            scrollView.contentView.postsFrameChangedNotifications = true
            widthObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView, weak textView] _ in
                MainActor.assumeIsolated {
                    guard let self, let scrollView, let textView else { return }
                    self.updateColumn(textView: textView, in: scrollView)
                }
            }
        }

        func stopObservingWidth() {
            if let widthObserver { NotificationCenter.default.removeObserver(widthObserver) }
            widthObserver = nil
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            inTextDidChange = true
            defer { inTextDidChange = false }
            text.wrappedValue = textView.string
            stopFlash()

            typedSingleCharacter = false

            guard !textView.hasMarkedText(), let edited = pendingEdit,
                  let storage = textView.textStorage else { return }
            pendingEdit = nil
            let clearsHighlight = lastHighlight != nil
            lastHighlight = nil
            MinimalTextEditor.restyle(
                storage, face: lastFontFace, size: lastFontSize,
                theme: lastTheme, transparency: lastTransparency,
                edited: clearsHighlight ? nil : edited
            )
            redrawLines(around: edited, in: textView)
            noteDraftReminders(around: edited, in: textView)
            commitDraftReminders(in: textView, includingCaretLine: false)
        }

        // MARK: Reminders

        private func noteDraftReminders(around edited: NSRange, in textView: NSTextView) {
            let before = lineBeforeEdit
            lineBeforeEdit = nil
            guard let storage = textView.textStorage else { return }
            let ns = storage.string as NSString
            let start = min(edited.location, ns.length)
            let end = min(max(start, NSMaxRange(edited)), ns.length)
            let lines = ns.lineRange(for: NSRange(location: start, length: end - start))
            guard ns.range(of: "remind me", options: .caseInsensitive, range: lines).location != NSNotFound
                    || before.map({ draftReminders.contains($0) }) == true else { return }
            var edited: [(line: String, range: NSRange)] = []
            ns.enumerateSubstrings(in: lines, options: .byLines) { line, range, _, _ in
                if let line { edited.append((line, range)) }
            }
            var origin = before
            if let before, !edited.contains(where: { $0.line == before }) {
                draftReminders.remove(before)
                restoredDrafts.remove(before)
                if let inherited = draftOrigins.removeValue(forKey: before) { origin = inherited }
            }
            for (line, range) in edited where line != before && Reminders.isReminder(line)
                && !reminderStore.isExternal(line)
                && (range.location >= storage.length
                    || storage.attribute(.wispCodeBlock, at: range.location, effectiveRange: nil) == nil) {
                draftReminders.insert(line)
                let putBack = editIsUndo || editInserts.contains(line) || before.map { Reminders.ticked(line) == $0 } == true
                if putBack { restoredDrafts.insert(line) } else { restoredDrafts.remove(line) }
                if let origin { draftOrigins[line] = origin }
            }
        }

        func commitDraftReminders(in textView: NSTextView, includingCaretLine: Bool) {
            guard !draftReminders.isEmpty else { return }
            let ns = textView.string as NSString
            let caret = min(textView.selectedRange().location, ns.length)
            let caretLine = Self.lineText(at: caret, in: ns)
            let finished = draftReminders.filter { includingCaretLine || $0 != caretLine }
            guard !finished.isEmpty else { return }
            let inNote = ReminderStore.present(finished, in: textView.string)
            for draft in finished {
                draftReminders.remove(draft)
                let origin = draftOrigins.removeValue(forKey: draft)
                let restored = restoredDrafts.remove(draft) != nil
                if inNote.contains(draft) { reminderStore.commit(line: draft, origin: origin, restored: restored) }
            }
        }

        func forgetDrafts() {
            draftReminders = []
            draftOrigins = [:]
            restoredDrafts = []
            lineBeforeEdit = nil
        }

        // MARK: NoteEditor

        func finishEditing() {
            guard let textView else { return }
            commitDraftReminders(in: textView, includingCaretLine: true)
        }

        func replaceLine(_ range: NSRange, reading line: String, with replacement: String) -> Bool {
            guard let textView else { return false }
            return replaceLine(range, reading: line, with: replacement, in: textView)
        }

        private func replaceLine(_ range: NSRange, reading line: String, with replacement: String, in textView: NSTextView) -> Bool {
            guard textView.string == text.wrappedValue else { return false }
            let ns = textView.string as NSString
            guard NSMaxRange(range) <= ns.length,
                  ns.lineRange(for: NSRange(location: range.location, length: 0)).location == range.location,
                  Self.lineText(at: range.location, in: ns) == line else { return false }
            LineEditing.apply(
                LineEditing.replacing(range, with: replacement, keeping: textView.selectedRange()),
                to: textView, scroll: false
            )
            return true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !textView.isFieldEditor,
                  pendingEdit == nil else { return }
            commitDraftReminders(in: textView, includingCaretLine: false)
        }

        func observeReminders(in textView: NSTextView) {
            let center = NotificationCenter.default
            reminderObservers.append(center.addObserver(
                forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
            ) { [weak self, weak textView] note in
                let sender = (note.object as? NSWindow).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, let textView, sender == textView.window.map(ObjectIdentifier.init) else { return }
                    self.commitDraftReminders(in: textView, includingCaretLine: true)
                }
            })
            reminderObservers.append(center.addObserver(
                forName: ReminderStore.didChange, object: nil, queue: .main
            ) { [weak textView] _ in
                MainActor.assumeIsolated { textView?.needsDisplay = true }
            })
        }

        func stopObservingReminders() {
            reminderObservers.forEach(NotificationCenter.default.removeObserver)
            reminderObservers = []
            flashTimer?.invalidate()
        }

        func flash(_ range: NSRange, in textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  range.length > 0, NSMaxRange(range) <= (textView.string as NSString).length else { return }
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: NSMaxRange(range), length: 0))
            textView.scrollRangeToVisible(range)
            flashTimer?.invalidate()
            if let previous = flashLayoutManager {
                previous.removeTemporaryAttribute(.backgroundColor, forCharacterRange: flashRange)
            }
            layoutManager.addTemporaryAttribute(.backgroundColor, value: Self.flashColor(1), forCharacterRange: range)
            flashLayoutManager = layoutManager
            flashRange = range
            flashStep = 0
            flashHoldsStill = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            flashTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.stepFlash() }
            }
        }

        private func stopFlash() {
            guard flashTimer?.isValid == true || flashLayoutManager != nil else { return }
            flashTimer?.invalidate()
            if let layoutManager = flashLayoutManager, let storage = layoutManager.textStorage {
                layoutManager.removeTemporaryAttribute(
                    .backgroundColor, forCharacterRange: NSRange(location: 0, length: storage.length)
                )
            }
            flashLayoutManager = nil
        }

        private func stepFlash() {
            guard let layoutManager = flashLayoutManager else {
                flashTimer?.invalidate()
                return
            }
            flashStep += 1
            let strength = flashHoldsStill
                ? (flashStep < 15 ? 1.0 : 0.0)
                : min(1, max(0, 1 - Double(flashStep - 5) / 10))
            if strength <= 0 {
                layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: flashRange)
                flashTimer?.invalidate()
            } else {
                layoutManager.addTemporaryAttribute(.backgroundColor, value: Self.flashColor(strength), forCharacterRange: flashRange)
            }
        }

        private static func flashColor(_ strength: Double) -> NSColor {
            NSColor.controlAccentColor.withAlphaComponent(0.28 * strength)
        }

        private static func lineText(at location: Int, in ns: NSString) -> String {
            LineEditing.splitTerminator(ns.substring(with: ns.lineRange(for: NSRange(location: location, length: 0)))).body
        }

        private func redrawLines(around edited: NSRange, in textView: NSTextView) {
            guard let layoutManager = textView.layoutManager else { return }
            let ns = textView.string as NSString
            let start = min(edited.location, ns.length)
            let end = min(max(start, NSMaxRange(edited)), ns.length)
            let paragraphs = ns.paragraphRange(for: NSRange(location: start, length: end - start))
            let glyphs = layoutManager.glyphRange(forCharacterRange: paragraphs, actualCharacterRange: nil)
            let originY = textView.textContainerOrigin.y
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
                textView.setNeedsDisplay(NSRect(
                    x: 0, y: rect.minY + originY, width: textView.bounds.width, height: rect.height
                ))
            }
        }

        // MARK: Checkbox clicks

        func gestureRecognizerShouldBegin(_ recognizer: NSGestureRecognizer) -> Bool {
            guard let click = recognizer as? NSClickGestureRecognizer,
                  let textView = recognizer.view as? NSTextView else { return false }
            let point = click.location(in: textView)
            if (textView as? CaretTextView)?.reminderTick(at: point) != nil { return true }
            if NSEvent.modifierFlags.contains(.command) {
                return Self.link(in: textView, at: point) != nil
            }
            return Self.checkboxRange(in: textView, at: point) != nil
        }

        @objc func handleCheckboxClick(_ recognizer: NSClickGestureRecognizer) {
            guard let textView = recognizer.view as? NSTextView else { return }
            let point = recognizer.location(in: textView)
            if tickReminder(at: point, in: textView) { return }
            if NSEvent.modifierFlags.contains(.command) {
                if let url = Self.link(in: textView, at: point) {
                    NSWorkspace.shared.open(url)
                }
                return
            }
            guard let box = Self.checkboxRange(in: textView, at: point) else { return }
            let state = NSRange(location: box.location + 1, length: 1)
            let current = (textView.string as NSString).substring(with: state)
            let selection = textView.selectedRange()
            replace(in: textView, range: state, with: current == " " ? "x" : " ")
            // The caret never lands inside the box: it stays where it was,
            // or goes to the end of the line if it was in the marker.
            let ns = textView.string as NSString
            let line = ns.lineRange(for: NSRange(location: box.location, length: 0))
            var lineEnd = NSMaxRange(line)
            while lineEnd > line.location, ns.character(at: lineEnd - 1) == 0x0A { lineEnd -= 1 }
            let inMarker = selection.location >= line.location && selection.location <= NSMaxRange(box)
            textView.setSelectedRange(inMarker ? NSRange(location: lineEnd, length: 0) : selection)
        }

        func tickReminder(at point: NSPoint, in textView: NSTextView) -> Bool {
            guard let line = (textView as? CaretTextView)?.reminderTick(at: point) else { return false }
            let text = (textView.string as NSString).substring(with: line)
            _ = replaceLine(line, reading: text, with: Reminders.ticked(text), in: textView)
            return true
        }

        private static func isInCodeBlock(_ textView: NSTextView, at location: Int) -> Bool {
            guard let storage = textView.textStorage, location < storage.length else { return false }
            return storage.attribute(.wispCodeBlock, at: location, effectiveRange: nil) != nil
        }

        private static func link(in textView: NSTextView, at point: NSPoint) -> URL? {
            guard let index = characterIndex(in: textView, at: point),
                  let storage = textView.textStorage else { return nil }
            return storage.attribute(.wispLink, at: index, effectiveRange: nil) as? URL
        }

        private static func characterIndex(in textView: NSTextView, at point: NSPoint) -> Int? {
            guard let layoutManager = textView.layoutManager,
                  let container = textView.textContainer,
                  layoutManager.numberOfGlyphs > 0 else { return nil }
            let origin = textView.textContainerOrigin
            let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
            var fraction: CGFloat = 0
            let glyph = layoutManager.glyphIndex(
                for: local, in: container, fractionOfDistanceThroughGlyph: &fraction
            )
            let bounds = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyph, length: 1), in: container
            )
            guard bounds.contains(local) else { return nil }
            let index = layoutManager.characterIndexForGlyph(at: glyph)
            return index < (textView.string as NSString).length ? index : nil
        }

        private static func checkboxRange(in textView: NSTextView, at point: NSPoint) -> NSRange? {
            guard let index = characterIndex(in: textView, at: point) else { return nil }
            let ns = textView.string as NSString
            let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
            let line = ns.substring(with: lineRange)
            guard let box = Checkbox.boxRange(in: line) else { return nil }
            let absolute = NSRange(location: lineRange.location + box.location, length: box.length)
            // The drawn checkbox covers the whole `- [ ]` marker.
            let bullet = lineRange.location + (line.prefix { $0 == " " || $0 == "\t" }.utf16.count)
            let marker = NSRange(location: bullet, length: NSMaxRange(absolute) - bullet)
            return NSLocationInRange(index, marker) ? absolute : nil
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return handleEnter(in: textView)
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                return acceptAnswer(in: textView)
            }
            return false
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            typedSingleCharacter = affectedCharRange.length == 0
                && (replacementString as NSString?)?.length == 1
            if !inTextDidChange {
                editIsUndo = textView.undoManager?.isUndoing == true || textView.undoManager?.isRedoing == true
                editInserts = replacementString ?? ""
            }
            if !inTextDidChange, !(textView.hasMarkedText() && lineBeforeEdit != nil) {
                let ns = textView.string as NSString
                let line = ns.lineRange(for: NSRange(location: min(affectedCharRange.location, ns.length), length: 0))
                lineBeforeEdit = NSMaxRange(affectedCharRange) <= NSMaxRange(line)
                    ? Self.lineText(at: line.location, in: ns) : nil
            }

            guard replacementString == "-",
                  affectedCharRange.length == 0
            else { return true }

            let s = textView.string as NSString
            let insertAt = affectedCharRange.location
            let lineRange = s.lineRange(for: NSRange(location: insertAt, length: 0))

            let beforeCursor = s.substring(with: NSRange(
                location: lineRange.location,
                length: insertAt - lineRange.location
            ))
            var lineEnd = lineRange.location + lineRange.length
            if lineEnd > lineRange.location, s.character(at: lineEnd - 1) == 0x0A {
                lineEnd -= 1
            }
            let afterCursor = s.substring(with: NSRange(
                location: insertAt,
                length: lineEnd - insertAt
            ))

            guard beforeCursor == "--", afterCursor.isEmpty,
                  !Self.isInCodeBlock(textView, at: lineRange.location) else { return true }

            let twoDashRange = NSRange(location: lineRange.location, length: 2)
            replaceWithHorizontalRule(in: textView, range: twoDashRange)
            return false
        }

        private func acceptAnswer(in textView: NSTextView) -> Bool {
            guard let storage = textView.textStorage,
                  let insertion = Self.answerInsertion(in: storage, selection: textView.selectedRange())
            else { return false }
            replace(in: textView, range: NSRange(location: insertion.location, length: 0), with: insertion.text)
            return true
        }

        static func answerInsertion(in storage: NSTextStorage, selection: NSRange) -> (location: Int, text: String)? {
            let ns = storage.string as NSString
            let caret = selection.location
            guard selection.length == 0, caret > 0, caret <= ns.length,
                  let answer = storage.attribute(.wispMathAnswer, at: caret - 1, effectiveRange: nil) as? String
            else { return nil }
            var i = caret
            while i < ns.length, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i += 1 }
            guard i == ns.length || [0x0A, 0x0D, 0x2028, 0x2029].contains(ns.character(at: i)) else { return nil }
            let gap = ns.character(at: caret - 1) == 0x3D ? " " : ""
            return (caret, gap + answer)
        }

        private func handleEnter(in textView: NSTextView) -> Bool {
            let s = textView.string as NSString
            let cursor = textView.selectedRange().location
            let lineRange = s.lineRange(for: NSRange(location: cursor, length: 0))
            var lineEnd = lineRange.location + lineRange.length
            if lineEnd > lineRange.location, s.character(at: lineEnd - 1) == 0x0A {
                lineEnd -= 1
            }
            let line = s.substring(with: NSRange(
                location: lineRange.location,
                length: lineEnd - lineRange.location
            ))

            if SmartEditing.isHorizontalRuleTrigger(line),
               !Self.isInCodeBlock(textView, at: lineRange.location) {
                let replaceRange = NSRange(
                    location: lineRange.location,
                    length: lineEnd - lineRange.location
                )
                replaceWithHorizontalRule(in: textView, range: replaceRange)
                return true
            }

            guard let marker = SmartEditing.nextListMarker(for: line) else {
                return false
            }

            if marker.isEmpty {
                let stripRange = NSRange(
                    location: lineRange.location,
                    length: cursor - lineRange.location
                )
                replace(in: textView, range: stripRange, with: "\n")
            } else {
                let insert = "\n" + marker
                replace(in: textView, range: NSRange(location: cursor, length: 0), with: insert)
            }
            return true
        }

        private func replaceWithHorizontalRule(in textView: NSTextView, range: NSRange) {
            let replacement = SmartEditing.horizontalRule + "\n"
            replace(in: textView, range: range, with: replacement)
            let hrLength = (SmartEditing.horizontalRule as NSString).length
            let hrRange = NSRange(location: range.location, length: hrLength)
            textView.textStorage?.addAttribute(
                .foregroundColor,
                value: NSColor.clear,
                range: hrRange
            )
        }

        private func replace(in textView: NSTextView, range: NSRange, with replacement: String) {
            guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
            textView.textStorage?.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()
            let newCursor = range.location + (replacement as NSString).length
            let newRange = NSRange(location: newCursor, length: 0)
            textView.setSelectedRange(newRange)
            textView.scrollRangeToVisible(newRange)
        }
    }
}

@MainActor
protocol NoteEditor: AnyObject {
    func finishEditing()
    func replaceLine(_ range: NSRange, reading line: String, with replacement: String) -> Bool
}
