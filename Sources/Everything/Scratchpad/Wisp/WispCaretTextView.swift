import AppKit

final class CaretTextView: NSTextView {
    var answerColor: NSColor = .tertiaryLabelColor {
        didSet { needsDisplay = true }
    }

    var labelFont: NSFont? {
        didSet { needsDisplay = true }
    }

    static var reminderLabel: ((String) -> TrailingLabel?)?

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawAnswers(in: rect)
    }

    private func drawAnswers(in dirtyRect: NSRect) {
        guard let layoutManager, let container = textContainer,
              let storage = textStorage, storage.length > 0 else { return }
        let origin = textContainerOrigin
        let band = NSRect(
            x: 0, y: dirtyRect.minY - origin.y,
            width: container.size.width, height: dirtyRect.height
        )
        let glyphs = layoutManager.glyphRange(forBoundingRect: band, in: container)
        guard glyphs.length > 0 else { return }
        let chars = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        storage.enumerateAttribute(.wispMathAnswer, in: chars) { value, range, _ in
            guard let answer = value as? String, range.length > 0 else { return }
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? bodyFont
            if let place = placement([(range.length == 1 ? " " : "", answer)], symbol: nil, fitting: false,
                                     after: range, font: font) {
                draw(place, symbol: nil, font: font, strong: false)
            }
        }
        for (anchor, label) in reminderLabels(in: chars) {
            guard let (place, symbol) = reminderPlacement(label, after: anchor) else { continue }
            draw(place, symbol: symbol, font: bodyFont, strong: hoveredTick == NSMaxRange(anchor))
        }
    }

    private func reminderLabels(in range: NSRange) -> [(anchor: NSRange, label: TrailingLabel)] {
        guard let hook = Self.reminderLabel, let storage = textStorage else { return [] }
        let ns = storage.string as NSString
        var found: [(NSRange, TrailingLabel)] = []
        ns.enumerateSubstrings(in: ns.lineRange(for: range), options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            guard Reminders.mightBeReminder(ns, line),
                  storage.attribute(.wispCodeBlock, at: line.location, effectiveRange: nil) == nil,
                  let anchor = Self.labelAnchor(of: line, in: ns),
                  let label = hook(ns.substring(with: line)) else { return }
            found.append((anchor, label))
        }
        return found
    }

    static func labelAnchor(of line: NSRange, in ns: NSString) -> NSRange? {
        var end = NSMaxRange(line)
        while end > line.location, ns.character(at: end - 1) == 0x20 || ns.character(at: end - 1) == 0x09 { end -= 1 }
        return end > line.location ? line : nil
    }

    private struct Placement {
        let text: String
        let textOrigin: NSPoint
        let symbolRect: NSRect?
    }

    private func reminderPlacement(_ label: TrailingLabel, after range: NSRange) -> (Placement, NSImage?)? {
        guard let storage = textStorage, NSMaxRange(range) <= storage.length else { return nil }
        let last = (storage.string as NSString).character(at: NSMaxRange(range) - 1)
        let lead = last == 0x20 || last == 0x09 ? "  " : "   "
        let symbol = label.symbol.flatMap { symbolImage($0, font: bodyFont) }
        var candidates = [(lead, label.full), (lead, label.short), (" ", label.short)]
        if symbol != nil { candidates.append((" ", "")) }
        return placement(candidates, symbol: symbol, fitting: true, after: range, font: bodyFont).map { ($0, symbol) }
    }

    private var symbolCache: [String: NSImage] = [:]

    private func symbolImage(_ name: String, font: NSFont) -> NSImage? {
        let key = "\(name) \(font.pointSize) \(answerColor)"
        if let cached = symbolCache[key] { return cached }
        let config = NSImage.SymbolConfiguration(pointSize: font.pointSize * 0.8, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [answerColor.withAlphaComponent(1)]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        if symbolCache.count > 8 { symbolCache = [:] }
        symbolCache[key] = image
        return image
    }

    private var bodyFont: NSFont { labelFont ?? font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize) }

    private func placement(
        _ candidates: [(lead: String, text: String)], symbol: NSImage?, fitting: Bool,
        after range: NSRange, font: NSFont
    ) -> Placement? {
        guard let layoutManager, let container = textContainer, NSMaxRange(range) > 0 else { return nil }
        let origin = textContainerOrigin
        let last = layoutManager.glyphIndexForCharacter(at: NSMaxRange(range) - 1)
        guard last < layoutManager.numberOfGlyphs else { return nil }
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: last, length: 1), in: container)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: last, effectiveRange: nil)
        let baseline = fragment.minY + layoutManager.location(forGlyphAt: last).y
        let x = origin.x + glyphRect.maxX
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        func width(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: attributes).width }
        let space = width(" ")
        let symbolWidth = symbol.map { $0.size.width } ?? 0
        func total(_ c: (lead: String, text: String)) -> CGFloat {
            width(c.lead) + (symbol == nil ? 0 : symbolWidth + (c.text.isEmpty ? 0 : space)) + width(c.text)
        }
        let room = visibleRect.maxX - x - 4
        guard let chosen = fitting ? candidates.first(where: { total($0) <= room }) : candidates.first else { return nil }
        var at = x + width(chosen.lead)
        var symbolRect: NSRect?
        if let symbol {
            let middle = origin.y + baseline - font.capHeight / 2
            symbolRect = NSRect(x: at, y: middle - symbol.size.height / 2, width: symbol.size.width, height: symbol.size.height)
            at += symbolWidth + space
        }
        return Placement(text: chosen.text, textOrigin: NSPoint(x: at, y: origin.y + baseline - font.ascender), symbolRect: symbolRect)
    }

    private func draw(_ place: Placement, symbol: NSImage?, font: NSFont, strong: Bool) {
        if let symbol, let rect = place.symbolRect {
            symbol.draw(in: rect, from: .zero, operation: .sourceOver,
                        fraction: strong ? 1 : answerColor.alphaComponent, respectFlipped: true, hints: nil)
        }
        NSAttributedString(string: place.text, attributes: [.font: font, .foregroundColor: answerColor])
            .draw(at: place.textOrigin)
    }

    // MARK: The tick on a sent reminder

    private var hoveredTick: Int? {
        didSet {
            guard hoveredTick != oldValue else { return }
            toolTip = hoveredTick == nil ? nil : "Mark done"
        }
    }
    private var hoveredRect: NSRect? {
        didSet {
            guard hoveredRect != oldValue else { return }
            if let oldValue { setNeedsDisplay(oldValue) }
            if let hoveredRect { setNeedsDisplay(hoveredRect) }
        }
    }

    private var tickTracking: NSTrackingArea?

    func reminderTick(at point: NSPoint) -> NSRange? {
        tickHit(at: point)?.line
    }

    private func tickHit(at point: NSPoint) -> (line: NSRange, labelEnd: Int, rect: NSRect)? {
        guard let layoutManager, let container = textContainer, let storage = textStorage,
              storage.length > 0, layoutManager.numberOfGlyphs > 0 else { return nil }
        let origin = textContainerOrigin
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: point.x - origin.x, y: point.y - origin.y), in: container)
        let ns = storage.string as NSString
        let index = min(layoutManager.characterIndexForGlyph(at: glyph), ns.length - 1)
        var start = 0, end = 0, contentsEnd = 0
        ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: index, length: 0))
        for (anchor, label) in reminderLabels(in: NSRange(location: start, length: contentsEnd - start)) where label.ticksLine {
            guard let place = reminderPlacement(label, after: anchor)?.0, let symbol = place.symbolRect,
                  symbol.insetBy(dx: -4, dy: -4).contains(point) else { continue }
            let whole = symbol.union(NSRect(origin: place.textOrigin, size: NSSize(width: visibleRect.maxX - place.textOrigin.x, height: symbol.height)))
            return (NSRange(location: start, length: contentsEnd - start), NSMaxRange(anchor), whole.insetBy(dx: -4, dy: -4))
        }
        return nil
    }

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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tickTracking, trackingAreas.contains(tickTracking) { return }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        tickTracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let hit = tickHit(at: convert(event.locationInWindow, from: nil))
        hoveredTick = hit?.labelEnd
        hoveredRect = hit?.rect
        if hit != nil { NSCursor.pointingHand.set() } else if isOverCheckbox(convert(event.locationInWindow, from: nil)) { NSCursor.arrow.set() }
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

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoveredTick = nil
        hoveredRect = nil
    }

    override func didChangeText() {
        hoveredTick = nil
        hoveredRect = nil
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

struct TrailingLabel: Equatable {
    let full: String
    let short: String
    var symbol: String? = nil
    var ticksLine = false
}
