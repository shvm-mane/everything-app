// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

final class RecorderTakeStore: @unchecked Sendable {
    static let shared = RecorderTakeStore()

    struct Take: Equatable, Sendable {
        let id: UUID
        let folder: URL

        var videoURL: URL { folder.appendingPathComponent(RecorderSupport.takeVideoName) }
        var pointerURL: URL { folder.appendingPathComponent(RecorderSupport.takePointerName) }
        var typingURL: URL { folder.appendingPathComponent(RecorderSupport.takeTypingName) }
        var editURL: URL { folder.appendingPathComponent(RecorderSupport.takeEditName) }
    }

    private let manager = FileManager.default

    private init() {}

    // MARK: - Location

    private var root: URL? {
        PrivateFileStore.containerURL?
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    func freeBytes() -> Int64 {
        guard let root else { return 0 }
        let probe = manager.fileExists(atPath: root.path)
            ? root
            : manager.homeDirectoryForCurrentUser
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    // MARK: - Lifecycle

    func makeTake() -> Take? {
        guard let root else { return nil }
        let id = UUID()
        let folder = root.appendingPathComponent(RecorderSupport.takeFolderName(id: id),
                                                 isDirectory: true)
        guard PrivateFileStore.createDirectory(at: folder) else { return nil }
        return Take(id: id, folder: folder)
    }

    func importVideo(at sourceURL: URL) -> Take? {
        guard let take = makeTake() else { return nil }
        guard importVideo(at: sourceURL, into: take) else {
            delete(take)
            return nil
        }
        return take
    }

    func importVideo(at sourceURL: URL, into take: Take) -> Bool {
        guard let values = try? sourceURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize > 0,
              Self.canImport(fileSize: Int64(fileSize), availableBytes: freeBytes(at: take.folder))
        else { return false }

        do {
            try manager.copyItem(at: sourceURL, to: take.videoURL)
            return true
        } catch {
            try? manager.removeItem(at: take.videoURL)
            return false
        }
    }

    static func canImport(fileSize: Int64, availableBytes: Int64) -> Bool {
        guard fileSize > 0, availableBytes >= fileSize else { return false }
        return availableBytes - fileSize >= RecorderSupport.minimumFreeBytesToContinue
    }

    func importImage(at sourceURL: URL, into take: Take) -> URL? {
        copyImage(at: sourceURL, into: take.folder)
    }

    func copyImage(at sourceURL: URL, into directory: URL) -> URL? {
        guard let values = try? sourceURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              Self.canImport(fileSize: Int64(fileSize), availableBytes: freeBytes(at: directory))
        else { return nil }

        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = folder.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
            try manager.copyItem(at: sourceURL, to: destination)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            guard MediaSupport.imageThumbnail(at: destination, maxPixel: 1) != nil else {
                try? manager.removeItem(at: folder)
                return nil
            }
            return destination
        } catch {
            try? manager.removeItem(at: folder)
            return nil
        }
    }

    private func freeBytes(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    func owns(_ take: Take) -> Bool {
        guard let root else { return false }
        let expected = root.appendingPathComponent(RecorderSupport.takeFolderName(id: take.id),
                                                    isDirectory: true)
        guard take.folder.standardizedFileURL == expected.standardizedFileURL,
              let folderValues = try? take.folder.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              folderValues.isDirectory == true,
              folderValues.isSymbolicLink != true,
              let videoValues = try? take.videoURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              videoValues.isRegularFile == true,
              videoValues.isSymbolicLink != true,
              (videoValues.fileSize ?? 0) > 0
        else { return false }
        return true
    }

    func delete(_ take: Take) {
        try? manager.removeItem(at: take.folder)
    }

    func saveDirectly(_ take: Take, to destination: URL) throws {
        try manager.copyItem(at: take.videoURL, to: destination)
        do {
            try manager.removeItem(at: take.folder)
        } catch {
            try? manager.removeItem(at: destination)
            throw error
        }
    }

    func takes() -> [Take] {
        guard let root,
              let names = try? manager.contentsOfDirectory(atPath: root.path)
        else { return [] }
        return names.compactMap { name in
            guard let id = RecorderSupport.takeID(fromFolderName: name) else { return nil }
            return Take(id: id, folder: root.appendingPathComponent(name, isDirectory: true))
        }
    }

    func finishedAt(_ take: Take) -> Date? {
        let values = try? take.videoURL.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    // MARK: - Sweep

    func sweep(keeping owned: Set<UUID> = [], now: Date = Date()) {
        let all = takes().filter { !owned.contains($0.id) }
        guard !all.isEmpty else { return }
        var byID: [UUID: Take] = [:]
        let described: [(id: UUID, finishedAt: Date?, createdAt: Date?)] = all.map { take in
            byID[take.id] = take
            let created = try? take.folder.resourceValues(forKeys: [.creationDateKey]).creationDate
            return (id: take.id, finishedAt: finishedAt(take), createdAt: created)
        }
        for id in RecorderSupport.orphanTakeIDs(described, now: now) {
            if let take = byID[id] { delete(take) }
        }
    }
}
