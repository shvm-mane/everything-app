// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

final class PermissionGuideOverlay {
    static let shared = PermissionGuideOverlay()

    static var suppressed = false

    private var panel: NSPanel?
    private var grantWatcher: AnyCancellable?
    private var dismissWork: DispatchWorkItem?
    private var staleWork: DispatchWorkItem?
    private let pollingDemandID = UUID()
    private static let staleAfter: TimeInterval = 12

    private init() {}

    func show(for kind: PermissionKind) {
        guard !Self.suppressed else { return }
        Permissions.shared.setActivePermissionSurface(pollingDemandID, visible: false)
        dismissWork?.cancel()
        dismissWork = nil
        staleWork?.cancel()
        staleWork = nil
        grantWatcher = nil
        panel?.orderOut(nil)
        panel = nil

        let language = L10n.shared.language
        let guide = FeatureStrings.permissionGuide(language)
        let permissionName = kind == .accessibility
            ? L10n.shared.s.permissionAccessibility
            : L10n.shared.s.permissionScreenRecording
        let model = PermissionGuideModel()
        let view = PermissionGuideCard(guide: guide, permissionName: permissionName,
                                       kind: kind, model: model,
                                       onStartOver: { Permissions.shared.startOver(kind) },
                                       onRelaunch: { appDelegate()?.relaunchApp() }) { [weak self] in
            self?.dismiss()
        }
        let stale = DispatchWorkItem { model.stale = true }
        staleWork = stale
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.staleAfter, execute: stale)

        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? .zero
        let frame = NSRect(x: visible.maxX - size.width - 20,
                           y: visible.maxY - size.height - 20,
                           width: size.width, height: size.height)

        let panel = OverlayPanel(contentRect: frame,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = host
        panel.orderFrontRegardless()
        self.panel = panel
        Permissions.shared.setActivePermissionSurface(pollingDemandID, visible: true)

        let publisher = kind == .accessibility
            ? Permissions.shared.$accessibility
            : Permissions.shared.$screenRecording
        grantWatcher = publisher
            .removeDuplicates()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                model.granted = true
                model.stale = false
                self?.staleWork?.cancel()
                if let self { Permissions.shared.setActivePermissionSurface(self.pollingDemandID, visible: false) }
                if kind == .accessibility { self?.scheduleDismiss() }
            }
    }

    private func scheduleDismiss() {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    func dismiss() {
        dismissWork?.cancel()
        dismissWork = nil
        staleWork?.cancel()
        staleWork = nil
        grantWatcher = nil
        panel?.orderOut(nil)
        panel = nil
        Permissions.shared.setActivePermissionSurface(pollingDemandID, visible: false)
    }
}

private final class PermissionGuideModel: ObservableObject {
    @Published var granted = false
    @Published var stale = false
}

private struct PermissionGuideCard: View {
    let guide: PermissionGuideStrings
    let permissionName: String
    let kind: PermissionKind
    @ObservedObject var model: PermissionGuideModel
    let onStartOver: () -> Void
    let onRelaunch: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(guide.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(permissionName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(guide.closeHelp)
            }

            VStack(alignment: .leading, spacing: 6) {
                stepRow(1, guide.stepOpen)
                stepRow(2, guide.stepToggle)
                stepRow(3, guide.stepReturn)
            }

            HStack(spacing: 7) {
                if model.granted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(guide.granted)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                    if kind == .screenRecording {
                        Spacer(minLength: 8)
                        Button(guide.relaunch, action: onRelaunch)
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView()
                        .controlSize(.small)
                    Text(guide.waiting)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)

            if model.stale, !model.granted {
                VStack(alignment: .leading, spacing: 6) {
                    Text(guide.staleHint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(guide.startOver, action: onStartOver)
                        .controlSize(.small)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
        )
        .animation(.easeOut(duration: 0.2), value: model.granted)
        .animation(.easeOut(duration: 0.2), value: model.stale)
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
