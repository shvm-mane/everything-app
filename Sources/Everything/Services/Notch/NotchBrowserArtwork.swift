// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import ImageIO

final class NotchBrowserArtwork {
    static let shared = NotchBrowserArtwork()

    private static let attemptDelays: [TimeInterval] = [0, 2, 5, 10, 18, 30]
    private static let failureCooldown: TimeInterval = 60
    private static let rememberedCovers = 8

    private let queue = DispatchQueue(label: "com.vorssaint.notch-browser-artwork", qos: .utility)
    private let lock = NSLock()
    private var covers: [String: Data] = [:]
    private var coverOrder: [String] = []
    private var failedAt: [String: Date] = [:]
    private var wanted: String?
    private var inFlight: String?
    private var generation = UUID()
    private var downloadSession: URLSession?
    private var session: (file: URL, modified: Date, size: Int, tabs: [NotchBrowserArtworkSupport.SessionTab]?)?

    private struct Lookup {
        let key: String
        let generation: UUID
        let bundle: String
        let title: String
        let artist: String?
        let started: Date
        let found: () -> Void
    }

    func artwork(for playback: NotchPlayback) -> Data? {
        guard let key = NotchBrowserArtworkSupport.lookupKey(for: playback) else { return nil }
        return lock.withLock { covers[key] }
    }

    func request(for playback: NotchPlayback?, found: @escaping () -> Void) {
        guard let playback, let key = NotchBrowserArtworkSupport.lookupKey(for: playback),
              let bundle = playback.track.appBundleIdentifier,
              let title = playback.track.title else { return cancel() }
        var previous: URLSession?
        let requested = lock.withLock { () -> UUID? in
            wanted = key
            guard inFlight != key else { return nil }
            generation = UUID()
            previous = downloadSession
            downloadSession = nil
            inFlight = nil
            guard covers[key] == nil,
                  failedAt[key].map({ Date().timeIntervalSince($0) >= Self.failureCooldown }) ?? true else { return nil }
            inFlight = key
            return generation
        }
        previous?.invalidateAndCancel()
        guard let requested else {
            queue.async { [self] in
                if lock.withLock({ inFlight == nil }) { session = nil }
            }
            return
        }
        attempt(0, Lookup(key: key, generation: requested, bundle: bundle, title: title, artist: playback.track.artist,
                          started: Date(), found: found))
    }

    func cancel() {
        let previous = lock.withLock { () -> URLSession? in
            generation = UUID()
            wanted = nil
            inFlight = nil
            let previous = downloadSession
            downloadSession = nil
            return previous
        }
        previous?.invalidateAndCancel()
        queue.async { [self] in
            if lock.withLock({ inFlight == nil }) { session = nil }
        }
    }

    private func accepts(_ lookup: Lookup) -> Bool {
        NotchBrowserArtworkSupport.isEnabled()
            && lock.withLock { generation == lookup.generation && wanted == lookup.key && inFlight == lookup.key }
    }

    private func load(_ url: URL, accept: String, for lookup: Lookup, completion: @escaping (Data?) -> Void) {
        guard accepts(lookup) else { return finish(lookup, failed: false) }
        let download = NotchBrowserArtworkDownload.load(url, accept: accept) { [self] data in
            queue.async { [self] in
                guard accepts(lookup) else { return finish(lookup, failed: false) }
                let current = lock.withLock { () -> Bool in
                    guard generation == lookup.generation, wanted == lookup.key else { return false }
                    downloadSession = nil
                    return true
                }
                guard current else { return }
                completion(data)
            }
        }
        let kept = lock.withLock { () -> Bool in
            guard generation == lookup.generation, wanted == lookup.key else { return false }
            downloadSession = download
            return true
        }
        if !kept { download.invalidateAndCancel() }
    }

    private func attempt(_ index: Int, _ lookup: Lookup, askedApple: Bool = false) {
        queue.asyncAfter(deadline: .now() + Self.attemptDelays[index]) { [self] in
            guard accepts(lookup) else {
                return finish(lookup, failed: false)
            }
            let saved = youTubeTabs(bundle: lookup.bundle)
            let urls = NotchBrowserArtworkSupport.artworkURLs(forTrack: lookup.title, artist: lookup.artist,
                                                              in: saved?.tabs ?? [])
            if !urls.isEmpty {
                download(urls, for: lookup) { [self] data in
                    if let data { store(data, for: lookup) } else { finish(lookup, failed: true) }
                }
                return
            }
            guard !askedApple, let saved, NotchBrowserArtworkSupport.asksAppleMusic(
                      tabs: saved.tabs, savedAt: saved.modified, lookupStarted: lookup.started),
                  let search = NotchBrowserArtworkSupport.appleMusicSearchURL(
                      title: lookup.title, artist: lookup.artist, country: Locale.current.region?.identifier)
            else { return retry(index, lookup, askedApple: askedApple) }
            load(search, accept: "application/json", for: lookup) { [self] reply in
                guard let reply, let cover = NotchBrowserArtworkSupport.appleMusicArtworkURL(
                    inSearch: reply, title: lookup.title, artist: lookup.artist)
                else { return retry(index, lookup, askedApple: true) }
                download([cover], for: lookup) { [self] data in
                    if let data { store(data, for: lookup) } else { retry(index, lookup, askedApple: true) }
                }
            }
        }
    }

    private func retry(_ index: Int, _ lookup: Lookup, askedApple: Bool) {
        guard accepts(lookup) else { return finish(lookup, failed: false) }
        if index + 1 < Self.attemptDelays.count {
            attempt(index + 1, lookup, askedApple: askedApple)
        } else {
            finish(lookup, failed: true)
        }
    }

    private func store(_ data: Data, for lookup: Lookup) {
        guard accepts(lookup) else { return finish(lookup, failed: false) }
        let stored = lock.withLock { () -> Bool in
            guard generation == lookup.generation, wanted == lookup.key else { return false }
            covers[lookup.key] = data
            coverOrder.removeAll { $0 == lookup.key }
            coverOrder.append(lookup.key)
            while coverOrder.count > Self.rememberedCovers { covers[coverOrder.removeFirst()] = nil }
            return true
        }
        guard stored else { return }
        finish(lookup, failed: false)
        lookup.found()
    }

    private func finish(_ lookup: Lookup, failed: Bool) {
        let idle = lock.withLock { () -> Bool in
            guard generation == lookup.generation else { return false }
            let key = lookup.key
            if inFlight == key { inFlight = nil }
            downloadSession = nil
            if failed {
                let now = Date()
                failedAt = failedAt.filter { now.timeIntervalSince($0.value) < Self.failureCooldown }
                failedAt[key] = now
            }
            return inFlight == nil
        }
        if idle { session = nil }
    }

    private func youTubeTabs(bundle: String) -> (modified: Date, tabs: [NotchBrowserArtworkSupport.SessionTab])? {
        guard let file = latestSessionFile(bundle: bundle) else { return nil }
        if let session, session.file == file.url, session.modified == file.modified, session.size == file.size {
            return session.tabs.map { (file.modified, $0) }
        }
        let tabs = autoreleasepool { () -> [NotchBrowserArtworkSupport.SessionTab]? in
            guard file.size <= NotchBrowserArtworkSupport.maximumSessionFileBytes,
                  let json = (try? Data(contentsOf: file.url)).flatMap(NotchBrowserArtworkSupport.decodeMozLZ4)
            else { return nil }
            return NotchBrowserArtworkSupport.youTubeTabs(NotchBrowserArtworkSupport.openTabs(inSession: json))
        }
        session = (file.url, file.modified, file.size, tabs)
        return tabs.map { (file.modified, $0) }
    }

    private func latestSessionFile(bundle: String) -> (url: URL, modified: Date, size: Int)? {
        guard let folder = NotchBrowserArtworkSupport.profileFolders[bundle],
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let profiles = (try? FileManager.default.contentsOfDirectory(
            at: support.appendingPathComponent(folder, isDirectory: true), includingPropertiesForKeys: nil)) ?? []
        return profiles
            .flatMap { profile in NotchBrowserArtworkSupport.sessionFiles.map { profile.appendingPathComponent($0) } }
            .compactMap { file -> (url: URL, modified: Date, size: Int)? in
                guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let modified = values.contentModificationDate, let size = values.fileSize else { return nil }
                return (file, modified, size)
            }
            .max { $0.modified < $1.modified }
    }

    private func download(_ urls: [URL], for lookup: Lookup, completion: @escaping (Data?) -> Void) {
        guard accepts(lookup) else { return finish(lookup, failed: false) }
        guard let url = urls.first else { return completion(nil) }
        load(url, accept: "image/jpeg", for: lookup) { [self] data in
            if let data, let square = Self.squareCover(data) {
                completion(square)
            } else {
                download(Array(urls.dropFirst()), for: lookup, completion: completion)
            }
        }
    }

    private static func squareCover(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let square = image.cropping(to: NotchBrowserArtworkSupport.centreSquare(
                  width: image.width, height: image.height)) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, square,
                                   [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

private final class NotchBrowserArtworkDownload: NSObject, URLSessionDataDelegate {
    private var data = Data()
    private var accepted = false
    private let completion: (Data?) -> Void
    private init(completion: @escaping (Data?) -> Void) { self.completion = completion }

    static func load(_ url: URL, accept: String, completion: @escaping (Data?) -> Void) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = ["User-Agent": "EVERYTHING", "Accept": accept]
        let delegate = NotchBrowserArtworkDownload(completion: completion)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        session.dataTask(with: url).resume()
        session.finishTasksAndInvalidate()
        return session
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        accepted = (response as? HTTPURLResponse)?.statusCode == 200
            && response.expectedContentLength <= NotchBrowserArtworkSupport.maximumArtworkBytes
        completionHandler(accepted ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard accepted, chunk.count <= NotchBrowserArtworkSupport.maximumArtworkBytes - data.count else {
            accepted = false
            dataTask.cancel()
            return
        }
        data.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        completion(error == nil && accepted ? data : nil)
    }
}
