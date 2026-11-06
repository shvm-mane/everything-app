// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import IOKit

struct CPUCoreTicks {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32

    func usage(since previous: Self) -> Double? {
        let current = [user, system, idle, nice]
        let earlier = [previous.user, previous.system, previous.idle, previous.nice]
        var deltas: [UInt64] = []
        for (new, old) in zip(current, earlier) {
            guard new >= old || old - new > UInt32.max / 2 else { return nil }
            deltas.append(UInt64(new &- old))
        }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return nil }
        return Double(total - deltas[2]) / Double(total)
    }
}

final class CPUCoreSampler {
    private var previous: (ticks: [CPUCoreTicks], time: TimeInterval)?

    func sample(now: TimeInterval) -> [Double?] {
        let stride = Int(CPU_STATE_MAX)
        guard let ticks = processorInfo(PROCESSOR_CPU_LOAD_INFO, stride: stride, { info, processors in
            (0..<processors).map { index in
                let base = index * stride
                return CPUCoreTicks(user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                                    system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                                    idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                                    nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            }
        }) else {
            previous = nil
            return []
        }
        defer { previous = (ticks, now) }
        guard let previous, previous.ticks.count == ticks.count,
              now > previous.time, now - previous.time <= 12.5 else {
            return Array(repeating: nil, count: ticks.count)
        }
        return zip(ticks, previous.ticks).map { $0.usage(since: $1) }
    }

    func reset() {
        previous = nil
    }
}

private func processorInfo<T>(_ flavor: processor_flavor_t, stride: Int,
                              _ read: (processor_info_array_t, Int) -> T) -> T? {
    var processors: natural_t = 0
    var info: processor_info_array_t?
    var count: mach_msg_type_number_t = 0
    let host = mach_host_self()
    defer { mach_port_deallocate(mach_task_self_, host) }
    guard host_processor_info(host, flavor, &processors, &info, &count) == KERN_SUCCESS, let info else { return nil }
    defer {
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                      vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride))
    }
    guard processors > 0, Int(processors) <= Int(count) / stride else { return nil }
    return read(info, Int(processors))
}

