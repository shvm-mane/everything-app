// SPDX-License-Identifier: GPL-3.0-or-later
// EVERYTHING: hands freed memory back to the system after transient work.

import Darwin
import Foundation

/// The allocator keeps pages freed by a closed island page, a colour pick's
/// frozen screen or a closed Settings window, and they keep counting against
/// the app's footprint. A moment after such work, this returns them. It frees
/// nothing still in use, so nothing visible changes.
enum MemoryRelief {
    private static let queue = DispatchQueue(label: "com.shvmane.everything.memory-relief", qos: .utility)
    private static var pending: DispatchWorkItem?
    private static let lock = NSLock()

    /// Debounced: a burst of calls relieves once, after things have settled.
    static func soon(after delay: TimeInterval = 1.5) {
        lock.lock(); defer { lock.unlock() }
        pending?.cancel()
        let work = DispatchWorkItem { _ = malloc_zone_pressure_relief(nil, 0) }
        pending = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
