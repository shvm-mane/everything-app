import AppKit

final class HorizontalRuleLayoutManager: NSLayoutManager {
    var ruleColor: NSColor = .secondaryLabelColor

    var codeBlockColor: NSColor?

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if let color = codeBlockColor,
           let storage = textStorage,
           let context = NSGraphicsContext.current?.cgContext {
            let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            storage.enumerateAttribute(.wispCodeBlock, in: charRange) { value, range, _ in
                guard value != nil else { return }
                let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                guard glyphs.length > 0 else { return }
                var union = CGRect.null
                enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
                    union = union.isNull ? rect : union.union(rect)
                }
                guard !union.isNull else { return }
                let panel = union.offsetBy(dx: origin.x, dy: origin.y)
                context.saveGState()
                context.setFillColor(color.cgColor)
                context.addPath(CGPath(
                    roundedRect: panel, cornerWidth: 5, cornerHeight: 5, transform: nil
                ))
                context.fillPath()
                context.restoreGState()
            }
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage = textStorage,
              let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        let nsString = textStorage.string as NSString
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        textStorage.enumerateAttribute(.wispBullet, in: charRange) { value, range, _ in
            guard let color = value as? NSColor, range.length > 0, let container = textContainers.first else { return }
            for index in range.location..<NSMaxRange(range) {
                let glyphs = glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
                guard glyphs.length > 0 else { continue }
                let rect = boundingRect(forGlyphRange: glyphs, in: container)
                let font = (textStorage.attribute(.font, at: index, effectiveRange: nil) as? NSFont)
                    ?? NSFont.systemFont(ofSize: 14)
                let marker = nsString.character(at: index) == 0x2D ? "–" : "•"
                let bullet = NSAttributedString(string: marker, attributes: [.font: font, .foregroundColor: color])
                let size = bullet.size()
                let fragment = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                let baseline = fragment.minY + self.location(forGlyphAt: glyphs.location).y
                bullet.draw(at: NSPoint(x: origin.x + rect.midX - size.width / 2,
                                        y: origin.y + baseline - font.ascender))
            }
        }

        textStorage.enumerateAttribute(.wispCheckbox, in: charRange) { value, range, _ in
            guard let mark = value as? WispCheckboxMark, range.length > 0,
                  let container = textContainers.first else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            // The box sits at the right end of the hidden marker, a small gap
            // before the text; sized from the marker's own font.
            let font = (textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
                ?? NSFont.systemFont(ofSize: 14)
            // Measured to the `]`, so a trailing space doesn't move the box.
            var boxRange = range
            if boxRange.length > 1, nsString.character(at: NSMaxRange(boxRange) - 1) == 0x20 { boxRange.length -= 1 }
            let whole = boundingRect(forGlyphRange: glyphRange(forCharacterRange: boxRange, actualCharacterRange: nil),
                                     in: container)
            let fragment = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let baseline = fragment.minY + self.location(forGlyphAt: glyphs.location).y
            let side = (font.capHeight + 5).rounded()
            let midY = origin.y + baseline - font.xHeight / 2
            let box = NSRect(x: origin.x + whole.maxX - side - 2, y: midY - side / 2, width: side, height: side)
            let path = NSBezierPath(roundedRect: box, xRadius: side * 0.28, yRadius: side * 0.28)
            if mark.checked {
                mark.color.withAlphaComponent(0.85).setFill()
                path.fill()
                let check = NSBezierPath()
                check.move(to: NSPoint(x: box.minX + side * 0.26, y: box.midY + side * 0.02))
                check.line(to: NSPoint(x: box.minX + side * 0.43, y: box.maxY - side * 0.27))
                check.line(to: NSPoint(x: box.maxX - side * 0.24, y: box.minY + side * 0.28))
                check.lineWidth = max(1.5, side * 0.13)
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                NSColor.black.withAlphaComponent(0.9).setStroke()
                check.stroke()
            } else {
                let inset = path
                inset.lineWidth = 1.4
                mark.color.withAlphaComponent(0.55).setStroke()
                inset.stroke()
            }
        }

        var lineStart = charRange.location
        let charEnd = charRange.location + charRange.length
        while lineStart < charEnd {
            let lineRange = nsString.lineRange(for: NSRange(location: lineStart, length: 0))
            if Self.isHorizontalRuleLine(lineRange: lineRange, in: nsString),
               textStorage.attribute(.wispCodeBlock, at: lineRange.location, effectiveRange: nil) == nil {
                let glyphRange = self.glyphRange(
                    forCharacterRange: lineRange,
                    actualCharacterRange: nil
                )
                if glyphRange.length > 0 {
                    let fragmentRect = lineFragmentRect(
                        forGlyphAt: glyphRange.location,
                        effectiveRange: nil
                    )
                    let cy = origin.y + fragmentRect.midY
                    let lineRect = CGRect(
                        x: origin.x + fragmentRect.minX,
                        y: cy - 0.5,
                        width: fragmentRect.width,
                        height: 1.0
                    )
                    context.saveGState()
                    context.setFillColor(ruleColor.cgColor)
                    context.fill(lineRect)
                    context.restoreGState()
                }
            }
            lineStart = lineRange.location + lineRange.length
        }
    }

    static func isHorizontalRuleLine(lineRange: NSRange, in nsString: NSString) -> Bool {
        var contentEnd = lineRange.location + lineRange.length
        if contentEnd > lineRange.location,
           nsString.character(at: contentEnd - 1) == 0x0A {
            contentEnd -= 1
        }
        let contentLength = contentEnd - lineRange.location
        if contentLength < 3 { return false }
        for i in 0..<contentLength {
            let c = nsString.character(at: lineRange.location + i)
            if c != 0x2D && c != 0x2500 { return false }
        }
        return true
    }

    static func isHorizontalRuleLine(_ line: String) -> Bool {
        let ns = line as NSString
        return isHorizontalRuleLine(
            lineRange: NSRange(location: 0, length: ns.length),
            in: ns
        )
    }
}
