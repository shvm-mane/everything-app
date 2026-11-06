// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

struct NotchClipboardSizeStrings {
    let entrySize: String
    let compact: String
    let comfortable: String
    let hint: String
}

enum NotchClipboardCardSize: String, CaseIterable, Identifiable {
    case compact, comfortable
    var id: String { rawValue }

    init(stored: String?) {
        self = stored.flatMap(NotchClipboardCardSize.init(rawValue:)) ?? .comfortable
    }

    static let dwell: TimeInterval = 0.7

    static let keyDwell: TimeInterval = 1.4

    static let maximumOpenLines = 8
    static let openLineHeight: CGFloat = 16
    static let openChrome: CGFloat = 48
    static let maximumOpenImage: CGFloat = 170
    static let minimumOpenImage: CGFloat = 80

    static let openTextFont = NSFont.systemFont(ofSize: 12)

    static func openLines(for text: String, width: CGFloat) -> Int {
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: openTextFont]).height
        let line = NSLayoutManager().defaultLineHeight(for: openTextFont)
        return min(maximumOpenLines, max(1, Int((measured / line).rounded(.up))))
    }

    static func openHeight(text: String, width: CGFloat) -> CGFloat {
        CGFloat(openLines(for: text, width: width)) * openLineHeight + openChrome
    }

    private struct MeasuredText: Hashable {
        let id: UUID
        let text: String
        let width: CGFloat
    }
    private static var measuredOpenHeights: [MeasuredText: CGFloat] = [:]

    static func openHeight(text: String, width: CGFloat, id: UUID) -> CGFloat {
        let key = MeasuredText(id: id, text: text, width: width)
        if let height = measuredOpenHeights[key] { return height }
        if measuredOpenHeights.count >= 512 { measuredOpenHeights.removeAll() }
        let height = openHeight(text: text, width: width)
        measuredOpenHeights[key] = height
        return height
    }

    static func openHeight(aspectRatio: CGFloat?, width: CGFloat) -> CGFloat {
        let natural = max(1, width) / max(0.2, aspectRatio ?? 1.5)
        return min(maximumOpenImage, max(minimumOpenImage, natural)) + openChrome
    }

    static func current(in defaults: UserDefaults = .standard) -> NotchClipboardCardSize {
        NotchClipboardCardSize(stored: defaults.string(forKey: DefaultsKey.notchClipboardCardSize))
    }
}

extension FeatureStrings {
    static func notchClipboardSize(_ language: AppLanguage) -> NotchClipboardSizeStrings {
        switch language {
        case .enUS: return NotchClipboardSizeStrings(
            entrySize: "Entry size",
            compact: "Compact",
            comfortable: "Comfortable",
            hint: "Compact entries show one or two lines and open up when the pointer rests on them.")
        }
    }
}
