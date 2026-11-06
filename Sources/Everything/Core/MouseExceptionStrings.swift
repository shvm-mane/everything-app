// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MouseExceptionStrings {
    let listTitle: String
    let addButton: String
    let removeButton: String
    let captionSmoothScroll: String
    let captionLinearScroll: String
    let captionScrollDirection: String
    let captionNavigation: String
    let captionButtonShortcuts: String
    let captionMiddleClick: String
    let captionFocusFollowsMouse: String
    let captionSuperKey: String
    let pausedSuperKey: String

    func caption(for scope: MouseExceptionScope) -> String {
        switch scope {
        case .smoothScroll: return captionSmoothScroll
        case .linearScroll: return captionLinearScroll
        case .scrollDirection: return captionScrollDirection
        case .focusFollowsMouse: return captionFocusFollowsMouse
        case .navigation: return captionNavigation
        case .buttonShortcuts: return captionButtonShortcuts
        case .middleClick: return captionMiddleClick
        case .superKey: return captionSuperKey
        }
    }
}

extension FeatureStrings {
    static func mouseExceptions(_ language: AppLanguage) -> MouseExceptionStrings {
        switch language {
        case .enUS: return .enUS
        }
    }
}

extension MouseExceptionStrings {
    static let enUS = MouseExceptionStrings(
        listTitle: "Apps to leave alone",
        addButton: "Add an app…",
        removeButton: "Remove",
        captionSmoothScroll: "The wheel keeps its plain steps in these apps, for apps that read it their own way, like 3D and design tools.",
        captionLinearScroll: "The wheel keeps the pace macOS gives it in these apps, for games and 3D tools that count the notches themselves.",
        captionScrollDirection: "The wheel keeps the direction macOS gives it in these apps.",
        captionNavigation: "The side buttons keep doing whatever these apps already do with them.",
        captionButtonShortcuts: "Your extra mouse buttons stay quiet in these apps, and the press reaches them instead.",
        captionMiddleClick: "A three finger click stays a normal click in these apps.",
        captionFocusFollowsMouse: "Hovering does not change focus or raise a window in these apps.",
        captionSuperKey: "While any of these apps is open, even in the background, Super Key pauses and the chosen key works normally.",
        pausedSuperKey: "Paused while a selected app is open"
    )

}
