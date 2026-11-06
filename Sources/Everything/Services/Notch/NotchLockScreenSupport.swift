// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

enum NotchLockScreenActivity: String, CaseIterable, Identifiable {
    case timer, calendar, agents, downloads

    var id: String { rawValue }
}

enum NotchLockScreenSupport {
    static let spaceLevel: Int32 = 400

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchLockScreen)
    }

    static func playsSounds(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchLockSounds)
    }

    static func showsMusic(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.modules(in: defaults).contains(.music)
    }

    static func showsMusic(isPlaying: Bool, playedWhileLocked: Bool) -> Bool {
        isPlaying || playedWhileLocked
    }

    static func timerFinished(_ session: NotchTimerSession, at now: TimeInterval) -> Bool {
        session.completed || session.deadline.map { now >= $0 } == true
    }

    static func activities(timer: Bool, calendar: Bool, agents: Bool, downloads: Bool) -> [NotchLockScreenActivity] {
        NotchLockScreenActivity.allCases.filter {
            switch $0 {
            case .timer: return timer
            case .calendar: return calendar
            case .agents: return agents
            case .downloads: return downloads
            }
        }
    }

    static func timestamp(_ interval: TimeInterval) -> String {
        let seconds = interval.isFinite ? Int(min(604_800, max(0, interval))) : 0
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func soundURL(locking: Bool, fileManager: FileManager = .default) -> URL? {
        if let padlock = Bundle(path: "/System/Library/Frameworks/SecurityInterface.framework")?
            .url(forResource: locking ? "lock" : "unlock", withExtension: "aif") {
            return padlock
        }
        let alert = URL(fileURLWithPath: "/System/Library/Sounds/\(locking ? "Tink" : "Pop").aiff")
        return fileManager.fileExists(atPath: alert.path) ? alert : nil
    }
}

enum NotchLockScreenLayout {
    static func clockBottom(screenHeight: CGFloat) -> CGFloat { max(236, screenHeight * 0.247) }
    static let rowGap: CGFloat = 18
    static let rowHeight: CGFloat = 30
    static let loginClearance: CGFloat = 250
    static let playerWidth: CGFloat = 460
    static let paneWidth: CGFloat = 404
    static let minimumPlayerHeight: CGFloat = 190

    private static func readable(_ screen: CGRect) -> Bool {
        [screen.minX, screen.minY, screen.width, screen.height].allSatisfy(\.isFinite)
            && screen.width >= playerWidth + 32 && screen.height > 0
    }

    static func rowFrame(in screen: CGRect) -> CGRect? {
        guard readable(screen) else { return nil }
        let width = min(screen.width - 64, 1000)
        let top = screen.maxY - clockBottom(screenHeight: screen.height) - rowGap
        guard top - rowHeight >= screen.minY + loginClearance else { return nil }
        return CGRect(x: (screen.midX - width / 2).rounded(), y: top - rowHeight, width: width, height: rowHeight)
    }

    static func playerFrame(in screen: CGRect) -> CGRect? {
        guard let row = rowFrame(in: screen) else { return nil }
        let bottom = screen.minY + loginClearance
        let height = row.minY - 10 - bottom
        guard height >= minimumPlayerHeight else { return nil }
        return CGRect(x: (screen.midX - playerWidth / 2).rounded(), y: bottom, width: playerWidth, height: height)
    }

    static func islandSurface(in screen: CGRect, cameraWidth: CGFloat, cameraHeight: CGFloat, wing: CGFloat) -> CGRect? {
        guard [screen.width, screen.height, cameraWidth, cameraHeight, wing].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        let width = min(screen.width - 24, cameraWidth + wing * 2)
        guard width > cameraWidth else { return nil }
        return CGRect(x: screen.midX - width / 2, y: screen.maxY - cameraHeight, width: width, height: cameraHeight)
    }

    static func islandFrame(around surface: CGRect) -> CGRect { surface.integral }
}
