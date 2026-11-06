// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation

enum MemoryRelief {
    private static let queue = DispatchQueue(label: "com.shvmane.everything.memory-relief", qos: .utility)
    private static var pending: DispatchWorkItem?
    private static let lock = NSLock()

    static func soon(after delay: TimeInterval = 1.5) {
        lock.lock(); defer { lock.unlock() }
        pending?.cancel()
        let work = DispatchWorkItem { _ = malloc_zone_pressure_relief(nil, 0) }
        pending = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
