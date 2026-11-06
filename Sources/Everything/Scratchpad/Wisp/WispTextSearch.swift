import Foundation

enum TextSearch {
    static func matches(in text: String, query: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let ns = text as NSString
        var result: [NSRange] = []
        var start = 0
        while start <= ns.length {
            let scan = NSRange(location: start, length: ns.length - start)
            let found = ns.range(of: query, options: [.caseInsensitive], range: scan)
            if found.location == NSNotFound { break }
            result.append(found)
            start = found.location + max(found.length, 1)
        }
        return result
    }
}
