// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum InstalledApps {
    struct InstalledApp: Identifiable, Equatable {
        let id: String
        let name: String
        let bundleID: String?
        let url: URL
        let isSystem: Bool
        var alternateNames: [String] = []
        var explicitIdentity: String? = nil

        var identity: String? {
            explicitIdentity ?? bundleID
        }

        var icon: NSImage {
            NSWorkspace.shared.icon(forFile: url.path)
        }
    }

    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private static func fileURL(forIdentity identity: String) -> URL? {
        guard MouseAppExceptionSupport.isExecutablePathIdentity(identity) else {
            return url(for: identity)
        }
        return URL(fileURLWithPath: identity)
    }

    static func location(for identity: String) -> String? {
        guard MouseAppExceptionSupport.isExecutablePathIdentity(identity) else { return nil }
        return ((identity as NSString).deletingLastPathComponent as NSString)
            .abbreviatingWithTildeInPath
    }

    static func displayName(fromFinderName finderName: String) -> String {
        var name = finderName
        if name.hasSuffix(".app") { name.removeLast(4) }
        return name
    }

    static func name(
        for bundleID: String,
        finderName: (String) -> String = { FileManager.default.displayName(atPath: $0) }
    ) -> String {
        guard let url = fileURL(forIdentity: bundleID) else { return bundleID }
        return displayName(fromFinderName: finderName(url.path))
    }

    static func icon(for bundleID: String) -> NSImage {
        if let url = fileURL(forIdentity: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    private static let systemPathPrefixes = ["/System/", "/Library/Apple/"]

    private static let systemBundleIDsOutsideFolders = ["com.apple.finder"]

    static func isSystemApplication(at url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return systemPathPrefixes.contains { path.hasPrefix($0) }
    }

    static func isInApplicationsFolder(_ url: URL) -> Bool {
        let containingDirectory = url.deletingLastPathComponent()
            .resolvingSymlinksInPath().standardizedFileURL.path
        let roots = [
            URL(fileURLWithPath: "/Applications").standardizedFileURL.path,
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")
                .standardizedFileURL.path,
        ]
        return roots.contains { containingDirectory == $0 || containingDirectory.hasPrefix($0 + "/") }
    }

    static func bundledApplications(in appURL: URL, fileManager fm: FileManager = .default) -> [URL] {
        ["Contents/Applications", "Contents/Developer/Applications"].flatMap { relativePath -> [URL] in
            let folder = appURL.appendingPathComponent(relativePath, isDirectory: true)
            guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return [] }
            return names.filter { $0.lowercased().hasSuffix(".app") }.sorted()
                .map { folder.appendingPathComponent($0, isDirectory: true) }
        }
    }

    static func installedApplications(includeSystemApplications: Bool = false,
                                      includeBundledApplications: Bool = false,
                                      spotlightPaths: [String] = [],
                                      roots folders: [URL]? = nil) -> [InstalledApp] {
        let fm = FileManager.default
        var roots = folders ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications", isDirectory: true),
        ]
        if includeSystemApplications, folders == nil {
            roots.append(URL(fileURLWithPath: "/System/Applications", isDirectory: true))
        }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        var seen = Set<String>()
        var apps: [InstalledApp] = []

        for root in roots where fm.fileExists(atPath: root.path) {
            guard let enumerator = fm.enumerator(at: root,
                                                includingPropertiesForKeys: keys,
                                                options: [.skipsPackageDescendants]) else {
                continue
            }
            for case let found as URL in enumerator {
                guard found.pathExtension == "app" else { continue }
                let shipped = includeBundledApplications ? bundledApplications(in: found, fileManager: fm) : []
                for url in [found] + shipped {
                    let resolved = url.resolvingSymlinksInPath()
                    let isSystemApp = isSystemApplication(at: url)
                    guard includeSystemApplications || !isSystemApp else { continue }
                    guard seen.insert(resolved.standardizedFileURL.path).inserted else { continue }
                    apps.append(app(at: url, fileManager: fm))
                }
            }
        }

        if includeSystemApplications {
            for bundleID in systemBundleIDsOutsideFolders {
                guard let url = url(for: bundleID),
                      seen.insert(url.resolvingSymlinksInPath().standardizedFileURL.path).inserted else {
                    continue
                }
                apps.append(app(at: url, fileManager: fm))
            }
        }

        for path in applicationScanPaths(folderPaths: [],
                                         spotlightPaths: spotlightPaths,
                                         homeDirectory: NSHomeDirectory()) {
            let url = URL(fileURLWithPath: path)
            guard fm.fileExists(atPath: path),
                  seen.insert(url.standardizedFileURL.path).inserted else { continue }
            apps.append(app(at: url, fileManager: fm))
            guard includeBundledApplications else { continue }
            for tool in bundledApplications(in: url, fileManager: fm)
            where seen.insert(tool.resolvingSymlinksInPath().standardizedFileURL.path).inserted {
                apps.append(app(at: tool, fileManager: fm))
            }
        }

        return apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func applicationScanPaths(folderPaths: [String],
                                     spotlightPaths: [String],
                                     homeDirectory: String) -> [String] {
        let home = URL(fileURLWithPath: homeDirectory)
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
        let homePrefix = home.hasSuffix("/") ? home : home + "/"
        var seen = Set<String>()
        var result: [String] = []

        func append(_ path: String, fromSpotlight: Bool) {
            let url = URL(fileURLWithPath: path)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            let normalized = url.path
            guard url.pathExtension.lowercased() == "app",
                  !isSystemApplication(at: url),
                  !normalized.split(separator: "/").dropLast().contains(where: {
                      $0.lowercased().hasSuffix(".app")
                  }) else { return }

            if fromSpotlight {
                guard normalized.hasPrefix(homePrefix) else { return }
                let components = normalized.dropFirst(homePrefix.count).split(separator: "/")
                let folders = components.dropLast()
                guard (1...3).contains(components.count),
                      components.first?.lowercased() != "library",
                      !folders.contains(where: { $0.hasPrefix(".") }) else { return }
            }

            guard seen.insert(normalized).inserted else { return }
            result.append(normalized)
        }

        folderPaths.forEach { append($0, fromSpotlight: false) }
        spotlightPaths.forEach { append($0, fromSpotlight: true) }
        return result
    }

    private static func app(at url: URL, fileManager fm: FileManager) -> InstalledApp {
        var name = fm.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        return InstalledApp(id: url.standardizedFileURL.path,
                            name: name,
                            bundleID: Bundle(url: url)?.bundleIdentifier,
                            url: url,
                            isSystem: isSystemApplication(at: url))
    }

    static func runningApplication(activationPolicy: NSApplication.ActivationPolicy,
                                   bundleID: String?,
                                   bundleURL: URL?,
                                   executableURL: URL?,
                                   localizedName: String?,
                                   acceptsExecutables: Bool) -> InstalledApp? {
        guard activationPolicy == .regular else { return nil }

        if let bundleID, bundleID.isEmpty { return nil }
        let isAppBundle = bundleURL?.pathExtension.caseInsensitiveCompare("app") == .orderedSame

        if let bundleID, let bundleURL, isAppBundle {
            let name = localizedName ?? FileManager.default.displayName(atPath: bundleURL.path)
            return InstalledApp(id: bundleURL.standardizedFileURL.path,
                                name: name,
                                bundleID: bundleID,
                                url: bundleURL,
                                isSystem: isSystemApplication(at: bundleURL),
                                explicitIdentity: nil)
        }

        guard acceptsExecutables, let executableURL else { return nil }
        guard let identity = MouseAppExceptionSupport.identity(
            bundleID: bundleID,
            executablePath: executableURL.path
        ) else { return nil }

        let isPathIdentity = MouseAppExceptionSupport.isExecutablePathIdentity(identity)
        let url = isPathIdentity ? URL(fileURLWithPath: identity) : executableURL
        let name = localizedName ?? FileManager.default.displayName(atPath: url.path)

        return InstalledApp(id: identity,
                            name: name,
                            bundleID: isPathIdentity ? nil : identity,
                            url: url,
                            isSystem: isSystemApplication(at: url),
                            explicitIdentity: identity)
    }

    static func runningApplication(_ app: NSRunningApplication,
                                   acceptsExecutables: Bool) -> InstalledApp? {
        runningApplication(activationPolicy: app.activationPolicy,
                           bundleID: app.bundleIdentifier,
                           bundleURL: app.bundleURL,
                           executableURL: app.executableURL,
                           localizedName: app.localizedName,
                           acceptsExecutables: acceptsExecutables)
    }

    static func deduplicatedAndFiltered(_ apps: [InstalledApp],
                                        excluding excludedIdentities: Set<String>) -> [InstalledApp] {
        var seen = Set<String>()
        return apps.filter { app in
            guard let identity = app.identity,
                  !excludedIdentities.contains(identity),
                  seen.insert(identity).inserted else { return false }
            return true
        }.sorted {
            let byName = $0.name.localizedCaseInsensitiveCompare($1.name)
            return byName == .orderedSame
                ? ($0.identity ?? "") < ($1.identity ?? "")
                : byName == .orderedAscending
        }
    }

    static func installedBundleApplications(excluding excludedBundleIDs: Set<String>,
                                            includeRunningApplications: Bool = false,
                                            acceptsExecutables: Bool = false) -> [InstalledApp] {
        var apps = installedApplications(includeSystemApplications: true)
        if includeRunningApplications {
            apps += NSWorkspace.shared.runningApplications.compactMap { runningApp in
                runningApplication(runningApp, acceptsExecutables: acceptsExecutables)
            }
        }

        return deduplicatedAndFiltered(apps, excluding: excludedBundleIDs)
    }
}
