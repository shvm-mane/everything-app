import Foundation

enum SmartEditing {
    static let horizontalRule = "---"

    static func isHorizontalRuleTrigger(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "---"
    }

    static func nextListMarker(for line: String) -> String? {
        if let match = line.firstMatch(of: /^([-*+])\s\[[ xX]\]\s?/) {
            if isEmptyAfter(match.range, in: line) { return "" }
            return "\(match.1) [ ] "
        }
        if let match = line.firstMatch(of: /^([-*+])\s/) {
            let bullet = String(match.1)
            if isEmptyAfter(match.range, in: line) { return "" }
            return "\(bullet) "
        }
        if let match = line.firstMatch(of: /^(\d+)\.\s/) {
            let n = Int(match.1) ?? 0
            if isEmptyAfter(match.range, in: line) { return "" }
            return "\(n + 1). "
        }
        if let match = line.firstMatch(of: /^([A-Z])\.\s/) {
            if isEmptyAfter(match.range, in: line) { return "" }
            let c = Character(String(match.1))
            guard c < "Z", let ascii = c.asciiValue else { return nil }
            return "\(Character(UnicodeScalar(ascii + 1))). "
        }
        if let match = line.firstMatch(of: /^([a-z])\.\s/) {
            if isEmptyAfter(match.range, in: line) { return "" }
            let c = Character(String(match.1))
            guard c < "z", let ascii = c.asciiValue else { return nil }
            return "\(Character(UnicodeScalar(ascii + 1))). "
        }
        return nil
    }

    private static func isEmptyAfter(_ range: Range<String.Index>, in line: String) -> Bool {
        line[range.upperBound...].trimmingCharacters(in: .whitespaces).isEmpty
    }
}
