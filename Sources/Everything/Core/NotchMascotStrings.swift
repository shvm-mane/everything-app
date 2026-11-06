// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchMascotStrings {
    let title: String
    let hint: String
    let visits: String
    let visitsHint: String
    let style: String
    let minimal: String
    let robot: String
    let shape: String
    let ball: String
    let egg: String
    let squircle: String
    let pill: String
    let color: String
    let pearl: String
    let mint: String
    let peach: String
    let lilac: String
    let lemon: String
    let rose: String
    let commandBar: String
    let commandBarHint: String
    let opensAs: String
    let droplet: String
    let openIsland: String
    let preview: String
    let previewHint: String
    let side: String
    let left: String
    let right: String
    let frequency: String
    let rare: String
    let normal: String
    let frequent: String
    let sky: String
    let hubDescription: String
    let appearance: String
    let behavior: String
    let reactions: String
    let reactionsHint: String
    let hidesWhenIdle: String
    let hidesWhenIdleHint: String
    let sayHi: String
    let sayHiHint: String
    let momentsTitle: String
    let visitMoment: String
    let timerStarted: String
    let downloadFailed: String
    let unlocked: String
    let petTip: String
    let livesInIsland: String
    let keywords: String

    func style(_ style: NotchMascotStyle) -> String {
        style == .robot ? robot : minimal
    }

    func shape(_ shape: NotchMascotShape) -> String {
        switch shape {
        case .ball: return ball
        case .egg: return egg
        case .squircle: return squircle
        case .pill: return pill
        }
    }

    func palette(_ palette: NotchMascotPalette) -> String {
        switch palette {
        case .pearl: return pearl
        case .mint: return mint
        case .peach: return peach
        case .lilac: return lilac
        case .lemon: return lemon
        case .rose: return rose
        case .sky: return sky
        }
    }

    func commandBarStyle(_ style: NotchCommandBarStyle) -> String {
        style == .island ? openIsland : droplet
    }

    func side(_ side: NotchMascotSide) -> String {
        side == .right ? right : left
    }

    func moment(_ moment: NotchMascotMoment, language: AppLanguage) -> String {
        switch moment {
        case .visit: return visitMoment
        case .timerStarted: return timerStarted
        case .timeIsUp: return FeatureStrings.notchActivities(language).finished
        case .music: return FeatureStrings.radialMenu(language).mediaNowPlaying
        case .agents: return FeatureStrings.notchAgents(language).title
        case .eventStarts: return FeatureStrings.notchCalendar(language).ongoing
        case .downloadFinished: return FeatureStrings.notchFiles(language).completed
        case .downloadFailed: return downloadFailed
        case .screenshot: return FeatureStrings.screenshot(language).pageTitle
        case .micMuted: return Strings.localized(language).micMutedHUD
        case .keepAwake: return Strings.localized(language).keepAwakeTitle
        case .charging: return FeatureStrings.notch(language).charging
        case .lowBattery: return FeatureStrings.notch(language).lowBattery
        case .unlocked: return unlocked
        }
    }

    var searchKeywords: [String] {
        [hint, visits, reactions, hidesWhenIdle, style, robot, shape, color, side, frequency, commandBar, keywords]
    }

    func frequency(_ frequency: NotchMascotVisitFrequency) -> String {
        switch frequency {
        case .rare: return rare
        case .normal: return normal
        case .frequent: return frequent
        }
    }
}

extension FeatureStrings {
    static func notchMascot(_ language: AppLanguage) -> NotchMascotStrings {
        switch language {
        case .enUS: return NotchMascotStrings(
            title: "Companion",
            hint: "A little friend who lives in the Dynamic Island. It rests there when nothing else is showing, and comes out over music and activities to say hello and react to what happens.",
            visits: "Appear now and then",
            visitsHint: "Every few minutes it passes through the island with a short animation.",
            style: "Style", minimal: "Minimal", robot: "Robot",
            shape: "Shape", ball: "Ball", egg: "Egg", squircle: "Rounded square", pill: "Pill",
            color: "Color", pearl: "Pearl", mint: "Mint", peach: "Peach", lilac: "Lilac", lemon: "Lemon", rose: "Rose",
            commandBar: "Command Bar in the island",
            commandBarHint: "With the keybind, the Command Bar comes out of the island with the companion as its face. It reacts while you search.",
            opensAs: "Opens as", droplet: "Drop", openIsland: "Open island",
            preview: "Companion preview", previewHint: "Click to see it react.",
            side: "Side of the camera", left: "Left", right: "Right",
            frequency: "How often", rare: "Rarely", normal: "Sometimes", frequent: "Often",
            sky: "Sky",
            hubDescription: "A little friend in the Dynamic Island who says hello now and then and reacts to what happens on your Mac.",
            appearance: "Appearance", behavior: "Behavior",
            reactions: "React to what happens",
            reactionsHint: "It comes out to react to music, timers, downloads, screenshots, the microphone, Keep awake and more.",
            hidesWhenIdle: "Hide when idle",
            hidesWhenIdleHint: "After half a minute with nothing going on, it hops into the island and the island goes back to its usual size. Visits and reactions still bring it out.",
            sayHi: "Say Hi", sayHiHint: "Plays a visit in the Dynamic Island now.",
            momentsTitle: "See how it reacts",
            visitMoment: "A visit", timerStarted: "Timer started", downloadFailed: "Download failed", unlocked: "Mac unlocked",
            petTip: "Rest the pointer on it to pet it. Left alone, it dozes off until you come back.",
            livesInIsland: "The companion lives in the Dynamic Island.",
            keywords: "mascot pet buddy character")
        }
    }
}
