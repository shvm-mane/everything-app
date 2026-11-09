import AppKit

final class CaretTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1, event.modifierFlags.intersection([.shift, .command, .option]).isEmpty,
           let layoutManager, let textContainer {
            let text = string as NSString
            let point = convert(event.locationInWindow, from: nil)
            let y = point.y - textContainerOrigin.y
            if text.length > 0, text.character(at: text.length - 1) == 0x0A {
                let glyphs = layoutManager.glyphRange(for: textContainer)
                if glyphs.length > 0 {
                    let last = layoutManager.lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
                    if y > last.maxY {
                        window?.makeFirstResponder(self)
                        setSelectedRange(NSRange(location: text.length, length: 0))
                        return
                    }
                }
            }
        }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return }
        let visible = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let chars = layoutManager.characterRange(forGlyphRange: visible, actualGlyphRange: nil)
        storage.enumerateAttribute(.wispCheckbox, in: chars) { value, range, _ in
            guard value != nil else { return }
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            addCursorRect(rect, cursor: .arrow)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if isOverCheckbox(convert(event.locationInWindow, from: nil)) { NSCursor.arrow.set() }
        else { super.cursorUpdate(with: event) }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if isOverCheckbox(convert(event.locationInWindow, from: nil)) { NSCursor.arrow.set() }
    }

    /// Whether `point` is over a task's drawn checkbox.
    private func isOverCheckbox(_ point: NSPoint) -> Bool {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return false }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: local, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        guard layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
            .contains(local) else { return false }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        return index < storage.length && storage.attribute(.wispCheckbox, at: index, effectiveRange: nil) != nil
    }

    override func didChangeText() {
        super.didChangeText()
        window?.invalidateCursorRects(for: self)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .option, !hasMarkedText(),
           let key = event.charactersIgnoringModifiers?.unicodeScalars.first?.value,
           key == UInt32(NSUpArrowFunctionKey) || key == UInt32(NSDownArrowFunctionKey) {
            if let edit = LineEditing.moveLines(
                in: string, selection: selectedRange(), up: key == UInt32(NSUpArrowFunctionKey)
            ) {
                LineEditing.apply(edit, to: self)
            }
            return
        }
        super.keyDown(with: event)
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        super.drawInsertionPoint(in: Self.caretRect(in: rect, font: caretFont), color: color, turnedOn: flag)
    }

    private var caretFont: NSFont? {
        guard let storage = textStorage, storage.length > 0 else { return font }
        let ns = storage.string as NSString
        let location = min(selectedRange().location, storage.length)
        var index: Int?
        if location > 0, !"\n\r\u{2028}\u{2029}".utf16.contains(ns.character(at: location - 1)) {
            index = location - 1
        } else if location < storage.length {
            index = location
        }
        guard let index else { return font }
        return storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont ?? font
    }

    static func caretRect(in rect: NSRect, font: NSFont?) -> NSRect {
        guard let font else { return rect }
        let height = (font.ascender - font.descender).rounded(.up)
        guard height < rect.height else { return rect }
        return NSRect(x: rect.minX, y: rect.maxY - height, width: rect.width, height: height)
    }
}

