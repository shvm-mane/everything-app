// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum PointerTapRunLoop {
    static func add(_ source: CFRunLoopSource) {
        CFRunLoopAddSource(runLoop, source, .commonModes)
    }

    static func remove(_ source: CFRunLoopSource, invalidating port: CFMachPort?) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            if let port {
                CFMachPortInvalidate(port)
            }
        }
        CFRunLoopWakeUp(runLoop)
    }

    private static let runLoop: CFRunLoop = {
        var started: CFRunLoop?
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            started = CFRunLoopGetCurrent()
            RunLoop.current.add(NSMachPort(), forMode: .common)
            ready.signal()
            while true {
                CFRunLoopRunInMode(.defaultMode, .greatestFiniteMagnitude, false)
            }
        }
        thread.name = "EVERYTHING Pointer Input"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return started!
    }()
}
