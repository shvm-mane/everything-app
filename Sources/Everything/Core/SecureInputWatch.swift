// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation
import IOKit

final class SecureInputWatch {
    private let onChange: (Bool) -> Void
    private var port: IONotificationPortRef?
    private var notification: io_object_t = 0
    private var lastSeen = false

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        guard port == nil else { return }
        let resources = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources")
        guard resources != MACH_PORT_NULL else { return }
        defer { IOObjectRelease(resources) }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        let result = IOServiceAddInterestNotification(
            port, resources, kIOBusyInterest, { context, _, _, _ in
                guard let context else { return }
                Unmanaged<SecureInputWatch>.fromOpaque(context).takeUnretainedValue().recheck()
            }, Unmanaged.passUnretained(self).toOpaque(), &notification)
        guard result == KERN_SUCCESS else {
            IONotificationPortDestroy(port)
            return
        }
        self.port = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        lastSeen = IsSecureEventInputEnabled()
    }

    func stop() {
        if notification != 0 { IOObjectRelease(notification) }
        notification = 0
        if let port { IONotificationPortDestroy(port) }
        port = nil
    }

    private func recheck() {
        let enabled = IsSecureEventInputEnabled()
        guard enabled != lastSeen else { return }
        lastSeen = enabled
        onChange(enabled)
    }
}
