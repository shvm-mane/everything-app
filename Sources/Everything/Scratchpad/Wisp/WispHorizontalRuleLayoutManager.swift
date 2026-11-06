import AppKit

/// NSLayoutManager subclass that paints a full-width horizontal rule
/// over any line whose entire content is HR markers (`-` and/or `─`,
/// 3+ characters). The HR characters themselves are kept in storage
/// (so the file on disk stays plain markdown — `---`) but rendered
/// with `foregroundColor = .clear` from the styling pass, so the only
/// visible thing on the line is the rule we draw here.
///
/// The line spans the line fragment's full width, which means it
/// tracks panel-width changes for free — resize the window and the
/// rule grows/shrinks with it.
final class HorizontalRuleLayoutManager: NSLayoutManager {
    /// Color used when stroking the rule. The editor updates this on
    /// every theme flip via applyPalette.
    var ruleColor: NSColor = .secondaryLabelColor

    /// Ground painted behind fenced code blocks. Set alongside
    /// `ruleColor`; nil paints nothing.
    var codeBlockColor: NSColor?

    /// Paint one panel per fenced block, spanning the line fragment's
    /// full width so it tracks the window like the rule above. An
    /// attribute-only `.backgroundColor` would stop at the end of each
    /// line and leave a ragged right edge.
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

        // Everything: list markers drawn as dashes or bullets, centred
        // where the hidden `-`/`*` sits, sized to the line's font.
        textStorage.enumerateAttribute(.wispBullet, in: charRange) { value, range, _ in
            guard let color = value as? NSColor, range.length > 0, let container = textContainers.first else { return }
            for index in range.location..<NSMaxRange(range) {
                let glyphs = glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
                guard glyphs.length > 0 else { continue }
                let rect = boundingRect(forGlyphRange: glyphs, in: container)
                let font = (textStorage.attribute(.font, at: index, effectiveRange: nil) as? NSFont)
                    ?? NSFont.systemFont(ofSize: 14)
                // `-` items read as dashes, `*` and `+` as dots.
                let marker = nsString.character(at: index) == 0x2D ? "–" : "•"
                let bullet = NSAttributedString(string: marker, attributes: [.font: font, .foregroundColor: color])
                let size = bullet.size()
                let fragment = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                // The glyph's baseline within its line; the view is flipped,
                // so drawing at a point places the text's top there.
                let baseline = fragment.minY + self.location(forGlyphAt: glyphs.location).y
                bullet.draw(at: NSPoint(x: origin.x + rect.midX - size.width / 2,
                                        y: origin.y + baseline - font.ascender))
            }
        }

        var lineStart = charRange.location
        let charEnd = charRange.location + charRange.length
        while lineStart < charEnd {
            let lineRange = nsString.lineRange(for: NSRange(location: lineStart, length: 0))
            // Inside a fenced block `---` is code, not a rule.
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

    /// Pure: is the given line content (a line range in `nsString`)
    /// an HR-only line — at least three characters, all of which are
    /// either `-` (0x2D) or `─` (0x2500), with the trailing newline
    /// allowed. Public so SelfTests can exercise it.
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

    /// Convenience for tests — takes a Swift String, treats the whole
    /// thing as the line content (no trailing newline expected).
    static func isHorizontalRuleLine(_ line: String) -> Bool {
        let ns = line as NSString
        return isHorizontalRuleLine(
            lineRange: NSRange(location: 0, length: ns.length),
            in: ns
        )
    }
}
