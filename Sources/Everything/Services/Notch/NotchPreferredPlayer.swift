// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum NotchPreferredPlayer {
    static let automatic = ""
    static let known = ["com.spotify.client", "com.apple.Music"]
    static var lastPlayed: String?

    static func choice(in defaults: UserDefaults = .standard) -> String {
        let value = defaults.string(forKey: DefaultsKey.notchPreferredPlayer) ?? automatic
        return value.utf8.count <= 256 ? value : automatic
    }

    static func resolve(choice: String, lastPlayed: String?, isInstalled: (String) -> Bool) -> String? {
        if !choice.isEmpty, isInstalled(choice) { return choice }
        if let lastPlayed, isInstalled(lastPlayed) { return lastPlayed }
        return known.first(where: isInstalled)
    }

    static func current() -> String? {
        resolve(choice: choice(), lastPlayed: lastPlayed) { InstalledApps.url(for: $0) != nil }
    }

    static func remember(_ playback: NotchPlayback?, in sources: [NotchPlaybackSource]) {
        guard let playback, playback.isPlaying, let bundle = playback.track.appBundleIdentifier,
              known.contains(bundle) || sources.contains(where: { $0.bundleIdentifier == bundle && $0.isMusicApp }) else { return }
        lastPlayed = bundle
    }

    typealias Choice = (bundleID: String, name: String)

    static func choices(in installed: [Choice], including chosen: String) -> [Choice] {
        guard !chosen.isEmpty, !installed.contains(where: { $0.bundleID == chosen }) else { return installed }
        return installed + [(chosen, chosen)]
    }

    static func loadInstalled(using load: @escaping @Sendable () -> [Choice] = { installed() }) async -> [Choice]? {
        guard !Task.isCancelled else { return nil }
        let choices = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: load())
            }
        }
        return Task.isCancelled ? nil : choices
    }

    static func installed() -> [Choice] {
        var ids = known.filter { InstalledApps.url(for: $0) != nil }
        for app in InstalledApps.installedApplications(includeSystemApplications: true) {
            guard let id = app.bundleID, !ids.contains(id),
                  Bundle(url: app.url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String == "public.app-category.music"
            else { continue }
            ids.append(id)
        }
        return ids.map { ($0, InstalledApps.name(for: $0)) }
    }

    static func openTitle(for id: String) -> String {
        return String(format: FeatureStrings.notchMusicExtras(L10n.shared.language).openNamedPlayer, InstalledApps.name(for: id))
    }

    @discardableResult
    static func open() -> Bool {
        guard let id = current(), let url = InstalledApps.url(for: id), Bundle(url: url)?.bundleIdentifier == id else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return true
    }
}
