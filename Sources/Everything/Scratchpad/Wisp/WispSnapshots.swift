import Foundation
import AppKit

enum Snapshots {
    static let folderName = "History"
    static let prefix = "scratchpad-"
    static let suffix = ".md"
    static let keep = 30

    static var folder: URL {
        StorageLocation.defaultFolder.appendingPathComponent(folderName)
    }

    private static let queue = DispatchQueue(label: "com.sulemaanhamza.wisp.snapshots")

    // MARK: - Pure helpers (unit-tested)

    static func isDrasticShrink(old: String, new: String) -> Bool {
        let o = old.count
        guard o >= 40 else { return false }
        let n = new.count
        if n == 0 { return true }
        return Double(n) < Double(o) * 0.5
    }

    static func filesToPrune(_ names: [String], keep: Int) -> [String] {
        let snaps = names
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }
            .sorted()
        guard snaps.count > keep else { return [] }
        return Array(snaps.prefix(snaps.count - keep))
    }

    static func filename(at date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss-SSS"
        return "\(prefix)\(f.string(from: date))\(suffix)"
    }

    // MARK: - Disk operations

    static func recordCheckpoint(text: String) {
        guard !text.isEmpty else { return }
        queue.sync { writeIfNew(content: text, now: Date()) }
    }

    static func recordOnSave(old: String, new: String) {
        guard isDrasticShrink(old: old, new: new) else { return }
        queue.sync { writeIfNew(content: old, now: Date()) }
    }

    static func revealInFinder() {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    // MARK: - Internals

    private static func writeIfNew(content: String, now: Date) {
        guard !content.isEmpty else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)

        if let recent = mostRecentSnapshot(),
           let recentContent = try? String(contentsOf: recent, encoding: .utf8),
           recentContent == content {
            return
        }

        try? content.write(to: freeURL(at: now), atomically: true, encoding: .utf8)
        prune()
    }

    private static func freeURL(at now: Date) -> URL {
        let base = filename(at: now)
        var candidate = folder.appendingPathComponent(base)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let stem = String(base.dropLast(suffix.count))
            candidate = folder.appendingPathComponent("\(stem)-\(n)\(suffix)")
            n += 1
        }
        return candidate
    }

    private static func mostRecentSnapshot() -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        guard let latest = names
            .filter({ $0.hasPrefix(prefix) && $0.hasSuffix(suffix) })
            .sorted()
            .last
        else { return nil }
        return folder.appendingPathComponent(latest)
    }

    private static func prune() {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in filesToPrune(names, keep: keep) {
            try? fm.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}
