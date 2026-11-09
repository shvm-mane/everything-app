import AppKit

enum LineEditing {
    struct Edit: Equatable {
        var range: NSRange
        var replacement: String
        var selection: NSRange
    }

    static func lineRange(for selection: NSRange, in ns: NSString) -> NSRange {
        var covered = selection
        if covered.length > 0, NSMaxRange(covered) > 0,
           isLineBreak(ns.character(at: NSMaxRange(covered) - 1)) {
            covered.length -= 1
        }
        return ns.lineRange(for: covered)
    }

    private static func isLineBreak(_ c: unichar) -> Bool {
        c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029
    }

    static func splitTerminator(_ line: String) -> (body: String, terminator: String) {
        let ns = line as NSString
        var end = ns.length
        while end > 0, isLineBreak(ns.character(at: end - 1)) { end -= 1 }
        return (ns.substring(to: end), ns.substring(from: end))
    }

    static func moveLines(in text: String, selection: NSRange, up: Bool) -> Edit? {
        let ns = text as NSString
        let lines = lineRange(for: selection, in: ns)
        if up {
            guard lines.location > 0 else { return nil }
            let above = ns.lineRange(for: NSRange(location: lines.location - 1, length: 0))
            let (moved, other) = swapped(ns.substring(with: lines), ns.substring(with: above))
            return Edit(
                range: NSRange(location: above.location, length: above.length + lines.length),
                replacement: moved + other,
                selection: NSRange(
                    location: above.location + (selection.location - lines.location),
                    length: selection.length
                )
            )
        } else {
            guard NSMaxRange(lines) < ns.length else { return nil }
            let below = ns.lineRange(for: NSRange(location: NSMaxRange(lines), length: 0))
            let (other, moved) = swapped(ns.substring(with: below), ns.substring(with: lines))
            let shift = (other as NSString).length
            let replacement = other + moved
            let end = lines.location + (replacement as NSString).length
            let location = min(lines.location + shift + (selection.location - lines.location), end)
            return Edit(
                range: NSRange(location: lines.location, length: lines.length + below.length),
                replacement: replacement,
                selection: NSRange(location: location, length: min(selection.length, end - location))
            )
        }
    }

    private static func swapped(_ first: String, _ second: String) -> (String, String) {
        let (body, terminator) = splitTerminator(first)
        guard terminator.isEmpty else { return (first, second) }
        let other = splitTerminator(second)
        return (body + other.terminator, other.body)
    }

    static func toggleTask(in text: String, selection: NSRange) -> Edit {
        let ns = text as NSString
        let lines = lineRange(for: selection, in: ns)
        var out: [String] = []
        var firstDelta = 0
        var index = 0
        var location = lines.location
        while location < NSMaxRange(lines) || (index == 0 && lines.length == 0) {
            let line = ns.lineRange(for: NSRange(location: location, length: 0))
            let (content, terminator) = splitTerminator(ns.substring(with: line))
            let toggled = toggleTask(line: content)
            if index == 0 { firstDelta = (toggled as NSString).length - (content as NSString).length }
            out.append(toggled + terminator)
            index += 1
            if line.length == 0 { break }
            location = NSMaxRange(line)
        }
        let replacement = out.joined()
        let selectionOut: NSRange
        if selection.length == 0 {
            let lineStart = lines.location
            let offset = selection.location - lineStart
            let markerEnd = ((replacement as NSString).length > 0)
                ? taskTextStart(in: replacement) : 0
            selectionOut = NSRange(location: lineStart + max(offset + firstDelta, markerEnd), length: 0)
        } else {
            selectionOut = NSRange(location: lines.location, length: (replacement as NSString).length)
        }
        return Edit(range: lines, replacement: replacement, selection: selectionOut)
    }

    static func toggleTask(line: String) -> String {
        if let toggled = Checkbox.toggling(line) { return toggled }
        let ns = line as NSString
        let indentEnd = leadingWhitespace(ns)
        let indent = ns.substring(to: indentEnd)
        let rest = ns.substring(from: indentEnd)
        if let first = rest.first, "-*+".contains(first),
           rest.dropFirst().first == " " || rest.dropFirst().first == "\t" {
            let text = rest.dropFirst(2).drop { $0 == " " || $0 == "\t" }
            return indent + String(first) + " [ ] " + text
        }
        return indent + "- [ ] " + rest
    }

    private static func taskTextStart(in text: String) -> Int {
        let ns = text as NSString
        let firstLine = splitTerminator(ns.substring(with: ns.lineRange(for: NSRange(location: 0, length: 0)))).body
        guard let box = Checkbox.boxRange(in: firstLine) else { return 0 }
        return min(NSMaxRange(box) + 1, (firstLine as NSString).length)
    }

    private static func leadingWhitespace(_ ns: NSString) -> Int {
        var i = 0
        while i < ns.length, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i += 1 }
        return i
    }

    static func dateStamp(_ date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd-MM-yyyy"
        return formatter.string(from: date)
    }

    static func replacing(_ range: NSRange, with replacement: String, keeping selection: NSRange) -> Edit {
        let delta = (replacement as NSString).length - range.length
        func moved(_ location: Int) -> Int {
            guard location > range.location else { return location }
            if location >= NSMaxRange(range) { return location + delta }
            return min(max(range.location, location + delta), range.location + (replacement as NSString).length)
        }
        let start = moved(selection.location)
        let end = moved(NSMaxRange(selection))
        return Edit(range: range, replacement: replacement, selection: NSRange(location: start, length: max(0, end - start)))
    }

    @MainActor
    static func apply(_ edit: Edit, to textView: NSTextView, scroll: Bool = true) {
        guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textView.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        textView.setSelectedRange(edit.selection)
        textView.didChangeText()
        if scroll { textView.scrollRangeToVisible(edit.selection) }
    }
}
