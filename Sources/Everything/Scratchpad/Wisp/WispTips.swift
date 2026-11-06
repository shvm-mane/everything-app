import Foundation

struct Tip: Identifiable, Equatable {
    let version: String
    let keys: String

    var id: String { keys + version }
}

enum Tips {
    static let seenKey = "wisp.SeenTipsVersion"

    static let all: [Tip] = [
        Tip(version: "0.1.46", keys: "Remind me in 10 minutes …"),
        Tip(version: "0.1.46", keys: "Remind me Friday at 3pm …"),
        Tip(version: "0.1.45", keys: "12 × 3 + 4 ="),
        Tip(version: "0.1.45", keys: "5 km in mi ="),
        Tip(version: "0.1.45", keys: "20% of 150 ="),
        Tip(version: "0.1.45", keys: "$12 × 3 ="),
        Tip(version: "0.1.45", keys: "⇧⌘D"),
        Tip(version: "0.1.44", keys: "⌘L"),
        Tip(version: "0.1.44", keys: "⌥↑ ⌥↓"),
        Tip(version: "0.1.44", keys: "⌘-click"),
        Tip(version: "0.1.44", keys: "⌘- ⌘= ⌘0"),
        Tip(version: "0.1.44", keys: "Font"),
        Tip(version: "0.1.42", keys: "- [ ]"),
        Tip(version: "0.1.42", keys: "⇧⌘↩"),
        Tip(version: "0.1.41", keys: "⌘F"),
        Tip(version: "0.1.42", keys: "`code` ```"),
        Tip(version: "0.1.42", keys: "wisp.Transparency"),
        Tip(version: "0.1.42", keys: "Reveal in Finder"),
    ]

    static var version: String {
        all.map(\.version).max(by: isOlder) ?? "0"
    }

    static func unseen(since seen: String?, limit: Int = .max) -> [Tip] {
        guard let seen else { return Array(all.prefix(limit)) }
        return Array(all.filter { isOlder(seen, $0.version) }.prefix(limit))
    }

    static func isOlder(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedAscending
    }
}
