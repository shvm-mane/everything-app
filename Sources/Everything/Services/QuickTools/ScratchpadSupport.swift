// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ScratchpadRetention: String, CaseIterable {
    case never
    case day
    case week
    case month

    var maxIdleInterval: TimeInterval? {
        switch self {
        case .never: return nil
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        }
    }

    static func sanitized(_ rawValue: String?) -> ScratchpadRetention {
        guard let rawValue,
              let retention = ScratchpadRetention(rawValue: rawValue) else {
            return .never
        }
        return retention
    }
}

struct ScratchpadMarkdownBlock: Equatable {
    enum Kind: Equatable {
        case paragraph
        case heading(Int)
        case unorderedListItem(depth: Int)
        case taskListItem(depth: Int, checked: Bool, box: Int)
        case orderedListItem(ordinal: Int, depth: Int)
        case quote(depth: Int)
        case code
        case thematicBreak
    }

    let kind: Kind
    let containerID: Int?
    let text: AttributedString
    var quoteDepth = 0
}

struct ScratchpadPad: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var text: String
    var modifiedAt: Date?
}

struct ScratchpadDocument: Codable, Equatable {
    static let maximumPadCount = 12
    static let maximumNameLength = 40

    var pads: [ScratchpadPad]
    var selectedID: UUID

    static func initial(defaultName: String,
                        id: UUID = UUID(),
                        text: String = "",
                        modifiedAt: Date? = nil) -> ScratchpadDocument {
        let name = ScratchpadSupport.nextPadName(defaultName: defaultName, existingNames: [])
        let pad = ScratchpadPad(id: id,
                                name: name,
                                text: text,
                                modifiedAt: text.isEmpty ? nil : modifiedAt)
        return ScratchpadDocument(pads: [pad], selectedID: pad.id)
    }

    static func decoded(_ data: Data?, defaultName: String) -> ScratchpadDocument? {
        guard let data,
              let decoded = try? JSONDecoder().decode(ScratchpadDocument.self, from: data)
        else { return nil }
        return decoded.sanitized(defaultName: defaultName)
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    func sanitized(defaultName: String) -> ScratchpadDocument {
        var seen = Set<UUID>()
        var cleanPads: [ScratchpadPad] = []
        for pad in pads.prefix(Self.maximumPadCount) where seen.insert(pad.id).inserted {
            let fallback = ScratchpadSupport.nextPadName(defaultName: defaultName,
                                                         existingNames: cleanPads.map(\.name))
            let name = ScratchpadSupport.sanitizedPadName(pad.name)
            cleanPads.append(ScratchpadPad(id: pad.id,
                                           name: name.isEmpty ? fallback : name,
                                           text: pad.text,
                                           modifiedAt: pad.text.isEmpty ? nil : pad.modifiedAt))
        }
        guard !cleanPads.isEmpty else { return .initial(defaultName: defaultName) }
        let selection = cleanPads.contains(where: { $0.id == selectedID })
            ? selectedID : cleanPads[0].id
        return ScratchpadDocument(pads: cleanPads, selectedID: selection)
    }

    func addingPad(defaultName: String, id: UUID = UUID()) -> ScratchpadDocument? {
        guard pads.count < Self.maximumPadCount else { return nil }
        var next = self
        let name = ScratchpadSupport.nextPadName(defaultName: defaultName,
                                                 existingNames: pads.map(\.name))
        next.pads.append(ScratchpadPad(id: id, name: name, text: "", modifiedAt: nil))
        next.selectedID = id
        return next
    }

    func selecting(_ id: UUID) -> ScratchpadDocument? {
        guard pads.contains(where: { $0.id == id }) else { return nil }
        var next = self
        next.selectedID = id
        return next
    }

    func renaming(_ id: UUID, to proposedName: String) -> ScratchpadDocument? {
        let name = ScratchpadSupport.sanitizedPadName(proposedName)
        guard !name.isEmpty, let index = pads.firstIndex(where: { $0.id == id }) else { return nil }
        var next = self
        next.pads[index].name = name
        return next
    }

    func removing(_ id: UUID) -> ScratchpadDocument? {
        guard pads.count > 1, let index = pads.firstIndex(where: { $0.id == id }) else { return nil }
        var next = self
        next.pads.remove(at: index)
        if selectedID == id {
            next.selectedID = next.pads[min(index, next.pads.count - 1)].id
        }
        return next
    }

    mutating func updateSelectedText(_ text: String, modifiedAt: Date) {
        guard let index = pads.firstIndex(where: { $0.id == selectedID }),
              pads[index].text != text else { return }
        pads[index].text = text
        pads[index].modifiedAt = text.isEmpty ? nil : modifiedAt
    }

    mutating func applyRetention(_ retention: ScratchpadRetention, now: Date) {
        for index in pads.indices where ScratchpadSupport.shouldClear(
            lastEdited: pads[index].modifiedAt, now: now, retention: retention
        ) {
            pads[index].text = ""
            pads[index].modifiedAt = nil
        }
    }
}

enum ScratchpadFocusedShortcut {
    enum Action: Equatable {
        case createPad
        case closeSelectedPad
        case hidePad
        case find
        case findNext
        case findPrevious
    }

    static func action(charactersIgnoringModifiers: String?,
                       commandOnly: Bool,
                       shift: Bool = false,
                       canCreatePad: Bool,
                       canClosePad: Bool) -> Action? {
        guard commandOnly else { return nil }
        switch charactersIgnoringModifiers?.lowercased() {
        case "g":
            return shift ? .findPrevious : .findNext
        case _ where shift:
            return nil
        case "t":
            return canCreatePad ? .createPad : nil
        case "w":
            return canClosePad ? .closeSelectedPad : .hidePad
        case "f":
            return .find
        default:
            return nil
        }
    }
}

enum ScratchpadSupport {
    static let backgroundOpacityRange: ClosedRange<Double> = 0...1

    static let defaultTextSize: Double = 13
    static let textSizeRange: ClosedRange<Double> = 10...22

    static func sanitizedTextSize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultTextSize }
        return min(max(value.rounded(), textSizeRange.lowerBound), textSizeRange.upperBound)
    }

    static func sanitizedBackgroundOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return backgroundOpacityRange.upperBound }
        return min(max(value, backgroundOpacityRange.lowerBound), backgroundOpacityRange.upperBound)
    }

    static func dismissesOnOutsideClick(isPinned: Bool, exportModalActive: Bool) -> Bool {
        !isPinned && !exportModalActive
    }

    static func markdownPreview(_ text: String) -> [ScratchpadMarkdownBlock] {
        guard !text.isEmpty else { return [] }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible,
            appliesSourcePositionAttributes: true)
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return [ScratchpadMarkdownBlock(kind: .paragraph,
                                            containerID: nil,
                                            text: AttributedString(text))]
        }

        var blocks: [ScratchpadMarkdownBlock] = []
        var currentID: Int?
        var currentKind = ScratchpadMarkdownBlock.Kind.paragraph
        var currentContainerID: Int?
        var currentQuoteDepth = 0
        var currentText = AttributedString()

        func finishBlock() {
            guard currentID != nil else { return }
            if currentKind == .code {
                while currentText.characters.last?.isNewline == true {
                    currentText.characters.removeLast()
                }
            }
            blocks.append(ScratchpadMarkdownBlock(kind: currentKind,
                                                  containerID: currentContainerID,
                                                  text: currentText,
                                                  quoteDepth: currentQuoteDepth))
            currentText = AttributedString()
        }

        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let blockID = components.first?.identity ?? 0
            if blockID != currentID {
                finishBlock()
                currentID = blockID
                let presentation = markdownBlockPresentation(components)
                currentKind = presentation.kind
                currentContainerID = presentation.containerID
                currentQuoteDepth = presentation.quoteDepth
            }
            currentText.append(AttributedString(parsed[run.range]))
        }
        finishBlock()
        let lineStarts = lineStarts(in: text)
        blocks = blocks.map { withTask($0, in: text, lineStarts: lineStarts) }

        return blocks.isEmpty
            ? [ScratchpadMarkdownBlock(kind: .paragraph,
                                       containerID: nil,
                                       text: AttributedString(text))]
            : blocks
    }

    private static func taskMarker(in text: String) -> (checked: Bool, length: Int)? {
        let characters = Array(text.prefix(4))
        func closes(_ at: Int) -> Bool { characters.count == at || characters[at] == " " || characters[at] == "\t" }
        guard characters.first == "[" else { return nil }
        if characters.count > 1, characters[1] == "]", closes(2) { return (false, 2) }
        if characters.count > 2, characters[2] == "]", closes(3) {
            if characters[1] == " " { return (false, 3) }
            if characters[1] == "x" || characters[1] == "X" { return (true, 3) }
        }
        return nil
    }

    private static func withTask(_ block: ScratchpadMarkdownBlock, in source: String,
                                 lineStarts: [String.Index]) -> ScratchpadMarkdownBlock {
        var text = block.text
        let first = text.runs.first
        text.markdownSourcePosition = nil
        let plain = ScratchpadMarkdownBlock(kind: block.kind, containerID: block.containerID, text: text,
                                            quoteDepth: block.quoteDepth)
        guard case .unorderedListItem(let depth) = block.kind,
              let first, first.inlinePresentationIntent == nil, first.link == nil,
              let position = first.markdownSourcePosition,
              position.startLine >= 1, position.startLine <= lineStarts.count, position.startColumn >= 1,
              let start = source.utf8.index(lineStarts[position.startLine - 1],
                                            offsetBy: position.startColumn - 1,
                                            limitedBy: source.utf8.endIndex),
              let marker = taskMarker(in: String(text.characters))
        else { return plain }
        let run = String(block.text[first.range].characters)
        guard run.hasPrefix(source[start...].prefix(run.count).prefix { !"\\&\u{0}".contains($0) })
        else { return plain }
        let box = NSRange(start..<start, in: source).location
        guard let written = taskBox(at: box, in: source),
              written.checked == marker.checked, written.length == marker.length else { return plain }
        let opening = text.characters.startIndex
        var end = text.characters.index(opening, offsetBy: marker.length)
        if end < text.characters.endIndex, text.characters[end] == " " || text.characters[end] == "\t" {
            end = text.characters.index(after: end)
        }
        text.removeSubrange(opening..<end)
        return ScratchpadMarkdownBlock(kind: .taskListItem(depth: depth, checked: marker.checked, box: box),
                                       containerID: block.containerID, text: text, quoteDepth: block.quoteDepth)
    }

    private static func lineStarts(in text: String) -> [String.Index] {
        let bytes = text.utf8
        var starts = [bytes.startIndex]
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            index = bytes.index(after: index)
            guard byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") else { continue }
            if byte == UInt8(ascii: "\r"), index < bytes.endIndex, bytes[index] == UInt8(ascii: "\n") {
                index = bytes.index(after: index)
            }
            starts.append(index)
        }
        return starts
    }

    private static func taskBox(at box: Int, in text: String) -> (checked: Bool, length: Int)? {
        let text = text as NSString
        func character(_ offset: Int) -> String? {
            box + offset < text.length ? text.substring(with: NSRange(location: box + offset, length: 1)) : nil
        }
        guard box >= 0, character(0) == "[" else { return nil }
        if character(1) == "]" { return (false, 2) }
        guard let mark = character(1), [" ", "x", "X"].contains(mark), character(2) == "]" else { return nil }
        return (mark != " ", 3)
    }

    static let taskScheme = "vorssaint-task"

    static func taskToggleEdit(box: Int, in text: String) -> (range: NSRange, replacement: String)? {
        guard let current = taskBox(at: box, in: text) else { return nil }
        if current.length == 2 { return (NSRange(location: box + 1, length: 0), "x") }
        return (NSRange(location: box + 1, length: 1), current.checked ? " " : "x")
    }

    private static let listMarker = try? NSRegularExpression(
        pattern: #"^([ \t]*(?:>[ \t]*)*)([-*+]|\d+[.)])([ \t]+)(\[[ xX]?\](?:[ \t]+|$))?"#)

    static func lineBreakEdit(in text: String, selection: NSRange) -> (range: NSRange, replacement: String, caret: Int) {
        let plain = (range: selection, replacement: "\n", caret: selection.location + 1)
        let whole = text as NSString
        guard selection.length == 0, selection.location <= whole.length, let listMarker else { return plain }
        let line = whole.lineRange(for: NSRange(location: selection.location, length: 0))
        var content = line
        while content.length > 0, "\n\r".contains(whole.substring(with: NSRange(location: NSMaxRange(content) - 1, length: 1))) {
            content.length -= 1
        }
        let lineText = whole.substring(with: content)
        guard let match = listMarker.firstMatch(in: lineText, range: NSRange(location: 0, length: (lineText as NSString).length))
        else { return plain }
        let markerEnd = content.location + match.range.length
        guard selection.location >= markerEnd else { return plain }
        let lineNS = lineText as NSString
        let prefix = lineNS.substring(with: match.range(at: 1))
        let marker = lineNS.substring(with: match.range(at: 2))
        let spacing = lineNS.substring(with: match.range(at: 3))
        let hasBox = match.range(at: 4).location != NSNotFound
        if selection.location == NSMaxRange(content), match.range.length == lineNS.length || lineNS.substring(from: match.range.length).trimmingCharacters(in: .whitespaces).isEmpty {
            return (content, "", content.location)
        }
        var next = marker
        if let digits = Int(marker.dropLast()), digits < Int.max, let delimiter = marker.last {
            next = "\(digits + 1)\(delimiter)"
        }
        let replacement = "\n" + prefix + next + spacing + (hasBox ? "[ ] " : "")
        return (selection, replacement, selection.location + (replacement as NSString).length)
    }

    static func completesEmptyTaskBox(before: String) -> Bool {
        guard before.hasSuffix("["), let marker = taskLine else { return false }
        let box = before + " ]"
        return marker.firstMatch(in: box, range: NSRange(box.startIndex..., in: box)) != nil
    }

    private static let taskLine = try? NSRegularExpression(pattern: #"^[\s>]*[-*+][ \t]+\[( |x|X)?\]([ \t]|$)"#)

    private static func markdownBlockPresentation(
        _ components: [PresentationIntent.IntentType]
    ) -> (kind: ScratchpadMarkdownBlock.Kind, containerID: Int?, quoteDepth: Int) {
        var listDepth = 0
        var listIsOrdered: Bool?
        var listOrdinal = 1
        var quoteDepth = 0
        var listQuoteDepth = 0
        var containerID: Int?

        for component in components {
            switch component.kind {
            case .header(let level):
                return (.heading(level), nil, 0)
            case .codeBlock:
                return (.code, nil, 0)
            case .thematicBreak:
                return (.thematicBreak, nil, 0)
            case .listItem(let ordinal):
                if listDepth == 0 { listOrdinal = ordinal }
            case .orderedList:
                listDepth += 1
                if listIsOrdered == nil { listIsOrdered = true }
                containerID = component.identity
            case .unorderedList:
                listDepth += 1
                if listIsOrdered == nil { listIsOrdered = false }
                containerID = component.identity
            case .blockQuote:
                quoteDepth += 1
                if listDepth > 0 { listQuoteDepth += 1 }
                containerID = component.identity
            case .paragraph, .table, .tableHeaderRow, .tableRow, .tableCell:
                break
            @unknown default:
                break
            }
        }

        if listIsOrdered == true {
            return (.orderedListItem(ordinal: listOrdinal, depth: max(1, listDepth)), containerID, listQuoteDepth)
        }
        if listIsOrdered == false {
            return (.unorderedListItem(depth: max(1, listDepth)), containerID, listQuoteDepth)
        }
        if quoteDepth > 0 { return (.quote(depth: quoteDepth), containerID, 0) }
        return (.paragraph, nil, 0)
    }

    static func sanitizedPadName(_ name: String) -> String {
        let words = name.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return String(words.joined(separator: " ").prefix(ScratchpadDocument.maximumNameLength))
    }

    static func nextPadName(defaultName: String, existingNames: [String]) -> String {
        let base = sanitizedPadName(defaultName)
        let safeBase = base.isEmpty ? "Scratchpad" : base
        let used = Set(existingNames)
        let firstName = "\(safeBase) 1"
        guard used.contains(safeBase) || used.contains(firstName) else { return firstName }
        for number in 2...ScratchpadDocument.maximumPadCount where !used.contains("\(safeBase) \(number)") {
            return "\(safeBase) \(number)"
        }
        return "\(safeBase) \(existingNames.count + 1)"
    }

    static func requiresCloseConfirmation(_ pad: ScratchpadPad) -> Bool {
        !pad.text.isEmpty
    }

    static func shouldClear(lastEdited: Date?, now: Date, retention: ScratchpadRetention) -> Bool {
        guard let limit = retention.maxIdleInterval, let lastEdited else { return false }
        let idle = now.timeIntervalSince(lastEdited)
        return idle > limit
    }

    static func exportFileName(title: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let safeTitle = sanitizedPadName(title)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "\(safeTitle) \(formatter.string(from: date)).txt"
    }
}

enum ScratchpadMark: String, CaseIterable {
    case bold, italic, strikethrough, heading, bullet
    case numbered, quote, code, link

    var wrap: String? {
        switch self {
        case .bold: return "**"
        case .italic: return "*"
        case .strikethrough: return "~~"
        case .code: return "`"
        case .heading, .bullet, .numbered, .quote, .link: return nil
        }
    }

    var lineCycle: [String] {
        switch self {
        case .heading: return ["# ", "## ", "### "]
        case .bullet: return ["- "]
        case .numbered: return ["1. "]
        case .quote: return ["> "]
        case .bold, .italic, .strikethrough, .code, .link: return []
        }
    }

    var isNumbered: Bool { self == .numbered }

    var glyph: String? { self == .heading ? "H" : nil }

    var symbol: String {
        switch self {
        case .bold: return "bold"
        case .italic: return "italic"
        case .strikethrough: return "strikethrough"
        case .heading: return "textformat.size"
        case .bullet: return "list.bullet"
        case .numbered: return "list.number"
        case .quote: return "text.quote"
        case .code: return "chevron.left.slash.chevron.right"
        case .link: return "link"
        }
    }
}

struct ScratchpadMarkEdit: Equatable {
    let range: NSRange
    let replacement: String
    let selection: NSRange
}

extension ScratchpadSupport {
    static func edit(applying mark: ScratchpadMark,
                     to text: String,
                     selection: NSRange) -> ScratchpadMarkEdit {
        let ns = text as NSString
        let location = min(max(selection.location, 0), ns.length)
        let length = min(max(selection.length, 0), ns.length - location)
        var safe = NSRange(location: location, length: length)
        if mark == .link {
            return linkEdit(in: ns, selection: safe)
        }
        if mark.wrap != nil {
            safe = trimmingSpace(from: safe, in: ns)
        }
        if mark == .italic {
            return italicEdit(in: ns, selection: safe)
        }
        if let wrap = mark.wrap {
            return inlineEdit(wrap: wrap, in: ns, selection: safe)
        }
        return linePrefixEdit(mark: mark, in: ns, selection: safe)
    }

    private static func trimmingSpace(from selection: NSRange, in ns: NSString) -> NSRange {
        func isSpace(_ unit: unichar) -> Bool {
            UnicodeScalar(unit).map(CharacterSet.whitespacesAndNewlines.contains) ?? false
        }
        var start = selection.location
        var end = selection.location + selection.length
        while start < end, isSpace(ns.character(at: start)) { start += 1 }
        while end > start, isSpace(ns.character(at: end - 1)) { end -= 1 }
        return start == end ? selection : NSRange(location: start, length: end - start)
    }

    static let linkPlaceholder = "url"

    private static func linkEdit(in ns: NSString, selection: NSRange) -> ScratchpadMarkEdit {
        if let existing = enclosingLink(in: ns, selection: selection) {
            if existing.isImage {
                return ScratchpadMarkEdit(range: selection,
                                          replacement: ns.substring(with: selection),
                                          selection: selection)
            }
            let label = ns.substring(with: existing.label)
            return ScratchpadMarkEdit(
                range: existing.whole,
                replacement: label,
                selection: NSRange(location: existing.whole.location,
                                   length: (label as NSString).length))
        }
        let selected = ns.substring(with: selection)
        let opening = (selected as NSString).length + 3
        return ScratchpadMarkEdit(
            range: selection,
            replacement: "[\(selected)](\(linkPlaceholder))",
            selection: NSRange(location: selection.location + opening,
                               length: (linkPlaceholder as NSString).length))
    }

    private static func enclosingLink(in ns: NSString,
                                      selection: NSRange) -> (whole: NSRange, label: NSRange, isImage: Bool)? {
        var start = 0
        while start < ns.length {
            defer { start += 1 }
            guard ns.character(at: start) == 91, !isEscaped(start, in: ns) else { continue }
            var labelEnd = start + 1
            var brackets = 1
            while labelEnd < ns.length, brackets > 0 {
                if !isEscaped(labelEnd, in: ns) {
                    if ns.character(at: labelEnd) == 91 { brackets += 1 }
                    if ns.character(at: labelEnd) == 93 { brackets -= 1 }
                }
                labelEnd += 1
            }
            guard brackets == 0, labelEnd < ns.length,
                  ns.character(at: labelEnd) == 40 else { continue }
            var end = labelEnd + 1
            var parentheses = 1
            while end < ns.length, parentheses > 0 {
                if !isEscaped(end, in: ns) {
                    if ns.character(at: end) == 40 { parentheses += 1 }
                    if ns.character(at: end) == 41 { parentheses -= 1 }
                }
                end += 1
            }
            guard parentheses == 0 else { continue }
            let whole = NSRange(location: start, length: end - start)
            if selection.length == 0 {
                guard selection.location > whole.location, selection.location < end else { continue }
            } else {
                guard selection.location >= whole.location,
                      selection.location + selection.length <= end else { continue }
            }
            let isImage = start > 0 && ns.character(at: start - 1) == 33
                && !isEscaped(start - 1, in: ns)
            return (whole, NSRange(location: start + 1, length: labelEnd - start - 2), isImage)
        }
        return nil
    }

    private static func isEscaped(_ index: Int, in ns: NSString) -> Bool {
        var cursor = index
        while cursor > 0, ns.character(at: cursor - 1) == 92 { cursor -= 1 }
        return (index - cursor) % 2 == 1
    }

    private static func inlineEdit(wrap: String,
                                   in ns: NSString,
                                   selection: NSRange) -> ScratchpadMarkEdit {
        let markerLength = (wrap as NSString).length
        let selected = ns.substring(with: selection)

        if selected.count >= wrap.count * 2,
           selected.hasPrefix(wrap), selected.hasSuffix(wrap) {
            let inner = String(selected.dropFirst(wrap.count).dropLast(wrap.count))
            return existingInlineEdit(wrap: wrap, inner: inner,
                                      whole: selection, selection: selection)
        }

        let before = NSRange(location: selection.location - markerLength, length: markerLength)
        let after = NSRange(location: selection.location + selection.length, length: markerLength)
        if before.location >= 0,
           after.location + after.length <= ns.length,
           ns.substring(with: before) == wrap,
           ns.substring(with: after) == wrap {
            return existingInlineEdit(
                wrap: wrap, inner: selected,
                whole: NSRange(location: before.location,
                               length: markerLength * 2 + selection.length),
                selection: selection)
        }

        return ScratchpadMarkEdit(
            range: selection,
            replacement: wrap + selected + wrap,
            selection: NSRange(location: selection.location + markerLength,
                               length: selection.length))
    }

    private static func existingInlineEdit(wrap: String, inner: String,
                                           whole: NSRange, selection: NSRange) -> ScratchpadMarkEdit {
        let pieces = inner.components(separatedBy: wrap)
        if pieces.count == 1 {
            return ScratchpadMarkEdit(
                range: whole, replacement: inner,
                selection: NSRange(location: whole.location, length: (inner as NSString).length))
        }
        let original = wrap + inner + wrap
        let hasOtherMarkup = wrap == "`"
            ? inner.hasPrefix("`") || inner.hasSuffix("`")
            : inner.contains("`") || inner.contains("](")
        guard (pieces.count - 1).isMultiple(of: 2),
              !inner.contains("\\" + wrap), !hasOtherMarkup else {
            return ScratchpadMarkEdit(range: whole, replacement: original, selection: selection)
        }
        let joined = pieces.joined()
        return ScratchpadMarkEdit(
            range: whole, replacement: wrap + joined + wrap,
            selection: NSRange(location: whole.location + (wrap as NSString).length,
                               length: (joined as NSString).length))
    }

    private static func italicEdit(in ns: NSString, selection: NSRange) -> ScratchpadMarkEdit {
        let selected = ns.substring(with: selection)
        let leading = selected.prefix(while: { $0 == "*" }).count
        let trailing = selected.reversed().prefix(while: { $0 == "*" }).count

        if leading % 2 == 1, trailing % 2 == 1, selected.count > leading + trailing - 1 {
            let inner = String(selected.dropFirst().dropLast())
            if leading == 1, trailing == 1, inner.contains("*"), !inner.contains("**") {
                return existingInlineEdit(wrap: "*", inner: inner,
                                          whole: selection, selection: selection)
            }
            if inner.contains("***") {
                return ScratchpadMarkEdit(range: selection, replacement: selected, selection: selection)
            }
            return ScratchpadMarkEdit(
                range: selection,
                replacement: inner,
                selection: NSRange(location: selection.location,
                                   length: (inner as NSString).length))
        }

        if starRun(in: ns, endingAt: selection.location) % 2 == 1,
           starRun(in: ns, startingAt: selection.location + selection.length) % 2 == 1 {
            let outer = NSRange(location: selection.location - 1, length: selection.length + 2)
            if starRun(in: ns, endingAt: selection.location) == 1,
               starRun(in: ns, startingAt: selection.location + selection.length) == 1,
               selected.contains("*"), !selected.contains("**") {
                return existingInlineEdit(wrap: "*", inner: selected,
                                          whole: outer, selection: selection)
            }
            if selected.contains("***") {
                return ScratchpadMarkEdit(range: outer,
                                          replacement: ns.substring(with: outer),
                                          selection: selection)
            }
            return ScratchpadMarkEdit(
                range: outer,
                replacement: selected,
                selection: NSRange(location: outer.location, length: selection.length))
        }

        return ScratchpadMarkEdit(
            range: selection,
            replacement: "*" + selected + "*",
            selection: NSRange(location: selection.location + 1, length: selection.length))
    }

    private static func starRun(in ns: NSString, endingAt index: Int) -> Int {
        var count = 0
        var cursor = index - 1
        while cursor >= 0, ns.substring(with: NSRange(location: cursor, length: 1)) == "*" {
            count += 1
            cursor -= 1
        }
        return count
    }

    private static func starRun(in ns: NSString, startingAt index: Int) -> Int {
        var count = 0
        var cursor = index
        while cursor < ns.length, ns.substring(with: NSRange(location: cursor, length: 1)) == "*" {
            count += 1
            cursor += 1
        }
        return count
    }

    private static func linePrefixEdit(mark: ScratchpadMark,
                                       in ns: NSString,
                                       selection: NSRange) -> ScratchpadMarkEdit {
        let cycle = mark.lineCycle
        guard !cycle.isEmpty else {
            return ScratchpadMarkEdit(range: selection, replacement: "", selection: selection)
        }
        let lineRange = ns.lineRange(for: selection)
        let block = ns.substring(with: lineRange)
        let terminator = block.hasSuffix("\n") ? "\n" : ""
        let body = terminator.isEmpty ? block : String(block.dropLast())
        let lines = body.components(separatedBy: "\n")

        func indent(of line: String) -> Substring { line.prefix(while: { $0 == " " || $0 == "\t" }) }
        let written = lines.map { String($0.dropFirst(indent(of: $0).count)) }.filter { !$0.isEmpty }
        let step: Int?
        if mark.isNumbered {
            step = !written.isEmpty && written.allSatisfy { numberedPrefix(of: $0) != nil } ? 0 : nil
        } else {
            step = cycle.firstIndex { prefix in
                !written.isEmpty && written.allSatisfy { $0.hasPrefix(prefix) }
            }
        }
        let next = step.map { $0 + 1 < cycle.count ? cycle[$0 + 1] : "" } ?? cycle[0]
        var ordinal = 0
        let updated: [String] = lines.map { line in
            let lead = String(indent(of: line))
            let rest = String(line.dropFirst(lead.count))
            if rest.isEmpty, lines.count > 1 { return line }
            let body = strippingLineMark(from: rest)
            guard !next.isEmpty else { return lead + body }
            guard mark.isNumbered else { return lead + next + body }
            ordinal += 1
            return lead + "\(ordinal). " + body
        }

        let replacement = updated.joined(separator: "\n") + terminator
        let firstDelta = (updated[0] as NSString).length - (lines[0] as NSString).length
        let totalDelta = (replacement as NSString).length - (block as NSString).length
        let start = max(lineRange.location, selection.location + firstDelta)
        let end = max(start, selection.location + selection.length + totalDelta)
        return ScratchpadMarkEdit(
            range: lineRange,
            replacement: replacement,
            selection: NSRange(location: start, length: end - start))
    }

    private static func strippingLineMark(from line: String) -> String {
        let hashes = line.prefix(while: { $0 == "#" })
        if !hashes.isEmpty, hashes.count <= 6, line.dropFirst(hashes.count).hasPrefix(" ") {
            return String(line.dropFirst(hashes.count + 1))
        }
        if let first = line.first, "-*+>".contains(first), line.dropFirst().hasPrefix(" ") {
            return String(line.dropFirst(2))
        }
        if let numbered = numberedPrefix(of: line) {
            return String(line.dropFirst(numbered.count))
        }
        return line
    }

    private static func numberedPrefix(of line: String) -> String? {
        let digits = line.prefix(while: { $0.isNumber })
        guard !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        return String(line.prefix(digits.count + 2))
    }
}
