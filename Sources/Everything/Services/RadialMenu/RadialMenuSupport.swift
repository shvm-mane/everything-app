// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

enum RadialMenuColor: String, Codable, CaseIterable, Identifiable {
    case accent, blue, purple, pink, red, orange, yellow, green, mint, cyan, indigo, graphite

    var id: String { rawValue }

    func color(for scheme: ColorScheme) -> Color {
        switch self {
        case .accent: return .accentColor
        case .blue: return scheme == .light ? Color(red: 0.00, green: 0.48, blue: 1.00) : .blue
        case .purple: return scheme == .light ? Color(red: 0.58, green: 0.20, blue: 0.85) : .purple
        case .pink: return scheme == .light ? Color(red: 0.88, green: 0.16, blue: 0.45) : .pink
        case .red: return scheme == .light ? Color(red: 0.85, green: 0.18, blue: 0.18) : .red
        case .orange: return scheme == .light ? Color(red: 0.95, green: 0.45, blue: 0.00) : .orange
        case .yellow: return scheme == .light ? Color(red: 0.85, green: 0.65, blue: 0.00) : .yellow
        case .green: return scheme == .light ? Color(red: 0.18, green: 0.65, blue: 0.25) : .green
        case .mint: return scheme == .light ? Color(red: 0.00, green: 0.68, blue: 0.60) : .mint
        case .cyan: return scheme == .light ? Color(red: 0.15, green: 0.65, blue: 0.85) : .cyan
        case .indigo: return scheme == .light ? Color(red: 0.35, green: 0.35, blue: 0.85) : .indigo
        case .graphite: return scheme == .light ? Color(white: 0.40) : Color(white: 0.65)
        }
    }

    var baseColor: Color {
        switch self {
        case .accent: return .accentColor
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .cyan: return .cyan
        case .indigo: return .indigo
        case .graphite: return .gray
        }
    }

    func title(_ strings: RadialMenuFeatureStrings) -> String {
        switch self {
        case .accent: return strings.colorAccent
        case .blue: return strings.colorBlue
        case .purple: return strings.colorPurple
        case .pink: return strings.colorPink
        case .red: return strings.colorRed
        case .orange: return strings.colorOrange
        case .yellow: return strings.colorYellow
        case .green: return strings.colorGreen
        case .mint: return strings.colorMint
        case .cyan: return strings.colorCyan
        case .indigo: return strings.colorIndigo
        case .graphite: return strings.colorGraphite
        }
    }
}

struct RadialMenuProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var color: RadialMenuColor = .accent
    var shortcut: String = ""
    var mouseButton: String = RadialMenuMouseTrigger.off.rawValue
    var items: [RadialMenuItem] = []
    var preset: String?
    var trackpadTap = false

    func displayName(_ text: RadialMenuFeatureStrings) -> String {
        name.isEmpty ? text.presetGeneral : name
    }

    func duplicate(named name: String) -> RadialMenuProfile {
        var copy = self
        copy.id = UUID()
        copy.name = name
        copy.shortcut = ""
        copy.mouseButton = RadialMenuMouseTrigger.off.rawValue
        copy.trackpadTap = false
        return copy
    }
}

extension RadialMenuProfile {
    private enum CodingKeys: String, CodingKey {
        case id, name, color, shortcut, mouseButton, items, preset, trackpadTap
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
                  color: try container.decodeIfPresent(RadialMenuColor.self, forKey: .color) ?? .accent,
                  shortcut: try container.decodeIfPresent(String.self, forKey: .shortcut) ?? "",
                  mouseButton: try container.decodeIfPresent(String.self, forKey: .mouseButton) ?? RadialMenuMouseTrigger.off.rawValue,
                  items: try container.decodeIfPresent([FailableRadialMenuItem].self, forKey: .items)?
                      .compactMap(\.value) ?? [],
                  preset: try container.decodeIfPresent(String.self, forKey: .preset),
                  trackpadTap: try container.decodeIfPresent(Bool.self, forKey: .trackpadTap) ?? false)
    }
}

private struct FailableRadialMenuProfile: Decodable {
    let value: RadialMenuProfile?

    init(from decoder: Decoder) throws {
        value = try? RadialMenuProfile(from: decoder)
    }
}

private struct RadialMenuProfileTriggers: Decodable {
    let mouseButton: String?
    let trackpadTap: Bool

    private enum CodingKeys: String, CodingKey { case mouseButton, trackpadTap }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        mouseButton = (try? container?.decodeIfPresent(String.self, forKey: .mouseButton)) ?? nil
        trackpadTap = (try? container?.decodeIfPresent(Bool.self, forKey: .trackpadTap)) ?? false
    }
}

enum RadialMenuProfilePreset: String, CaseIterable, Identifiable {
    case general, media, tools, windowLayout, quickToggles, blank

    var id: String { rawValue }

    func title(_ strings: RadialMenuFeatureStrings) -> String {
        switch self {
        case .general: return strings.presetGeneral
        case .media: return strings.presetMedia
        case .tools: return strings.presetTools
        case .windowLayout: return strings.presetWindowLayout
        case .quickToggles: return strings.presetQuickToggles
        case .blank: return strings.presetBlank
        }
    }

    var defaultColor: RadialMenuColor {
        switch self {
        case .general: return .accent
        case .media: return .purple
        case .tools: return .cyan
        case .windowLayout: return .orange
        case .quickToggles: return .mint
        case .blank: return .graphite
        }
    }

    func makeItems() -> [RadialMenuItem] {
        switch self {
        case .general:
            return RadialMenuSupport.starterItems
        case .media:
            return [
                RadialMenuItem(kind: .media, payload: RadialMenuMediaKey.playPause.rawValue),
                RadialMenuItem(kind: .media, payload: RadialMenuMediaKey.nextTrack.rawValue),
                RadialMenuItem(kind: .media, payload: RadialMenuMediaKey.nowPlaying.rawValue),
                RadialMenuItem(kind: .media, payload: RadialMenuMediaKey.previousTrack.rawValue),
            ]
        case .tools:
            return [
                RadialMenuItem(kind: .tool, payload: RadialMenuTool.screenshot.rawValue),
                RadialMenuItem(kind: .tool, payload: RadialMenuTool.colorPicker.rawValue),
                RadialMenuItem(kind: .tool, payload: RadialMenuTool.screenOCR.rawValue),
                RadialMenuItem(kind: .tool, payload: RadialMenuTool.screenRecorder.rawValue),
                RadialMenuItem(kind: .tool, payload: RadialMenuTool.micMute.rawValue),
                RadialMenuItem(kind: .tool, payload: RadialMenuTool.scratchpad.rawValue),
            ]
        case .windowLayout:
            return [
                RadialMenuItem(kind: .windowLayout, payload: WindowLayoutAction.maximize.rawValue),
                RadialMenuItem(kind: .windowLayout, payload: WindowLayoutAction.rightHalf.rawValue),
                RadialMenuItem(kind: .windowLayout, payload: WindowLayoutAction.bottomHalf.rawValue),
                RadialMenuItem(kind: .windowLayout, payload: WindowLayoutAction.leftHalf.rawValue),
                RadialMenuItem(kind: .windowLayout, payload: WindowLayoutAction.topHalf.rawValue),
            ]
        case .quickToggles:
            return [
                RadialMenuItem(kind: .quickToggle, payload: RadialMenuQuickToggle.darkMode.rawValue),
                RadialMenuItem(kind: .quickToggle, payload: RadialMenuQuickToggle.desktopIcons.rawValue),
                RadialMenuItem(kind: .quickToggle, payload: RadialMenuQuickToggle.hiddenFiles.rawValue),
                RadialMenuItem(kind: .quickToggle, payload: RadialMenuQuickToggle.lockScreen.rawValue),
                RadialMenuItem(kind: .quickToggle, payload: RadialMenuQuickToggle.emptyTrash.rawValue),
            ]
        case .blank:
            return []
        }
    }

    func createProfile(name: String? = nil,
                       color: RadialMenuColor? = nil,
                       shortcut: String = "",
                       mouseButton: String = RadialMenuMouseTrigger.off.rawValue) -> RadialMenuProfile {
        RadialMenuProfile(id: UUID(),
                           name: name ?? "",
                           color: color ?? defaultColor,
                           shortcut: shortcut,
                           mouseButton: mouseButton,
                           items: makeItems(),
                           preset: rawValue)
    }
}

struct RadialMenuItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case app, file, url, shortcut, tool, quickToggle, windowLayout, media, submenu
    }

    var id = UUID()
    var kind = Kind.app
    var name = ""
    var symbolName = ""
    var payload = ""
    var customIconData: Data? = nil
    var children: [RadialMenuItem] = []

    var tool: RadialMenuTool? {
        kind == .tool ? RadialMenuTool(rawValue: payload) : nil
    }

    var mediaKey: RadialMenuMediaKey? {
        kind == .media ? RadialMenuMediaKey(rawValue: payload) : nil
    }

    var quickToggle: RadialMenuQuickToggle? {
        kind == .quickToggle ? RadialMenuQuickToggle(rawValue: payload) : nil
    }

    var windowLayoutAction: WindowLayoutAction? {
        kind == .windowLayout ? WindowLayoutAction(rawValue: payload) : nil
    }

    var defaultSymbolName: String {
        switch kind {
        case .app: return "app"
        case .file: return "folder"
        case .url: return "link"
        case .shortcut: return "command"
        case .tool: return tool?.symbolName ?? "wrench.and.screwdriver"
        case .quickToggle: return quickToggle?.symbolName ?? "togglepower"
        case .windowLayout: return windowLayoutAction?.symbolName ?? AppFeature.windowLayout.symbolName
        case .media:
            switch mediaKey {
            case .previousTrack: return "backward.fill"
            case .nextTrack: return "forward.fill"
            case .nowPlaying: return "music.note"
            default: return "playpause.fill"
            }
        case .submenu: return "ellipsis.circle"
        }
    }

    var effectiveSymbolName: String {
        symbolName.isEmpty ? defaultSymbolName : symbolName
    }
}

enum RadialMenuQuickToggle: String, Codable, CaseIterable, Identifiable {
    case darkMode, emptyTrash, quitAllApps, ejectDisks, hiddenFiles, desktopIcons,
         lockScreen, displayOff, screenSaver

    var id: String { rawValue }

    var feature: AppFeature {
        self == .quitAllApps ? .quitApps : .quickToggles
    }

    var symbolName: String {
        switch self {
        case .darkMode: return "moon.fill"
        case .emptyTrash: return "trash"
        case .quitAllApps: return "xmark.app"
        case .ejectDisks: return "eject.fill"
        case .hiddenFiles: return "eye"
        case .desktopIcons: return "desktopcomputer"
        case .lockScreen: return "lock.fill"
        case .displayOff: return "display"
        case .screenSaver: return "sparkles.tv"
        }
    }
}

extension RadialMenuItem {
    private enum CodingKeys: String, CodingKey {
        case id, kind, name, symbolName, payload, customIconData, children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  kind: try container.decode(Kind.self, forKey: .kind),
                  name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
                  symbolName: try container.decodeIfPresent(String.self, forKey: .symbolName) ?? "",
                  payload: try container.decodeIfPresent(String.self, forKey: .payload) ?? "",
                  customIconData: try container.decodeIfPresent(Data.self, forKey: .customIconData),
                  children: try container.decodeIfPresent([FailableRadialMenuItem].self, forKey: .children)?
                      .compactMap(\.value) ?? [])
    }
}

private struct FailableRadialMenuItem: Decodable {
    let value: RadialMenuItem?

    init(from decoder: Decoder) throws {
        value = try? RadialMenuItem(from: decoder)
    }
}

enum RadialMenuTool: String, Codable, CaseIterable, Identifiable {
    case screenshot, screenRecorder, colorPicker, screenOCR, micMute, clipboardHistory, quickLauncher,
         cameraPreview, scratchpad, shelf, cleaner, uninstaller, appUpdates, cleaningMode, keepAwake

    var id: String { rawValue }

    var title: String {
        self == .colorPicker ? "Color Picker" : rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    var feature: AppFeature {
        switch self {
        case .screenshot: return .screenshot
        case .screenRecorder: return .screenRecorder
        case .colorPicker: return .colorPicker
        case .screenOCR: return .screenOCR
        case .micMute: return .micMute
        case .clipboardHistory: return .clipboardHistory
        case .quickLauncher: return .quickLauncher
        case .cameraPreview: return .cameraPreview
        case .scratchpad: return .scratchpad
        case .shelf: return .shelf
        case .cleaner: return .cleaner
        case .uninstaller: return .uninstaller
        case .appUpdates: return .appUpdates
        case .cleaningMode: return .cleaningMode
        case .keepAwake: return .keepAwake
        }
    }

    var symbolName: String { feature.symbolName }

    func isRunnable(isFeatureAvailable: (AppFeature) -> Bool = { $0.isAvailable },
                    boolFor: (String) -> Bool = { UserDefaults.standard.bool(forKey: $0) }) -> Bool {
        guard isFeatureAvailable(feature) else { return false }
        return self != .shelf || boolFor(DefaultsKey.shelfEnabled)
    }
}

enum RadialMenuMouseTrigger: Equatable, Identifiable {
    case off
    case button(Int64)

    static let back = button(MouseButtonShortcutSupport.backButtonNumber)
    static let forward = button(MouseButtonShortcutSupport.forwardButtonNumber)

    var id: String { rawValue }

    var rawValue: String {
        switch self {
        case .off: return "off"
        case .button(let number):
            if number == MouseButtonShortcutSupport.backButtonNumber { return "back" }
            if number == MouseButtonShortcutSupport.forwardButtonNumber { return "forward" }
            return "button:\(number)"
        }
    }

    var buttonNumber: Int64? {
        guard case .button(let number) = self else { return nil }
        return number
    }

    static func sanitized(_ raw: String?) -> RadialMenuMouseTrigger {
        switch raw {
        case "back": return .back
        case "forward": return .forward
        case let value?:
            guard value.hasPrefix("button:"),
                  let number = Int64(value.dropFirst("button:".count)),
                  MouseButtonShortcutSupport.buttonRange.contains(number) else { return .off }
            return .button(number)
        default: return .off
        }
    }
}

enum RadialMenuActivationMode: String, CaseIterable, Identifiable {
    case pressOrHold
    case press
    case hold

    var id: String { rawValue }

    static func sanitized(_ raw: String?) -> RadialMenuActivationMode {
        RadialMenuActivationMode(rawValue: raw ?? "") ?? .pressOrHold
    }

    func startsHeld(requestedHold: Bool, hasHeldButton: Bool,
                    shortcutHasModifiers: Bool) -> Bool {
        guard self != .press else { return false }
        return hasHeldButton || (requestedHold && shortcutHasModifiers)
    }

    func releaseAction(hasSelection: Bool) -> RadialMenuReleaseAction {
        if hasSelection { return .select }
        return self == .hold ? .dismiss : .stayOpen
    }
}

enum RadialMenuReleaseAction: Equatable {
    case stayOpen, dismiss, select
}

extension RadialMenuSupport {
    static func shortcutIsStillHeld(modifiersHeld: Bool, superKeyHeld: Bool) -> Bool {
        modifiersHeld || superKeyHeld
    }

    static func claimsMouseButton(_ button: Int64) -> Bool {
        claimsMouseButton(button, defaults: .standard)
    }

    static func claimsMouseButton(_ button: Int64, defaults: UserDefaults) -> Bool {
        guard defaults.bool(forKey: AppFeature.radialMenu.availabilityKey),
              defaults.bool(forKey: DefaultsKey.radialMenuEnabled) else { return false }
        return claimedMouseButtons(defaults.data(forKey: DefaultsKey.radialMenuProfiles),
                                   defaults: defaults).contains(button)
    }
}

enum RadialMenuMediaKey: String, Codable, CaseIterable, Identifiable {
    case playPause, previousTrack, nextTrack, nowPlaying

    var id: String { rawValue }

    var auxKeyType: Int32? {
        switch self {
        case .playPause: return 16
        case .previousTrack: return 20
        case .nextTrack: return 19
        case .nowPlaying: return nil
        }
    }
}

struct RadialNowPlayingSnapshot: Equatable {
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: Data?
    let appBundleIdentifier: String?
    let appPID: Int32?

    var radialLabel: String? {
        let parts = [title, artist].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

enum RadialNowPlayingState: Equatable {
    case loading
    case nothingPlaying
    case playing(RadialNowPlayingSnapshot)
}

enum RadialNowPlayingSupport {
    static let titleKey = "kMRMediaRemoteNowPlayingInfoTitle"
    static let artistKey = "kMRMediaRemoteNowPlayingInfoArtist"
    static let albumKey = "kMRMediaRemoteNowPlayingInfoAlbum"
    static let artworkDataKey = "kMRMediaRemoteNowPlayingInfoArtworkData"
    static let playbackRateKey = "kMRMediaRemoteNowPlayingInfoPlaybackRate"

    private static let forbiddenScalars = CharacterSet.controlCharacters.union(.newlines)
    static let maximumArtworkBytes = 12 * 1_024 * 1_024
    static let maximumAdapterReplyBytes = maximumArtworkBytes / 3 * 4 + 1_024 * 1_024

    static func playbackIsActive(remoteIsPlaying: Bool?, info: [String: Any]) -> Bool {
        if let remoteIsPlaying { return remoteIsPlaying }
        return (info[playbackRateKey] as? NSNumber)?.doubleValue ?? 0 > 0
    }

    struct AdapterReply {
        let info: [String: Any]
        let pid: Int32
        let displayID: String?
        let isPlaying: Bool?
    }

    static func adapterReply(from data: Data) -> AdapterReply? {
        let blank: Set<UInt8> = [0x20, 0x09, 0x0D]
        guard let line = data.split(separator: 0x0A).last(where: { $0.contains { !blank.contains($0) } }),
              let object = try? JSONSerialization.jsonObject(with: line),
              let fields = object as? [String: Any],
              fields["error"] == nil else { return nil }
        var info: [String: Any] = [:]
        for key in [titleKey, artistKey, albumKey] {
            if let value = fields[key] as? String { info[key] = value }
        }
        for key in [playbackRateKey, "kMRMediaRemoteNowPlayingInfoDuration",
                    "kMRMediaRemoteNowPlayingInfoElapsedTime"] {
            if let value = fields[key] as? NSNumber { info[key] = value }
        }
        if fields["artworkUnchanged"] as? Bool == true { info["artworkUnchanged"] = true }
        for key in ["canSeek", "canSkipNext", "canSkipPrevious"] {
            if let value = fields[key] as? Bool { info[key] = value }
        }
        if let identifier = fields["itemIdentifier"] as? String, !identifier.isEmpty,
           identifier.utf8.count <= 512, !identifier.contains("\0") { info["itemIdentifier"] = identifier }
        if let artwork = fields["artworkBase64"] as? String,
           let bytes = Data(base64Encoded: artwork), !bytes.isEmpty {
            info[artworkDataKey] = bytes
        }
        return AdapterReply(info: info,
                            pid: (fields["pid"] as? NSNumber)?.int32Value ?? 0,
                            displayID: fields["displayID"] as? String,
                            isPlaying: fields["isPlaying"] as? Bool)
    }

    static func snapshot(info: [String: Any],
                         isPlaying: Bool,
                         appBundleIdentifier: String?,
                         appPID: Int32) -> RadialNowPlayingSnapshot? {
        guard isPlaying else { return nil }
        let title = sanitizedText(info[titleKey])
        let artist = sanitizedText(info[artistKey])
        let album = sanitizedText(info[albumKey])
        let bundleIdentifier = sanitizedBundleIdentifier(appBundleIdentifier)
        let pid = appPID > 0 ? appPID : nil
        let artworkData = sanitizedArtworkData(info[artworkDataKey])
        guard title != nil || bundleIdentifier != nil || pid != nil else { return nil }
        return RadialNowPlayingSnapshot(title: title,
                                        artist: artist,
                                        album: album,
                                        artworkData: artworkData,
                                        appBundleIdentifier: bundleIdentifier,
                                        appPID: pid)
    }

    private static func sanitizedText(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let clean = String(String.UnicodeScalarView(
            trimmed.unicodeScalars.filter { !forbiddenScalars.contains($0) }))
        return clean.isEmpty ? nil : String(clean.prefix(300))
    }

    private static func sanitizedBundleIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 255,
              !trimmed.unicodeScalars.contains(where: { forbiddenScalars.contains($0) })
        else { return nil }
        return trimmed
    }

    private static func sanitizedArtworkData(_ value: Any?) -> Data? {
        guard let data = value as? Data, !data.isEmpty, data.count <= maximumArtworkBytes else {
            return nil
        }
        return data
    }
}

enum RadialMenuSupport {
    static let sessionMoveMask: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDragged, .otherMouseDragged,
    ]

    static let maxItemsPerWheel = 12
    static let maxDepth = 2

    static let symbolNames = [
        "star.fill", "heart.fill", "bolt.fill", "flame.fill", "sparkles",
        "folder.fill", "doc.fill", "tray.full.fill", "terminal.fill", "globe",
        "envelope.fill", "message.fill", "music.note", "headphones", "camera.fill",
        "photo.fill", "video.fill", "gamecontroller.fill", "calendar", "clock.fill",
        "house.fill", "cart.fill", "hammer.fill", "paintbrush.fill", "book.fill",
        "keyboard", "magnifyingglass", "airplane",
        "checkmark.circle.fill", "xmark.circle.fill", "plus.circle.fill", "minus.circle.fill",
        "exclamationmark.triangle.fill", "questionmark.circle.fill", "info.circle.fill",
        "lock.fill", "lock.open.fill", "key.fill", "person.fill", "person.2.fill",
        "bell.fill", "flag.fill", "bookmark.fill", "tag.fill",
        "paperclip", "link", "scissors", "doc.on.clipboard",
        "square.and.arrow.up", "square.and.arrow.down", "trash.fill", "archivebox.fill",
        "externaldrive.fill", "internaldrive.fill", "display", "desktopcomputer",
        "laptopcomputer", "iphone", "ipad", "applewatch",
        "wifi", "network", "antenna.radiowaves.left.and.right",
        "speaker.wave.2.fill", "mic.fill", "waveform",
        "play.fill", "pause.fill", "stop.fill", "backward.fill", "forward.fill",
        "shuffle", "repeat",
        "sun.max.fill", "moon.fill", "lightbulb.fill", "battery.100", "power",
        "eye.fill", "eye.slash.fill", "location.fill", "map.fill",
        "paperplane.fill", "bubble.left.fill", "phone.fill",
        "gearshape.fill", "slider.horizontal.3", "switch.2", "command",
        "printer.fill", "textformat", "number",
    ]

    static func isValidPayload(_ item: RadialMenuItem) -> Bool {
        switch item.kind {
        case .app, .file: return !item.payload.isEmpty
        case .url: return normalizedURL(item.payload) != nil
        case .shortcut: return GlobalShortcut(storageValue: item.payload) != nil
        case .tool: return item.tool != nil
        case .quickToggle: return item.quickToggle != nil
        case .windowLayout: return item.windowLayoutAction != nil
        case .media: return item.mediaKey != nil
        case .submenu: return true
        }
    }

    static func sanitized(_ items: [RadialMenuItem], depth: Int = 0) -> [RadialMenuItem] {
        guard depth < maxDepth else { return [] }
        var seen = Set<UUID>()
        var result: [RadialMenuItem] = []
        for var item in items {
            guard result.count < maxItemsPerWheel, seen.insert(item.id).inserted else { continue }
            item.name = String(item.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
            item.payload = item.payload.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidPayload(item) else { continue }
            if item.kind == .url, let normalized = normalizedURL(item.payload) {
                item.payload = normalized
            }
            if let customData = item.customIconData {
                if customData.count > RadialMenuFaviconFetcher.maxStoredIconBytes || NSImage(data: customData) == nil {
                    item.customIconData = nil
                }
            }
            if item.kind == .submenu {
                guard depth + 1 < maxDepth else { continue }
                item.children = sanitized(item.children, depth: depth + 1)
            } else {
                item.children = []
            }
            result.append(item)
        }
        return result
    }

    static func decode(_ data: Data?) -> [RadialMenuItem] {
        guard let data else { return starterItems }
        let decoded = (try? JSONDecoder().decode([FailableRadialMenuItem].self, from: data)) ?? []
        return sanitized(decoded.compactMap(\.value))
    }

    static func encode(_ items: [RadialMenuItem]) -> Data? {
        try? JSONEncoder().encode(sanitized(items))
    }

    static func normalizedURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if hasExplicitScheme(trimmed) {
            guard let url = URL(string: trimmed) else { return nil }
            if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                return url.host != nil ? trimmed : nil
            }
            return trimmed
        }
        let candidate = "https://" + trimmed
        guard let url = URL(string: candidate), url.host != nil else { return nil }
        return candidate
    }

    private static func hasExplicitScheme(_ value: String) -> Bool {
        if value.contains("://") { return true }
        guard value.first?.isLetter == true,
              let colon = value.firstIndex(of: ":"),
              value[..<colon].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." })
        else { return false }
        let after = value.index(after: colon)
        guard after < value.endIndex else { return false }
        guard value[after].isNumber else { return true }
        let prefix = value[..<colon]
        return !prefix.contains(".") && prefix.lowercased() != "localhost"
    }

    static let starterItems: [RadialMenuItem] = [
        RadialMenuItem(kind: .tool, payload: RadialMenuTool.colorPicker.rawValue),
        RadialMenuItem(kind: .file, payload: "~/Downloads"),
        RadialMenuItem(kind: .file, payload: "/Applications"),
        RadialMenuItem(kind: .file, payload: "~/Desktop"),
        RadialMenuItem(kind: .url, name: "GitHub", payload: "https://github.com"),
    ]

    static func needsAccessibility(_ items: [RadialMenuItem]) -> Bool {
        items.contains { item in
            switch item.kind {
            case .shortcut, .windowLayout: return true
            case .media: return item.mediaKey?.auxKeyType != nil
            case .submenu: return needsAccessibility(item.children)
            default: return false
            }
        }
    }

    static func needsAccessibility(_ profiles: [RadialMenuProfile]) -> Bool {
        profiles.contains { profile in
            RadialMenuMouseTrigger.sanitized(profile.mouseButton) != .off
                || profile.trackpadTap
                || needsAccessibility(profile.items)
        }
    }

    static func hasTrigger(_ profile: RadialMenuProfile) -> Bool {
        GlobalShortcut(storageValue: profile.shortcut) != nil
            || RadialMenuMouseTrigger.sanitized(profile.mouseButton) != .off
            || profile.trackpadTap
    }

    static func assigning(mouseButton raw: String, to profileID: UUID,
                          in profiles: [RadialMenuProfile]) -> [RadialMenuProfile] {
        let button = RadialMenuMouseTrigger.sanitized(raw).buttonNumber
        return profiles.map { profile in
            var profile = profile
            if profile.id == profileID {
                profile.mouseButton = raw
            } else if let button,
                      RadialMenuMouseTrigger.sanitized(profile.mouseButton).buttonNumber == button {
                profile.mouseButton = RadialMenuMouseTrigger.off.rawValue
            }
            return profile
        }
    }

    static func claimedMouseButtons(_ data: Data?, defaults: UserDefaults = .standard) -> [Int64] {
        if let data, let decoded = try? JSONDecoder().decode([RadialMenuProfileTriggers].self, from: data) {
            return decoded.compactMap { RadialMenuMouseTrigger.sanitized($0.mouseButton).buttonNumber }
        }
        let legacy = RadialMenuMouseTrigger.sanitized(
            defaults.string(forKey: DefaultsKey.radialMenuMouseButton))
        return legacy.buttonNumber.map { [$0] } ?? []
    }

    static func opensFromMouseOrTrackpad(_ data: Data?, defaults: UserDefaults = .standard) -> Bool {
        if let data, let decoded = try? JSONDecoder().decode([RadialMenuProfileTriggers].self, from: data) {
            return decoded.contains {
                RadialMenuMouseTrigger.sanitized($0.mouseButton) != .off || $0.trackpadTap
            }
        }
        return RadialMenuMouseTrigger.sanitized(
            defaults.string(forKey: DefaultsKey.radialMenuMouseButton)) != .off
    }

    static func decodeProfiles(_ data: Data?, defaults: UserDefaults = .standard) -> [RadialMenuProfile] {
        var profiles = decodeStoredProfiles(data, defaults: defaults)
        for index in profiles.indices {
            profiles[index].shortcut = ""
            profiles[index].mouseButton = RadialMenuMouseTrigger.off.rawValue
            profiles[index].items = profiles[index].items.filter(\.isEverythingKind)
        }
        if !profiles.isEmpty, !profiles.contains(where: \.trackpadTap) { profiles[0].trackpadTap = true }
        return profiles
    }

    private static func decodeStoredProfiles(_ data: Data?, defaults: UserDefaults) -> [RadialMenuProfile] {
        if let data, let decoded = try? JSONDecoder().decode([FailableRadialMenuProfile].self, from: data) {
            let sanitized = sanitizedProfiles(decoded.compactMap(\.value))
            if !sanitized.isEmpty { return sanitized }
        }
        let legacyItemsData = defaults.data(forKey: DefaultsKey.radialMenuItems)
        let legacyShortcut = ""
        let legacyMouseButton = defaults.string(forKey: DefaultsKey.radialMenuMouseButton)
            ?? RadialMenuMouseTrigger.off.rawValue

        let items = decode(legacyItemsData)
        let initialProfile = RadialMenuProfile(
            id: UUID(),
            name: "",
            color: .accent,
            shortcut: legacyShortcut,
            mouseButton: legacyMouseButton,
            items: items,
            preset: RadialMenuProfilePreset.general.rawValue
        )
        return [initialProfile]
    }

    static func profileShortcuts(defaults: UserDefaults = .standard) -> [GlobalShortcut] {
        decodeProfiles(defaults.data(forKey: DefaultsKey.radialMenuProfiles), defaults: defaults)
            .compactMap { GlobalShortcut(storageValue: $0.shortcut) }
    }

    static func profile(using shortcut: GlobalShortcut, in profiles: [RadialMenuProfile],
                        excluding profileID: UUID) -> RadialMenuProfile? {
        profiles.first { $0.id != profileID && GlobalShortcut(storageValue: $0.shortcut) == shortcut }
    }

    static func encodeProfiles(_ profiles: [RadialMenuProfile]) -> Data? {
        try? JSONEncoder().encode(sanitizedProfiles(profiles))
    }

    static func sanitizedProfiles(_ profiles: [RadialMenuProfile]) -> [RadialMenuProfile] {
        var seenIDs = Set<UUID>()
        var seenButtons = Set<Int64>()
        var result: [RadialMenuProfile] = []
        for var profile in profiles {
            guard seenIDs.insert(profile.id).inserted else { continue }
            profile.name = String(profile.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
            profile.items = sanitized(profile.items)
            profile.shortcut = profile.shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
            if !profile.shortcut.isEmpty && GlobalShortcut(storageValue: profile.shortcut) == nil {
                profile.shortcut = ""
            }
            profile.mouseButton = RadialMenuMouseTrigger.sanitized(profile.mouseButton).rawValue
            if let button = RadialMenuMouseTrigger.sanitized(profile.mouseButton).buttonNumber,
               !seenButtons.insert(button).inserted {
                profile.mouseButton = RadialMenuMouseTrigger.off.rawValue
            }
            result.append(profile)
        }
        if result.isEmpty {
            result.append(RadialMenuProfilePreset.general.createProfile(shortcut: GlobalShortcut.radialMenuDefault.storageValue))
        }
        return result
    }

    static func containsNowPlaying(_ items: [RadialMenuItem]) -> Bool {
        items.contains { item in
            item.mediaKey == .nowPlaying
                || (item.kind == .submenu && containsNowPlaying(item.children))
        }
    }

    static func usesWindowLayout(_ items: [RadialMenuItem]) -> Bool {
        items.contains { item in
            item.kind == .windowLayout
                || (item.kind == .submenu && usesWindowLayout(item.children))
        }
    }
}

enum RadialMenuLayout {
    static let panelSize: CGFloat = 320
    static let wheelDiameter: CGFloat = 240
    static let ringRadius: CGFloat = 86
    static let chipSize: CGFloat = 42
    static let hubDiameter: CGFloat = 76
    static let deadZoneRadius: CGFloat = 38
    static let moveActivationDistance: CGFloat = 8
}

enum RadialMenuGeometry {
    static func angle(dx: CGFloat, dyUp: CGFloat) -> CGFloat {
        let raw = atan2(dx, dyUp)
        return raw < 0 ? raw + 2 * .pi : raw
    }

    static func index(forAngle angle: CGFloat, itemCount: Int) -> Int? {
        guard itemCount > 0 else { return nil }
        let step = 2 * .pi / CGFloat(itemCount)
        let shifted = (angle + step / 2).truncatingRemainder(dividingBy: 2 * .pi)
        let index = Int(shifted / step)
        return min(max(index, 0), itemCount - 1)
    }

    static func highlightedIndex(dx: CGFloat, dyUp: CGFloat,
                                 deadZoneRadius: CGFloat, itemCount: Int) -> Int? {
        guard itemCount > 0 else { return nil }
        let distance = (dx * dx + dyUp * dyUp).squareRoot()
        guard distance >= deadZoneRadius else { return nil }
        return index(forAngle: angle(dx: dx, dyUp: dyUp), itemCount: itemCount)
    }

    static func unitPosition(index: Int, itemCount: Int) -> (dx: CGFloat, dyUp: CGFloat) {
        guard itemCount > 0 else { return (0, 1) }
        let theta = 2 * .pi * CGFloat(index) / CGFloat(itemCount)
        return (sin(theta), cos(theta))
    }
}

enum RadialMenuFaviconFetcher {
    static let maxStoredIconBytes = 65536
    static let maxDownloadBytes = 2 * 1_024 * 1_024
    static let maxSourceDimension = 4_096
    static let maxSourcePixels = 16_777_216

    static func fetchFavicon(for rawURL: String, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let normalized = RadialMenuSupport.normalizedURL(rawURL), let page = URL(string: normalized),
              let fallback = faviconURL(for: rawURL) else {
            DispatchQueue.main.async { completion(.failure(FaviconError.invalidURL)) }
            return
        }
        FaviconDownload(url: page, byteLimit: maxDownloadBytes, accept: "text/html") { result in
            var candidates: [URL] = []
            if case let .success(html) = result, let text = String(data: html.prefix(512 * 1024), encoding: .utf8)
                ?? String(data: html.prefix(512 * 1024), encoding: .isoLatin1) {
                candidates = linkedIcons(in: text, base: page)
            }
            let root = fallback.deletingLastPathComponent()
            candidates += [root.appendingPathComponent("apple-touch-icon.png"), fallback]
            tryCandidates(candidates, completion: completion)
        }.start()
    }

    private static func tryCandidates(_ urls: [URL], completion: @escaping (Result<Data, Error>) -> Void) {
        guard let url = urls.first else {
            DispatchQueue.main.async { completion(.failure(FaviconError.notFound)) }
            return
        }
        FaviconDownload(url: url, byteLimit: maxDownloadBytes, accept: "image/*") { result in
            if case let .success(data) = result, sourceDimensionsAreSafe(data),
               let image = NSImage(data: data), image.size.width > 0, image.size.height > 0,
               let png = scaledPNGData(from: image) {
                DispatchQueue.main.async { completion(.success(png)) }
            } else {
                tryCandidates(Array(urls.dropFirst()), completion: completion)
            }
        }.start()
    }

    static func linkedIcons(in html: String, base: URL) -> [URL] {
        guard let tag = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: .caseInsensitive) else { return [] }
        func attribute(_ name: String, in text: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: "\\b\(name)\\s*=\\s*[\"']([^\"']+)[\"']",
                                                       options: .caseInsensitive),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
        var found: [(url: URL, score: Int)] = []
        for match in tag.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let range = Range(match.range, in: html) else { continue }
            let text = String(html[range])
            guard let rel = attribute("rel", in: text)?.lowercased(), rel.contains("icon"), !rel.contains("mask"),
                  let href = attribute("href", in: text), let url = URL(string: href, relativeTo: base)?.absoluteURL,
                  url.scheme == "https" || url.scheme == "http" else { continue }
            let size = attribute("sizes", in: text).flatMap { Int($0.lowercased().split(separator: "x").first ?? "") } ?? 0
            let svg = url.pathExtension.lowercased() == "svg"
            found.append((url, svg ? -1 : (rel.contains("apple") ? 1000 : 0) + size))
        }
        return found.sorted { $0.score > $1.score }.map(\.url)
    }

    static func faviconURL(for rawURL: String) -> URL? {
        guard let normalized = RadialMenuSupport.normalizedURL(rawURL),
              let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        components.user = nil
        components.password = nil
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func sourceDimensionsAreSafe(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0,
              width <= maxSourceDimension, height <= maxSourceDimension,
              width <= maxSourcePixels / height
        else { return false }
        return true
    }

    static func scaledPNGData(from image: NSImage, targetSize: CGFloat = 64) -> Data? {
        let size = NSSize(width: targetSize, height: targetSize)
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()

        guard let tiffData = newImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return png.count <= maxStoredIconBytes ? png : nil
    }

    enum FaviconError: Error {
        case invalidURL
        case notFound
    }

    private struct Origin: Equatable {
        let scheme: String
        let host: String
        let port: Int

        init?(_ url: URL) {
            guard let scheme = url.scheme?.lowercased(),
                  let host = url.host?.lowercased() else { return nil }
            self.scheme = scheme
            self.host = host
            port = url.port ?? (scheme == "https" ? 443 : 80)
        }
    }

    private final class FaviconDownload: NSObject, URLSessionDataDelegate {
        private let url: URL
        private let byteLimit: Int
        private let completion: (Result<Data, Error>) -> Void
        private let origin: Origin
        private var session: URLSession?
        private var data = Data()
        private var finished = false

        private let accept: String

        init(url: URL, byteLimit: Int, accept: String = "image/*", completion: @escaping (Result<Data, Error>) -> Void) {
            self.url = url
            self.byteLimit = byteLimit
            self.accept = accept
            self.completion = completion
            origin = Origin(url)!
        }

        func start() {
            var request = URLRequest(url: url,
                                     cachePolicy: .reloadIgnoringLocalCacheData,
                                     timeoutInterval: 5)
            request.setValue(accept, forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                             forHTTPHeaderField: "User-Agent")
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 5
            let session = URLSession(configuration: configuration,
                                     delegate: self,
                                     delegateQueue: nil)
            self.session = session
            session.dataTask(with: request).resume()
        }

        func urlSession(_ session: URLSession,
                        dataTask: URLSessionDataTask,
                        didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  response.expectedContentLength <= 0
                    || response.expectedContentLength <= Int64(byteLimit)
            else {
                completionHandler(.cancel)
                finish(.failure(FaviconError.notFound))
                return
            }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession,
                        dataTask: URLSessionDataTask,
                        didReceive chunk: Data) {
            guard data.count + chunk.count <= byteLimit else {
                dataTask.cancel()
                finish(.failure(FaviconError.notFound))
                return
            }
            data.append(chunk)
        }

        func urlSession(_ session: URLSession,
                        task: URLSessionTask,
                        willPerformHTTPRedirection newResponse: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            guard let redirectURL = request.url, let next = Origin(redirectURL),
                  next.host.siteRoot == origin.host.siteRoot else {
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }

        func urlSession(_ session: URLSession,
                        task: URLSessionTask,
                        didCompleteWithError error: Error?) {
            if let error {
                finish(.failure(error))
            } else {
                finish(.success(data))
            }
        }

        private func finish(_ result: Result<Data, Error>) {
            guard !finished else { return }
            finished = true
            session?.finishTasksAndInvalidate()
            session = nil
            completion(result)
        }
    }
}

extension RadialMenuItem {
    var isEverythingKind: Bool {
        switch kind {
        case .file, .url: return true
        case .tool: return RadialMenuTool(rawValue: payload) == .colorPicker
        default: return false
        }
    }
}

private extension String {
    var siteRoot: String { split(separator: ".").suffix(2).joined(separator: ".") }
}
