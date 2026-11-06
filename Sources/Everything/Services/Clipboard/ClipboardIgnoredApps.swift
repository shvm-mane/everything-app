// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

final class ClipboardIgnoredApps: ObservableObject {
    static let shared = ClipboardIgnoredApps()

    @Published private(set) var apps: [String] = []

    private var lookup: Set<String> = []
    private var candidates: Set<String> = []
    private var activationObserver: NSObjectProtocol?
    private var historyIsRunning = false
    private let ownBundleID = Bundle.main.bundleIdentifier
    private var historyPanelWasKey = false

    private init() {
        reload()
    }

    // MARK: - The list

    func reload() {
        let defaults = UserDefaults.standard
        let raw = defaults.stringArray(forKey: DefaultsKey.clipboardHistoryIgnoredApps) ?? []
        let sanitized = Defaults.sanitizedBundleIdentifierList(raw)
        if raw != sanitized {
            defaults.set(sanitized, forKey: DefaultsKey.clipboardHistoryIgnoredApps)
        }
        apps = sanitized
        lookup = Set(sanitized)
    }

    func add(_ bundleID: String) {
        let bundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty, !apps.contains(bundleID) else { return }
        UserDefaults.standard.set(apps + [bundleID], forKey: DefaultsKey.clipboardHistoryIgnoredApps)
        reload()
    }

    func remove(_ bundleID: String) {
        guard apps.contains(bundleID) else { return }
        UserDefaults.standard.set(apps.filter { $0 != bundleID },
                                  forKey: DefaultsKey.clipboardHistoryIgnoredApps)
        reload()
    }

    // MARK: - Watching

    func setHistoryRunning(_ running: Bool) {
        guard historyIsRunning != running else { return }
        historyIsRunning = running
        if running {
            guard activationObserver == nil else { return }
            candidates = Self.frontmostBundleID().map { [$0] } ?? []
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let app = notification
                    .userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                    let bundleID = app.bundleIdentifier else { return }
                self?.candidates.insert(bundleID)
            }
        } else if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
            candidates = []
            historyPanelWasKey = false
        }
    }

    // MARK: - The question the history asks

    func sourceSinceLastCheck(declared: String?, remote: Bool,
                              historyPanelIsKey: Bool, historyPanelClosing: Bool)
        -> (excluded: Bool, bundleID: String?, fromHistoryPanel: Bool) {
        guard historyIsRunning else { return (false, nil, false) }
        let trimmed = declared?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let mark = trimmed.isEmpty || trimmed.utf8.count > 255 ? nil : trimmed
        let fromHistoryPanel = mark == nil && (historyPanelWasKey || historyPanelIsKey)
        let guessed = candidates.count == 1 && !fromHistoryPanel ? candidates.first : nil
        let named: String? = mark.map { $0 == ownBundleID ? nil : $0 } ?? guessed
        let source = (excluded: !candidates.isDisjoint(with: lookup) || mark.map { lookup.contains($0) } == true,
                      bundleID: remote ? nil : named,
                      fromHistoryPanel: fromHistoryPanel)
        candidates = Self.frontmostBundleID().map { [$0] } ?? []
        historyPanelWasKey = historyPanelIsKey && !historyPanelClosing
        return source
    }

    private static func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
