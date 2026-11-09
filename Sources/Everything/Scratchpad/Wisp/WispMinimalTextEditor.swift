import SwiftUI
import AppKit

struct MinimalTextEditor: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int
    var scrollToken: Int
    var scrollTarget: Int
    var findHighlightToken: Int
    var findHighlightRange: NSRange
    var fontSize: FontSize
    var fontFace: FontFace
    var theme: WispTheme
    var transparency: Transparency

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
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
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
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate, NSGestureRecognizerDelegate {
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
        weak var textView: NSTextView?

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
            text.wrappedValue = textView.string

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
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, !textView.isFieldEditor,
                  pendingEdit == nil else { return }
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
            if NSEvent.modifierFlags.contains(.command) {
                return Self.link(in: textView, at: point) != nil
            }
            return Self.checkboxRange(in: textView, at: point) != nil
        }

        @objc func handleCheckboxClick(_ recognizer: NSClickGestureRecognizer) {
            guard let textView = recognizer.view as? NSTextView else { return }
            let point = recognizer.location(in: textView)
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

        /// Keeps the caret out of the hidden `- [ ] ` marker drawn as a checkbox.
        func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange old: NSRange,
                      toCharacterRange new: NSRange) -> NSRange {
            guard new.length == 0 else { return new }
            let ns = textView.string as NSString
            guard new.location <= ns.length else { return new }
            let lineRange = ns.lineRange(for: NSRange(location: new.location, length: 0))
            let line = ns.substring(with: lineRange)
            guard let box = Checkbox.boxRange(in: line) else { return new }
            var end = lineRange.location + NSMaxRange(box)
            if end < ns.length, ns.character(at: end) == 0x20 { end += 1 }
            guard new.location < end else { return new }
            if old.length == 0, old.location == end, new.location < end, lineRange.location > 0 {
                return NSRange(location: lineRange.location - 1, length: 0)
            }
            return NSRange(location: end, length: 0)
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
            return false
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            typedSingleCharacter = affectedCharRange.length == 0
                && (replacementString as NSString?)?.length == 1
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
