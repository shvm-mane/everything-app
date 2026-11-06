// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import UniformTypeIdentifiers

enum ShelfSelectionSupport {
    static func isClearSelectionShortcut(keyCode: UInt16,
                                         hasSelectionModifiers: Bool) -> Bool {
        keyCode == 53 && !hasSelectionModifiers
    }

    static func rangeSelectionIDs<ID: Equatable>(allIDs: [ID],
                                                 anchorID: ID?,
                                                 targetID: ID) -> [ID] {
        guard let target = allIDs.firstIndex(of: targetID) else { return [] }
        let anchor = anchorID.flatMap { allIDs.firstIndex(of: $0) } ?? target
        let bounds = min(anchor, target)...max(anchor, target)
        return Array(allIDs[bounds])
    }
}

struct ShelfShortcutSelectionRequests {
    enum Outcome: Equatable {
        case discard
        case toggle
        case add([URL])
    }

    private var lastTicket: UInt64 = 0
    private var pendingTicket: UInt64?

    var hasPending: Bool { pendingTicket != nil }

    mutating func begin() -> UInt64 {
        lastTicket &+= 1
        pendingTicket = lastTicket
        return lastTicket
    }

    mutating func invalidate() {
        pendingTicket = nil
    }

    mutating func resolve(_ ticket: UInt64, urls: [URL], stillAllowed: Bool,
                          shelvedPaths: Set<String> = []) -> Outcome {
        guard ticket == pendingTicket else { return .discard }
        pendingTicket = nil
        guard stillAllowed else { return .discard }
        let fresh = urls.filter { !shelvedPaths.contains($0.standardizedFileURL.path) }
        return fresh.isEmpty ? .toggle : .add(fresh)
    }
}

struct ShelfRevealNode: Equatable {
    let id: UUID
    let children: [ShelfRevealNode]

    init(id: UUID, children: [ShelfRevealNode] = []) {
        self.id = id
        self.children = children
    }
}

enum ShelfRevealSupport {
    static func visibleAncestorID(of target: UUID,
                                  in nodes: [ShelfRevealNode],
                                  expanded: Set<UUID>) -> UUID? {
        for node in nodes {
            if node.id == target { return node.id }
            guard !node.children.isEmpty else { continue }
            guard let deeper = visibleAncestorID(of: target,
                                                 in: node.children,
                                                 expanded: expanded) else { continue }
            return expanded.contains(node.id) ? deeper : node.id
        }
        return nil
    }

    static func shouldReveal(serial: Int, lastHonored: Int?) -> Bool {
        serial != lastHonored
    }
}

enum ShelfTileLayout {
    static func columnCount(contentWidth: CGFloat,
                            tileWidth: CGFloat,
                            spacing: CGFloat,
                            inset: CGFloat) -> Int {
        let usable = contentWidth - inset * 2 + spacing
        return max(1, Int(usable / (tileWidth + spacing)))
    }

    static func rowCount(contentHeight: CGFloat,
                         tileHeight: CGFloat,
                         spacing: CGFloat,
                         inset: CGFloat) -> Int {
        let usable = contentHeight - inset * 2 + spacing
        return max(1, Int(usable / (tileHeight + spacing)))
    }

    static func sidewaysTileFrame(index: Int,
                                  rows: Int,
                                  tileSize: CGSize,
                                  spacing: CGFloat,
                                  inset: CGFloat) -> CGRect {
        let safeRows = max(1, rows)
        let column = index / safeRows
        let row = index % safeRows
        return CGRect(x: inset + CGFloat(column) * (tileSize.width + spacing),
                      y: inset + CGFloat(row) * (tileSize.height + spacing),
                      width: tileSize.width,
                      height: tileSize.height)
    }

    static func sidewaysDocumentSize(itemCount: Int,
                                     rows: Int,
                                     visibleSize: CGSize,
                                     tileSize: CGSize,
                                     spacing: CGFloat,
                                     inset: CGFloat) -> CGSize {
        let safeRows = max(1, rows)
        let columns = max(1, Int(ceil(Double(itemCount) / Double(safeRows))))
        let filledRows = min(safeRows, max(1, itemCount))
        let width = inset * 2 + CGFloat(columns) * tileSize.width + CGFloat(columns - 1) * spacing
        let height = inset * 2 + CGFloat(filledRows) * tileSize.height + CGFloat(filledRows - 1) * spacing
        return CGSize(width: max(width, visibleSize.width), height: max(height, visibleSize.height))
    }

    static func tileFrame(index: Int,
                          columns: Int,
                          tileSize: CGSize,
                          spacing: CGFloat,
                          inset: CGFloat) -> CGRect {
        let safeColumns = max(1, columns)
        let column = index % safeColumns
        let row = index / safeColumns
        return CGRect(x: inset + CGFloat(column) * (tileSize.width + spacing),
                      y: inset + CGFloat(row) * (tileSize.height + spacing),
                      width: tileSize.width,
                      height: tileSize.height)
    }
}

enum ShelfInteractionSupport {
    static func allowsAutomaticOpen(sourceBundleIdentifier: String?,
                                    excludedBundleIdentifiers: Set<String>) -> Bool {
        guard let sourceBundleIdentifier, !sourceBundleIdentifier.isEmpty else { return true }
        return !excludedBundleIdentifiers.contains(sourceBundleIdentifier)
    }

    static func isContentDrag(gestureChangeCount: Int,
                              restingChangeCount: Int,
                              changeCount: Int,
                              beganInDock: Bool,
                              hasDroppableContent: () -> Bool) -> Bool {
        let baseline = beganInDock ? restingChangeCount : gestureChangeCount
        guard changeCount != baseline else { return false }
        return hasDroppableContent()
    }

    static func shouldCloseAfterDrag(dropAccepted: Bool,
                                     draggedItemCount: Int,
                                     closeAfterDrop: Bool,
                                     pinned: Bool) -> Bool {
        dropAccepted && draggedItemCount > 0 && closeAfterDrop && !pinned
    }

    static func shouldRemoveAfterDrag(dropAccepted: Bool,
                                      draggedItemCount: Int,
                                      removeAfterDrop: Bool) -> Bool {
        dropAccepted && draggedItemCount > 0 && removeAfterDrop
    }

    static func removableAfterDrag(_ draggedIDs: [UUID], protectedIDs: Set<UUID>) -> [UUID] {
        draggedIDs.filter { !protectedIDs.contains($0) }
    }

    static func offersMoveOutside(removeAfterDrop: Bool, dragIncludesPinned: Bool,
                                  dragIncludesPackageContent: Bool) -> Bool {
        removeAfterDrop && !dragIncludesPinned && !dragIncludesPackageContent
    }

    static func isInsidePackage(_ url: URL, isPackage: (URL) -> Bool) -> Bool {
        var directory = url.standardizedFileURL.deletingLastPathComponent().resolvingSymlinksInPath()
        while directory.path != "/", !directory.path.isEmpty {
            if isPackage(directory) { return true }
            directory = directory.deletingLastPathComponent()
        }
        return false
    }

    static func editableImage(in urls: [URL]) -> URL? {
        guard urls.count == 1, let url = urls.first,
              UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .image) == true
        else { return nil }
        return url
    }
}

enum ShelfPasteboardSupport {
    static func mergedItemIndices(companionPositions: [Int], receiverIndices: [Int],
                                  promisePositions: [Int]) -> [Int] {
        let positions = companionPositions + receiverIndices.map { index in
            promisePositions.indices.contains(index) ? promisePositions[index] : Int.max
        }
        return positions.indices.sorted {
            positions[$0] == positions[$1] ? $0 < $1 : positions[$0] < positions[$1]
        }
    }

    static let filePromiseTypeIdentifiers: Set<String> = {
        var ids = Set(NSFilePromiseReceiver.readableDraggedTypes)
        ids.formUnion(["Apple files promise pasteboard type",
                       "com.apple.pasteboard.promised-file-url",
                       "com.apple.pasteboard.promised-file-content-type"])
        return ids
    }()

    private static let directDroppableTypes: Set<String> = [
        NSPasteboard.PasteboardType.fileURL.rawValue,
        NSPasteboard.PasteboardType.string.rawValue,
        NSPasteboard.PasteboardType.tiff.rawValue,
        NSPasteboard.PasteboardType.png.rawValue,
        UTType.gif.identifier,
        UTType.fileURL.identifier,
        UTType.image.identifier,
        UTType.url.identifier,
        UTType.text.identifier,
        UTType.plainText.identifier,
        "NSFilenamesPboardType",
        "NSURLPboardType"
    ]

    private static let supportedUTTypes: [UTType] = [
        .fileURL, .gif, .image, .url, .text, .plainText
    ]

    static func isFilePromiseType(_ rawValue: String) -> Bool {
        filePromiseTypeIdentifiers.contains(rawValue)
    }

    static func isDroppablePasteboardType(_ rawValue: String) -> Bool {
        if isFilePromiseType(rawValue) { return true }
        if directDroppableTypes.contains(rawValue) { return true }
        guard let utType = UTType(rawValue) else { return false }
        return supportedUTTypes.contains { utType.conforms(to: $0) }
    }

}

enum ShelfTooltipLeafKind {
    case image, file, note, link
}

struct ShelfTooltipPileBreakdown: Equatable {
    var images = 0
    var files = 0
    var notes = 0
    var links = 0

    var total: Int { images + files + notes + links }
}

struct ShelfTooltipStrings {
    let itemsFormat: String
    let itemsFew: String
    let imageSingular: String
    let imageFew: String
    let imagePlural: String
    let fileSingular: String
    let fileFew: String
    let filePlural: String
    let noteSingular: String
    let noteFew: String
    let notePlural: String
    let linkSingular: String
    let linkFew: String
    let linkPlural: String
    let agreement: CountAgreement

    enum Form { case one, few, many }

    func form(for count: Int) -> Form {
        let magnitude = abs(count)
        switch agreement {
        case .oneAndMany:
            return magnitude == 1 ? .one : .many
        case .byWholeNumber:
            if magnitude == 1 { return .one }
            return (2...4).contains(magnitude) ? .few : .many
        case .byLastDigits:
            if (11...14).contains(magnitude % 100) { return .many }
            switch magnitude % 10 {
            case 1: return .one
            case 2, 3, 4: return .few
            default: return .many
            }
        }
    }
}

enum ShelfTooltipSupport {
    static let textCap = 500

    static func text(forFileNamed title: String, resolvedKind: String?) -> String {
        guard let resolvedKind, !resolvedKind.isEmpty else { return title }
        return "\(title)\n\(resolvedKind)"
    }

    static func text(forText string: String, cap: Int = textCap) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > cap else { return trimmed }
        return String(trimmed.prefix(cap)) + "…"
    }

    static func text(forLink url: URL, cap: Int = textCap) -> String {
        let string = url.absoluteString
        guard string.count > cap else { return string }
        return String(string.prefix(cap)) + "…"
    }

    static func breakdown(of kinds: [ShelfTooltipLeafKind]) -> ShelfTooltipPileBreakdown {
        var result = ShelfTooltipPileBreakdown()
        for kind in kinds {
            switch kind {
            case .image: result.images += 1
            case .file: result.files += 1
            case .note: result.notes += 1
            case .link: result.links += 1
            }
        }
        return result
    }

    static func text(forPile breakdown: ShelfTooltipPileBreakdown, strings: ShelfTooltipStrings) -> String {
        var parts: [String] = []
        func worded(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
            switch strings.form(for: count) {
            case .one: return String(format: one, count)
            case .few: return String(format: few, count)
            case .many: return String(format: many, count)
            }
        }
        if breakdown.images > 0 {
            parts.append(worded(breakdown.images,
                                strings.imageSingular, strings.imageFew, strings.imagePlural))
        }
        if breakdown.files > 0 {
            parts.append(worded(breakdown.files,
                                strings.fileSingular, strings.fileFew, strings.filePlural))
        }
        if breakdown.notes > 0 {
            parts.append(worded(breakdown.notes,
                                strings.noteSingular, strings.noteFew, strings.notePlural))
        }
        if breakdown.links > 0 {
            parts.append(worded(breakdown.links,
                                strings.linkSingular, strings.linkFew, strings.linkPlural))
        }
        let itemsText = strings.form(for: breakdown.total) == .few
            ? String(format: strings.itemsFew, breakdown.total)
            : String(format: strings.itemsFormat, breakdown.total)
        guard !parts.isEmpty else { return itemsText }
        return "\(itemsText): \(parts.joined(separator: ", "))"
    }
}

enum ShelfEdge: Equatable {
    case left, right
}

struct ShelfEdgeMatch: Equatable {
    let edge: ShelfEdge
    let screen: CGRect
}

struct ShelfEdgeScreen: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
}

enum ShelfEdgeDragSupport {
    static let triggerDistance: CGFloat = 200
    static let retreatDistance: CGFloat = 330
    static let dwell: TimeInterval = 0.15

    static func match(at point: CGPoint, screens: [ShelfEdgeScreen], distance: CGFloat) -> ShelfEdgeMatch? {
        let ordered = screens.enumerated().sorted {
            distanceSquared(from: point, to: $0.element.frame) < distanceSquared(from: point, to: $1.element.frame)
        }
        for (index, screen) in ordered {
            let frame = screen.frame
            guard frame.width > 0, frame.height > 0,
                  point.x >= frame.minX - distance, point.x <= frame.maxX + distance,
                  point.y >= frame.minY - distance, point.y <= frame.maxY + distance
            else { continue }
            let others = screens.enumerated().compactMap { $0.offset == index ? nil : $0.element.frame }
            let nearLeft = point.x <= frame.minX + distance
                && point.x >= screen.visibleFrame.minX
                && !hasNeighbor(at: CGPoint(x: frame.minX - distance - 1, y: point.y), frames: others)
            if nearLeft { return ShelfEdgeMatch(edge: .left, screen: frame) }
            let nearRight = point.x >= frame.maxX - distance
                && point.x <= screen.visibleFrame.maxX
                && !hasNeighbor(at: CGPoint(x: frame.maxX + distance + 1, y: point.y), frames: others)
            if nearRight { return ShelfEdgeMatch(edge: .right, screen: frame) }
        }
        return nil
    }

    static func stillNear(_ match: ShelfEdgeMatch, point: CGPoint, distance: CGFloat) -> Bool {
        let withinHeight = point.y >= match.screen.minY - distance && point.y <= match.screen.maxY + distance
        guard withinHeight else { return false }
        switch match.edge {
        case .left: return point.x <= match.screen.minX + distance
        case .right: return point.x >= match.screen.maxX - distance
        }
    }

    static func hasDwelled(since: TimeInterval, now: TimeInterval, required: TimeInterval = dwell) -> Bool {
        now - since >= required
    }

    private static func distanceSquared(from point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return dx * dx + dy * dy
    }

    private static func hasNeighbor(at point: CGPoint, frames: [CGRect]) -> Bool {
        frames.contains { $0.insetBy(dx: -1, dy: -1).contains(point) }
    }
}

enum ShelfDockPlacement: String {
    case menuBar, topCenter

    static func current(in defaults: UserDefaults = .standard) -> Self {
        guard !NotchSupport.isEnabled(in: defaults),
              defaults.string(forKey: DefaultsKey.shelfDockPlacement) == Self.topCenter.rawValue
        else { return .menuBar }
        return .topCenter
    }

    func frame(size: CGSize, visible: CGRect, safeTop: CGFloat, anchor: CGRect?) -> CGRect {
        var x = self == .topCenter
            ? visible.midX - size.width / 2
            : anchor.map { $0.midX - size.width / 2 } ?? (visible.maxX - size.width - 12)
        x = min(max(visible.minX + 8, x), visible.maxX - size.width - 8)
        let top = self == .topCenter ? min(visible.maxY - 4, safeTop) : visible.maxY - 4
        return CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }
}

enum ShelfDockDragSupport {
    static let dwell: TimeInterval = 0.15

    static let triggerMargin: CGFloat = 16

    static let retreatMargin: CGFloat = 32

    static func triggerFrame(pillFrame: CGRect?,
                             anchorFrame: CGRect?,
                             screenFrame: CGRect?) -> CGRect? {
        if let pillFrame, pillFrame.width > 0, pillFrame.height > 0 {
            let padded = pillFrame.insetBy(dx: -triggerMargin, dy: -triggerMargin)
            if let anchorFrame, anchorFrame.width > 0, anchorFrame.height > 0 {
                return padded.union(anchorFrame.insetBy(dx: -triggerMargin, dy: 0))
            }
            return padded
        }
        if let anchorFrame, anchorFrame.width > 0, anchorFrame.height > 0 {
            let fallbackHeight: CGFloat = 32
            let pillY = anchorFrame.minY - 4 - fallbackHeight
            let estimatedPill = CGRect(x: anchorFrame.midX - 36,
                                       y: pillY,
                                       width: 72,
                                       height: fallbackHeight)
            return estimatedPill.insetBy(dx: -triggerMargin, dy: -triggerMargin).union(anchorFrame)
        }
        return nil
    }

    static func isPointNearDock(point: CGPoint,
                                isProximate: Bool,
                                panelFrame: CGRect?,
                                anchorFrame: CGRect?,
                                screenFrame: CGRect?) -> Bool {
        if isProximate, let panelFrame, panelFrame.width > 0, panelFrame.height > 0 {
            return panelFrame.insetBy(dx: -retreatMargin, dy: -retreatMargin).contains(point)
        }
        guard let target = triggerFrame(pillFrame: panelFrame,
                                       anchorFrame: anchorFrame,
                                       screenFrame: screenFrame) else {
            return false
        }
        return target.contains(point)
    }

    static func hasDwelled(since: TimeInterval, now: TimeInterval, required: TimeInterval = dwell) -> Bool {
        now - since >= required
    }
}

struct ShelfPersistedItem: Codable, Equatable {
    enum Kind: String, Codable {
        case file, text, link, batch
    }

    let id: UUID
    let kind: Kind
    let title: String
    var text: String?
    var url: String?
    var path: String?
    var bookmark: Data?
    var children: [ShelfPersistedItem]?
    var pinned: Bool?

    init(id: UUID,
         kind: Kind,
         title: String,
         text: String? = nil,
         url: String? = nil,
         path: String? = nil,
         bookmark: Data? = nil,
         children: [ShelfPersistedItem]? = nil,
         pinned: Bool? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.url = url
        self.path = path
        self.bookmark = bookmark
        self.children = children
        self.pinned = pinned == true ? true : nil
    }
}

extension ShelfPersistedItem {
    private enum CodingKeys: String, CodingKey {
        case id, kind, title, text, url, path, bookmark, children, pinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  kind: try container.decode(Kind.self, forKey: .kind),
                  title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
                  text: try container.decodeIfPresent(String.self, forKey: .text),
                  url: try container.decodeIfPresent(String.self, forKey: .url),
                  path: try container.decodeIfPresent(String.self, forKey: .path),
                  bookmark: try container.decodeIfPresent(Data.self, forKey: .bookmark),
                  children: try container.decodeIfPresent([FailableShelfPersistedItem].self, forKey: .children)?
                      .compactMap(\.value),
                  pinned: try container.decodeIfPresent(Bool.self, forKey: .pinned))
    }
}

private struct FailableShelfPersistedItem: Decodable {
    let value: ShelfPersistedItem?

    init(from decoder: Decoder) throws {
        value = try? ShelfPersistedItem(from: decoder)
    }
}

enum ShelfStoreLoad: Equatable {
    case items([ShelfPersistedItem])
    case partial([ShelfPersistedItem])
    case unreadable
}

enum ShelfPersistenceSupport {
    static let maxLeaves = 200
    static let maxTextLength = 200_000
    static let maxDepth = 4

    static func load(_ data: Data?) -> ShelfStoreLoad {
        guard let data else { return .items([]) }
        guard let decoded = try? JSONDecoder().decode([FailableShelfPersistedItem].self,
                                                      from: data) else { return .unreadable }
        let items = decoded.compactMap(\.value)
        if !decoded.isEmpty, items.isEmpty { return .unreadable }
        let stored = storedEntryCount(try? JSONSerialization.jsonObject(with: data))
        return stored == readEntryCount(items) ? .items(items) : .partial(items)
    }

    private static func storedEntryCount(_ json: Any?) -> Int {
        guard let entries = json as? [Any] else { return 0 }
        return entries.reduce(0) { total, entry in
            total + 1 + storedEntryCount((entry as? [String: Any])?["children"])
        }
    }

    private static func readEntryCount(_ items: [ShelfPersistedItem]) -> Int {
        items.reduce(0) { $0 + 1 + readEntryCount($1.children ?? []) }
    }

    static func boundedLiveText(_ text: String) -> String? {
        let bounded = String(text.prefix(maxTextLength))
        guard !bounded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return bounded
    }

    static func canAdd(existingLeaves: Int, newLeaves: Int) -> Bool {
        existingLeaves >= 0 && newLeaves > 0 && existingLeaves <= maxLeaves - newLeaves
    }

    static func containsKeptFile(under path: String, keptPaths: Set<String>) -> Bool {
        let path = URL(fileURLWithPath: path).standardizedFileURL.path
        return keptPaths.contains(path) || keptPaths.contains { $0.hasPrefix(path + "/") }
    }

    static func writeGeneratedFile(_ data: Data, named name: String, in store: URL,
                                   container: URL? = PrivateFileStore.containerURL) -> URL? {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else { return nil }
        let directory = store.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard PrivateFileStore.createDirectory(at: directory, container: container) else { return nil }
        let url = directory.appendingPathComponent(name)
        guard PrivateFileStore.write(data, to: url) else {
            try? FileManager.default.removeItem(at: directory)
            return nil
        }
        return url
    }

    static func discardablePayloadPaths(candidatePaths: [String],
                                        referencedPaths: Set<String>) -> Set<String> {
        Set(candidatePaths).subtracting(referencedPaths)
    }

    static func needsPersistAfterRestore(restoredIsEmpty: Bool, liveItemCount: Int) -> Bool {
        restoredIsEmpty || liveItemCount > 0
    }

    static func sanitized(_ items: [ShelfPersistedItem],
                          fileExists: (String) -> Bool,
                          resolveBookmark: (Data) -> String? = { _ in nil }) -> [ShelfPersistedItem] {
        var remainingLeaves = maxLeaves
        return sanitized(items, depth: 0, remainingLeaves: &remainingLeaves,
                         fileExists: fileExists, resolveBookmark: resolveBookmark)
    }

    static func unmountedVolumeRoot(of path: String) -> String? {
        let components = (path as NSString).pathComponents
        guard components.count > 2, components[0] == "/", components[1] == "Volumes" else {
            return nil
        }
        return "/Volumes/" + components[2]
    }

    private static func sanitized(_ items: [ShelfPersistedItem],
                                  depth: Int,
                                  remainingLeaves: inout Int,
                                  fileExists: (String) -> Bool,
                                  resolveBookmark: (Data) -> String?) -> [ShelfPersistedItem] {
        guard depth < maxDepth else { return [] }
        var result: [ShelfPersistedItem] = []
        for item in items {
            guard remainingLeaves > 0 else { break }
            switch item.kind {
            case .file:
                guard let path = item.path, !path.isEmpty else { continue }
                var keptPath = path
                var keptTitle = item.title
                if !fileExists(path) {
                    guard let bookmark = item.bookmark,
                          let healed = resolveBookmark(bookmark),
                          fileExists(healed) else { continue }
                    keptPath = healed
                    keptTitle = (healed as NSString).lastPathComponent
                }
                remainingLeaves -= 1
                result.append(ShelfPersistedItem(id: item.id, kind: .file, title: keptTitle,
                                                 path: keptPath, bookmark: item.bookmark,
                                                 pinned: item.pinned))
            case .text:
                guard let text = item.text,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                remainingLeaves -= 1
                result.append(ShelfPersistedItem(id: item.id, kind: .text, title: item.title,
                                                 text: String(text.prefix(maxTextLength)),
                                                 pinned: item.pinned))
            case .link:
                guard let raw = item.url, let url = URL(string: raw),
                      url.scheme != nil, !url.isFileURL else { continue }
                remainingLeaves -= 1
                result.append(ShelfPersistedItem(id: item.id, kind: .link, title: item.title, url: raw,
                                                 pinned: item.pinned))
            case .batch:
                let children = sanitized(item.children ?? [], depth: depth + 1,
                                         remainingLeaves: &remainingLeaves,
                                         fileExists: fileExists, resolveBookmark: resolveBookmark)
                if children.isEmpty { continue }
                if children.count == 1 {
                    var survivor = children[0]
                    if item.pinned == true { survivor.pinned = true }
                    result.append(survivor)
                    continue
                }
                result.append(ShelfPersistedItem(id: item.id, kind: .batch, title: item.title,
                                                 children: children, pinned: item.pinned))
            }
        }
        return result
    }
}
