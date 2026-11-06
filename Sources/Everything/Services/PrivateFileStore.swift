// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum PrivateFileStore {
    private static let directoryPermissions = 0o700
    private static let filePermissions = 0o600

    static var containerURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier
        else { return nil }
        return base.appendingPathComponent(bundleID, isDirectory: true)
    }

    @discardableResult
    static func createDirectory(at url: URL, container: URL? = containerURL) -> Bool {
        let manager = FileManager.default
        guard (try? manager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: directoryPermissions])) != nil
        else { return false }
        for directory in directoriesToTighten(from: url, container: container) {
            try? manager.setAttributes([.posixPermissions: directoryPermissions],
                                       ofItemAtPath: directory.path)
        }
        return true
    }

    @discardableResult
    static func write(_ data: Data, to url: URL) -> Bool {
        guard (try? data.write(to: url, options: .atomic)) != nil else { return false }
        try? FileManager.default.setAttributes([.posixPermissions: filePermissions],
                                               ofItemAtPath: url.path)
        return true
    }

    static func directoriesToTighten(from url: URL, container: URL?) -> [URL] {
        var chain = [url.standardizedFileURL]
        guard let containerPath = container?.standardizedFileURL.path else { return chain }
        var current = chain[0]
        while current.path != containerPath, current.path.hasPrefix(containerPath + "/") {
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { break }
            chain.append(parent)
            current = parent
        }
        return chain
    }
}
