// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

extension NotchQuickAccessSide {
    func title(_ l10n: L10n) -> String {
        let text = FeatureStrings.notch(l10n.language)
        switch self {
        case .left: return text.quickAccessLeft
        case .right: return text.quickAccessRight
        case .bottom: return FeatureStrings.notchEditor(l10n.language).bottom
        }
    }
}

