// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

enum DockTileResolver {
    static func application(forTileAt index: Int,
                            in items: [AXUIElement],
                            bundlePath: String) -> NSRunningApplication? {
        let instances = runningInstances(bundlePath: bundlePath)
        guard let first = instances.first, items.indices.contains(index) else { return nil }
        let tile = items[index]
        guard instances.count > 1 else {
            return soleInstanceIsBehind(tile, bundlePath: bundlePath, items: { items }) ? first : nil
        }
        return instance(forTile: tile,
                        amongTiles: tiles(in: items, bundlePath: bundlePath, including: tile),
                        instances: instances,
                        bundlePath: bundlePath)
    }

    enum TileResolution {
        case unknown
        case unpaired
        case instance(NSRunningApplication)
    }

    static func resolution(forTile tile: AXUIElement) -> TileResolution {
        guard let url = readURL(tile).url else { return .unknown }
        let bundlePath = url.standardizedFileURL.path
        let instances = runningInstances(bundlePath: bundlePath)
        guard let first = instances.first else { return .unknown }
        guard instances.count > 1 else {
            return soleInstanceIsBehind(tile, bundlePath: bundlePath, items: { dockItems(holding: tile) })
                ? .instance(first) : .unpaired
        }
        let tiles = dockItems(holding: tile).map {
            self.tiles(in: $0, bundlePath: bundlePath, including: tile)
        }
        return instance(forTile: tile, amongTiles: tiles, instances: instances, bundlePath: bundlePath)
            .map { .instance($0) } ?? .unpaired
    }

    private static func dockItems(holding tile: AXUIElement) -> [AXUIElement]? {
        guard let parent = elementAttribute(tile, kAXParentAttribute as String),
              stringAttribute(parent, kAXRoleAttribute as String) == "AXList"
        else { return nil }
        return elementArray(parent, kAXChildrenAttribute as String)
    }

    private static func soleInstanceIsBehind(_ tile: AXUIElement,
                                             bundlePath: String,
                                             items: () -> [AXUIElement]?) -> Bool {
        DockClickSupport.soleInstanceIsBehindTile(
            tileReadsRunning: readRunning(tile).isRunning,
            anotherTileReadsRunning: {
                guard let list = items() else { return false }
                return tiles(in: list, bundlePath: bundlePath, including: tile).tiles
                    .contains { !CFEqual($0, tile) }
            })
    }

    private static func runningInstances(bundlePath: String) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
                && $0.bundleURL?.standardizedFileURL.path == bundlePath
        }
    }

    private struct TileList {
        var tiles: [AXUIElement] = []
        var complete = true
    }

    private static func tiles(in items: [AXUIElement],
                              bundlePath: String,
                              including tile: AXUIElement) -> TileList {
        var list = TileList()
        for item in items {
            if !CFEqual(item, tile) {
                let read = readURL(item)
                if !read.answered { list.complete = false }
                guard read.url?.standardizedFileURL.path == bundlePath else { continue }
            }
            let running = readRunning(item)
            if !running.answered { list.complete = false }
            if running.isRunning { list.tiles.append(item) }
        }
        return list
    }

    private struct TileKey: Equatable {
        let element: AXUIElement
        static func == (lhs: TileKey, rhs: TileKey) -> Bool { CFEqual(lhs.element, rhs.element) }
    }

    private static let pairingLock = NSLock()
    private static var pairings: [String: [DockTilePairing<TileKey>]] = [:]

    private static func instance(forTile tile: AXUIElement,
                                 amongTiles list: TileList?,
                                 instances: [NSRunningApplication],
                                 bundlePath: String) -> NSRunningApplication? {
        let described = instances.map {
            DockAppInstance(pid: $0.processIdentifier,
                            launchTime: DockClickSupport.launchTime(
                                processStartMicroseconds: KillProcessService.startTime(for: $0.processIdentifier),
                                launchDate: $0.launchDate))
        }
        let hit = TileKey(element: tile)
        let paired = pairingLock.withLock { () -> [DockTilePairing<TileKey>] in
            let previous = pairings[bundlePath] ?? []
            let tiles = list?.tiles.map(TileKey.init(element:)) ?? [hit]
            let complete = list?.complete ?? false
            let made = DockClickSupport.pairTiles(tiles,
                                                  instances: described,
                                                  previous: previous,
                                                  complete: complete)
            if DockClickSupport.canPairByOrder(tileCount: tiles.count,
                                               instanceCount: described.count,
                                               complete: complete) {
                pairings[bundlePath] = made
            }
            return made
        }
        guard let pid = paired.first(where: { $0.tile == hit })?.pid else { return nil }
        return instances.first { $0.processIdentifier == pid }
    }

    // MARK: - Accessibility reads

    private static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func elementArray(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let array = value as? [AXUIElement]
        else { return nil }
        return array
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func readRunning(_ element: AXUIElement) -> (isRunning: Bool, answered: Bool) {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, "AXIsApplicationRunning" as CFString, &value) {
        case .success:
            return ((value as? Bool) ?? true, true)
        case .noValue, .attributeUnsupported:
            return (true, true)
        default:
            return (true, false)
        }
    }

    private static func readURL(_ element: AXUIElement) -> (url: URL?, answered: Bool) {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value) {
        case .success:
            guard let value, CFGetTypeID(value) == CFURLGetTypeID() else { return (nil, true) }
            return ((value as! CFURL) as URL, true)
        case .noValue, .attributeUnsupported:
            return (nil, true)
        default:
            return (nil, false)
        }
    }
}
