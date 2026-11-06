// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case downloading(progress: Double?)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date?
    @Published private(set) var availableNotes: String?

    private var downloadURL: URL?
    private var refreshTimer: Timer?
    private var downloadSession: URLSession?

    private init() {}

    var autoCheckEnabled: Bool {
        get { UserDefaults.standard.object(forKey: DefaultsKey.autoCheckUpdates) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.autoCheckUpdates)
            configureAutomaticChecks()
        }
    }

    var includeBetaUpdates: Bool {
        get {
            if let explicit = UserDefaults.standard.object(forKey: DefaultsKey.includeBetaUpdates) as? Bool {
                return explicit
            }
            return AppInfo.isBeta
        }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.includeBetaUpdates)
        }
    }

    // MARK: - Scheduling

    func startAutomaticChecks() {
        return ()
    }

    private func configureAutomaticChecks() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard autoCheckEnabled else { return }
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in
            self?.check(manual: false)
        }
        timer.tolerance = 60 * 5
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    // MARK: - Check

    func check(manual: Bool) {
        return ()
    }

    func checkIfStale(maxAge: TimeInterval = 15 * 60) {
        return ()
    }

    // MARK: - Download & install

    func downloadAndInstall() {
        return ()
    }

    private static func volumeIsReadOnly(_ path: String) -> Bool {
        let values = try? URL(fileURLWithPath: path)
            .resourceValues(forKeys: [.volumeIsReadOnlyKey])
        return values?.volumeIsReadOnly ?? true
    }

    // MARK: - Install result

    // MARK: - Version compare

    static func isNewer(_ latest: String, than current: String) -> Bool {
        UpdateServiceSupport.isNewer(latest, than: current)
    }
}

// MARK: - GitHub API shapes

