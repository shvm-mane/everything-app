import Foundation

/// Pure, case-insensitive literal substring search. Returns every match
/// as an NSRange (UTF-16 offsets) so the results line up directly with
/// NSTextView's range API. No regex, no word-boundary, no replace —
/// deliberately minimal.
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
            // Advance past this match; max(.,1) guards against a zero-
            // length match looping forever (can't happen with a non-empty
            // query, but cheap insurance).
            start = found.location + max(found.length, 1)
        }
        return result
    }
}
