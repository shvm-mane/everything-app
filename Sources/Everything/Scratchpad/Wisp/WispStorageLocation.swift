import Foundation

enum StorageLocation {
    static let folderKey = "wisp.ScratchpadFolder"
    static let scratchpadFilename = "scratchpad.md"
    static let backupPrefix = "scratchpad-local-backup-"

    static var defaultFolder: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Everything").appendingPathComponent("Scratchpad")
    }

    static var currentFolder: URL {
        if let path = UserDefaults.standard.string(forKey: folderKey),
           !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return defaultFolder
    }

    static var currentURL: URL {
        scratchpadURL(in: currentFolder)
    }

    static var isCustom: Bool {
        guard let path = UserDefaults.standard.string(forKey: folderKey) else {
            return false
        }
        return !path.isEmpty
    }

    static func scratchpadURL(in folder: URL) -> URL {
        folder.appendingPathComponent(scratchpadFilename)
    }

    // MARK: - iCloud placeholders

    static func placeholderFilename(for filename: String) -> String {
        ".\(filename).icloud"
    }

    static func placeholderURL(in folder: URL) -> URL {
        folder.appendingPathComponent(placeholderFilename(for: scratchpadFilename))
    }

    static func hasScratchpad(in folder: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: scratchpadURL(in: folder).path)
            || fm.fileExists(atPath: placeholderURL(in: folder).path)
    }

    static func hasUndownloadedScratchpad(in folder: URL) -> Bool {
        let fm = FileManager.default
        return !fm.fileExists(atPath: scratchpadURL(in: folder).path)
            && fm.fileExists(atPath: placeholderURL(in: folder).path)
    }

    @discardableResult
    static func startDownloadIfPlaceholder(
        in folder: URL = StorageLocation.currentFolder
    ) -> Bool {
        guard hasUndownloadedScratchpad(in: folder) else { return false }
        try? FileManager.default.startDownloadingUbiquitousItem(
            at: scratchpadURL(in: folder)
        )
        return true
    }

    enum SwitchError: LocalizedError {
        case destinationNotDownloaded

        var errorDescription: String? {
            "That folder's scratchpad hasn't downloaded from iCloud yet."
        }
        var recoverySuggestion: String? {
            "Wisp has asked iCloud for it. Try again in a moment."
        }
    }

    static func backupFilename(at date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime]
        let stamp = formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
        return "\(backupPrefix)\(stamp).md"
    }

    struct SwitchResult {
        let newText: String
        let backupURL: URL?
        let loadedExisting: Bool
    }

    static func setFolder(_ folder: URL, currentText: String) throws -> SwitchResult {
        let fm = FileManager.default
        let oldURL = currentURL
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let newURL = scratchpadURL(in: folder)

        if (newURL.standardizedFileURL.path) == (oldURL.standardizedFileURL.path) {
            return SwitchResult(newText: currentText, backupURL: nil, loadedExisting: false)
        }

        if hasUndownloadedScratchpad(in: folder) {
            startDownloadIfPlaceholder(in: folder)
            throw SwitchError.destinationNotDownloaded
        }

        if fm.fileExists(atPath: newURL.path) {
            let backupURL = oldURL.deletingLastPathComponent()
                .appendingPathComponent(backupFilename())
            try? currentText.write(to: backupURL, atomically: true, encoding: .utf8)
            let loaded = (try? String(contentsOf: newURL, encoding: .utf8)) ?? currentText
            try? fm.removeItem(at: oldURL)
            UserDefaults.standard.set(folder.path, forKey: folderKey)
            return SwitchResult(newText: loaded, backupURL: backupURL, loadedExisting: true)
        } else {
            try currentText.write(to: newURL, atomically: true, encoding: .utf8)
            try? fm.removeItem(at: oldURL)
            UserDefaults.standard.set(folder.path, forKey: folderKey)
            return SwitchResult(newText: currentText, backupURL: nil, loadedExisting: false)
        }
    }

    static func resetToDefault(currentText: String) throws {
        guard isCustom else { return }
        let fm = FileManager.default
        try fm.createDirectory(at: defaultFolder, withIntermediateDirectories: true)
        let defaultURL = scratchpadURL(in: defaultFolder)
        try currentText.write(to: defaultURL, atomically: true, encoding: .utf8)
        UserDefaults.standard.removeObject(forKey: folderKey)
    }
}
