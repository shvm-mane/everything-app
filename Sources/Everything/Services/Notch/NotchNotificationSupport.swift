// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

struct NotchNotificationContent: Equatable, Sendable {
    let app: String
    let title: String
    let subtitle: String
    let body: String

    var compactTitle: String { title.isEmpty ? app : title }

    var compactDetail: String {
        [subtitle, body].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var accessibilityText: String {
        [app, title, subtitle, body].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

struct NotchSystemNotification: Equatable, Identifiable, Sendable {
    let id: UUID
    let content: NotchNotificationContent
    let received: Date
    var canOpen: Bool
}

struct NotchNotificationInbox {
    private(set) var items: [NotchSystemNotification] = []
    private var seen = Set<UUID>()
    private var primed = false

    mutating func update(_ live: [NotchSystemNotification]) -> [NotchSystemNotification] {
        let byID = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        items = items.map { item in
            if let current = byID[item.id] { return current }
            var expired = item; expired.canOpen = false
            return expired
        }
        var arrivals: [NotchSystemNotification] = []
        for item in live where seen.insert(item.id).inserted {
            guard primed else { continue }
            items.insert(item, at: 0)
            if items.count > NotchNotificationSupport.maximumItems { items.removeLast() }
            arrivals.append(item)
        }
        primed = true
        if seen.count > 200 { seen = Set(items.map(\.id) + live.map(\.id)) }
        return arrivals
    }

    mutating func dismiss(_ id: UUID) { items.removeAll { $0.id == id } }

    mutating func clear() { items.removeAll() }
}

enum NotchNotificationSupport {
    struct Text: Equatable {
        let identifier: String
        let value: String
    }

    static let bannerRoles: Set<String> = ["AXNotificationCenterAlert", "AXNotificationCenterBanner"]
    static let stackRoles: Set<String> = ["AXNotificationCenterAlertStack", "AXNotificationCenterBannerStack"]
    static let maximumItems = 50
    static let nativeCloseGrace: TimeInterval = 1.2
    static var movesNativeWindow: Bool {
        if #available(macOS 27, *) { return true }
        return false
    }

    static func sourceBundleIdentifier(for names: [String],
                                       applications: [(name: String, bundleIdentifier: String)]) -> String? {
        func label(_ value: String) -> String {
            let scalars = value.unicodeScalars.filter {
                ![0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069].contains($0.value)
            }
            return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let names = names.filter { $0.utf8.count <= 256 }.map(label).filter { !$0.isEmpty }
        let matches = Set(applications.filter { app in
            names.contains { label(app.name).compare($0, options: .caseInsensitive) == .orderedSame }
        }.map(\.bundleIdentifier))
        return matches.count == 1 ? matches.first : nil
    }

    static func sourceBundleIdentifier(for names: [String],
                                       running: [(name: String, bundleIdentifier: String)],
                                       installed: [(name: String, bundleIdentifier: String)]) -> String? {
        sourceBundleIdentifier(for: names, applications: running)
            ?? sourceBundleIdentifier(for: names, applications: running + installed)
    }

    static func applicationLabel(from description: String, content: NotchNotificationContent) -> String? {
        let suffix = ", " + [content.title, content.subtitle, content.body].filter { !$0.isEmpty }.joined(separator: ", ")
        guard description.utf8.count <= 50_000, description.hasSuffix(suffix) else { return nil }
        let source = String(description.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return source.isEmpty || source.utf8.count > 256 ? nil : source
    }

    static func dismissesNative(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchDismissNativeNotifications)
    }

    static func closeAction(in actions: [String], title: String) -> String? {
        guard !title.isEmpty else { return nil }
        let matches = actions.filter { $0.components(separatedBy: "\n").first == "Name:" + title }
        return matches.count == 1 ? matches.first : nil
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults)
            && AppFeature.notchNotifications.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchNotificationsEnabled)
            && NotchSupport.modules(in: defaults).contains(.notifications)
    }

    static func content(from texts: [Text]) -> NotchNotificationContent? {
        func values(_ identifier: String) -> [String] {
            texts.filter { $0.identifier == identifier }.map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        let headers = values("header"), titles = values("title"), bodies = values("body")
        let subtitles = values("subtitle")
        if texts.allSatisfy({ $0.identifier.isEmpty }), (2...3).contains(texts.count),
           texts.allSatisfy({ !$0.value.isEmpty && $0.value.utf8.count <= 16_384 }) {
            return NotchNotificationContent(app: "", title: texts[0].value,
                                            subtitle: texts.count == 3 ? texts[1].value : "",
                                            body: texts[texts.count - 1].value)
        }
        guard headers.count <= 1, titles.count == 1, bodies.count <= 1, subtitles.count <= 1,
              texts.allSatisfy({ $0.value.utf8.count <= 16_384 }) else { return nil }
        return NotchNotificationContent(app: headers.first ?? "", title: titles[0],
                                        subtitle: subtitles.first ?? "", body: bodies.first ?? "")
    }

    static func nativeIdentity(_ identifier: String?) -> String? {
        guard let identifier, identifier.utf8.count <= 2_048,
              identifier.range(of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
                               options: .regularExpression) != nil else { return nil }
        return identifier
    }
}

enum NotchNotificationBannerLayout {
    static let iconSize: CGFloat = 22
    static let spacing: CGFloat = 8
    static let wingRange: ClosedRange<CGFloat> = NotchNotice.minimumWing...190
    static let inset: CGFloat = 16
    static let air: CGFloat = 6
    static let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let messageFont = NSFont.systemFont(ofSize: 11)

    static func messageLines(stripHeight: CGFloat) -> Int { stripHeight >= 30 ? 2 : 1 }

    static func wings(for content: NotchNotificationContent, wrapsMessage: Bool = false) -> NotchNoticeWings {
        func width(_ text: String, _ font: NSFont) -> CGFloat {
            (String(text.prefix(240)) as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
        }
        let title = iconSize + spacing + width(content.compactTitle, titleFont)
        var detail = width(content.compactDetail, messageFont)
        let room = wingRange.upperBound - inset - air
        if wrapsMessage, detail > room {
            let wrapped = (String(content.compactDetail.prefix(240)) as NSString).boundingRect(
                with: CGSize(width: room, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: messageFont])
            detail = min(room, wrapped.width.rounded(.up))
        }
        func fitted(_ side: CGFloat) -> CGFloat { min(wingRange.upperBound, max(wingRange.lowerBound, side + inset + air)) }
        return NotchNoticeWings(leading: fitted(title), trailing: fitted(detail))
    }
}

enum NotchNotificationPreviewLayout {
    static let iconSize: CGFloat = 26
    static let headerHeight: CGFloat = 28
    static let spacing: CGFloat = 8
    static let actionHeight: CGFloat = 28
    static let titleFont = NSFont.systemFont(ofSize: 14, weight: .semibold)
    static let subtitleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let bodyFont = NSFont.systemFont(ofSize: 13)
    static let titleLines = 2
    static let subtitleLines = 1
    static let bodyLines = 6

    static func contentHeight(for content: NotchNotificationContent, width: CGFloat) -> CGFloat {
        let blocks = [textHeight(content.title, font: titleFont, lines: titleLines, width: width),
                      textHeight(content.subtitle, font: subtitleFont, lines: subtitleLines, width: width),
                      textHeight(content.body, font: bodyFont, lines: bodyLines, width: width)].filter { $0 > 0 }
        return headerHeight + (blocks + [actionHeight]).reduce(0) { $0 + spacing + $1 }
    }

    static func textHeight(_ text: String, font: NSFont, lines: Int, width: CGFloat) -> CGFloat {
        guard !text.isEmpty, width > 0 else { return 0 }
        let line = ceil(font.ascender - font.descender + font.leading)
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height
        return min(ceil(measured) + 1, line * CGFloat(max(1, lines)) + 1)
    }
}
