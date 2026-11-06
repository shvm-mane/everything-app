// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices

struct EnhancedUserInterfaceSuspension {
    private static let attribute = "AXEnhancedUserInterface" as CFString
    private let application: AXUIElement

    static func suspend(forAppOf window: AXUIElement) -> EnhancedUserInterfaceSuspension? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success, pid != 0 else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.35)
        guard isEnabled(on: application) else { return nil }
        _ = AXUIElementSetAttributeValue(application, Self.attribute, kCFBooleanFalse)
        guard !isEnabled(on: application) else { return nil }
        return EnhancedUserInterfaceSuspension(application: application)
    }

    private static func isEnabled(on application: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, Self.attribute, &value) == .success else { return false }
        return (value as? Bool) == true
    }

    func resume() {
        _ = AXUIElementSetAttributeValue(application, Self.attribute, kCFBooleanTrue)
    }
}
