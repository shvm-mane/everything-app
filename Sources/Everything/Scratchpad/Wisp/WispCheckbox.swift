import Foundation

enum Checkbox {
    static func boxRange(in line: String) -> NSRange? {
        let ns = line as NSString
        var i = 0
        while i < ns.length, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 {
            i += 1
        }
        guard i < ns.length else { return nil }
        let bullet = ns.character(at: i)
        guard bullet == 0x2D || bullet == 0x2A || bullet == 0x2B else { return nil }
        i += 1
        guard i < ns.length, ns.character(at: i) == 0x20 else { return nil }
        i += 1
        guard i + 2 < ns.length, ns.character(at: i) == 0x5B else { return nil }
        let state = ns.character(at: i + 1)
        guard state == 0x20 || state == 0x78 || state == 0x58 else { return nil }
        guard ns.character(at: i + 2) == 0x5D else { return nil }
        return NSRange(location: i, length: 3)
    }

    static func isChecked(_ line: String) -> Bool {
        guard let box = boxRange(in: line) else { return false }
        let state = (line as NSString).character(at: box.location + 1)
        return state == 0x78 || state == 0x58
    }

    static func toggling(_ line: String) -> String? {
        guard let box = boxRange(in: line) else { return nil }
        let ns = line as NSString
        let replacement = isChecked(line) ? " " : "x"
        return ns.replacingCharacters(
            in: NSRange(location: box.location + 1, length: 1),
            with: replacement
        )
    }
}
