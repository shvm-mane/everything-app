// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import AppKit
import ScreenCaptureKit

enum RecorderFailure: Equatable {
    case permissionDenied
    case noContent
    case streamFailed
    case writerFailed
    case diskFull
}

protocol RecorderCaptureEngineDelegate: AnyObject {
    func captureEngine(_ engine: RecorderCaptureEngine,
                       didOutput sampleBuffer: CMSampleBuffer,
                       of kind: RecorderCaptureEngine.Kind)
    func captureEngine(_ engine: RecorderCaptureEngine, didStopWith failure: RecorderFailure)
}

final class RecorderCaptureEngine: NSObject {
    enum Kind {
        case video
        case systemAudio
        case microphone
    }

    weak var delegate: RecorderCaptureEngineDelegate?

    private let queue = DispatchQueue(label: "com.vorssaint.recorder.capture",
                                      qos: .userInitiated)
    private let lifecycleLock = NSLock()
    private var lifecycle = RecorderCaptureLifecycle()
    private var stream: SCStream?

    var isRunning: Bool {
        lifecycleLock.withLock { lifecycle.isRunning }
    }

    // MARK: - Lifecycle

    func start(region: RecorderSupport.Region,
               frameRate: Int,
               capturesSystemAudio: Bool,
               excludedWindowNumbers: [Int],
               willStartCapture: (CMTime) -> Void,
               isCancelled: @escaping () -> Bool) async -> RecorderFailure? {
        guard lifecycleLock.withLock({ self.stream == nil }), !isCancelled() else {
            return .streamFailed
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
        } catch {
            return Self.failure(for: error)
        }
        guard !isCancelled() else { return .streamFailed }

        let preparedFilter: SCContentFilter? = Self.filter(
            for: region,
            in: content,
            excluding: excludedWindowNumbers)
        guard let filter = preparedFilter else { return .noContent }

        let configuration = SCStreamConfiguration()
        configuration.width = Int(region.pixelRect.width)
        configuration.height = Int(region.pixelRect.height)
        configuration.minimumFrameInterval = CMTime(value: 1,
                                                    timescale: CMTimeScale(frameRate))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.scalesToFit = region.windowID != nil
        configuration.preservesAspectRatio = true
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.shouldBeOpaque = true
        configuration.ignoreShadowsDisplay = true
        configuration.ignoreShadowsSingleWindow = true
        if region.windowID == nil {
            configuration.sourceRect = Self.sourceRect(for: region)
        }
        if capturesSystemAudio {
            configuration.capturesAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            configuration.excludesCurrentProcessAudio = true
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            if capturesSystemAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            }
            guard !isCancelled() else { return .streamFailed }
            let willStart = lifecycleLock.withLock { () -> Bool in
                guard self.stream == nil, lifecycle.beginStart() else { return false }
                self.stream = stream
                return true
            }
            guard willStart else { return .streamFailed }
            willStartCapture(CMClockGetTime(CMClockGetHostTimeClock()))
            try await stream.startCapture()
        } catch {
            let failure = Self.failure(for: error)
            lifecycleLock.withLock {
                lifecycle.stop()
                if self.stream === stream { self.stream = nil }
            }
            await stopAndDrain(stream)
            return failure
        }

        if isCancelled() {
            lifecycleLock.withLock {
                lifecycle.stop()
                if self.stream === stream { self.stream = nil }
            }
            await stopAndDrain(stream)
            return .streamFailed
        }

        let didStart = lifecycleLock.withLock { () -> Bool in
            guard self.stream === stream, lifecycle.didStart() else { return false }
            return true
        }
        guard didStart else {
            await stopAndDrain(stream)
            return .streamFailed
        }
        return nil
    }

    func stop() async {
        let stream = lifecycleLock.withLock { () -> SCStream? in
            lifecycle.stop()
            let stream = self.stream
            self.stream = nil
            return stream
        }
        if let stream { try? await stream.stopCapture() }
        queue.sync {}
    }

    private func stopAndDrain(_ stream: SCStream) async {
        try? await stream.stopCapture()
        queue.sync {}
    }

    // MARK: - Filter

    private static func filter(for region: RecorderSupport.Region,
                               in content: SCShareableContent,
                               excluding windowNumbers: [Int]) -> SCContentFilter? {
        if let windowID = region.windowID,
           let window = content.windows.first(where: { $0.windowID == windowID }) {
            return SCContentFilter(desktopIndependentWindow: window)
        }
        guard let display = content.displays.first(where: { $0.displayID == region.displayID })
        else { return nil }
        let excluded = Set(windowNumbers.map { CGWindowID($0) })
        let ownPID = NSRunningApplication.current.processIdentifier
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == ownPID }
        guard let ownApplication = content.applications.first(where: { $0.processID == ownPID })
                ?? ownWindows.compactMap(\.owningApplication).first else { return nil }
        let exceptedIDs = RecorderSupport.exceptedOwnWindowIDs(
            ownWindowIDs: Set(ownWindows.map(\.windowID)),
            protectedWindowIDs: excluded
        )
        let ordinaryWindows = ownWindows.filter { exceptedIDs.contains($0.windowID) }
        return SCContentFilter(display: display,
                               excludingApplications: [ownApplication],
                               exceptingWindows: ordinaryWindows)
    }

    private static func sourceRect(for region: RecorderSupport.Region) -> CGRect {
        let scale = region.scale > 0 ? region.scale : 1
        return CGRect(x: region.pixelRect.origin.x / scale,
                      y: region.pixelRect.origin.y / scale,
                      width: region.pixelRect.width / scale,
                      height: region.pixelRect.height / scale)
    }

    // MARK: - Errors

    private static func failure(for error: Error) -> RecorderFailure {
        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain,
              let code = SCStreamError.Code(rawValue: nsError.code)
        else { return .streamFailed }
        switch code {
        case .userDeclined:
            return .permissionDenied
        case .noWindowList, .noDisplayList, .noCaptureSource:
            return .noContent
        default:
            return .streamFailed
        }
    }
}

final class RecorderMicrophoneCapture: NSObject,
                                       AVCaptureAudioDataOutputSampleBufferDelegate,
                                       @unchecked Sendable {
    var onSample: ((CMSampleBuffer) -> Void)?

    private let queue = DispatchQueue(label: "com.vorssaint.recorder.microphone",
                                      qos: .userInitiated)
    private let session = AVCaptureSession()
    private var targetClock: CMClock?
    private var configured = false

    func start(synchronizingTo clock: CMClock) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard configureIfNeeded() else {
                    continuation.resume(returning: false)
                    return
                }
                targetClock = clock
                session.startRunning()
                continuation.resume(returning: session.isRunning)
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if session.isRunning { session.stopRunning() }
                targetClock = nil
                continuation.resume()
            }
        }
    }

    private func configureIfNeeded() -> Bool {
        if configured { return true }
        guard let device = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return false }

        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input)
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
        configured = true
        return true
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let sourceClock = session.synchronizationClock,
              let targetClock,
              CMSampleBufferIsValid(sampleBuffer)
        else { return }
        guard let synchronized = RecorderSampleTiming.converted(sampleBuffer,
            from: sourceClock, to: targetClock)
        else { return }
        onSample?(synchronized)
    }

}

// MARK: - Stream callbacks

extension RecorderCaptureEngine: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard lifecycleLock.withLock({
            lifecycle.acceptsSamples && self.stream === stream
        }),
              CMSampleBufferIsValid(sampleBuffer),
              let clock = stream.synchronizationClock else { return }
        let kind: Kind
        switch type {
        case .screen:
            guard Self.carriesPixels(sampleBuffer) else { return }
            kind = .video
        case .audio:
            kind = .systemAudio
        default:
            return
        }
        guard let synchronized = RecorderSampleTiming.converted(sampleBuffer,
            from: clock, to: CMClockGetHostTimeClock()) else { return }
        delegate?.captureEngine(self, didOutput: synchronized, of: kind)
    }

    private static func carriesPixels(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return false }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let raw = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: raw)
        else { return false }
        return status == .complete || status == .started
    }
}

extension RecorderCaptureEngine: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let shouldReport = lifecycleLock.withLock { () -> Bool in
            guard lifecycle.acceptsSamples, self.stream === stream else { return false }
            lifecycle.stop()
            self.stream = nil
            return true
        }
        guard shouldReport else { return }
        let failure = Self.failure(for: error)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.captureEngine(self, didStopWith: failure)
        }
    }
}
