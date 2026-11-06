// SPDX-License-Identifier: GPL-3.0-or-later
// EVERYTHING: Dynamic Island, scratchpad, radial menu, instant spaces and more.

import AppKit

Defaults.register()
// Settings from Vorssaint, Wisp and InstantSpaceSwitcher come over once; the
// choices EVERYTHING fixes are applied on every launch.
LegacyImport.runIfNeeded()
LegacyImport.applyEverythingChoices(defaults: .standard)
NotchControlItem.keyboardLightIsSupported = { BrightnessService.keyboardLightIsSupported }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
