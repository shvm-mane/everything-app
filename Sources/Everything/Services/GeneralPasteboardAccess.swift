// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

final class GeneralPasteboardAccess {
    static let shared = GeneralPasteboardAccess()

    typealias DeadlineScheduler = (_ delay: TimeInterval,
                                   _ action: @escaping () -> Void) -> (() -> Void)

    private let queue: DispatchQueue
    private let now: () -> TimeInterval
    private let scheduleDeadline: DeadlineScheduler

    init(label: String = "EVERYTHING.Pasteboard.general",
         now: @escaping () -> TimeInterval = {
             TimeInterval(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
         },
         scheduleDeadline: DeadlineScheduler? = nil) {
        queue = DispatchQueue(label: label, qos: .utility)
        self.now = now
        self.scheduleDeadline = scheduleDeadline ?? { delay, action in
            let item = DispatchWorkItem(block: action)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            return { item.cancel() }
        }
    }

    func async(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }

    func async<T>(_ work: @escaping () -> T, then completion: @escaping (T) -> Void) {
        queue.async {
            let result = work()
            DispatchQueue.main.async { completion(result) }
        }
    }

    func async<T>(timeout: TimeInterval,
                   _ work: @escaping (_ isExpired: () -> Bool) -> T?,
                   then completion: @escaping (T?) -> Void,
                   didFinish: @escaping (T?) -> Void = { _ in }) {
        let deadline = now() + timeout
        let delivery = PasteboardResultDelivery(completion)
        let cancelDeadline = scheduleDeadline(timeout) { delivery.complete(nil) }
        queue.async {
            let isExpired = { self.now() >= deadline }
            let value = isExpired() ? nil : work(isExpired)
            DispatchQueue.main.async {
                cancelDeadline()
                didFinish(value)
                delivery.complete(isExpired() ? nil : value)
            }
        }
    }
}

private final class PasteboardResultDelivery<Value> {
    private var completion: ((Value?) -> Void)?

    init(_ completion: @escaping (Value?) -> Void) {
        self.completion = completion
    }

    func complete(_ value: Value?) {
        precondition(Thread.isMainThread)
        let callback = completion
        completion = nil
        callback?(value)
    }
}
