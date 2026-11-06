// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

final class RecorderGIFWorkspace {
    static var root: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName,
                                    isDirectory: true)
            .appendingPathComponent("GIF Exports", isDirectory: true)
    }

    let folder: URL
    var fileURL: URL { folder.appendingPathComponent("animation.gif") }
    private var lease: Int32

    init(root: URL = RecorderGIFWorkspace.root) throws {
        let rootLease = try Self.lockRoot(root)
        defer { Darwin.close(rootLease) }
        Self.sweepUnlocked(root: root)
        folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        lease = Self.openLease(in: folder)
        guard lease >= 0, flock(lease, LOCK_EX | LOCK_NB) == 0 else {
            if lease >= 0 { Darwin.close(lease) }
            lease = -1
            try? FileManager.default.removeItem(at: folder)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    deinit { discard() }

    func discard() {
        guard lease >= 0 else { return }
        try? FileManager.default.removeItem(at: folder)
        Darwin.close(lease)
        lease = -1
    }

    static func sweep(root: URL = RecorderGIFWorkspace.root) {
        guard FileManager.default.fileExists(atPath: root.path),
              let rootLease = try? lockRoot(root) else { return }
        defer { Darwin.close(rootLease) }
        sweepUnlocked(root: root)
    }

    private static func lockRoot(_ root: URL) throws -> Int32 {
        guard PrivateFileStore.createDirectory(at: root, container: root) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let lease = openLease(in: root)
        guard lease >= 0, flock(lease, LOCK_EX) == 0 else {
            if lease >= 0 { Darwin.close(lease) }
            throw CocoaError(.fileWriteUnknown)
        }
        return lease
    }

    private static func openLease(in folder: URL) -> Int32 {
        Darwin.open(folder.appendingPathComponent(".lease").path,
                    O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    }

    private static func sweepUnlocked(root: URL) {
        let manager = FileManager.default
        guard let folders = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return }
        for folder in folders {
            guard UUID(uuidString: folder.lastPathComponent) != nil,
                  let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let lease = openLease(in: folder)
            guard lease >= 0 else { continue }
            if flock(lease, LOCK_EX | LOCK_NB) == 0 {
                try? manager.removeItem(at: folder)
            }
            Darwin.close(lease)
        }
    }
}
