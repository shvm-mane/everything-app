import AppKit

extension NSAttributedString.Key {

    static let wispLink = NSAttributedString.Key("wispLink")
    static let wispBullet = NSAttributedString.Key("wispBullet")
    static let wispCheckbox = NSAttributedString.Key("wispCheckbox")
}

/// How a task's checkbox is drawn in place of its `- [ ]` marker.
final class WispCheckboxMark: NSObject {
    let checked: Bool
    let color: NSColor

    init(checked: Bool, color: NSColor) {
        self.checked = checked
        self.color = color
    }
}

@MainActor
enum MarkdownStyler {
    nonisolated static let lineHeightMultiple: CGFloat = 1.35

    private static let boldPattern = try! NSRegularExpression(
        pattern: #"\*\*([^\s*](?:[^*\n\r\u2029]*[^\s*])?)\*\*"#
    )
    private static let italicPattern = try! NSRegularExpression(
        pattern: #"\*([^\s*](?:[^*\n\r\u2029]*[^\s*])?)\*"#
    )
    private static let codePattern = try! NSRegularExpression(pattern: #"`([^`\n\r\u2029]+)`"#)
    private static let headingPattern = try! NSRegularExpression(pattern: #"^(#{1,6})\s+\S"#)
    private static let linkPattern = try! NSRegularExpression(
        pattern: #"\bhttps?://(?:[^\s<>"'`()\[\]]|\([^\s<>"'`()]*\))*(?:[^\s<>"'`.,;:!?()\[\]*]|\([^\s<>"'`()]*\))"#
    )

    nonisolated static func bodyParagraph() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = lineHeightMultiple
        return paragraph
    }

    static func restyle(
        _ storage: NSTextStorage,
        face: FontFace,
        size: FontSize,
        theme: WispTheme,
        transparency: Transparency,
        edited: NSRange? = nil
    ) {
        let ns = storage.string as NSString
        guard ns.length > 0 else { return }
        let fences = fenceLineStarts(in: ns)
        var range = NSRange(location: 0, length: ns.length)
        if let edited {
            let start = min(max(0, edited.location), ns.length)
            let end = min(max(start, NSMaxRange(edited)) + 1, ns.length)
            let dirty = ns.paragraphRange(for: NSRange(location: start, length: end - start))
            if blocksUnchanged(after: dirty, in: storage, fences: fences) {
                range = dirty
            }
        }
        guard range.length > 0 else { return }

        let style = Style(face: face, size: size, theme: theme, transparency: transparency)
        storage.beginEditing()
        defer { storage.endEditing() }
        storage.setAttributes([
            .font: style.base,
            .foregroundColor: style.palette.text,
            .paragraphStyle: style.body,
        ], range: range)
        let text = ns as String
        styleLines(in: range, storage: storage, ns: ns, text: text, fences: fences, style: style)
        styleInline(in: range, storage: storage, ns: ns, text: text, style: style)
    }

    // MARK: Lines

    private static func styleLines(
        in range: NSRange, storage: NSTextStorage, ns: NSString, text: String,
        fences: [Int], style: Style
    ) {
        var lineStart = range.location
        let end = NSMaxRange(range)
        while lineStart < end {
            let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            lineStart = NSMaxRange(lineRange)
            var content = lineRange
            if content.length > 0, ns.character(at: NSMaxRange(content) - 1) == 0x0A {
                content.length -= 1
            }

            let isFence = contains(fences, lineRange.location)
            if isFence || isInsideBlock(lineRange.location, fences: fences) {
                storage.addAttributes([.font: style.mono, .wispCodeBlock: true], range: lineRange)
                if isFence, content.length > 0 {
                    storage.addAttribute(.foregroundColor, value: style.syntax, range: content)
                }
                continue
            }
            guard content.length > 0 else { continue }

            if HorizontalRuleLayoutManager.isHorizontalRuleLine(lineRange: lineRange, in: ns) {
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: content)
                continue
            }

            let first = ns.character(at: content.location)
            if first == 0x23,
               let match = headingPattern.firstMatch(in: text, range: content) {
                let hashes = match.range(at: 1)
                storage.addAttributes([
                    .font: style.heading(level: hashes.length),
                    .paragraphStyle: style.headingParagraph,
                ], range: content)
                storage.addAttribute(.foregroundColor, value: style.syntax, range: hashes)
                continue
            }

            if mayBeTask(ns, content) {
                let line = ns.substring(with: content)
                if Checkbox.boxRange(in: line) != nil {
                    styleCheckedItem(content, storage: storage, ns: ns, style: style)
                } else {
                    styleBullet(content, storage: storage, ns: ns, style: style)
                }
            }
        }
    }

    private static func styleBullet(
        _ content: NSRange, storage: NSTextStorage, ns: NSString, style: Style
    ) {
        var i = content.location
        let end = NSMaxRange(content)
        while i < end, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i += 1 }
        guard i + 1 < end, ns.character(at: i + 1) == 0x20 else { return }
        let marker = NSRange(location: i, length: 1)
        storage.addAttributes([.foregroundColor: NSColor.clear,
                               .wispBullet: style.palette.text], range: marker)
        let prefix = ns.substring(with: NSRange(location: content.location, length: i + 2 - content.location))
        let indent = (prefix as NSString).size(withAttributes: [.font: style.base]).width
        let paragraph = (style.body.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        paragraph.headIndent = indent
        storage.addAttribute(.paragraphStyle, value: paragraph, range: content)
    }

    private static func styleCheckedItem(
        _ content: NSRange, storage: NSTextStorage, ns: NSString, style: Style
    ) {
        let line = ns.substring(with: content)
        guard let box = Checkbox.boxRange(in: line) else { return }
        let checked = Checkbox.isChecked(line)
        // The `- [ ]` marker is hidden and drawn as a checkbox; the text
        // wraps under itself, not under the marker.
        var bullet = content.location
        while ns.character(at: bullet) == 0x20 || ns.character(at: bullet) == 0x09 { bullet += 1 }
        let markerEnd = content.location + NSMaxRange(box)
        let marker = NSRange(location: bullet, length: markerEnd - bullet)
        if checked { storage.addAttribute(.foregroundColor, value: style.done, range: content) }
        // The `- [ ] ` stays in the line's font, hidden; the box is drawn
        // over its right end. A ticked `x` is kerned to a space's width so
        // ticked and open tasks line up.
        var spanEnd = NSMaxRange(marker)
        if spanEnd < NSMaxRange(content), ns.character(at: spanEnd) == 0x20 { spanEnd += 1 }
        let markerSpan = NSRange(location: marker.location, length: spanEnd - marker.location)
        storage.addAttributes([.foregroundColor: NSColor.clear,
                               .wispCheckbox: WispCheckboxMark(checked: checked, color: style.palette.text)],
                              range: markerSpan)
        let font = (storage.attribute(.font, at: marker.location, effectiveRange: nil) as? NSFont) ?? style.base
        if checked {
            let extra = ("x" as NSString).size(withAttributes: [.font: font]).width
                - (" " as NSString).size(withAttributes: [.font: font]).width
            storage.addAttribute(.kern, value: -extra, range: NSRange(location: content.location + box.location + 1, length: 1))
        }
        let prefix = ns.substring(with: NSRange(location: content.location, length: spanEnd - content.location))
            .replacingOccurrences(of: "x", with: " ").replacingOccurrences(of: "X", with: " ")
        let paragraph = (style.body.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        paragraph.headIndent = (prefix as NSString).size(withAttributes: [.font: font]).width
        storage.addAttribute(.paragraphStyle, value: paragraph, range: content)
        guard checked else { return }
        var textStart = content.location + NSMaxRange(box)
        while textStart < NSMaxRange(content), ns.character(at: textStart) == 0x20 { textStart += 1 }
        let textLength = NSMaxRange(content) - textStart
        guard textLength > 0 else { return }
        storage.addAttributes([
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .strikethroughColor: style.done,
        ], range: NSRange(location: textStart, length: textLength))
    }

    private static func mayBeTask(_ ns: NSString, _ content: NSRange) -> Bool {
        var i = content.location
        let end = NSMaxRange(content)
        while i < end, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i += 1 }
        guard i < end else { return false }
        let c = ns.character(at: i)
        return c == 0x2D || c == 0x2A || c == 0x2B
    }

    // MARK: Inline

    private static func styleInline(
        in range: NSRange, storage: NSTextStorage, ns: NSString, text: String, style: Style
    ) {
        func inCodeBlock(_ r: NSRange) -> Bool {
            storage.attribute(.wispCodeBlock, at: r.location, effectiveRange: nil) != nil
        }
        func dim(_ location: Int, _ length: Int) {
            storage.addAttribute(
                .foregroundColor, value: style.syntax,
                range: NSRange(location: location, length: length)
            )
        }

        codePattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range, !inCodeBlock(r) else { return }
            storage.addAttributes([.font: style.mono, .backgroundColor: style.codeBackground], range: r)
            dim(r.location, 1)
            dim(NSMaxRange(r) - 1, 1)
        }
        func isCode(_ r: NSRange) -> Bool {
            inCodeBlock(r)
                || storage.attribute(.backgroundColor, at: r.location, effectiveRange: nil) != nil
                || storage.attribute(.backgroundColor, at: NSMaxRange(r) - 1, effectiveRange: nil) != nil
        }

        boldPattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range, !isCode(r) else { return }
            let current = storage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont
            storage.addAttribute(.font, value: style.adding(.bold, to: current), range: r)
            dim(r.location, 2)
            dim(NSMaxRange(r) - 2, 2)
        }
        italicPattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range, !isCode(r) else { return }
            if r.location > 0, ns.character(at: r.location - 1) == 0x2A { return }
            if NSMaxRange(r) < ns.length, ns.character(at: NSMaxRange(r)) == 0x2A { return }
            let current = storage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont
            storage.addAttribute(.font, value: style.adding(.italic, to: current), range: r)
            dim(r.location, 1)
            dim(NSMaxRange(r) - 1, 1)
        }
        linkPattern.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range, !isCode(r),
                  let url = linkURL(ns.substring(with: r)) else { return }
            storage.addAttributes([
                .wispLink: url,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: style.syntax,
            ], range: r)
        }
    }

    static func linkURL(_ text: String) -> URL? {
        if let url = URL(string: text) { return url }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(charactersIn: "#%")
        return text.addingPercentEncoding(withAllowedCharacters: allowed).flatMap(URL.init(string:))
    }

    // MARK: Fences

    static func fenceLineStarts(in ns: NSString) -> [Int] {
        var starts: [Int] = []
        var searchFrom = 0
        while searchFrom < ns.length {
            let hit = ns.range(
                of: "```", options: .literal,
                range: NSRange(location: searchFrom, length: ns.length - searchFrom)
            )
            guard hit.location != NSNotFound else { break }
            let line = ns.lineRange(for: NSRange(location: hit.location, length: 0))
            var i = line.location
            while i < hit.location, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 {
                i += 1
            }
            if i == hit.location { starts.append(line.location) }
            searchFrom = NSMaxRange(line)
        }
        return starts
    }

    private static func isInsideBlock(_ lineStart: Int, fences: [Int]) -> Bool {
        countBelow(fences, lineStart) % 2 == 1
    }

    private static func blocksUnchanged(
        after dirty: NSRange, in storage: NSTextStorage, fences: [Int]
    ) -> Bool {
        let ns = storage.string as NSString
        var location = NSMaxRange(dirty)
        while location < ns.length {
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            if !contains(fences, line.location) {
                let expected = isInsideBlock(line.location, fences: fences)
                let actual = storage.attribute(.wispCodeBlock, at: line.location, effectiveRange: nil) != nil
                return expected == actual
            }
            location = NSMaxRange(line)
        }
        return true
    }

    private static func countBelow(_ sorted: [Int], _ value: Int) -> Int {
        var low = 0, high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid] < value { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private static func contains(_ sorted: [Int], _ value: Int) -> Bool {
        let i = countBelow(sorted, value)
        return i < sorted.count && sorted[i] == value
    }

    // MARK: Fonts and colours for one pass

    @MainActor
    private struct Style {
        let base: NSFont
        let bold: NSFont
        let italic: NSFont
        let mono: NSFont
        let palette: WispPalette
        let syntax: NSColor
        let done: NSColor
        let codeBackground: NSColor
        let body: NSParagraphStyle
        let headingParagraph: NSParagraphStyle

        init(face: FontFace, size: FontSize, theme: WispTheme, transparency: Transparency) {
            base = MinimalTextEditor.makeFont(face: face, size: size.pointSize)
            bold = Self.trait(base, .bold)
            italic = Self.trait(base, .italic)
            mono = NSFont.monospacedSystemFont(ofSize: base.pointSize * 0.92, weight: .regular)
            palette = WispPalette.for(theme)
            syntax = palette.syntax
            done = palette.text.withAlphaComponent(0.4)
            codeBackground = WispPalette.codeBackground(for: theme, transparency: transparency)
            body = MarkdownStyler.bodyParagraph()
            let heading = NSMutableParagraphStyle()
            heading.lineHeightMultiple = MarkdownStyler.lineHeightMultiple
            heading.paragraphSpacingBefore = (base.pointSize * 0.4).rounded()
            headingParagraph = heading
        }

        func heading(level: Int) -> NSFont {
            let scale: CGFloat
            switch level {
            case 1: scale = 1.40
            case 2: scale = 1.20
            case 3: scale = 1.05
            default: scale = 1.0
            }
            let descriptor = base.fontDescriptor.withSymbolicTraits(.bold)
            return NSFont(descriptor: descriptor, size: (base.pointSize * scale).rounded()) ?? bold
        }

        func adding(_ traits: NSFontDescriptor.SymbolicTraits, to current: NSFont?) -> NSFont {
            guard let current, current != base else { return traits == .bold ? bold : italic }
            return Self.trait(current, traits)
        }

        static func trait(_ font: NSFont, _ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
            let merged = font.fontDescriptor.symbolicTraits.union(traits)
            return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(merged), size: font.pointSize) ?? font
        }
    }
}
