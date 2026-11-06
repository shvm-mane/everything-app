// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

Defaults.register()
LegacyImport.runIfNeeded()
LegacyImport.applyEverythingChoices(defaults: .standard)
NotchControlItem.keyboardLightIsSupported = { BrightnessService.keyboardLightIsSupported }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
