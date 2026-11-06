// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchArtworkTint: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    static func from(red: Double, green: Double, blue: Double) -> NotchArtworkTint? {
        let channels = [red, green, blue]
        guard channels.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }),
              let highest = channels.max(), let lowest = channels.min(),
              highest > 0.05 else { return nil }
        let range = highest - lowest
        guard range / highest >= 0.12 else { return nil }
        let stretched = channels.map { min(1, max(0, ($0 - lowest) / range * 0.86 + 0.06)) }
        return NotchArtworkTint(red: stretched[0], green: stretched[1], blue: stretched[2])
    }
}

struct NotchPlayback: Equatable {
    static let gapGracePeriod: TimeInterval = 1.5

    let track: RadialNowPlayingSnapshot
    let isPlaying: Bool
    let elapsed: TimeInterval
    let duration: TimeInterval
    let rate: Double
    let sampledAt: Date
    let canSeek: Bool
    var hasPosition: Bool = true
    var itemIdentifier: String? = nil
    var commandContext: NotchPlaybackContext? = nil
    var canSendCommandsDirectly = false
    var canSkipNext: Bool? = nil
    var canSkipPrevious: Bool? = nil

    static func sameRecording(_ first: NotchPlayback?, _ second: NotchPlayback?) -> Bool {
        first?.commandContext == second?.commandContext && first?.track.appPID == second?.track.appPID
    }

    func position(at date: Date) -> TimeInterval {
        min(duration, max(0, elapsed + (isPlaying ? max(0, date.timeIntervalSince(sampledAt)) * rate : 0)))
    }

    func seekPosition(_ proposed: Double, allowed: Bool? = nil) -> Double? {
        guard allowed ?? canSeek, duration > 0, proposed.isFinite else { return nil }
        return min(duration, max(0, proposed))
    }

    static func decode(_ data: Data, now: Date = Date(), previousArtwork: Data? = nil,
                       commandContext: NotchPlaybackContext? = nil,
                       canSendCommandsDirectly: Bool = false) -> NotchPlayback? {
        guard let reply = RadialNowPlayingSupport.adapterReply(from: data) else { return nil }
        var info = reply.info
        if info["artworkUnchanged"] as? Bool == true {
            info[RadialNowPlayingSupport.artworkDataKey] = previousArtwork
        }
        guard let track = RadialNowPlayingSupport.snapshot(
                info: info, isPlaying: true,
                appBundleIdentifier: reply.displayID, appPID: reply.pid) else { return nil }
        func seconds(_ key: String) -> Double {
            guard let value = (reply.info[key] as? NSNumber)?.doubleValue,
                  value.isFinite, value >= 0 else { return 0 }
            return min(value, 7 * 24 * 60 * 60)
        }
        let rawRate = (reply.info[RadialNowPlayingSupport.playbackRateKey] as? NSNumber)?.doubleValue
        let rate: Double
        if let rawRate, rawRate.isFinite { rate = min(16, max(0, rawRate)) }
        else { rate = 1 }
        return NotchPlayback(track: track,
                             isPlaying: RadialNowPlayingSupport.playbackIsActive(
                                remoteIsPlaying: reply.isPlaying, info: reply.info),
                             elapsed: seconds("kMRMediaRemoteNowPlayingInfoElapsedTime"),
                             duration: seconds("kMRMediaRemoteNowPlayingInfoDuration"),
                             rate: rate, sampledAt: now,
                             canSeek: reply.info["canSeek"] as? Bool == true,
                             hasPosition: (reply.info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)
                                .map { $0.doubleValue.isFinite && $0.doubleValue >= 0 } == true,
                             itemIdentifier: reply.info["itemIdentifier"] as? String,
                             commandContext: commandContext?.pid == track.appPID ? commandContext : nil,
                             canSendCommandsDirectly: canSendCommandsDirectly,
                             canSkipNext: reply.info["canSkipNext"] as? Bool,
                             canSkipPrevious: reply.info["canSkipPrevious"] as? Bool)
    }
}

struct NotchArtworkCache<Artwork> {
    static var transitionDuration: TimeInterval { 1.5 }
    private struct Identity: Equatable {
        let pid: Int32?
        let bundle: String?
        let item: String?
        let title: String?
        let artist: String?
        let album: String?

        init(_ playback: NotchPlayback) {
            pid = playback.track.appPID
            bundle = playback.track.appBundleIdentifier
            item = playback.itemIdentifier
            title = playback.track.title
            artist = playback.track.artist
            album = playback.track.album
        }
    }

    private var identity: Identity?
    private var artworkData: Data?
    private var inheritedUntil: Date?
    private(set) var artwork: Artwork?
    private(set) var expiresAt: Date?

    mutating func update(_ incoming: Artwork?, for playback: NotchPlayback?, now: Date = Date()) {
        guard let playback else { self = Self(); return }
        let next = Identity(playback)
        if identity?.pid != next.pid || identity?.bundle != next.bundle { self = Self() }
        if identity != next || inheritedUntil.map({ now >= $0 }) == true { inheritedUntil = nil }
        if let incoming {
            if artworkData == nil || playback.track.artworkData != artworkData {
                inheritedUntil = nil
            } else if identity != next {
                inheritedUntil = now.addingTimeInterval(Self.transitionDuration)
            }
            artwork = incoming
            identity = next
            artworkData = playback.track.artworkData
            expiresAt = nil
        } else if identity == next, inheritedUntil == nil {
            expiresAt = nil
        } else if artwork != nil {
            if expiresAt == nil { expiresAt = inheritedUntil ?? now.addingTimeInterval(Self.transitionDuration) }
            expire(at: now)
        }
    }

    mutating func expire(at now: Date = Date()) {
        guard let expiresAt, now >= expiresAt else { return }
        self = Self()
    }
}

struct NotchTrackChange {
    private struct Song {
        let title: String
        let artist: String?

        func matches(_ other: Song) -> Bool {
            title == other.title && (artist == nil || other.artist == nil || artist == other.artist)
        }
    }

    private var songs: [String: Song] = [:]

    mutating func isNewSong(_ playback: NotchPlayback?, first: Bool) -> Bool {
        guard let playback, let player = Self.player(of: playback), let song = Self.song(of: playback) else { return false }
        guard !first else { songs[player] = song; return false }
        guard playback.isPlaying else { return false }
        guard let previous = songs.updateValue(song, forKey: player) else { return false }
        return !previous.matches(song)
    }

    static func isBetweenSongs(_ next: NotchPlayback?, after current: NotchPlayback,
                               sources: [NotchPlaybackSource] = []) -> Bool {
        guard let next else { return true }
        guard current.isPlaying, !next.isPlaying else { return false }
        guard let player = Self.player(of: next), player == Self.player(of: current) else {
            return !sources.contains { $0.pid == current.track.appPID && $0.hasTrack }
        }
        guard let song = Self.song(of: next), let played = Self.song(of: current) else { return true }
        return !song.matches(played)
    }

    mutating func reset() { songs = [:] }

    private static func player(of playback: NotchPlayback) -> String? {
        playback.track.appBundleIdentifier ?? playback.track.appPID.map(String.init)
    }

    private static func song(of playback: NotchPlayback) -> Song? {
        cleaned(playback.track.title).map { Song(title: $0, artist: cleaned(playback.track.artist)) }
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
