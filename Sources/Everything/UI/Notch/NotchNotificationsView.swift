// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct NotchNotificationPreviewView: View {
    let notice: NotchNotice
    let content: NotchNotificationContent
    @ObservedObject var service: NotchService
    @ObservedObject private var notifications = NotchNotificationService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchNotificationStrings { FeatureStrings.notchNotifications(l10n.language) }
    private var item: NotchSystemNotification? {
        notifications.items.first { $0.id == notice.notificationID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchNotificationPreviewLayout.spacing) {
            HStack(spacing: 8) {
                NotchNotificationAppIcon(app: content.app, size: NotchNotificationPreviewLayout.iconSize)
                Text(content.app.isEmpty ? text.title : content.app)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let item {
                    Text(item.received, format: .dateTime.hour().minute())
                        .font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.45))
                }
                NotchIconButton(symbol: "xmark", title: text.dismiss) { service.dismissNotification(notice) }
            }
            .frame(height: NotchNotificationPreviewLayout.headerHeight)
            if !content.title.isEmpty {
                Text(content.title)
                    .font(Font(NotchNotificationPreviewLayout.titleFont as CTFont))
                    .lineLimit(NotchNotificationPreviewLayout.titleLines)
            }
            if !content.subtitle.isEmpty {
                Text(content.subtitle)
                    .font(Font(NotchNotificationPreviewLayout.subtitleFont as CTFont))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(NotchNotificationPreviewLayout.subtitleLines)
            }
            if !content.body.isEmpty {
                Text(content.body)
                    .font(Font(NotchNotificationPreviewLayout.bodyFont as CTFont))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(NotchNotificationPreviewLayout.bodyLines)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                if let item, notifications.canOpen(item) {
                    Button(text.open) { service.activateNotice(notice) }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(notifications.openingID != nil)
                }
                if notifications.openingID == notice.notificationID { ProgressView().controlSize(.small) }
                Spacer(minLength: 8)
                if notifications.items.count > 1 {
                    Button { service.open(.notifications) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "tray.full").font(.system(size: 11, weight: .medium))
                            Text(notifications.items.count, format: .number)
                                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        }
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(NotchButtonStyle(cornerRadius: 12))
                    .modifier(NotchControlSurface(cornerRadius: 12))
                    .help(text.title)
                    .accessibilityLabel(text.title)
                    .accessibilityValue(Text(notifications.items.count, format: .number))
                }
            }
            .frame(height: NotchNotificationPreviewLayout.actionHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(notice.accessibilityText)
        .environment(\.locale, l10n.language.formattingLocale())
    }
}

struct NotchNotificationAppIcon: View {
    let app: String
    let size: CGFloat
    @ObservedObject private var service = NotchNotificationService.shared

    var body: some View {
        Group {
            if let icon = service.icon(for: app) {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: size * 0.48, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: size, height: size)
                    .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: size * 0.24))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
