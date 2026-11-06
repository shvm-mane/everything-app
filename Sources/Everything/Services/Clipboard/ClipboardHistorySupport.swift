// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

enum ClipboardHistoryLayout: String, CaseIterable {
    case cards
    case list

    static func current(in defaults: UserDefaults = .standard) -> ClipboardHistoryLayout {
        defaults.string(forKey: DefaultsKey.clipboardHistoryLayout).flatMap(Self.init(rawValue:)) ?? .list
    }

    var sideArrowsMoveSelection: Bool { self == .cards }
}

enum ClipboardHistoryWindowSizing {
    static let compactDefault = NSSize(width: 560, height: 420)
    static let compactMinimum = NSSize(width: 560, height: 300)
    static let previewExtra = NSSize(width: 280, height: 80)

    static func minimumSize(preview: Bool) -> NSSize {
        NSSize(width: compactMinimum.width + (preview ? previewExtra.width : 0),
               height: compactMinimum.height + (preview ? previewExtra.height : 0))
    }

    static func contentSize(preview: Bool, savedWidth: Double, savedHeight: Double,
                            visibleFrame: NSRect) -> NSSize {
        let minimum = minimumSize(preview: preview)
        let width = savedWidth.isFinite && savedWidth >= compactMinimum.width
            ? CGFloat(savedWidth) : compactDefault.width
        let height = savedHeight.isFinite && savedHeight >= compactMinimum.height
            ? CGFloat(savedHeight) : compactDefault.height
        let requested = NSSize(width: width + (preview ? previewExtra.width : 0),
                               height: height + (preview ? previewExtra.height : 0))
        return constrainedSize(NSSize(width: max(minimum.width, requested.width),
                                      height: max(minimum.height, requested.height)),
                               visibleFrame: visibleFrame)
    }

    static func constrainedSize(_ size: NSSize, visibleFrame: NSRect) -> NSSize {
        NSSize(width: min(size.width, max(1, visibleFrame.width - 32)),
               height: min(size.height, max(1, visibleFrame.height - 32)))
    }

    static func savedCompactSize(from contentSize: NSSize, preview: Bool) -> NSSize? {
        let width = contentSize.width - (preview ? previewExtra.width : 0)
        let height = contentSize.height - (preview ? previewExtra.height : 0)
        guard width.isFinite, height.isFinite,
              width >= compactMinimum.width, height >= compactMinimum.height else { return nil }
        return NSSize(width: width, height: height)
    }
}

struct ClipboardHistoryCaptureState {
    private(set) var generation = 0
    private(set) var inFlight = false
    private(set) var needsBaseline = true

    mutating func restart() {
        generation &+= 1
        needsBaseline = true
    }

    mutating func invalidate() {
        generation &+= 1
    }

    mutating func begin() -> Int? {
        guard !inFlight else { return nil }
        inFlight = true
        generation &+= 1
        return generation
    }

    func accepts(_ token: Int) -> Bool {
        token == generation
    }

    mutating func expire(_ token: Int) {
        if accepts(token) { invalidate() }
    }

    mutating func finish() {
        inFlight = false
    }

    mutating func didBaseline() {
        needsBaseline = false
    }
}

enum ClipboardHistoryPasteRestore {
    static let window: TimeInterval = 3

    static func isWithinWindow(capturedAt: Date, now: Date) -> Bool {
        now >= capturedAt && now.timeIntervalSince(capturedAt) <= window
    }
}

enum ClipboardHistoryChangeCount {
    static func accepted(read: Int, since: Int, last: Int) -> Int? {
        if read < since { return read }
        return read > last ? read : nil
    }
}

enum ClipboardHistoryEntryKind: String, Codable {
    case text
    case image
    case files
}

struct ClipboardHistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    var text: String
    var copiedAt: Date
    var pinnedAt: Date?
    let kind: ClipboardHistoryEntryKind
    let filePaths: [String]
    let imageFile: String?
    let imageHash: String?
    let imageWidth: Int?
    let imageHeight: Int?
    var sourceBundleID: String?

    init(id: UUID = UUID(),
         text: String,
         copiedAt: Date = Date(),
         pinnedAt: Date? = nil,
         kind: ClipboardHistoryEntryKind = .text,
         filePaths: [String] = [],
         imageFile: String? = nil,
         imageHash: String? = nil,
         imageWidth: Int? = nil,
         imageHeight: Int? = nil) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
        self.pinnedAt = pinnedAt
        self.kind = kind
        self.filePaths = filePaths
        self.imageFile = imageFile
        self.imageHash = imageHash
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }

    var isPinned: Bool {
        pinnedAt != nil
    }

    var fileNames: [String] {
        filePaths.map { ($0 as NSString).lastPathComponent }
    }

    var imageDimensionsLabel: String {
        guard let imageWidth, let imageHeight else { return "" }
        return "\(imageWidth)×\(imageHeight)"
    }

    var preview: String {
        switch kind {
        case .text:
            let prefix = text.prefix(ClipboardHistoryEditing.previewCharacters)
            let collapsed = prefix
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let visible = collapsed.isEmpty ? String(prefix) : collapsed
            return prefix.endIndex == text.endIndex ? visible : visible + "…"
        case .image:
            return imageDimensionsLabel
        case .files:
            return fileNames.joined(separator: ", ")
        }
    }

    var cardPreview: String {
        guard kind == .text else { return preview }
        let prefix = text.prefix(ClipboardHistoryEditing.previewCharacters)
        let spaced = prefix
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = spaced.isEmpty ? String(prefix) : spaced
        return prefix.endIndex == text.endIndex ? visible : visible + "…"
    }

    var color: ColorValue? {
        kind == .text ? ColorValue(text: text) : nil
    }

    func menuBarText(maxCharacters: Int) -> String {
        let base: String
        if kind == .image {
            let imageLabel = FeatureStrings.clipboard(L10n.shared.language).imageEntryLabel
            base = "\(imageLabel) · \(imageDimensionsLabel)"
        } else {
            base = preview.components(separatedBy: .newlines).joined(separator: " ")
        }
        guard base.count > maxCharacters else { return base }
        return String(base.prefix(maxCharacters)) + "…"
    }

    func matchesContent(of other: ClipboardHistoryEntry) -> Bool {
        guard kind == other.kind else { return false }
        switch kind {
        case .text: return text == other.text
        case .image: return imageHash != nil && imageHash == other.imageHash
        case .files: return filePaths == other.filePaths
        }
    }

    func searchableText(imageLabel: String) -> String {
        switch kind {
        case .text: return text
        case .image: return "\(imageLabel) png \(imageDimensionsLabel)"
        case .files:
            let names = fileNames.joined(separator: " ")
            let hasImage = filePaths.contains { ClipboardHistoryImageSupport.isImageFileName($0) }
            return hasImage ? "\(imageLabel) \(names)" : names
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, copiedAt, pinnedAt, kind, filePaths, imageFile, imageHash, imageWidth, imageHeight
        case sourceBundleID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decode(String.self, forKey: .text)
        copiedAt = try container.decodeIfPresent(Date.self, forKey: .copiedAt) ?? Date()
        pinnedAt = try container.decodeIfPresent(Date.self, forKey: .pinnedAt)
        kind = try container.decodeIfPresent(ClipboardHistoryEntryKind.self, forKey: .kind) ?? .text
        filePaths = try container.decodeIfPresent([String].self, forKey: .filePaths) ?? []
        imageFile = try container.decodeIfPresent(String.self, forKey: .imageFile)
        imageHash = try container.decodeIfPresent(String.self, forKey: .imageHash)
        imageWidth = try container.decodeIfPresent(Int.self, forKey: .imageWidth)
        imageHeight = try container.decodeIfPresent(Int.self, forKey: .imageHeight)
        sourceBundleID = try container.decodeIfPresent(String.self, forKey: .sourceBundleID)
    }
}

enum ClipboardHistoryEditing {
    static let maxCharacters = 1_000_000
    static let maxStoredTextUTF8Bytes = 64 * 1_024 * 1_024
    static let maxEncodedHistoryBytes = 96 * 1_024 * 1_024
    static let previewCharacters = 2_000
    static let tooltipCharacters = 200

    struct EncodedHistory {
        let entries: [ClipboardHistoryEntry]
        let data: Data
    }

    static func storableText(_ text: String) -> String? {
        guard text.count <= maxCharacters,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }

    static func canSave(original: String, draft: String) -> Bool {
        guard let text = storableText(draft) else { return false }
        return text != original
    }

    static func unpinned(_ entry: ClipboardHistoryEntry, now: Date = Date()) -> ClipboardHistoryEntry {
        var entry = entry
        entry.pinnedAt = nil
        entry.copiedAt = now
        return entry
    }

    static func retainedEntries(_ entries: [ClipboardHistoryEntry],
                                recentLimit: Int,
                                retentionDays: Int = 0,
                                ageExemptIDs: Set<UUID> = [],
                                now: Date = Date(),
                                textByteLimit: Int = maxStoredTextUTF8Bytes) -> [ClipboardHistoryEntry] {
        var remainingBytes = max(0, textByteLimit)
        func retained(_ candidates: [ClipboardHistoryEntry], limit: Int?) -> [ClipboardHistoryEntry] {
            var result: [ClipboardHistoryEntry] = []
            for entry in candidates {
                if let limit, result.count >= limit { break }
                let byteCount = entry.kind == .text ? entry.text.utf8.count : 0
                guard byteCount <= remainingBytes else { continue }
                remainingBytes -= byteCount
                result.append(entry)
            }
            return result
        }
        let pinned = retained(entries.filter(\.isPinned), limit: nil)
        let recentLimitOrNil = recentLimit <= 0 ? nil : recentLimit
        let cutoff = retentionDays > 0
            ? now.addingTimeInterval(-Double(retentionDays) * 86_400)
            : nil
        let recent = retained(entries.filter { entry in
            guard !entry.isPinned else { return false }
            guard let cutoff, !ageExemptIDs.contains(entry.id) else { return true }
            return entry.copiedAt >= cutoff
        }, limit: recentLimitOrNil)
        return pinned + recent
    }

    static func preservesPinnedEntries(from original: [ClipboardHistoryEntry],
                                       in retained: [ClipboardHistoryEntry]) -> Bool {
        let retainedIDs = Set(retained.map(\.id))
        return original.lazy.filter(\.isPinned).allSatisfy { retainedIDs.contains($0.id) }
    }

    static func canLoadEncodedHistory(byteCount: Int?) -> Bool {
        guard let byteCount else { return false }
        return byteCount >= 0 && byteCount <= maxEncodedHistoryBytes
    }

    static func pinnedEntriesFit(_ entries: [ClipboardHistoryEntry],
                                 byteLimit: Int = maxEncodedHistoryBytes) -> Bool {
        let pinned = entries.filter(\.isPinned)
        let rawBound = pinned.reduce(0) { total, entry in
            total + 512 + entry.text.utf8.count + (entry.imageFile?.utf8.count ?? 0)
                + entry.filePaths.reduce(0) { $0 + $1.utf8.count + 3 }
        }
        guard rawBound > (byteLimit - 2) / 6 else { return true }
        let encoder = JSONEncoder()
        var encodedSize = 2
        for (offset, entry) in pinned.enumerated() {
            guard let encoded = try? encoder.encode(entry) else { return false }
            encodedSize += encoded.count + (offset == 0 ? 0 : 1)
            if encodedSize > byteLimit { return false }
        }
        return true
    }

    static func encodedHistory(_ entries: [ClipboardHistoryEntry],
                               byteLimit: Int = maxEncodedHistoryBytes) -> EncodedHistory? {
        guard byteLimit >= 2 else { return nil }
        let encoder = JSONEncoder()
        let ordered = entries.filter(\.isPinned) + entries.filter { !$0.isPinned }
        var retained: [ClipboardHistoryEntry] = []
        var encodedEntries: [Data] = []
        var encodedSize = 2

        for entry in ordered {
            guard let encoded = try? encoder.encode(entry) else { return nil }
            let addedSize = encoded.count + (encodedEntries.isEmpty ? 0 : 1)
            guard encodedSize + addedSize <= byteLimit else { continue }
            retained.append(entry)
            encodedEntries.append(encoded)
            encodedSize += addedSize
        }

        var data = Data(capacity: encodedSize)
        data.append(0x5B)
        for (index, encoded) in encodedEntries.enumerated() {
            if index > 0 { data.append(0x2C) }
            data.append(encoded)
        }
        data.append(0x5D)
        return EncodedHistory(entries: retained, data: data)
    }
}

enum ClipboardImageRecognition {
    static let maxPixels = 24_000_000

    static func decodeMaxPixelSize(width: Int, height: Int) -> Int {
        let longest = max(width, height, 1)
        let pixels = Double(max(width, 1)) * Double(max(height, 1))
        guard pixels > Double(maxPixels) else { return longest }
        return max(1, Int(Double(longest) * (Double(maxPixels) / pixels).squareRoot()))
    }

    static func scaledSize(width: Int, height: Int) -> (width: Int, height: Int)? {
        let longest = max(width, height, 1)
        let side = decodeMaxPixelSize(width: width, height: height)
        guard side < longest else { return nil }
        let shorter = max(1, Int(Double(min(width, height)) * Double(side) / Double(longest)))
        return width >= height ? (width: side, height: shorter) : (width: shorter, height: side)
    }
}

struct ClipboardHistorySearchFolded: Equatable {
    let searchableText: String
    let normalizedText: String
    let words: Set<String>

    init(searchableText: String) {
        self.searchableText = searchableText
        let folded = ClipboardHistorySearch.normalized(searchableText)
        self.normalizedText = folded
        self.words = ClipboardHistorySearch.words(in: folded)
    }
}

struct ClipboardHistorySearchCandidate: Equatable {
    var index: Int
    var text: String {
        didSet {
            normalizedText = ClipboardHistorySearch.normalized(text)
            words = ClipboardHistorySearch.words(in: normalizedText)
        }
    }
    var isPinned: Bool
    private(set) var normalizedText: String
    private(set) var words: Set<String>

    init(index: Int,
         text: String,
         isPinned: Bool,
         normalizedText: String? = nil,
         words: Set<String>? = nil) {
        self.index = index
        self.text = text
        self.isPinned = isPinned
        let folded = normalizedText ?? ClipboardHistorySearch.normalized(text)
        self.normalizedText = folded
        self.words = words ?? ClipboardHistorySearch.words(in: folded)
    }
}

struct ClipboardHistorySearchCache {
    private var foldedEntries: [UUID: ClipboardHistorySearchFolded] = [:]
    private var cachedCandidates: [ClipboardHistorySearchCandidate] = []
    private var cachedStamp: Int?
    private var cachedImageLabel: String?

    var cachedEntryCount: Int { foldedEntries.count }
    var candidateCount: Int { cachedCandidates.count }
    private(set) var foldCount = 0

    mutating func candidates(for entries: [ClipboardHistoryEntry],
                             stamp: Int,
                             imageLabel: String) -> [ClipboardHistorySearchCandidate] {
        if cachedStamp == stamp && cachedImageLabel == imageLabel {
            return cachedCandidates
        }

        if entries.isEmpty {
            clear()
            cachedStamp = stamp
            cachedImageLabel = imageLabel
            return []
        }

        var nextFolded: [UUID: ClipboardHistorySearchFolded] = [:]
        nextFolded.reserveCapacity(entries.count)

        let candidates = entries.enumerated().map { index, entry in
            let searchable = entry.searchableText(imageLabel: imageLabel)
            let folded: ClipboardHistorySearchFolded
            if let existing = foldedEntries[entry.id], existing.searchableText == searchable {
                folded = existing
            } else {
                folded = ClipboardHistorySearchFolded(searchableText: searchable)
                foldCount += 1
            }
            nextFolded[entry.id] = folded
            return ClipboardHistorySearchCandidate(index: index,
                                                   text: searchable,
                                                   isPinned: entry.isPinned,
                                                   normalizedText: folded.normalizedText,
                                                   words: folded.words)
        }

        foldedEntries = nextFolded
        cachedStamp = stamp
        cachedImageLabel = imageLabel
        cachedCandidates = candidates
        return candidates
    }

    mutating func prune(keeping entries: [ClipboardHistoryEntry], imageLabel: String? = nil) {
        if entries.isEmpty {
            clear()
            return
        }
        guard !foldedEntries.isEmpty || !cachedCandidates.isEmpty else { return }
        guard let label = imageLabel ?? cachedImageLabel else { return }
        cachedCandidates.removeAll()
        cachedStamp = nil
        var retained: [UUID: ClipboardHistorySearchFolded] = [:]
        retained.reserveCapacity(foldedEntries.count)
        for entry in entries {
            if let existing = foldedEntries[entry.id],
               existing.searchableText == entry.searchableText(imageLabel: label) {
                retained[entry.id] = existing
            }
        }
        foldedEntries = retained
    }

    func isCached(id: UUID) -> Bool {
        foldedEntries[id] != nil
    }

    mutating func clear() {
        foldedEntries.removeAll()
        cachedCandidates.removeAll()
        cachedStamp = nil
        cachedImageLabel = nil
    }
}

enum ClipboardHistorySearch {
    static func rankedIndexes(candidates: [ClipboardHistorySearchCandidate],
                              matching query: String) -> [Int] {
        let normalizedQuery = normalized(query)
        let tokens = queryTokens(normalizedQuery)
        guard !tokens.isEmpty else { return candidates.map(\.index) }

        return candidates
            .compactMap { candidate -> (index: Int, score: Int, originalOrder: Int)? in
                let text = candidate.normalizedText
                guard tokens.allSatisfy({ text.contains($0) }) else { return nil }
                return (candidate.index,
                        score(for: text,
                              words: candidate.words,
                              normalizedQuery: normalizedQuery,
                              tokens: tokens,
                              isPinned: candidate.isPinned),
                        candidate.index)
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.originalOrder < $1.originalOrder
            }
            .map(\.index)
    }

    static func matches(_ text: String, query: String) -> Bool {
        let normalizedQuery = normalized(query)
        let tokens = queryTokens(normalizedQuery)
        guard !tokens.isEmpty else { return true }
        let normalizedText = normalized(text)
        return tokens.allSatisfy { normalizedText.contains($0) }
    }

    static func searchTokens(for query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func highlightRanges(in text: String, tokens: [String]) -> [Range<String.Index>] {
        guard !text.isEmpty, !tokens.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        for token in tokens {
            guard !token.isEmpty else { continue }
            var search = text.startIndex..<text.endIndex
            while search.lowerBound < text.endIndex,
                  let r = text.range(of: token,
                                     options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                     range: search) {
                ranges.append(r)
                if r.upperBound == search.lowerBound {
                    break
                }
                search = r.upperBound..<text.endIndex
            }
        }
        return ranges
    }

    static func words(in normalizedText: String) -> Set<String> {
        Set(normalizedText.split(whereSeparator: \.isWhitespace).map(String.init))
    }

    private static func score(for text: String,
                              words: Set<String>,
                              normalizedQuery: String,
                              tokens: [String],
                              isPinned: Bool) -> Int {
        var score = isPinned ? 30 : 0
        if text == normalizedQuery { score += 1_200 }
        if text.hasPrefix(normalizedQuery) { score += 900 }
        if text.contains(normalizedQuery) { score += 700 }

        for token in tokens {
            if words.contains(token) {
                score += 140
            } else if words.contains(where: { $0.hasPrefix(token) }) {
                score += 80
            } else {
                score += 40
            }
        }
        return score
    }

    private static func queryTokens(_ normalizedQuery: String) -> [String] {
        normalizedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: nil)
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ClipboardHistoryPreview {
    static func handlesSpace(selectionIsVisible: Bool, hasModifiers: Bool) -> Bool {
        selectionIsVisible && !hasModifiers
    }
}

enum ClipboardHistoryNavigation {
    static func step(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, key: String?,
                     layout: ClipboardHistoryLayout) -> Int? {
        let sideArrowsMove = modifiers.isEmpty && layout.sideArrowsMoveSelection
        if keyCode == UInt16(kVK_DownArrow) || (modifiers == [.control] && key == "n")
            || (sideArrowsMove && keyCode == UInt16(kVK_RightArrow)) {
            return 1
        }
        if keyCode == UInt16(kVK_UpArrow) || (modifiers == [.control] && key == "p")
            || (sideArrowsMove && keyCode == UInt16(kVK_LeftArrow)) {
            return -1
        }
        return nil
    }
}

enum ClipboardHistoryEscape {
    enum Action: Equatable {
        case clearBatchSelection
        case hideWindow
    }

    static func action(batchCount: Int) -> Action {
        batchCount > 0 ? .clearBatchSelection : .hideWindow
    }
}

enum ClipboardHistoryFocus {
    static func textViewOwnsKeys(isComposing: Bool, isFieldEditor: Bool, isEditable: Bool) -> Bool {
        isComposing || (isEditable && !isFieldEditor)
    }
}

enum ClipboardHistoryBatch {
    static func combinedText(_ texts: [String]) -> String {
        texts.joined(separator: "\n")
    }

    static func orderedSelectedIndexes<ID: Hashable>(allIDs: [ID], selectedIDs: Set<ID>) -> [Int] {
        allIDs.indices.filter { selectedIDs.contains(allIDs[$0]) }
    }

    static func rangeSelectionIDs<ID>(allIDs: [ID], anchor: Int, target: Int) -> [ID] {
        guard !allIDs.isEmpty else { return [] }
        let low = min(max(min(anchor, target), 0), allIDs.count - 1)
        let high = min(max(max(anchor, target), 0), allIDs.count - 1)
        return Array(allIDs[low...high])
    }

    enum PasteMode: Equatable {
        case files([String])
        case text(String)
        case rich([RichPart])
    }

    enum RichPart: Equatable {
        case text(String)
        case image(String)
    }

    static func pasteMode(for entries: [ClipboardHistoryEntry]) -> PasteMode? {
        guard !entries.isEmpty else { return nil }
        if entries.allSatisfy({ $0.kind == .files }) {
            return .files(entries.flatMap(\.filePaths))
        }
        if entries.contains(where: { $0.kind == .image }) {
            let parts = entries.compactMap { entry -> RichPart? in
                switch entry.kind {
                case .text: return .text(entry.text)
                case .files: return .text(entry.filePaths.joined(separator: "\n"))
                case .image: return entry.imageFile.map(RichPart.image)
                }
            }
            return parts.isEmpty ? nil : .rich(parts)
        }
        let texts = entries.map { entry in
            entry.kind == .files ? entry.filePaths.joined(separator: "\n") : entry.text
        }
        return .text(combinedText(texts))
    }

    static func listOwnsCopyShortcut(batchCount: Int) -> Bool {
        batchCount > 0
    }

    static func listOwnsSelectAllShortcut(batchCount: Int, queryIsEmpty: Bool) -> Bool {
        batchCount > 0 || queryIsEmpty
    }

    static func listOwnsDeleteShortcut(batchCount: Int) -> Bool {
        batchCount > 0
    }

    static func richPlainText(_ parts: [RichPart]) -> String {
        combinedText(parts.compactMap { part in
            if case let .text(text) = part { return text }
            return nil
        })
    }
}

enum ClipboardHistoryCapturePolicy {
    static func isCopiedScreenshot(_ paths: [String], in directory: URL?) -> Bool {
        guard paths.count == 1,
              let directory else { return false }
        return ScreenshotSupport.isCopiedScreenshot(URL(fileURLWithPath: paths[0]), in: directory)
    }
}

enum ClipboardHistoryPasteboardText {
    static func preferredText(webURLString: String?, plainText: String?) -> String? {
        let plain = trimmed(plainText)
        if let plain,
           let normalizedPlain = normalizedWebURL(plain) {
            return normalizedPlain
        }

        guard let webURL = normalizedWebURL(webURLString) else { return plain }
        guard let plain else { return webURL }
        return shouldPreferWebURL(webURL, over: plain) ? webURL : plain
    }

    private static func shouldPreferWebURL(_ webURL: String, over plain: String) -> Bool {
        guard !plain.contains(where: \.isWhitespace) else { return false }
        if plain.hasPrefix("//") { return true }
        let stripped = stripWebScheme(webURL)
        return plain == stripped.withSlashes || plain == stripped.withoutSlashes
    }

    private static func normalizedWebURL(_ raw: String?) -> String? {
        guard let text = trimmed(raw),
              !text.contains(where: \.isWhitespace),
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        return url.absoluteString
    }

    private static func stripWebScheme(_ value: String) -> (withSlashes: String, withoutSlashes: String) {
        let lower = value.lowercased()
        let withSlashes: String
        if lower.hasPrefix("http://") {
            withSlashes = "//" + String(value.dropFirst("http://".count))
        } else if lower.hasPrefix("https://") {
            withSlashes = "//" + String(value.dropFirst("https://".count))
        } else {
            withSlashes = value
        }
        return (withSlashes, String(withSlashes.drop { $0 == "/" }))
    }

    private static func trimmed(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

extension NSPasteboard.PasteboardType {
    static let source = NSPasteboard.PasteboardType("org.nspasteboard.source")
    static let remoteClipboard = NSPasteboard.PasteboardType("com.apple.is-remote-clipboard")
}

extension NSPasteboard {
    func declareVorssaintSource() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        setString(bundleID, forType: .source)
    }
}

enum ClipboardHistorySensitiveText {
    static let concealedPasteboardType = "org.nspasteboard.ConcealedType"

    static func isConcealed(_ types: [String]) -> Bool {
        types.contains(concealedPasteboardType)
    }

    static let transientPasteboardTypes: Set<String> = [
        "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType",
    ]

    static func isTransient(_ types: [String]) -> Bool {
        types.contains(where: transientPasteboardTypes.contains)
    }

    private static let credentialName = #"(?:password|passwd|secret|token|api[_-]?key|private[_-]?key|authorization)"#
    private static let credentialEnding = #"(?:[_-]?(?:access[_-]?)?key(?:[_-]?base)?|[_-]?confirmation|[_-]?\d{1,3})?"#
    private static let credentialAssignment = try? NSRegularExpression(
        pattern: #"(?<![\w-])(?:[\w-]*\#(credentialName)\#(credentialEnding)["']?[ \t]*[:=][ \t]*|--[\w-]*\#(credentialName)\#(credentialEnding)[ \t]+)["']?[^\s"'`,;{}\[\]]"#,
        options: [.caseInsensitive]
    )

    static func looksSensitive(_ text: String) -> Bool {
        if credentialAssignment?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            return true
        }
        if isWebURL(text) { return false }
        if isIdentifierCode(text) { return false }

        guard text.count >= 20, text.count <= 160, !text.contains(where: { $0.isWhitespace }) else {
            return false
        }
        let hasLetter = text.contains { $0.isLetter }
        let hasDigit = text.contains { $0.isNumber }
        let hasSymbol = text.contains { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }
        return hasLetter && hasDigit && hasSymbol
    }

    private static func isIdentifierCode(_ text: String) -> Bool {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("{"), value.hasSuffix("}") {
            value = String(value.dropFirst().dropLast())
        }
        let groups = value.split(separator: "-", omittingEmptySubsequences: false)
        guard groups.map(\.count) == [8, 4, 4, 4, 12] else { return false }
        return groups.allSatisfy { $0.allSatisfy(\.isHexDigit) }
    }

    private static func isWebURL(_ text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            return false
        }
        return true
    }
}

enum ClipboardHistoryImageSupport {
    static func editorImage(for entry: ClipboardHistoryEntry, directory: URL) -> NSImage? {
        guard entry.kind == .image, let name = entry.imageFile,
              !name.isEmpty, (name as NSString).lastPathComponent == name
        else { return nil }
        return NSImage(contentsOf: directory.appendingPathComponent(name))
    }

    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "webp", "bmp", "ico", "icns", "svg", "avif"
    ]

    static func isImageFileName(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return imageExtensions.contains(ext)
    }

    static func isImageFilePath(_ path: String, fileManager: FileManager = .default) -> Bool {
        guard isImageFileName(path) else { return false }
        return fileManager.fileExists(atPath: path)
    }
}
