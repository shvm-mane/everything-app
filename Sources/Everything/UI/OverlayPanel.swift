// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

class OverlayPanel: NSPanel {
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .unknown }
}
