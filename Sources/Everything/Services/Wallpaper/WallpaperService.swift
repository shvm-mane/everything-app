// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import ImageIO
import UniformTypeIdentifiers

final class WallpaperService: ObservableObject {
    static let shared = WallpaperService()

    struct OwnSource: Identifiable, Equatable {
        let id: String
        let title: String
        let isFolder: Bool
        let isReachable: Bool
        let bookmark: Data
    }

    @Published private(set) var entries: [WallpaperSupport.Entry] = []
    @Published private(set) var ownSources: [OwnSource] = []
    @Published private(set) var filter: WallpaperSupport.Filter = .all
    @Published private(set) var lastError: String?
    @Published private(set) var appliedPath: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isApplying = false
    @Published private(set) var isDownloading = false
    @Published private(set) var thumbEpoch = 0

    private var ownBookmarks: [Data] = []
    private var excludedOwnPaths: Set<String> = []
    private var fileBookmarkByPath: [String: Data] = [:]
    private var pathByFileBookmark: [Data: String] = [:]
    private var scopedURLs: [URL] = []
    private var openPanel: NSOpenPanel?
    private var cachedApple: [WallpaperSupport.Entry]?
    private let galleryLifecycle = WallpaperGalleryLifecycle()
    private var applyToken = UUID()
    private let applyGenerationLock = NSLock()
    private var applyGeneration = UUID()

    private init() {
        loadBookmarks()
        loadExclusions()
        loadFilter()
    }

    var isAvailable: Bool { AppFeature.wallpaper.isAvailable }

    var ownFolderSources: [OwnSource] {
        ownSources.filter(\.isFolder)
    }

    var removableChipSources: [OwnSource] {
        if isLoading {
            return ownSources.filter { $0.isFolder || !$0.isReachable }
        }
        let ownIDs = Set(entries.lazy.filter { $0.source == .own }.map(\.id))
        return ownSources.filter { source in
            if source.isFolder || !source.isReachable { return true }
            guard let path = pathByFileBookmark[source.bookmark] else { return true }
            return !ownIDs.contains(path)
        }
    }

    var visibleEntries: [WallpaperSupport.Entry] {
        WallpaperSupport.filtered(entries, by: filter)
    }

    var applyAllDisplays: Bool {
        get {
            if UserDefaults.standard.object(forKey: DefaultsKey.wallpaperApplyAllDisplays) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: DefaultsKey.wallpaperApplyAllDisplays)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.wallpaperApplyAllDisplays)
            objectWillChange.send()
        }
    }

    func syncWithPreferences() {
        if !isAvailable {
            galleryLifecycle.endAll()
            let cancelled = UUID()
            applyToken = cancelled
            setApplyGeneration(cancelled)
            stopAccessing()
            cachedApple = nil
            bumpThumbGeneration()
            WallpaperThumbnailCache.clear()
            ownSources = []
            entries = []
            lastError = nil
            appliedPath = nil
            isLoading = false
            isApplying = false
            isDownloading = false
            WallpaperStore.removeBackup()
            return
        }
        WallpaperStore.migrateLegacyBackupIfNeeded()
        if galleryLifecycle.isVisible { refresh(forceAppleRescan: false) }
    }

    func suspend() {
        stopAccessing()
    }

    func setFilter(_ filter: WallpaperSupport.Filter) {
        self.filter = filter
        UserDefaults.standard.set(filter.rawValue, forKey: DefaultsKey.wallpaperFilter)
        preparePageThumbs(for: filter, around: 1)
    }

    func prefetchNearbyPages(for filter: WallpaperSupport.Filter, around page: Int) {
        let visible = WallpaperSupport.filtered(entries, by: filter)
        let current = WallpaperSupport.pageSlice(visible, page: page)
        let next = WallpaperSupport.pageSlice(visible, page: page + 1)
        WallpaperThumbnailCache.prefetch(current.map(\.previewURL) + next.map(\.previewURL))
    }

    func preparePageThumbs(for filter: WallpaperSupport.Filter, around page: Int) {
        bumpThumbGeneration()
        prefetchNearbyPages(for: filter, around: page)
    }

    func beginViewing(_ viewer: UUID) {
        galleryLifecycle.begin(viewer)
        refresh(forceAppleRescan: false)
    }

    func endViewing(_ viewer: UUID) {
        guard galleryLifecycle.end(viewer) else { return }
        isLoading = false
        bumpThumbGeneration()
    }

    private func bumpThumbGeneration() {
        WallpaperThumbnailCache.beginGeneration()
        thumbEpoch &+= 1
    }

    func refresh(forceAppleRescan: Bool = false) {
        guard isAvailable else {
            entries = []
            isLoading = false
            return
        }
        guard galleryLifecycle.isVisible else { return }
        let resolved = resolveOwnBookmarks()
        startAccessing(resolved)
        rebuildOwnSources(from: resolved)
        let roots = resolved.map(\.url)
        let excluded = excludedOwnPaths
        let appleCache = forceAppleRescan ? nil : cachedApple
        let token = galleryLifecycle.invalidate()
        bumpThumbGeneration()
        if entries.isEmpty {
            isLoading = true
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let apple = appleCache ?? WallpaperSupport.enumerateAppleEntries()
            guard self?.galleryLifecycle.accepts(token) == true else { return }

            var imageURLs: [URL] = []
            for root in roots {
                guard self?.galleryLifecycle.accepts(token) == true else { return }
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir) else {
                    continue
                }
                if isDir.boolValue {
                    let found = WallpaperSupport.images(inFolder: root) {
                        self?.galleryLifecycle.accepts(token) == true
                    }
                    guard self?.galleryLifecycle.accepts(token) == true else { return }
                    for url in found where !excluded.contains(url.standardizedFileURL.path) {
                        imageURLs.append(url)
                    }
                } else if WallpaperSupport.isStillImageURL(root) {
                    let path = root.standardizedFileURL.path
                    if !excluded.contains(path) {
                        imageURLs.append(root)
                    }
                }
            }
            guard self?.galleryLifecycle.accepts(token) == true else { return }

            let own = WallpaperSupport.ownEntries(from: imageURLs)
            let merged = WallpaperSupport.merge(apple: apple, own: own)
            DispatchQueue.main.async {
                guard let self, self.galleryLifecycle.accepts(token) else { return }
                if appleCache == nil {
                    self.cachedApple = apple
                }
                self.entries = merged
                self.isLoading = false
                self.prefetchNearbyPages(for: self.filter, around: 1)
            }
        }
    }

    func apply(_ entry: WallpaperSupport.Entry) {
        guard isAvailable else { return }
        lastError = nil
        let url = entry.imageURL.standardizedFileURL
        let chosen = targetScreens()
        guard !chosen.isEmpty else {
            lastError = FeatureStrings.wallpaper(L10n.shared.language).applyFailed
            return
        }

        let token = UUID()
        applyToken = token
        setApplyGeneration(token)
        let applyAll = applyAllDisplays
        isApplying = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.applyToken == token {
                    self.isApplying = false
                    self.isDownloading = false
                }
            }

            let localOK = await self.ensureLocalFile(url, token: token)
            guard self.isAvailable, self.applyToken == token else { return }
            if !localOK {
                self.lastError = FeatureStrings.wallpaper(L10n.shared.language).downloadFailed
                return
            }

            let currentOK = await self.setDesktopImage(url, on: chosen, token: token)
            guard self.isAvailable, self.applyToken == token else { return }

            if applyAll {
                let expected = token
                let allOK = await Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self else { return false }
                    return WallpaperStore.setImageOnAllSpaces(url) {
                        self.currentApplyGeneration() == expected
                    }
                }.value
                guard self.isAvailable, self.applyToken == token else { return }
                if allOK || currentOK {
                    self.appliedPath = url.path
                }
                if !allOK && !currentOK {
                    self.lastError = FeatureStrings.wallpaper(L10n.shared.language).applyFailed
                }
                return
            }

            if currentOK {
                self.appliedPath = url.path
            } else {
                self.lastError = FeatureStrings.wallpaper(L10n.shared.language).applyFailed
            }
        }
    }

    static func needsCloudDownload(_ url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isUbiquitousItem == true
        else { return false }
        return values.ubiquitousItemDownloadingStatus != .current
    }

    @MainActor
    private func ensureLocalFile(_ url: URL, token: UUID) async -> Bool {
        guard Self.needsCloudDownload(url) else { return true }
        isDownloading = true
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            return false
        }
        let deadline = ContinuousClock.now + .seconds(60)
        while ContinuousClock.now < deadline {
            guard isAvailable, applyToken == token else { return false }
            if (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingErrorKey])
                .ubiquitousItemDownloadingError) != nil {
                return false
            }
            if !Self.needsCloudDownload(url) { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return !Self.needsCloudDownload(url)
    }

    private func setApplyGeneration(_ token: UUID) {
        applyGenerationLock.lock()
        applyGeneration = token
        applyGenerationLock.unlock()
    }

    private func currentApplyGeneration() -> UUID {
        applyGenerationLock.lock()
        defer { applyGenerationLock.unlock() }
        return applyGeneration
    }

    private func targetScreens() -> [NSScreen] {
        if applyAllDisplays {
            return NSScreen.screens
        }
        if let screen = NSScreen.withMouse {
            return [screen]
        }
        return NSScreen.screens.first.map { [$0] } ?? []
    }

    @MainActor
    private func setDesktopImage(_ url: URL, on screens: [NSScreen], token: UUID) async -> Bool {
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true,
        ]
        var needsPause = false
        for screen in screens {
            if NSWorkspace.shared.desktopImageURL(for: screen)?.standardizedFileURL == url {
                do {
                    try NSWorkspace.shared.setDesktopImageURL(
                        URL(fileURLWithPath: ""), for: screen, options: [:])
                    needsPause = true
                } catch {
                }
            }
        }
        if needsPause {
            try? await Task.sleep(for: .milliseconds(400))
            guard isAvailable, applyToken == token else { return false }
        }
        var ok = true
        for screen in screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
            } catch {
                ok = false
            }
        }
        return ok
    }

    func addImages(inNotch: Bool) {
        guard isAvailable else { return }
        if let openPanel { bringForward(openPanel, inNotch: inNotch); return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        let types = WallpaperSupport.imageExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowedContentTypes = types.isEmpty ? [.image] : types
        panel.message = FeatureStrings.wallpaper(L10n.shared.language).addImagePrompt
        present(panel, inNotch: inNotch) { [weak self] urls in
            self?.remember(urls: urls)
        }
    }

    func addFolder(inNotch: Bool) {
        guard isAvailable else { return }
        if let openPanel { bringForward(openPanel, inNotch: inNotch); return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = FeatureStrings.wallpaper(L10n.shared.language).addFolderPrompt
        present(panel, inNotch: inNotch) { [weak self] urls in
            self?.remember(urls: urls)
        }
    }

    var isChoosingSource: Bool { openPanel != nil }

    func openSystemWallpaperSettings() {
        guard let url = WallpaperSupport.systemWallpaperSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Bookmarks

    private func present(_ panel: NSOpenPanel, inNotch: Bool, completion: @escaping ([URL]) -> Void) {
        openPanel = panel
        if !inNotch { PanelInteractionState.shared.isPresentingPopoverModal = true }
        panel.begin { [weak self] response in
            if !inNotch { PanelInteractionState.shared.isPresentingPopoverModal = false }
            guard let self else { return }
            self.openPanel = nil
            guard response == .OK else { return }
            completion(panel.urls)
        }
        bringForward(panel, inNotch: inNotch)
    }

    private func bringForward(_ panel: NSOpenPanel, inNotch: Bool) {
        if inNotch, let island = NotchService.shared.presentationWindow {
            panel.level = NSWindow.Level(rawValue: island.level.rawValue + 1)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func remember(urls: [URL]) {
        for url in urls {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if exists && !isDir.boolValue && !WallpaperSupport.isStillImageURL(url) {
                continue
            }
            guard let data = try? url.bookmarkData(options: .withSecurityScope,
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil)
            else { continue }
            let path = url.standardizedFileURL.path
            ownBookmarks.removeAll { existing in
                resolveBookmark(existing)?.standardizedFileURL.path == path
            }
            ownBookmarks.append(data)
            excludedOwnPaths.remove(path)
            if exists && isDir.boolValue {
                excludedOwnPaths = excludedOwnPaths.filter { !$0.hasPrefix(path + "/") }
            }
        }
        persistBookmarks()
        persistExclusions()
        rebuildOwnSources()
        refresh(forceAppleRescan: false)
    }

    func removeOwnSource(_ source: OwnSource) {
        guard isAvailable else { return }
        removeOwnBookmark(source.bookmark, knownFolder: source.isFolder)
    }

    func removeOwnEntry(_ entry: WallpaperSupport.Entry) {
        guard isAvailable, entry.source == .own else { return }
        let path = entry.id
        if let data = fileBookmarkByPath[path] {
            removeOwnBookmark(data, knownFolder: false)
            return
        }
        excludedOwnPaths.insert(path)
        persistExclusions()
        galleryLifecycle.invalidate()
        entries.removeAll { $0.id == path }
    }

    private func removeOwnBookmark(_ data: Data, knownFolder: Bool?) {
        if let url = resolveBookmark(data) {
            let path = url.standardizedFileURL.path
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            let isFolder = knownFolder ?? (exists ? isDir.boolValue : url.hasDirectoryPath)
            if isFolder {
                excludedOwnPaths = excludedOwnPaths.filter { !$0.hasPrefix(path + "/") }
            } else {
                excludedOwnPaths.remove(path)
            }
            persistExclusions()
        }
        ownBookmarks.removeAll { $0 == data }
        persistBookmarks()
        rebuildOwnSources()
        refresh(forceAppleRescan: false)
    }

    private func loadBookmarks() {
        ownBookmarks = UserDefaults.standard.array(forKey: DefaultsKey.wallpaperOwnBookmarks) as? [Data]
            ?? []
    }

    private func persistBookmarks() {
        UserDefaults.standard.set(ownBookmarks, forKey: DefaultsKey.wallpaperOwnBookmarks)
    }

    private func loadExclusions() {
        let list = UserDefaults.standard.array(forKey: DefaultsKey.wallpaperExcludedOwnPaths) as? [String]
            ?? []
        excludedOwnPaths = Set(list)
    }

    private func persistExclusions() {
        UserDefaults.standard.set(Array(excludedOwnPaths).sorted(),
                                  forKey: DefaultsKey.wallpaperExcludedOwnPaths)
    }

    private func rebuildOwnSources(from resolved: [ResolvedBookmark]? = nil) {
        let unavailable = FeatureStrings.wallpaper(L10n.shared.language).sourceUnavailable
        var byData: [Data: URL] = [:]
        if let resolved {
            for item in resolved {
                byData[item.data] = item.url
            }
        }
        var fileMap: [String: Data] = [:]
        var pathMap: [Data: String] = [:]
        ownSources = ownBookmarks.enumerated().map { index, data in
            let id = bookmarkIdentity(data, index: index)
            let url = byData[data] ?? resolveBookmark(data)
            if let url {
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                let isFolder = exists ? isDir.boolValue : url.hasDirectoryPath
                if exists && !isDir.boolValue {
                    let path = url.standardizedFileURL.path
                    fileMap[path] = data
                    pathMap[data] = path
                }
                return OwnSource(id: id,
                                 title: url.lastPathComponent,
                                 isFolder: isFolder,
                                 isReachable: exists,
                                 bookmark: data)
            }
            return OwnSource(id: id,
                             title: unavailable,
                             isFolder: false,
                             isReachable: false,
                             bookmark: data)
        }
        fileBookmarkByPath = fileMap
        pathByFileBookmark = pathMap
    }

    private func bookmarkIdentity(_ data: Data, index: Int) -> String {
        var hasher = Hasher()
        hasher.combine(data)
        return "bm-\(hasher.finalize())-\(index)"
    }

    private func loadFilter() {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.wallpaperFilter) ?? ""
        filter = WallpaperSupport.Filter(rawValue: raw) ?? .all
    }

    private func stopAccessing() {
        for url in scopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        scopedURLs.removeAll()
    }

    private func startAccessing(_ resolved: [ResolvedBookmark]? = nil) {
        stopAccessing()
        let items = resolved ?? resolveOwnBookmarks()
        for item in items {
            if item.url.startAccessingSecurityScopedResource() {
                scopedURLs.append(item.url)
            }
        }
    }

    private struct ResolvedBookmark {
        let data: Data
        let url: URL
    }

    private func resolveOwnBookmarks() -> [ResolvedBookmark] {
        var result: [ResolvedBookmark] = []
        var seen = Set<String>()
        for data in ownBookmarks {
            guard let url = resolveBookmark(data) else { continue }
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            result.append(ResolvedBookmark(data: data, url: url))
        }
        return result
    }

    private func resolveBookmark(_ data: Data) -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: data,
                        options: [.withSecurityScope, .withoutUI, .withoutMounting],
                        relativeTo: nil,
                        bookmarkDataIsStale: &stale)
    }
}

enum WallpaperThumbnailCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 400
        return cache
    }()

    private static let lock = NSLock()
    private static var generation = UUID()

    private static let prefetchQueue = DispatchQueue(
        label: "com.vorssaint.utils.wallpaper-thumbs",
        qos: .utility,
        attributes: .concurrent
    )

    static func image(for url: URL, maxPixel: Int = 160) -> NSImage? {
        cache.object(forKey: key(url, maxPixel))
    }

    static func store(_ image: NSImage, for url: URL, maxPixel: Int = 160) {
        cache.setObject(image, forKey: key(url, maxPixel))
    }

    static func clear() {
        cache.removeAllObjects()
    }

    static func beginGeneration() {
        lock.lock()
        generation = UUID()
        lock.unlock()
    }

    static func cancelPending() {
        beginGeneration()
    }

    static func snapshotGeneration() -> UUID {
        currentGeneration
    }

    static func matchesGeneration(_ generation: UUID) -> Bool {
        currentGeneration == generation
    }

    private static var currentGeneration: UUID {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    static func prefetch(_ urls: [URL], maxPixel: Int = 160) {
        guard !urls.isEmpty else { return }
        let gen = currentGeneration
        prefetchQueue.async {
            prefetchSync(urls, maxPixel: maxPixel, generation: gen)
        }
    }

    static func prefetchSync(_ urls: [URL], maxPixel: Int = 160, generation: UUID? = nil) {
        let gen = generation ?? currentGeneration
        for url in urls {
            guard currentGeneration == gen else { return }
            _ = loadSync(url: url, maxPixel: maxPixel, generation: gen)
        }
    }

    static func load(url: URL, maxPixel: Int = 160, generation: UUID) async -> NSImage? {
        if let hit = image(for: url, maxPixel: maxPixel) { return hit }
        return await withCheckedContinuation { continuation in
            prefetchQueue.async {
                let loaded = loadSync(url: url, maxPixel: maxPixel, generation: generation)
                continuation.resume(returning: loaded)
            }
        }
    }

    static func loadSync(url: URL, maxPixel: Int = 160, generation: UUID? = nil) -> NSImage? {
        if let hit = image(for: url, maxPixel: maxPixel) { return hit }
        if let generation, currentGeneration != generation { return nil }
        guard let cgImage = decodeCGThumbnail(url: url, maxPixel: maxPixel) else { return nil }
        if let generation, currentGeneration != generation { return nil }
        let image = NSImage(cgImage: cgImage,
                            size: NSSize(width: cgImage.width, height: cgImage.height))
        store(image, for: url, maxPixel: maxPixel)
        return image
    }

    private static func decodeCGThumbnail(url: URL, maxPixel: Int) -> CGImage? {
        guard !WallpaperService.needsCloudDownload(url) else { return nil }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func key(_ url: URL, _ maxPixel: Int) -> NSString {
        "\(url.standardizedFileURL.path)#\(maxPixel)" as NSString
    }
}
