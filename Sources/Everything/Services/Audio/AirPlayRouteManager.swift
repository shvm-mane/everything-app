// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import AVKit
import Combine
import CoreMedia
import Foundation
import ObjectiveC

final class AirPlayRouteManager: NSObject, ObservableObject {
    static let shared = AirPlayRouteManager()

    static let airPlaySentinelUID = "vorssaint.output.airplay"

    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var activeSpeakerName: String?
    private(set) static var isPresentingPicker = false

    private static let snapshotLock = NSLock()
    private static var snapshotIsListed = false
    private static var snapshotSpeakerName: String?
    private static var snapshotIsConnected = false

    static var isListed: Bool {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return snapshotIsListed
    }

    static var isSpeakerConnected: Bool {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return snapshotIsConnected
    }

    static var currentSpeakerName: String? {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return snapshotSpeakerName
    }

    private var cachedIsConnected: Bool = false
    private var cachedSpeakerName: String?

    private var routingContext: NSObject?
    private var routingContextID: String?
    private var pollTimer: Timer?
    private var contextObservers: [NSObjectProtocol] = []
    private var onChange: (() -> Void)?

    private typealias MsgSendClass = @convention(c) (AnyClass, Selector) -> AnyObject?
    private typealias MsgSendObj = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
    private typealias MsgSendObjReturn = @convention(c) (AnyObject, Selector) -> AnyObject?

    private let msgSendSym = dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend")

    private override init() {
        dispatchPrecondition(condition: .onQueue(.main))
        super.init()
        let systemSupported: Bool
        if #available(macOS 27, *) { systemSupported = true } else { systemSupported = false }
        if systemSupported {
            dlopen("/System/Library/Frameworks/AVKit.framework/AVKit", RTLD_NOW)
            dlopen("/System/Library/Frameworks/AVFoundation.framework/AVFoundation", RTLD_NOW)
            setupContext()
        }
        self.isAvailable = AirPlayAvailability.isAvailable(
            mixerSupported: systemSupported,
            hasContext: routingContext != nil,
            contextID: routingContextID,
            pickerCanBind: AVRoutePickerView.instancesRespond(to: sel_registerName("setOutputContextID:")),
            rendererCanBind: AVSampleBufferAudioRenderer.instancesRespond(to: sel_registerName("setOutputContext:")))
    }

    deinit {
        pollTimer?.invalidate()
    }

    func activate(onChange: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.onChange = onChange
        Self.snapshotLock.lock()
        Self.snapshotIsListed = isAvailable
        Self.snapshotLock.unlock()
        guard isAvailable, let context = routingContext else { return }
        refreshActiveDevice()
        if contextObservers.isEmpty {
            contextObservers = ["AVOutputContextOutputDeviceDidChangeNotification",
                                "AVOutputContextOutputDevicesDidChangeNotification"].map { name in
                NotificationCenter.default.addObserver(forName: Notification.Name(name), object: context,
                                                       queue: .main) { [weak self] _ in
                    self?.refreshActiveDevice()
                }
            }
        }
        updateStreamCheck()
    }

    func deactivate() {
        dispatchPrecondition(condition: .onQueue(.main))
        contextObservers.forEach(NotificationCenter.default.removeObserver)
        contextObservers = []
        pollTimer?.invalidate()
        pollTimer = nil
        idleCheck?.cancel()
        idleCheck = nil
        streamLock.lock()
        idleTimer.forgetSilence()
        streamLock.unlock()
        onChange = nil
        Self.snapshotLock.lock()
        Self.snapshotIsListed = false
        Self.snapshotIsConnected = false
        Self.snapshotLock.unlock()
    }

    private func setupContext() {
        guard let cls = NSClassFromString("AVOutputContext"), let sym = msgSendSym else { return }
        let msgClass = unsafeBitCast(sym, to: MsgSendClass.self)
        let defaultShared = sel_registerName("defaultSharedOutputContext")
        guard class_getClassMethod(cls, defaultShared) != nil,
              let context = msgClass(cls, defaultShared) as? NSObject else { return }
        routingContext = context
        routingContextID = AirPlayPrivateAPI.string(context, "ID")
    }

    private func makeRoutePickerView() -> AVRoutePickerView? {
        guard isAvailable, let contextID = routingContextID, let sym = msgSendSym else { return nil }
        let picker = AVRoutePickerView()
        let msgObj = unsafeBitCast(sym, to: MsgSendObj.self)
        let setCtxSel = sel_registerName("setOutputContextID:")
        guard picker.responds(to: setCtxSel) else { return nil }
        msgObj(picker, setCtxSel, contextID as AnyObject)
        picker.delegate = self
        return picker
    }

    private var fallbackWindow: NSWindow?
    private weak var fallbackPicker: AVRoutePickerView?
    private var pickerGeneration = 0

    func presentPicker() {
        guard isAvailable else { return }
        closePickerWindow()

        let mouseLoc = NSEvent.mouseLocation
        let win = NSWindow(
            contentRect: NSRect(x: mouseLoc.x - 10, y: mouseLoc.y - 10, width: 20, height: 20),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.alphaValue = 0.01
        win.level = .popUpMenu
        win.hasShadow = false
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        if let picker = makeRoutePickerView() {
            picker.frame = NSRect(x: 0, y: 0, width: 20, height: 20)
            win.contentView?.addSubview(picker)
            win.orderFrontRegardless()
            self.fallbackWindow = win
            self.fallbackPicker = picker

            DispatchQueue.main.asyncAfter(deadline: .now() + 180) { [weak self, weak win] in
                guard let self, let win, self.fallbackWindow === win else { return }
                self.closePickerWindow()
            }

            if let button = findButton(in: picker) {
                button.performClick(nil)
            }
        }
    }

    private func closePickerWindow() {
        fallbackWindow?.orderOut(nil)
        fallbackWindow = nil
        fallbackPicker = nil
        pickerGeneration += 1
        Self.isPresentingPicker = false
    }

    private func findButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton { return button }
        for subview in view.subviews {
            if let found = findButton(in: subview) { return found }
        }
        return nil
    }

    func refreshActiveDevice() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let context = routingContext, let sym = msgSendSym else { return }
        let msgObjReturn = unsafeBitCast(sym, to: MsgSendObjReturn.self)

        var name: String? = nil
        let outputDevicesSel = sel_registerName("outputDevices")
        if context.responds(to: outputDevicesSel),
           let devices = msgObjReturn(context, outputDevicesSel) as? [NSObject] {
            let names = devices.compactMap { dev -> String? in
                guard let n = AirPlayPrivateAPI.string(dev, "name"), !n.isEmpty, !n.hasPrefix("APEndpoint") else {
                    return nil
                }
                return n
            }
            if !names.isEmpty {
                name = names.sorted().joined(separator: " + ")
            }
        }

        if name == nil {
            let outputDevSel = sel_registerName("outputDevice")
            if context.responds(to: outputDevSel),
               let dev = msgObjReturn(context, outputDevSel) as? NSObject,
               let n = AirPlayPrivateAPI.string(dev, "name"),
               !n.isEmpty, !n.hasPrefix("APEndpoint") {
                name = n
            }
        }

        let outputDevSel = sel_registerName("outputDevice")
        let hasDevice = context.responds(to: outputDevSel) && msgObjReturn(context, outputDevSel) != nil
        let connected = AirPlayAvailability.isConnected(hasDevice: hasDevice, speakerName: name,
                                                        failedSpeakerName: streamingFailedFor)

        let connectedChanged = cachedIsConnected != connected
        let nameChanged = cachedSpeakerName != name
        cachedIsConnected = connected
        cachedSpeakerName = name
        Self.snapshotLock.lock()
        Self.snapshotSpeakerName = name
        Self.snapshotIsConnected = connected
        Self.snapshotLock.unlock()

        if connectedChanged {
            self.isConnected = connected
        }
        if nameChanged {
            self.activeSpeakerName = name
        }
        if connectedChanged || nameChanged {
            onChange?()
        }
    }

    func bindOutputContext(to audioObject: AnyObject) -> Bool {
        guard let context = routingContext, let sym = msgSendSym else { return false }
        let setCtxSel = sel_registerName("setOutputContext:")
        guard audioObject.responds(to: setCtxSel) else { return false }
        let msgObj = unsafeBitCast(sym, to: MsgSendObj.self)
        msgObj(audioObject, setCtxSel, context)
        return true
    }

    // MARK: - Per-App AirPlay Streaming

    private var airPlayRenderer: AirPlayRenderer?
    private let mixerSource = MixingAudioSource()
    private lazy var streams = AirPlayStreamRegistry(mixer: mixerSource)
    private let streamLock = NSLock()

    func addAudioStream(appID: String, buffer: AudioRingBuffer) -> AirPlayStreamRegistration? {
        streamLock.lock()
        defer { streamLock.unlock() }
        if idleTimer.startsRendererForNewStream {
            startRendererIfNeeded()
            guard airPlayRenderer != nil else { return nil }
        }
        let registration = streams.register(appID: appID, buffer: buffer) { [weak self] token in
            self?.endAudioStream(token)
        }
        DispatchQueue.main.async { [weak self] in
            self?.updateStreamCheck()
            self?.scheduleIdleCheck()
        }
        return registration
    }

    // MARK: Pausing for silence

    private var idleTimer = AirPlayIdleTimer()
    private var idleCheck: DispatchWorkItem?

    func routedAudioChanged(active: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        streamLock.lock()
        let freshRenderer = idleTimer.update(active: active, now: ProcessInfo.processInfo.systemUptime,
                                             rendererStartedAt: airPlayRenderer?.startedAt)
        if freshRenderer {
            stopRenderer()
            if !streams.isEmpty { startRendererIfNeeded() }
        }
        streamLock.unlock()
        guard active else {
            scheduleIdleCheck()
            return
        }
        idleCheck?.cancel()
        idleCheck = nil
        updateStreamCheck()
    }

    private func scheduleIdleCheck() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard idleCheck == nil else { return }
        streamLock.lock()
        let remaining = idleTimer.secondsUntilStop(now: ProcessInfo.processInfo.systemUptime,
                                                   rendererStartedAt: airPlayRenderer?.startedAt)
        streamLock.unlock()
        guard let remaining else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.idleCheck = nil
            self?.stopIfSilent()
        }
        idleCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: work)
    }

    private func stopIfSilent() {
        streamLock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        let rendererStartedAt = airPlayRenderer?.startedAt
        let remaining = idleTimer.secondsUntilStop(now: now, rendererStartedAt: rendererStartedAt)
        if idleTimer.stopsForSilence(now: now, rendererStartedAt: rendererStartedAt) {
            stopRenderer()
        }
        streamLock.unlock()
        guard let remaining else { return }
        guard remaining <= 0 else {
            scheduleIdleCheck()
            return
        }
        updateStreamCheck()
    }

    private func updateStreamCheck() {
        dispatchPrecondition(condition: .onQueue(.main))
        streamLock.lock()
        let streaming = airPlayRenderer != nil
        streamLock.unlock()
        let wanted = AirPlayAvailability.runsBackupCheck(rendererRunning: streaming, mixerActive: onChange != nil,
                                                         available: isAvailable)
        if wanted, pollTimer == nil {
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                self?.refreshActiveDevice()
            }
        } else if !wanted, let timer = pollTimer {
            timer.invalidate()
            pollTimer = nil
        }
    }

    private var streamingFailedFor: String?

    private func rendererFailed(_ renderer: AirPlayRenderer) {
        streamLock.lock()
        let current = airPlayRenderer === renderer
        streamLock.unlock()
        if current { reportStreamingFailure() }
    }

    func reportStreamingFailure() {
        dispatchPrecondition(condition: .onQueue(.main))
        streamingFailedFor = cachedSpeakerName ?? ""
        refreshActiveDevice()
    }

    func prepareToStream() -> Bool {
        streamLock.lock()
        defer { streamLock.unlock() }
        if !idleTimer.startsRendererForNewStream { return true }
        startRendererIfNeeded()
        return airPlayRenderer != nil
    }

    func stopIfIdle() {
        streamLock.lock()
        defer { streamLock.unlock() }
        if streams.isEmpty {
            stopRenderer()
        }
    }

    private func endAudioStream(_ token: Int) {
        streamLock.lock()
        defer { streamLock.unlock() }
        if streams.remove(token) {
            stopRenderer()
            idleTimer.lastStreamEnded()
            DispatchQueue.main.async { [weak self] in self?.updateStreamCheck() }
        }
    }

    private func startRendererIfNeeded() {
        guard airPlayRenderer == nil else { return }
        guard let renderer = AirPlayRenderer(source: mixerSource, manager: self) else { return }
        renderer.onFailure = { [weak self, weak renderer] in
            guard let self, let renderer else { return }
            self.rendererFailed(renderer)
        }
        renderer.start()
        self.airPlayRenderer = renderer
    }

    private func stopRenderer() {
        airPlayRenderer?.stop()
        airPlayRenderer = nil
    }
}

// MARK: - Private API access

enum AirPlayPrivateAPI {
    static func string(_ object: NSObject, _ key: String) -> String? {
        guard object.responds(to: NSSelectorFromString(key)) else { return nil }
        return object.value(forKey: key) as? String
    }
}

// MARK: - Availability

enum AirPlayAvailability {
    static func isConnected(hasDevice: Bool, speakerName: String?, failedSpeakerName: String?) -> Bool {
        guard hasDevice, let speakerName else { return false }
        return speakerName != failedSpeakerName
    }

    static func isAvailable(mixerSupported: Bool, hasContext: Bool, contextID: String?,
                            pickerCanBind: Bool, rendererCanBind: Bool) -> Bool {
        mixerSupported && hasContext && !(contextID?.isEmpty ?? true) && pickerCanBind && rendererCanBind
    }

    static func runsBackupCheck(rendererRunning: Bool, mixerActive: Bool, available: Bool) -> Bool {
        rendererRunning && mixerActive && available
    }
}

// MARK: - Silence

struct AirPlayIdleTimer {
    static let delay: TimeInterval = 10
    static let freshStreamAfter: TimeInterval = 1
    private var silentSince: TimeInterval?
    private var isPaused = false

    @discardableResult
    mutating func update(active: Bool, now: TimeInterval, rendererStartedAt: TimeInterval?) -> Bool {
        guard active else {
            if silentSince == nil {
                silentSince = now
            }
            return false
        }
        let pauseBegan = silentSince
        silentSince = nil
        if isPaused {
            isPaused = false
            return true
        }
        guard let pauseBegan, let rendererStartedAt, rendererStartedAt < pauseBegan else { return false }
        return now - pauseBegan >= Self.freshStreamAfter
    }

    func secondsUntilStop(now: TimeInterval, rendererStartedAt: TimeInterval?) -> TimeInterval? {
        guard let silentSince else { return nil }
        let quietSince = max(silentSince, rendererStartedAt ?? silentSince)
        return max(0, quietSince + Self.delay - now)
    }

    mutating func stopsForSilence(now: TimeInterval, rendererStartedAt: TimeInterval?) -> Bool {
        guard rendererStartedAt != nil,
              let remaining = secondsUntilStop(now: now, rendererStartedAt: rendererStartedAt),
              remaining <= 0 else { return false }
        isPaused = true
        return true
    }

    var startsRendererForNewStream: Bool { !isPaused }

    mutating func lastStreamEnded() {
        isPaused = false
    }

    mutating func forgetSilence() {
        silentSince = nil
    }
}

// MARK: - Stream registrations

final class AirPlayStreamRegistry: @unchecked Sendable {
    private struct Entry {
        let token: Int
        let buffer: AudioRingBuffer
    }

    private let mixer: MixingAudioSource
    private let lock = NSLock()
    private var nextToken = 0
    private var lanes: [String: [Entry]] = [:]

    init(mixer: MixingAudioSource) {
        self.mixer = mixer
    }

    func register(appID: String, buffer: AudioRingBuffer,
                  onEnd: @escaping (Int) -> Void) -> AirPlayStreamRegistration {
        lock.lock()
        defer { lock.unlock() }
        nextToken += 1
        let token = nextToken
        lanes[appID, default: []].append(Entry(token: token, buffer: buffer))
        mixer.setBuffer(buffer, forKey: appID, startingAt: buffer.writePosition)
        return AirPlayStreamRegistration(token: token, onEnd: onEnd)
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return lanes.isEmpty
    }

    func remove(_ token: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let appID = lanes.first(where: { $0.value.contains { $0.token == token } })?.key,
              var entries = lanes[appID],
              let index = entries.firstIndex(where: { $0.token == token }) else { return false }
        let wasAudible = index == entries.count - 1
        entries.remove(at: index)
        if let fallback = entries.last {
            lanes[appID] = entries
            if wasAudible {
                mixer.setBuffer(fallback.buffer, forKey: appID, startingAt: fallback.buffer.writePosition)
            }
        } else {
            lanes.removeValue(forKey: appID)
            mixer.removeBuffer(forKey: appID)
        }
        return lanes.isEmpty
    }
}

final class AirPlayStreamRegistration: @unchecked Sendable {
    let token: Int
    private let lock = NSLock()
    private var onEnd: ((Int) -> Void)?

    init(token: Int, onEnd: @escaping (Int) -> Void) {
        self.token = token
        self.onEnd = onEnd
    }

    func end() {
        lock.lock()
        let pending = onEnd
        onEnd = nil
        lock.unlock()
        pending?(token)
    }
}

// MARK: - Feed scheduling

final class AirPlayFeedDriver: @unchecked Sendable {
    static let sharedQueue = DispatchQueue(label: "com.vorssaint.utils.airplay.render", qos: .userInitiated)
    private static let queueKey = DispatchSpecificKey<Void>()

    private let queue: DispatchQueue
    private let interval: DispatchTimeInterval
    private let timerLock = NSLock()
    private var timer: DispatchSourceTimer?
    private var isActive = false

    init(queue: DispatchQueue = AirPlayFeedDriver.sharedQueue, interval: DispatchTimeInterval = .milliseconds(25)) {
        self.queue = queue
        self.interval = interval
        queue.setSpecific(key: Self.queueKey, value: ())
    }

    func start(_ step: @escaping () -> Void) {
        queue.sync { isActive = true }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: interval)
        source.setEventHandler { [weak self] in
            guard let self, self.isActive else { return }
            step()
        }
        timerLock.lock()
        timer?.cancel()
        timer = source
        timerLock.unlock()
        source.resume()
    }

    func stop() {
        timerLock.lock()
        let source = timer
        timer = nil
        timerLock.unlock()
        source?.cancel()
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            isActive = false
        } else {
            queue.sync { isActive = false }
        }
    }
}

// MARK: - Ring Buffer & Streaming Pipeline

final class AudioRingBuffer: @unchecked Sendable {
    private let capacityFrames: Int
    private let storage: UnsafeMutablePointer<Float>
    private let positions: UnsafeMutablePointer<Int64>

    init(sampleRate: Double = 44_100, capacityFrames: Int = 1 << 16, startingFramePosition: Int64 = 0) {
        var cap = 1
        while cap < capacityFrames { cap <<= 1 }
        self.capacityFrames = cap
        storage = .allocate(capacity: cap * 2)
        storage.initialize(repeating: 0, count: cap * 2)
        positions = .allocate(capacity: 3)
        positions.initialize(repeating: startingFramePosition, count: 2)
        (positions + 2).initialize(to: Int64(bitPattern: (sampleRate > 0 ? sampleRate : 44_100).bitPattern))
    }

    var sampleRate: Double {
        get { Double(bitPattern: UInt64(bitPattern: OSAtomicAdd64Barrier(0, positions + 2))) }
        set {
            guard newValue > 0, newValue.isFinite else { return }
            let replacement = Int64(bitPattern: newValue.bitPattern)
            while true {
                let current = OSAtomicAdd64Barrier(0, positions + 2)
                if OSAtomicCompareAndSwap64Barrier(current, replacement, positions + 2) { return }
            }
        }
    }

    deinit {
        storage.deallocate()
        positions.deallocate()
    }

    private var head: UnsafeMutablePointer<Int64> { positions }
    private var tail: UnsafeMutablePointer<Int64> { positions + 1 }

    func write(frames: UnsafePointer<Float>, frameCount: Int, channels: Int = 2, gain: Float) {
        guard channels > 0 else { return }
        let t = OSAtomicAdd64Barrier(0, tail)
        let h = OSAtomicAdd64Barrier(0, head)
        let used = min(capacityFrames, max(0, Int(t - h)))
        let count = min(frameCount, capacityFrames - used)
        guard count > 0 else { return }

        let mask = Int64(capacityFrames - 1)
        let right = min(1, channels - 1)
        for i in 0..<count {
            let slot = Int((t + Int64(i)) & mask) * 2
            let frame = i * channels
            storage[slot] = frames[frame] * gain
            storage[slot + 1] = frames[frame + right] * gain
        }
        _ = OSAtomicAdd64Barrier(Int64(count), tail)
    }

    var writePosition: Int64 { OSAtomicAdd64Barrier(0, tail) }

    var availableFrames: Int {
        let h = OSAtomicAdd64Barrier(0, head)
        let t = OSAtomicAdd64Barrier(0, tail)
        return max(0, Int(t - h))
    }

    func skip(to position: Int64) {
        let h = OSAtomicAdd64Barrier(0, head)
        let target = min(position, OSAtomicAdd64Barrier(0, tail))
        if target > h { _ = OSAtomicAdd64Barrier(target - h, head) }
    }

    @discardableResult
    func read(into destination: UnsafeMutablePointer<Float>, frameCount: Int) -> Int {
        let h = OSAtomicAdd64Barrier(0, head)
        let t = OSAtomicAdd64Barrier(0, tail)
        let count = min(frameCount, max(0, Int(t - h)))

        let mask = Int64(capacityFrames - 1)
        for i in 0..<count {
            let slot = Int((h + Int64(i)) & mask) * 2
            destination[i * 2] = storage[slot]
            destination[i * 2 + 1] = storage[slot + 1]
        }
        if count < frameCount {
            (destination + count * 2).update(repeating: 0, count: (frameCount - count) * 2)
        }
        if count > 0 {
            _ = OSAtomicAdd64Barrier(Int64(count), head)
        }
        return count
    }
}

final class LinearResampler: @unchecked Sendable {
    private let buffer: AudioRingBuffer
    private var phase: Double = 0
    private var carry: [Float] = []
    private var scratch = [Float](repeating: 0, count: 8192 * 2)

    private var startPosition: Int64?

    static let maximumBacklog = 0.2
    static let keptBacklog = 0.05

    init(buffer: AudioRingBuffer, startingAt position: Int64? = nil) {
        self.buffer = buffer
        self.startPosition = position
    }

    func read(into destination: UnsafeMutablePointer<Float>, frameCount: Int) {
        if let position = startPosition {
            startPosition = nil
            buffer.skip(to: position)
        }
        let rate = buffer.sampleRate
        if buffer.availableFrames > Int(rate * Self.maximumBacklog) {
            buffer.skip(to: buffer.writePosition - Int64(rate * Self.keptBacklog))
            carry.removeAll(keepingCapacity: true)
            phase = 0
        }
        guard frameCount > 0 else { return }
        let sourceRate = buffer.sampleRate > 0 ? buffer.sampleRate : 44_100
        let ratio = sourceRate / 44_100.0

        if abs(ratio - 1.0) < 0.0001 {
            buffer.read(into: destination, frameCount: frameCount)
            carry.removeAll(keepingCapacity: true)
            phase = 0
            return
        }

        let totalNeeded = Int(phase + Double(frameCount - 1) * ratio) + 2
        let carryFrames = carry.count / 2
        let freshNeeded = max(0, totalNeeded - carryFrames)

        if scratch.count < totalNeeded * 2 {
            scratch = [Float](repeating: 0, count: totalNeeded * 2)
        }

        scratch.withUnsafeMutableBufferPointer { sourceBuffer in
            guard let source = sourceBuffer.baseAddress else { return }
            for (index, sample) in carry.enumerated() { source[index] = sample }
            if freshNeeded > 0 {
                buffer.read(into: source + carry.count, frameCount: freshNeeded)
            }

            for frame in 0..<frameCount {
                let position = phase + Double(frame) * ratio
                let index = min(Int(position), totalNeeded - 2)
                let fraction = Float(position - Double(index))

                let left0 = source[index * 2]
                let right0 = source[index * 2 + 1]
                let left1 = source[(index + 1) * 2]
                let right1 = source[(index + 1) * 2 + 1]

                destination[frame * 2] = left0 + (left1 - left0) * fraction
                destination[frame * 2 + 1] = right0 + (right1 - right0) * fraction
            }

            let endPosition = phase + Double(frameCount) * ratio
            let consumed = min(Int(endPosition), totalNeeded)
            phase = endPosition - Double(consumed)

            carry.removeAll(keepingCapacity: true)
            for index in (consumed * 2)..<(totalNeeded * 2) {
                carry.append(source[index])
            }
        }
    }
}

final class MixingAudioSource: @unchecked Sendable {
    private let lock = NSLock()
    private var resamplers: [String: LinearResampler] = [:]
    private var mixBus = [Float](repeating: 0, count: 4096 * 2)
    private var laneBus = [Float](repeating: 0, count: 4096 * 2)
    private let limiter = BoostLookaheadLimiter(channels: 2)
    private let limiterRelease = BoostLimiter.release(sampleRate: 44_100)

    func setBuffer(_ buffer: AudioRingBuffer, forKey key: String, startingAt position: Int64? = nil) {
        lock.lock()
        resamplers[key] = LinearResampler(buffer: buffer, startingAt: position)
        lock.unlock()
    }

    func removeBuffer(forKey key: String) {
        lock.lock()
        resamplers.removeValue(forKey: key)
        lock.unlock()
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return resamplers.isEmpty
    }

    func readFrames(into buffer: UnsafeMutablePointer<Int16>, frameCount: Int) {
        lock.lock()
        let lanes = Array(resamplers.values)
        lock.unlock()

        let samples = frameCount * 2
        if mixBus.count < samples {
            mixBus = [Float](repeating: 0, count: samples)
            laneBus = [Float](repeating: 0, count: samples)
        }

        mixBus.withUnsafeMutableBufferPointer { mix in
            guard let mixBase = mix.baseAddress else { return }
            for index in 0..<samples { mixBase[index] = 0 }

            laneBus.withUnsafeMutableBufferPointer { lane in
                guard let laneBase = lane.baseAddress else { return }
                for resampler in lanes {
                    resampler.read(into: laneBase, frameCount: frameCount)
                    for index in 0..<samples { mixBase[index] += laneBase[index] }
                }
            }
            limiter.process(mixBase, frames: frameCount, channels: 2, release: limiterRelease)

            for index in 0..<samples {
                let scaled = mixBase[index] * 32_767
                buffer[index] = Int16(max(-32_768, min(32_767, scaled)))
            }
        }
    }
}

struct AirPlayRendererWatch {
    static let stallLimit: TimeInterval = 10
    static let startLimit: TimeInterval = 60
    private var startedAt: TimeInterval?
    private var lastReady: TimeInterval?
    private var hasPlayed = false
    private var reported = false

    mutating func shouldReport(failed: Bool, ready: Bool, playing: Bool, now: TimeInterval) -> Bool {
        guard !reported else { return false }
        if startedAt == nil { startedAt = now }
        hasPlayed = hasPlayed || playing
        if ready || !playing || lastReady == nil { lastReady = now }
        let stalled = now - (lastReady ?? now) > Self.stallLimit
        let neverStarted = !hasPlayed && now - (startedAt ?? now) > Self.startLimit
        guard failed || stalled || neverStarted else { return false }
        reported = true
        return true
    }
}

final class AirPlayRenderer: @unchecked Sendable {
    private let source: MixingAudioSource
    private let renderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let feed = AirPlayFeedDriver()
    var onFailure: (() -> Void)?
    let startedAt = ProcessInfo.processInfo.systemUptime
    private var watch = AirPlayRendererWatch()

    private let formatDescription: CMAudioFormatDescription
    private let sampleRate: Double = 44_100
    private let framesPerChunk = 2_048
    private var started = false
    private var nextPTS = CMTime.zero

    init?(source: MixingAudioSource, manager: AirPlayRouteManager) {
        self.source = source

        var asbd = AudioStreamBasicDescription(
            mSampleRate: 44_100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &asbd,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &format
        ) == noErr, let format else { return nil }
        self.formatDescription = format

        guard manager.bindOutputContext(to: renderer) else { return nil }
        synchronizer.addRenderer(renderer)
    }

    func start() {
        guard !started else { return }
        started = true
        nextPTS = CMTime.zero

        synchronizer.setRate(1.0, time: .zero)
        feed.start { [weak self] in
            self?.provide()
        }
    }

    func stop() {
        guard started else { return }
        started = false
        feed.stop()
        renderer.flush()
        synchronizer.rate = 0
    }

    deinit { feed.stop() }

    private let targetLookahead = 0.75

    private func provide() {
        if watch.shouldReport(failed: renderer.status == .failed, ready: renderer.isReadyForMoreMediaData,
                              playing: CMTimeGetSeconds(synchronizer.currentTime()) > 0.1,
                              now: ProcessInfo.processInfo.systemUptime) {
            let failure = onFailure
            DispatchQueue.main.async { failure?() }
        }
        let now = synchronizer.currentTime()
        if CMTimeCompare(nextPTS, now) < 0 {
            nextPTS = CMTimeAdd(now, CMTime(value: CMTimeValue(sampleRate * 0.05), timescale: CMTimeScale(sampleRate)))
        }
        while renderer.isReadyForMoreMediaData {
            let lookahead = CMTimeGetSeconds(CMTimeSubtract(nextPTS, synchronizer.currentTime()))
            if lookahead > targetLookahead { break }

            guard let buffer = makeSampleBuffer() else { break }
            renderer.enqueue(buffer)
        }
    }

    private func makeSampleBuffer() -> CMSampleBuffer? {
        let format = formatDescription
        let frames = framesPerChunk
        let byteCount = frames * 4

        var pcm = [Int16](repeating: 0, count: frames * 2)
        pcm.withUnsafeMutableBufferPointer { source.readFrames(into: $0.baseAddress!, frameCount: frames) }

        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: byteCount, flags: 0, blockBufferOut: &blockBuffer
        ) == kCMBlockBufferNoErr, let block = blockBuffer else { return nil }

        let copied = pcm.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: byteCount)
        }
        guard copied == kCMBlockBufferNoErr else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: nextPTS, decodeTimeStamp: .invalid
        )
        var sampleSize = 4
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sampleBuffer
        ) == noErr, let buffer = sampleBuffer else { return nil }

        nextPTS = CMTimeAdd(nextPTS, CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(sampleRate)))
        return buffer
    }
}

extension AirPlayRouteManager: AVRoutePickerViewDelegate {
    func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
        streamingFailedFor = nil
        pickerGeneration += 1
        Self.isPresentingPicker = true
    }

    func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
        let generation = pickerGeneration
        let isCurrent = routePickerView === fallbackPicker
        if isCurrent {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.fallbackPicker === routePickerView else { return }
                self.fallbackWindow?.orderOut(nil)
                self.fallbackWindow = nil
                self.fallbackPicker = nil
            }
        }
        refreshActiveDevice()
        for delay in [1.0, 2.5, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshActiveDevice()
            }
        }
        guard isCurrent else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.pickerGeneration == generation else { return }
            Self.isPresentingPicker = false
        }
    }
}
