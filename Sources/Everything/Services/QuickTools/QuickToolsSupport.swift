// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import UniformTypeIdentifiers

enum QuickToolsSupport {
    static func sampledColor(in image: CGImage, x: Int, y: Int) -> NSColor? {
        guard let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))
        else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: pixel)
        guard let color = bitmap.colorAt(x: 0, y: 0) else { return nil }
        var components = [CGFloat](repeating: 0, count: color.numberOfComponents)
        color.getComponents(&components)
        guard components.count == bitmap.colorSpace.numberOfColorComponents + 1
        else { return nil }
        return NSColor(colorSpace: bitmap.colorSpace,
                       components: components,
                       count: components.count)
    }

    // MARK: - Quick launcher

    enum GridDirection {
        case up, down, left, right
    }

    enum GridFlow: Equatable {
        case rows(columns: Int)
        case columns(rows: Int)
    }

    static func gridIndex(after index: Int,
                          count: Int,
                          columns: Int,
                          direction: GridDirection) -> Int {
        guard count > 0, columns > 0 else { return 0 }
        let current = min(max(index, 0), count - 1)
        let candidate: Int
        switch direction {
        case .left: candidate = current - 1
        case .right: candidate = current + 1
        case .up: candidate = current - columns
        case .down: candidate = current + columns
        }
        guard candidate >= 0, candidate < count else { return current }
        if direction == .left, current % columns == 0 { return current }
        if direction == .right, current % columns == columns - 1 { return current }
        return candidate
    }

    static func gridIndex(after index: Int, count: Int, flow: GridFlow, direction: GridDirection) -> Int {
        switch flow {
        case .rows(let columns):
            return gridIndex(after: index, count: count, columns: columns, direction: direction)
        case .columns(let rows):
            let transposed: GridDirection
            switch direction {
            case .up: transposed = .left
            case .down: transposed = .right
            case .left: transposed = .up
            case .right: transposed = .down
            }
            return gridIndex(after: index, count: count, columns: max(1, rows), direction: transposed)
        }
    }

    static func hiddenIDs(from raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    static func serializeHiddenIDs(_ ids: Set<String>) -> String {
        ids.sorted().joined(separator: ",")
    }

    struct RecognizedLine {
        let text: String
        let x: Double
        let y: Double
    }

    static func joinedRecognizedText(_ lines: [RecognizedLine],
                                     removingLineBreaks: Bool) -> String {
        let texts = lines
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                let rowA = (1 - $0.y) * 50
                let rowB = (1 - $1.y) * 50
                if abs(rowA - rowB) >= 0.5 { return rowA < rowB }
                return $0.x < $1.x
            }
            .map(\.text)
        guard removingLineBreaks else { return texts.joined(separator: "\n") }

        let normalizedTexts = texts.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return normalizedTexts.reduce(into: "") { joined, line in
            guard !joined.isEmpty else {
                joined = line
                return
            }
            let joinsTightly = joined.unicodeScalars.last.map(isTightScriptScalar) == true
                && line.unicodeScalars.first.map(isTightScriptScalar) == true
            joined.append(joinsTightly ? "" : " ")
            joined.append(line)
        }
    }

    private static func isTightScriptScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3000...0x312F,
             0x3190...0x9FFF,
             0xF900...0xFAFF,
             0xFF01...0xFF9F,
             0x20000...0x2FA1F:
            return true
        default:
            return false
        }
    }

    // MARK: - QR codes

    struct DecodedBarcode {
        let payload: String
        let x: Double
        let y: Double
    }

    static func joinedBarcodePayloads(_ codes: [DecodedBarcode]) -> String {
        codes
            .filter { !$0.payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted {
                let rowA = (1 - $0.y) * 50
                let rowB = (1 - $1.y) * 50
                if abs(rowA - rowB) >= 0.5 { return rowA < rowB }
                return $0.x < $1.x
            }
            .map(\.payload)
            .joined(separator: "\n")
    }

    // MARK: - Paste as plain text

    static func isMatchStyleEquivalent(commandCharacter: String?,
                                       modifierMask: UInt32?,
                                       isEnabled: Bool) -> Bool {
        let shiftAndOption: UInt32 = 1 | 2
        return commandCharacter?.uppercased() == "V"
            && modifierMask == shiftAndOption
            && isEnabled
    }

    static func isMediaTextFallback(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard !trimmed.contains(where: { $0.isWhitespace }) else { return false }
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("data:") || lowercased.hasPrefix("blob:")
            || (trimmed.contains("://") && URL(string: trimmed)?.scheme != nil) { return true }
        let name = trimmed as NSString
        guard !name.deletingPathExtension.isEmpty, !name.pathExtension.isEmpty,
              let type = UTType(filenameExtension: name.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .audiovisualContent) || type.conforms(to: .pdf)
    }

    static func openableURL(from payload: String) -> URL? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(where: { $0.isWhitespace }),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}
