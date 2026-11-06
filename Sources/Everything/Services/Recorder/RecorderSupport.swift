// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Accelerate
import CoreGraphics
import CoreMedia
import Foundation

final class RecorderStartGate: @unchecked Sendable {
    private enum Finalizer {
        case startFailure
        case stop
    }

    private let lock = NSLock()
    private var starting = false
    private var cancelled = false
    private var finalizer: Finalizer?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func begin() -> Bool {
        lock.withLock {
            guard !cancelled, !starting else { return false }
            starting = true
            return true
        }
    }

    var isAuthorized: Bool {
        lock.withLock { !cancelled }
    }

    func claimStartFailure() -> Bool {
        lock.withLock {
            guard finalizer == nil else { return false }
            cancelled = true
            finalizer = .startFailure
            return true
        }
    }

    func cancelAndClaimStop() -> Bool {
        lock.withLock {
            cancelled = true
            guard finalizer == nil else { return false }
            finalizer = .stop
            return true
        }
    }

    func finish() {
        let continuations = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            guard starting else { return [] }
            starting = false
            defer { waiters.removeAll() }
            return waiters
        }
        continuations.forEach { $0.resume() }
    }

    func waitUntilFinished() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { () -> Bool in
                guard starting else { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }
}

struct RecorderCaptureLifecycle {
    private enum State: Equatable {
        case idle
        case starting
        case running
        case stopped
    }

    private var state: State = .idle

    var acceptsSamples: Bool { state == .starting || state == .running }
    var isRunning: Bool { state == .running }

    mutating func beginStart() -> Bool {
        guard state == .idle else { return false }
        state = .starting
        return true
    }

    mutating func didStart() -> Bool {
        guard state == .starting else { return false }
        state = .running
        return true
    }

    mutating func stop() {
        state = .stopped
    }
}

struct RecorderPauseTimeline {
    private struct Interval {
        let start: Double
        let end: Double
    }

    private var intervals: [Interval] = []
    private var pauseStart: Double?

    var isPaused: Bool { pauseStart != nil }

    @discardableResult
    mutating func pause(at time: Double) -> Bool {
        guard time.isFinite, pauseStart == nil else { return false }
        pauseStart = time
        return true
    }

    @discardableResult
    mutating func resume(at time: Double) -> Bool {
        guard time.isFinite, let start = pauseStart else { return false }
        intervals.append(Interval(start: start, end: max(start, time)))
        pauseStart = nil
        return true
    }

    func elapsed(since origin: Double, at time: Double) -> Double {
        guard origin.isFinite, time.isFinite, time > origin else { return 0 }
        return max(0, time - origin - excludedDuration(from: origin, to: time))
    }

    func sampleTime(start: Double, duration: Double, since origin: Double) -> Double? {
        guard start.isFinite, duration.isFinite, origin.isFinite, start >= origin else { return nil }
        let end = start + max(0, duration)
        guard !overlapsPause(from: start, to: end) else { return nil }
        return elapsed(since: origin, at: start)
    }

    func eventTime(_ time: Double, since origin: Double) -> Double? {
        guard time.isFinite, origin.isFinite,
              !overlapsPause(from: time, to: time)
        else { return nil }
        return elapsed(since: origin, at: time)
    }

    private func excludedDuration(from lower: Double, to upper: Double) -> Double {
        let closed = intervals.reduce(0.0) { total, interval in
            total + max(0, min(upper, interval.end) - max(lower, interval.start))
        }
        guard let pauseStart else { return closed }
        return closed + max(0, upper - max(lower, pauseStart))
    }

    private func overlapsPause(from start: Double, to end: Double) -> Bool {
        let isInstant = end <= start
        let overlaps: (Double, Double) -> Bool = { pauseStart, pauseEnd in
            if isInstant { return start >= pauseStart && start < pauseEnd }
            return start < pauseEnd && end > pauseStart
        }
        if intervals.contains(where: { overlaps($0.start, $0.end) }) { return true }
        guard let pauseStart else { return false }
        return isInstant ? start >= pauseStart : end > pauseStart
    }
}

final class RecorderPauseClock {
    private let lock = NSLock()
    private var timeline = RecorderPauseTimeline()
    private var origin: Double?

    var isPaused: Bool { lock.withLock { timeline.isPaused } }

    @discardableResult
    func begin(at time: Double) -> Bool {
        lock.withLock {
            guard origin == nil, time.isFinite else { return false }
            origin = time
            return true
        }
    }

    @discardableResult
    func pause(at time: Double) -> Bool {
        lock.withLock { origin != nil && timeline.pause(at: time) }
    }

    @discardableResult
    func resume(at time: Double) -> Bool {
        lock.withLock { timeline.resume(at: time) }
    }

    func elapsed(at time: Double) -> Double {
        lock.withLock {
            guard let origin else { return 0 }
            return timeline.elapsed(since: origin, at: time)
        }
    }

    func sampleTime(start: Double, duration: Double) -> Double? {
        lock.withLock {
            guard let origin else { return nil }
            return timeline.sampleTime(start: start, duration: duration, since: origin)
        }
    }

    func eventTime(_ time: Double) -> Double? {
        lock.withLock {
            guard let origin, time >= origin else { return nil }
            return timeline.eventTime(time, since: origin)
        }
    }
}

enum RecorderSupport {
    static func pendingStartIsAuthorized(requestGeneration: Int,
                                         currentGeneration: Int,
                                         featureIsAvailable: Bool) -> Bool {
        featureIsAvailable && requestGeneration == currentGeneration
    }

    // MARK: - What is being recorded

    static func exceptedOwnWindowIDs(ownWindowIDs: Set<CGWindowID>,
                                     protectedWindowIDs: Set<CGWindowID>) -> Set<CGWindowID> {
        ownWindowIDs.subtracting(protectedWindowIDs)
    }

    struct Region: Equatable {
        let displayID: CGDirectDisplayID
        let windowID: CGWindowID?
        let pixelRect: CGRect
        let anchorRect: CGRect
        let scale: CGFloat

        var pixelSize: CGSize { pixelRect.size }
    }

    static let minimumSide: CGFloat = 32

    static func evenSize(_ size: CGSize) -> CGSize {
        CGSize(width: evenSide(size.width), height: evenSide(size.height))
    }

    private static func evenSide(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return minimumSide }
        let rounded = max(minimumSide, value.rounded(.down))
        return rounded.truncatingRemainder(dividingBy: 2) == 0 ? rounded : rounded - 1
    }

    static func snappedPixelRect(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        guard rect.width.isFinite, rect.height.isFinite,
              rect.origin.x.isFinite, rect.origin.y.isFinite
        else { return CGRect(origin: bounds.origin, size: evenSize(bounds.size)) }

        let clamped = rect.intersection(bounds).isNull ? bounds : rect.intersection(bounds)
        var origin = CGPoint(x: clamped.origin.x.rounded(.down),
                             y: clamped.origin.y.rounded(.down))
        var size = evenSize(clamped.size)
        if origin.x + size.width > bounds.maxX {
            origin.x = max(bounds.minX, (bounds.maxX - size.width).rounded(.down))
        }
        if origin.y + size.height > bounds.maxY {
            origin.y = max(bounds.minY, (bounds.maxY - size.height).rounded(.down))
        }
        size = evenSize(CGSize(width: min(size.width, bounds.maxX - origin.x),
                               height: min(size.height, bounds.maxY - origin.y)))
        return CGRect(origin: origin, size: size)
    }

    // MARK: - System audio source

    static func trustsSystemAudioTap(previously trusted: Bool,
                                     tapHeardSound: Bool,
                                     streamHeardSound: Bool) -> Bool {
        if tapHeardSound { return true }
        if streamHeardSound { return false }
        return trusted
    }

    static let appTapSettling = CMTime(value: 1, timescale: 2)

    static func streamSoundCountsAgainstTap(at time: CMTime,
                                            hearsOneApp: Bool,
                                            pipelineStart: UInt64) -> Bool {
        guard hearsOneApp else { return true }
        guard pipelineStart != 0, time.isNumeric else { return false }
        return time > CMClockMakeHostTimeFromSystemUnits(pipelineStart) + appTapSettling
    }

    static func systemAudioApp(windowOwner: pid_t?, ownProcess: pid_t) -> pid_t? {
        guard let windowOwner, windowOwner > 0, windowOwner != ownProcess else { return nil }
        return windowOwner
    }

    static func rebuildsAppTap<Process: Hashable>(tapped: Set<Process>, current: Set<Process>) -> Bool {
        !current.isEmpty && current != tapped
    }

    static func restoreTapLevel(_ samples: UnsafeMutablePointer<Float>, count: Int, channels: Int,
                                gain: Float, limiter: inout BoostLimiter, release: Float) {
        guard count > 0, channels > 0 else { return }
        var gain = gain
        vDSP_vsmul(samples, 1, &gain, samples, 1, vDSP_Length(count))
        limiter.process(samples, frames: count / channels, channels: channels, release: release)
    }

    // MARK: - Frame rate

    static let frameRates = [30, 60]

    static func sanitizedFrameRate(_ raw: Int) -> Int {
        frameRates.contains(raw) ? raw : 60
    }

    // MARK: - Quality

    enum Quality: String, CaseIterable {
        case small, balanced, high

        var outputScale: CGFloat {
            switch self {
            case .small: return 0.5
            case .balanced, .high: return 1
            }
        }

        var bitsPerPixel: Double {
            switch self {
            case .small: return 0.05
            case .balanced: return 0.06
            case .high: return 0.09
            }
        }

        var keyframeSeconds: Double {
            switch self {
            case .small, .balanced: return 10
            case .high: return 2
            }
        }
    }

    static func sanitizedQuality(_ raw: String?) -> Quality {
        Quality(rawValue: raw ?? "") ?? .balanced
    }

    static func averageBitRate(width: Int, height: Int, fps: Int, quality: Quality) -> Int {
        let pixels = Double(max(1, width)) * Double(max(1, height))
        let raw = pixels * Double(max(1, fps)) * quality.bitsPerPixel
        return Int(min(max(raw, 800_000), 60_000_000).rounded())
    }

    static let takeQuality: Quality = .high

    static func outputSize(source: CGSize, quality: Quality) -> CGSize {
        evenSize(CGSize(width: source.width * quality.outputScale,
                        height: source.height * quality.outputScale))
    }

    // MARK: - Canvas

    enum Aspect: String, CaseIterable {
        case original, wide, square, vertical

        var ratio: CGFloat? {
            switch self {
            case .original: return nil
            case .wide: return 16.0 / 9.0
            case .square: return 1
            case .vertical: return 9.0 / 16.0
            }
        }
    }

    static func sanitizedAspect(_ raw: String?) -> Aspect {
        Aspect(rawValue: raw ?? "") ?? .original
    }

    struct VideoGeometry: Equatable {
        let size: CGSize
        let transform: CGAffineTransform
    }

    static func videoGeometry(naturalSize: CGSize,
                              preferredTransform: CGAffineTransform) -> VideoGeometry {
        guard naturalSize.width.isFinite, naturalSize.height.isFinite,
              naturalSize.width > 0, naturalSize.height > 0
        else { return VideoGeometry(size: .zero, transform: .identity) }
        let naturalRect = CGRect(origin: .zero, size: naturalSize)
        let displayed = naturalRect.applying(preferredTransform)
        guard displayed.width.isFinite, displayed.height.isFinite,
              displayed.width != 0, displayed.height != 0
        else { return VideoGeometry(size: .zero, transform: .identity) }
        var normalized = preferredTransform
        normalized.tx -= displayed.minX
        normalized.ty -= displayed.minY
        return VideoGeometry(
            size: evenSize(CGSize(width: abs(displayed.width), height: abs(displayed.height))),
            transform: normalized)
    }

    static let maximumCanvasEdge: CGFloat = 3840

    static func canvasSize(source: CGSize,
                           padding: Double,
                           aspect: Aspect,
                           cropsToAspect: Bool = false) -> CGSize {
        guard source.width > 0, source.height > 0 else { return evenSize(source) }
        let margin = min(0.35, max(0, padding))
        let inner = 1 - 2 * margin
        guard inner > 0.05 else { return evenSize(source) }
        var width = source.width / inner
        var height = source.height / inner
        if let ratio = aspect.ratio {
            if cropsToAspect {
                if width / height > ratio {
                    width = height * ratio
                } else {
                    height = width / ratio
                }
            } else {
                if width / height < ratio {
                    width = height * ratio
                } else {
                    height = width / ratio
                }
            }
        }
        let longest = max(width, height)
        if longest > maximumCanvasEdge {
            let factor = maximumCanvasEdge / longest
            width *= factor
            height *= factor
        }
        return evenSize(CGSize(width: width, height: height))
    }

    static func cardRect(canvas: CGSize,
                         source: CGSize,
                         padding: Double,
                         fillsCanvas: Bool = false) -> CGRect {
        guard source.width > 0, source.height > 0, canvas.width > 0, canvas.height > 0
        else { return CGRect(origin: .zero, size: canvas) }
        let margin = min(0.35, max(0, padding))
        let available = CGSize(width: canvas.width * (1 - 2 * margin),
                               height: canvas.height * (1 - 2 * margin))
        let factors = (available.width / source.width, available.height / source.height)
        let factor = fillsCanvas ? max(factors.0, factors.1) : min(factors.0, factors.1)
        let size = CGSize(width: (source.width * factor).rounded(),
                          height: (source.height * factor).rounded())
        return CGRect(x: ((canvas.width - size.width) / 2).rounded(),
                      y: ((canvas.height - size.height) / 2).rounded(),
                      width: size.width,
                      height: size.height)
    }

    static func cardCorner(_ factor: Double, cardSize: CGSize) -> CGFloat {
        let clamped = min(1, max(0, factor))
        return (clamped * min(cardSize.width, cardSize.height) * 0.09).rounded()
    }

    static let pointerSizeRange: ClosedRange<Double> = 0.5...2.0
    static let zoomAmountRange: ClosedRange<Double> = 1.2...3.0
    static let audioGainRange: ClosedRange<Double> = 0...1

    static func sanitizedPointerSize(_ raw: Double) -> Double {
        guard raw.isFinite else { return 1 }
        return min(pointerSizeRange.upperBound, max(pointerSizeRange.lowerBound, raw))
    }

    static func sanitizedZoomAmount(_ raw: Double) -> Double {
        guard raw.isFinite else { return 1.8 }
        return min(zoomAmountRange.upperBound, max(zoomAmountRange.lowerBound, raw))
    }

    static func sanitizedAudioGain(_ raw: Double) -> Double {
        guard raw.isFinite else { return 1 }
        return min(audioGainRange.upperBound, max(audioGainRange.lowerBound, raw))
    }

    static func blurBlockSize(for area: CGSize,
                              strength: Int = ScreenshotSupport.BlurStrength.defaultLevel) -> CGFloat {
        let side = min(area.width, area.height)
        let base: CGFloat = side.isFinite && side > 0 ? min(48, max(8, (side / 3).rounded())) : 8
        return max(2, (base * ScreenshotSupport.BlurStrength.blockFactor(for: strength)).rounded())
    }

    static func unitPoint(at location: CGPoint,
                          in viewSize: CGSize,
                          sourceSize: CGSize) -> CGPoint? {
        guard sourceSize.width > 0, sourceSize.height > 0,
              viewSize.width > 0, viewSize.height > 0
        else { return nil }
        let fit = min(viewSize.width / sourceSize.width, viewSize.height / sourceSize.height)
        let shown = CGSize(width: sourceSize.width * fit, height: sourceSize.height * fit)
        let originX = (viewSize.width - shown.width) / 2
        let originY = (viewSize.height - shown.height) / 2
        return CGPoint(x: (location.x - originX) / shown.width,
                       y: (location.y - originY) / shown.height)
    }

    static func pointerPixelSize(sourceSize: CGSize, userScale: Double, systemScale: Double) -> CGFloat {
        let base = max(24, sourceSize.height * 0.028)
        return (base * CGFloat(sanitizedPointerSize(userScale)) * CGFloat(max(1, systemScale)))
            .rounded()
    }

    // MARK: - Elapsed time

    static func elapsedLabel(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    // MARK: - Takes

    static let takeVideoName = "take.mov"
    static let takePointerName = "pointer.bin"
    static let takeTypingName = "typing.json"
    static let takeEditName = "edit.json"
    static let takeFolderPrefix = "Take-"

    static func takeFolderName(id: UUID) -> String {
        takeFolderPrefix + id.uuidString
    }

    static func takeID(fromFolderName name: String) -> UUID? {
        guard name.hasPrefix(takeFolderPrefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(takeFolderPrefix.count)))
    }

    static let orphanMaxAge: TimeInterval = 24 * 3600
    static let unwrittenMaxAge: TimeInterval = 3600

    static func orphanTakeIDs(_ takes: [(id: UUID, finishedAt: Date?, createdAt: Date?)],
                              now: Date) -> [UUID] {
        takes.compactMap { take in
            if let finishedAt = take.finishedAt {
                return now.timeIntervalSince(finishedAt) > orphanMaxAge ? take.id : nil
            }
            guard let createdAt = take.createdAt else { return nil }
            return now.timeIntervalSince(createdAt) > unwrittenMaxAge ? take.id : nil
        }
    }

    // MARK: - Finished file

    static func stagingURL(for destination: URL) -> URL {
        let name = ".vorssaint-partial-\(UUID().uuidString)"
        let staged = destination.deletingLastPathComponent().appendingPathComponent(name)
        return destination.pathExtension.isEmpty
            ? staged
            : staged.appendingPathExtension(destination.pathExtension)
    }

    static func commitExport(from staged: URL, to destination: URL) -> Bool {
        let manager = FileManager.default
        do {
            if manager.fileExists(atPath: destination.path) {
                _ = try manager.replaceItemAt(destination, withItemAt: staged)
            } else {
                try manager.moveItem(at: staged, to: destination)
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Trim

    struct Trim: Equatable {
        var start: Double
        var end: Double

        var duration: Double { max(0, end - start) }
    }

    static let minimumTrimSeconds: Double = 0.2

    static func sanitizedTrim(start: Double, end: Double, duration: Double) -> Trim {
        guard duration > 0, duration.isFinite else { return Trim(start: 0, end: 0) }
        let floorEnd = end.isFinite && end > 0 ? min(end, duration) : duration
        let cappedStart = start.isFinite ? max(0, min(start, duration)) : 0
        let span = min(minimumTrimSeconds, duration)
        if floorEnd - cappedStart < span {
            let clampedStart = min(cappedStart, duration - span)
            return Trim(start: max(0, clampedStart), end: max(0, clampedStart) + span)
        }
        return Trim(start: cappedStart, end: floorEnd)
    }

    // MARK: - Filmstrip

    static func filmstripTimes(duration: Double, count: Int) -> [Double] {
        guard duration > 0, count > 0 else { return [] }
        return (0..<count).map { index in
            (Double(index) + 0.5) / Double(count) * duration
        }
    }

    // MARK: - GIF

    enum GIFSize: String, CaseIterable {
        case small, medium, large

        var longEdge: CGFloat {
            switch self {
            case .small: return 420
            case .medium: return 600
            case .large: return 800
            }
        }
    }

    static func sanitizedGIFSize(_ raw: String?) -> GIFSize {
        GIFSize(rawValue: raw ?? "") ?? .medium
    }

    static let gifFrameRates = [8, 12, 15]

    static func sanitizedGIFFrameRate(_ raw: Int) -> Int {
        gifFrameRates.contains(raw) ? raw : 12
    }

    static func gifFrameCount(duration: Double, fps: Int) -> Int {
        guard duration.isFinite, duration > 0, fps > 0 else { return 0 }
        let count = (duration * Double(fps)).rounded(.down)
        guard count.isFinite, count < Double(Int.max) else { return 0 }
        return max(1, Int(count))
    }

    static func gifOutputSize(source: CGSize, size: GIFSize) -> CGSize {
        let longest = max(source.width, source.height)
        guard longest > 0 else { return CGSize(width: size.longEdge, height: size.longEdge) }
        let factor = min(1, size.longEdge / longest)
        return evenSize(CGSize(width: source.width * factor, height: source.height * factor))
    }

    // MARK: - Disk

    static let minimumFreeBytesToStart: Int64 = 2_000_000_000
    static let minimumFreeBytesToContinue: Int64 = 500_000_000

    static func canStart(freeBytes: Int64) -> Bool {
        freeBytes >= minimumFreeBytesToStart
    }

    static func shouldStopForDisk(freeBytes: Int64) -> Bool {
        freeBytes < minimumFreeBytesToContinue
    }

    static func estimatedBytesPerSecond(pixelSize: CGSize, fps: Int) -> Int64 {
        let bits = averageBitRate(width: Int(pixelSize.width),
                                  height: Int(pixelSize.height),
                                  fps: fps,
                                  quality: takeQuality)
        return Int64(Double(bits) / 8)
    }
}
