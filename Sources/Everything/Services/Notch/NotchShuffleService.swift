// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

final class NotchShuffleService: ObservableObject {
    static let shared = NotchShuffleService()
    @Published private(set) var availability: NotchMusicAutomation.Availability?
    @Published private(set) var enabled: Bool?
    @Published private(set) var allowed = true
    @Published private(set) var pending = false
    @Published private(set) var requestingAccess = false
    private let queue = DispatchQueue(label: "com.vorssaint.notch-shuffle", qos: .utility)
    private var generation = UUID()
    private var switchID = UUID()
    private var open = false

    private init() {}

    var isOffered: Bool {
        guard let availability else { return false }
        return availability.access == .consent || (availability.access == .granted && enabled != nil)
    }

    func refresh(for playback: NotchPlayback?) {
        let target = playback.flatMap(NotchMusicAutomation.Target.init)
        let requested = UUID()
        generation = requested
        open = true
        if availability?.target != target { availability = nil; enabled = nil; pending = false; switchID = UUID() }
        guard let target else { return }
        queue.async { [weak self] in
            let available = NotchMusicAutomation.inspect(target).flatMap { $0.capabilities.shuffle == nil ? nil : $0 }
            let state = available.flatMap(NotchMusicAutomation.shuffle(of:))
            let allowed = available.map(NotchMusicAutomation.shuffleAllowed(by:)) ?? true
            DispatchQueue.main.async {
                guard let self, self.generation == requested else { return }
                self.availability = available
                self.enabled = state
                self.allowed = allowed
            }
        }
    }

    func toggle() {
        guard !pending, !requestingAccess, let available = availability, available.target.isCurrent else { return }
        if available.access == .consent { requestAccess(available); return }
        guard available.access == .granted, allowed, let current = enabled else { return }
        pending = true
        let id = UUID()
        switchID = id
        queue.async { [weak self] in
            let sent = NotchMusicAutomation.setShuffle(!current, availability: available)
            DispatchQueue.main.async {
                guard let self, self.switchID == id else { return }
                self.pending = false
                guard self.availability?.target == available.target else { return }
                self.enabled = sent ? !current : current
                if !sent { self.refresh(for: NotchMusicService.shared.playback) }
            }
            self?.queue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                let state = NotchMusicAutomation.shuffle(of: available)
                DispatchQueue.main.async {
                    guard let self, self.switchID == id, self.availability?.target == available.target,
                          let state else { return }
                    self.enabled = state
                }
            }
        }
    }

    func stop() {
        open = false
        generation = UUID()
        switchID = UUID()
        availability = nil
        enabled = nil
        allowed = true
        pending = false
    }

    private func requestAccess(_ available: NotchMusicAutomation.Availability) {
        requestingAccess = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if available.target.isCurrent { _ = AppleScriptRunner.consentToAutomate(bundleID: available.target.bundleIdentifier) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.requestingAccess = false
                guard self.open else { return }
                NotchMusicService.shared.refreshAutomation()
                self.refresh(for: NotchMusicService.shared.playback)
            }
        }
    }
}
