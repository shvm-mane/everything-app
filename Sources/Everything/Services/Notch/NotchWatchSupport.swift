// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum NotchWatchCondition: String, CaseIterable, Identifiable {
    case changes
    case settles
    case contains
    case reaches

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .changes: return "arrow.triangle.2.circlepath"
        case .settles: return "pause.circle"
        case .contains: return "text.magnifyingglass"
        case .reaches: return "flag.checkered"
        }
    }

    static func saved(in defaults: UserDefaults = .standard) -> NotchWatchCondition {
        NotchWatchCondition(rawValue: defaults.string(forKey: DefaultsKey.notchWatchCondition) ?? "") ?? .changes
    }
}

enum NotchWatchOutcome: Equatable {
    case changed
    case settled
    case shows(String)
    case reached(String)
    case closed

    var mascotReaction: NotchMascotReaction {
        switch self {
        case .changed: return .perk
        case .settled, .shows, .reached: return .celebrate
        case .closed: return .confused
        }
    }
}

struct NotchWatchTracker {
    static let settleInterval: TimeInterval = 30
    static let changeConfirmation: TimeInterval = 3

    let condition: NotchWatchCondition
    let text: String
    let target: Double?
    let decimalSeparator: String
    let groupsWithSpace: Bool

    private(set) var baseline: String?
    private(set) var changedSince: Date?
    private(set) var current: String?
    private(set) var lastChange: Date?
    private(set) var sawChange = false
    private(set) var start: Double?

    init(condition: NotchWatchCondition, text: String = "", target: Double? = nil,
         decimalSeparator: String = ".", groupsWithSpace: Bool = false) {
        self.condition = condition
        self.text = text
        self.target = target
        self.decimalSeparator = decimalSeparator
        self.groupsWithSpace = groupsWithSpace
    }

    init(condition: NotchWatchCondition, text: String, target: Double?, locale: Locale) {
        self.init(condition: condition, text: text, target: target,
                  decimalSeparator: locale.decimalSeparator ?? ".",
                  groupsWithSpace: NotchWatchSupport.groupsWithSpace(locale))
    }

    var isReady: Bool {
        switch condition {
        case .changes, .settles: return true
        case .contains: return !NotchWatchSupport.normalized(text).isEmpty
        case .reaches: return target != nil
        }
    }

    mutating func observe(signature: String?, reading: String, at date: Date) -> NotchWatchOutcome? {
        guard isReady else { return nil }
        switch condition {
        case .changes:
            guard let signature else { return nil }
            guard let baseline else { self.baseline = signature; return nil }
            guard !NotchWatchSupport.sameSignature(signature, baseline) else { changedSince = nil; return nil }
            guard let changedSince else { self.changedSince = date; return nil }
            return date.timeIntervalSince(changedSince) >= Self.changeConfirmation ? .changed : nil
        case .settles:
            if let signature, !NotchWatchSupport.sameSignature(signature, current) {
                if current != nil { sawChange = true }
                current = signature
                lastChange = date
                return nil
            }
            guard sawChange, let lastChange, date.timeIntervalSince(lastChange) >= Self.settleInterval else { return nil }
            return .settled
        case .contains:
            let wanted = NotchWatchSupport.normalized(text)
            return NotchWatchSupport.normalized(reading).contains(wanted) ? .shows(text) : nil
        case .reaches:
            guard let target,
                  let value = NotchWatchSupport.number(in: reading, decimalSeparator: decimalSeparator,
                                                       groupsWithSpace: groupsWithSpace) else { return nil }
            let shown = NotchWatchSupport.headline(from: reading, groupsWithSpace: groupsWithSpace)
            guard let start else {
                self.start = value
                return value == target ? .reached(shown) : nil
            }
            if start < target, value >= target { return .reached(shown) }
            if start > target, value <= target { return .reached(shown) }
            return nil
        }
    }
}

enum NotchWatchSupport {
    static let visibleInterval: TimeInterval = 1
    static let backgroundInterval: TimeInterval = 2
    static let rereadInterval: TimeInterval = 10
    static let maximumRecognitionSide = 900
    static let headlineLength = 22
    static let stripWingRange: ClosedRange<CGFloat> = 56...150
    static let thumbnailWidth: CGFloat = 40

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.notchWatch.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchWatchEnabled)
            && NotchSupport.modules(in: defaults).contains(.watch)
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func headline(from text: String,
                         groupsWithSpace: Bool = NotchWatchSupport.groupsWithSpace(.autoupdatingCurrent)) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return "" }
        let joined = lines.joined(separator: " ")
        if let percent = firstMatch(percentPattern(groupsWithSpace: groupsWithSpace), in: text) {
            return percent.components(separatedBy: .whitespaces).joined()
        }
        if first.count <= headlineLength { return first }
        if let clock = firstMatch(clockPattern, in: joined) { return clock }
        if let amount = firstMatch(amountPattern, in: joined) { return amount }
        return String(first.prefix(headlineLength - 1)) + "…"
    }

    static func lines(in text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func headline(from text: String, line: Int?) -> String {
        let lines = lines(in: text)
        guard let line, lines.indices.contains(line) else { return headline(from: text) }
        let chosen = lines[line]
        return chosen.count <= headlineLength ? chosen : String(chosen.prefix(headlineLength - 1)) + "…"
    }

    static func number(in text: String, decimalSeparator: String = ".", groupsWithSpace: Bool = false) -> Double? {
        if let percent = firstMatch(percentPattern(groupsWithSpace: groupsWithSpace), in: text) {
            return parse(String(percent.dropLast()), decimalSeparator: decimalSeparator)
        }
        let pattern = groupsWithSpace ? spacedNumberPattern + "|" + numberPattern : numberPattern
        guard let raw = firstMatch(pattern, in: text) else { return nil }
        return parse(raw, decimalSeparator: decimalSeparator)
    }

    static func groupsWithSpace(_ locale: Locale) -> Bool {
        guard let separator = locale.groupingSeparator, !separator.isEmpty else { return false }
        return separator.unicodeScalars.allSatisfy { CharacterSet.whitespaces.contains($0) }
    }

    static func parse(_ raw: String, decimalSeparator: String = ".") -> Double? {
        var digits = raw.components(separatedBy: .whitespaces).joined()
        let negative = digits.hasPrefix("-") || digits.hasPrefix("−")
        digits = digits.trimmingCharacters(in: CharacterSet(charactersIn: "+-−"))
        let lastDot = digits.lastIndex(of: ".")
        let lastComma = digits.lastIndex(of: ",")
        switch (lastDot, lastComma) {
        case let (dot?, comma?):
            if dot > comma {
                digits = digits.replacingOccurrences(of: ",", with: "")
            } else {
                digits = digits.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            }
        case (nil, _?):
            digits = groupsThousands(digits, mark: ",", decimalSeparator: decimalSeparator)
                ? digits.replacingOccurrences(of: ",", with: "")
                : digits.replacingOccurrences(of: ",", with: ".")
        case (_?, nil):
            if groupsThousands(digits, mark: ".", decimalSeparator: decimalSeparator) {
                digits = digits.replacingOccurrences(of: ".", with: "")
            }
        case (nil, nil):
            break
        }
        guard let value = Double(digits), value.isFinite else { return nil }
        return negative ? -value : value
    }

    private static func groupsThousands(_ digits: String, mark: Character, decimalSeparator: String) -> Bool {
        let groups = digits.split(separator: mark, omittingEmptySubsequences: false)
        if groups.count > 2 { return true }
        guard groups.count == 2, groups[1].count == 3, groups[0] != "0" else { return false }
        return decimalSeparator != String(mark)
    }

    static func formatted(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(locale))
    }

    static func typedNumber(_ text: String, locale: Locale) -> Double? {
        let digits = text.components(separatedBy: .whitespaces).joined()
        return number(in: digits, decimalSeparator: locale.decimalSeparator ?? ".")
    }

    static func fingerprint(_ image: CGImage) -> [UInt8]? {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? pixels.map { $0 / 16 } : nil
    }

    static func sameFingerprint(_ lhs: [UInt8]?, _ rhs: [UInt8]?) -> Bool {
        guard let lhs, let rhs, lhs.count == rhs.count else { return false }
        let moved = zip(lhs, rhs).filter { abs(Int($0) - Int($1)) > 1 }.count
        let nudged = zip(lhs, rhs).filter { $0 != $1 }.count
        return moved == 0 && nudged <= 3
    }

    static func signature(text: String, fingerprint: [UInt8]?) -> String? {
        let normalized = normalized(text)
        if !normalized.isEmpty { return normalized }
        return fingerprint.map { imagePrefix + $0.map(String.init).joined(separator: ".") }
    }

    static func sameSignature(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        if lhs == rhs { return true }
        guard lhs.hasPrefix(imagePrefix), rhs.hasPrefix(imagePrefix) else { return false }
        func cells(_ signature: String) -> [UInt8] {
            signature.dropFirst(imagePrefix.count).split(separator: ".").compactMap { UInt8($0) }
        }
        return sameFingerprint(cells(lhs), cells(rhs))
    }

    private static let imagePrefix = "image:"

    static func standalone(_ image: CGImage) -> CGImage {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }

    static func pixelCrop(_ crop: CGRect, windowSize: CGSize, imageSize: CGSize) -> CGRect? {
        guard windowSize.width > 0, windowSize.height > 0 else { return nil }
        let scaleX = imageSize.width / windowSize.width
        let scaleY = imageSize.height / windowSize.height
        let rect = CGRect(x: crop.minX * scaleX, y: crop.minY * scaleY,
                          width: crop.width * scaleX, height: crop.height * scaleY).integral
            .intersection(CGRect(origin: .zero, size: imageSize))
        return rect.isNull || rect.width < 4 || rect.height < 4 ? nil : rect
    }

    static func windowCrop(for area: CGRect, windows: [(id: CGWindowID, bounds: CGRect)])
        -> (id: CGWindowID, crop: CGRect)? {
        let middle = CGPoint(x: area.midX, y: area.midY)
        guard let window = windows.first(where: { $0.bounds.contains(middle) }) else { return nil }
        let inside = area.intersection(window.bounds)
        guard !inside.isNull, inside.width >= 8, inside.height >= 8 else { return nil }
        return (window.id, inside.offsetBy(dx: -window.bounds.minX, dy: -window.bounds.minY))
    }

    private static func percentPattern(groupsWithSpace: Bool) -> String {
        "(?:" + (groupsWithSpace ? spacedNumberPattern + "|" : "") + numberPattern + #")[ \x{00A0}\x{202F}]?%"#
    }
    private static let clockPattern = #"\b\d{1,2}:\d{2}(?::\d{2})?\b"#
    private static let amountPattern = #"[-+]?\d[\d.,]*(?:\s?[A-Za-z]{1,3}\b)?"#
    private static let numberPattern = #"[-+−]?\d[\d.,]*\d|[-+−]?\d"#
    private static let spacedNumberPattern = #"[-+−]?\d{1,3}(?:[ \x{00A0}\x{202F}]\d{3})+(?:[.,]\d+)?"#

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespaces)
    }
}
