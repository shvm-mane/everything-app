// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

final class AppAppearanceController: ObservableObject {
    static let shared = AppAppearanceController()

    @Published var appearance: AppAppearance {
        didSet {
            guard appearance != oldValue else { return }
            UserDefaults.standard.set(appearance.rawValue, forKey: DefaultsKey.appearance)
            apply()
        }
    }

    @Published var liquidGlassEnabled: Bool {
        didSet {
            guard liquidGlassEnabled != oldValue else { return }
            UserDefaults.standard.set(liquidGlassEnabled, forKey: DefaultsKey.liquidGlassEnabled)
        }
    }

    @Published var notchLiquidGlassEnabled: Bool {
        didSet {
            guard notchLiquidGlassEnabled != oldValue else { return }
            UserDefaults.standard.set(notchLiquidGlassEnabled, forKey: DefaultsKey.notchLiquidGlassEnabled)
        }
    }

    private init() {
        appearance = AppAppearance.sanitized(
            UserDefaults.standard.string(forKey: DefaultsKey.appearance)
        )
        liquidGlassEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.liquidGlassEnabled)
        notchLiquidGlassEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.notchLiquidGlassEnabled)
    }

    private weak var panel: NSPopover?

    func apply() {
        NSApp.appearance = nsAppearance
        panel?.appearance = nsAppearance
    }

    func follow(panel popover: NSPopover) {
        panel = popover
        popover.appearance = nsAppearance
    }

    private var nsAppearance: NSAppearance? {
        switch appearance {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}
