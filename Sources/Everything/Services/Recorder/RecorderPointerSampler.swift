// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

final class RecorderPointerSampler {
    private let region: RecorderSupport.Region
    private let displayBounds: CGRect
    private let pauseClock: RecorderPauseClock

    private var thread: Thread?
    private var clickMonitor: Any?
    private let lock = NSLock()
    private var samples: [RecorderMotion.Sample] = []
    private var identities: [UInt64] = []
    private var clicks: [RecorderMotion.Click] = []
    private let cursors = RecorderCursorCatalog()
    private var running = false
    private var generation = 0
    private var lastSeed: Int32?
    private var currentIdentity: UInt64 = 0
    private let displayScale: Double

    private static let sampleRate: Double = 125

    init(region: RecorderSupport.Region, pauseClock: RecorderPauseClock) {
        self.region = region
        self.pauseClock = pauseClock
        displayBounds = CGDisplayBounds(region.displayID)
        displayScale = region.scale > 0 ? region.scale : 2
    }

    // MARK: - Lifecycle

    func start() {
        guard thread == nil else { return }
        let generation = lock.withLock { () -> Int in
            self.generation += 1
            running = true
            samples.removeAll(keepingCapacity: true)
            samples.reserveCapacity(Int(Self.sampleRate) * 60)
            identities.removeAll(keepingCapacity: true)
            identities.reserveCapacity(Int(Self.sampleRate) * 60)
            lastSeed = nil
            currentIdentity = 0
            clicks.removeAll(keepingCapacity: true)
            return self.generation
        }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
        ) { [weak self] event in
            self?.record(event, generation: generation)
        }

        let thread = Thread { [weak self] in
            self?.loop(generation: generation)
        }
        thread.qualityOfService = .userInteractive
        thread.name = "com.vorssaint.recorder.pointer"
        self.thread = thread
        thread.start()
    }

    func stop() -> RecorderPointerTrack {
        thread = nil
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        return lock.withLock {
            running = false
            let track = RecorderPointerTrack.packing(samples: samples,
                                                     identities: identities,
                                                     clicks: clicks,
                                                     catalog: cursors.collected(),
                                                     systemScale: cursors.systemScale,
                                                     displayScale: displayScale)
            samples.removeAll()
            identities.removeAll()
            clicks.removeAll()
            return track
        }
    }

    // MARK: - Sampling

    private func loop(generation: Int) {
        let interval = 1.0 / Self.sampleRate
        while lock.withLock({ running && self.generation == generation }) {
            let now = CACurrentMediaTime()
            if let time = pauseClock.eventTime(now),
               let point = normalizedPointerLocation() {
                lock.withLock {
                    guard running, self.generation == generation else { return }
                    let seed = cursors.currentSeed()
                    if seed != lastSeed {
                        lastSeed = seed
                        let identity = cursors.captureCurrentShape()
                        if identity != 0 { currentIdentity = identity }
                    }
                    let sample = RecorderMotion.Sample(
                        time: time,
                        point: point,
                        isPointerVisible: cursors.isPointerVisible()
                    )
                    samples.append(sample)
                    identities.append(currentIdentity)
                }
            }
            let elapsed = CACurrentMediaTime() - now
            if elapsed < interval {
                Thread.sleep(forTimeInterval: interval - elapsed)
            }
        }
    }

    private func normalizedPointerLocation() -> CGPoint? {
        guard let location = CGEvent(source: nil)?.location,
              location.x.isFinite, location.y.isFinite
        else { return nil }
        let scale = region.scale > 0 ? region.scale : 1
        let originX = displayBounds.origin.x + region.pixelRect.origin.x / scale
        let originY = displayBounds.origin.y + region.pixelRect.origin.y / scale
        let width = region.pixelRect.width / scale
        let height = region.pixelRect.height / scale
        guard width > 0, height > 0 else { return nil }
        return CGPoint(x: (location.x - originX) / width,
                       y: (location.y - originY) / height)
    }

    private func record(_ event: NSEvent, generation: Int) {
        lock.withLock {
            guard running, self.generation == generation else { return }
            guard let time = pauseClock.eventTime(CACurrentMediaTime())
            else { return }
            let isDown = event.type == .leftMouseDown || event.type == .rightMouseDown
            let click = RecorderMotion.Click(time: time, isDown: isDown)
            clicks.append(click)
        }
    }

}
