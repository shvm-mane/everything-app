// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import CoreImage
import Darwin
import Foundation
import ScreenCaptureKit

final class WindowPreviewProvider {
    static let shared = WindowPreviewProvider()

    private static let defaultMaxPixelSize: CGFloat = 640

    private var cache: [CGWindowID: CGImage] = [:]
    private var lastTouched: [CGWindowID: TimeInterval] = [:]
    private static let cacheLimit = 48
    private static let cacheByteBudget = 64 * 1024 * 1024
    private var captureTask: Task<Void, Never>?
    private var warmTask: Task<Void, Never>?
    private var activationToken: NSObjectProtocol?
    private var pendingWarmPid: pid_t?
    private var pressureSource: DispatchSourceMemoryPressure?

    init() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: .critical, queue: .main)
        source.setEventHandler { [weak self] in
            self?.cache.removeAll()
            self?.lastTouched.removeAll()
        }
        source.resume()
        pressureSource = source
    }

    deinit {
        pressureSource?.cancel()
    }

    func cachedPreview(for windowID: CGWindowID) -> CGImage? {
        if cache[windowID] != nil {
            lastTouched[windowID] = ProcessInfo.processInfo.systemUptime
        }
        return cache[windowID]
    }

    func refreshPreviews(for items: [SwitcherItem],
                         maxPixelSize: CGFloat = defaultMaxPixelSize,
                         excludedAppsKey: String,
                         onUpdate: @escaping (CGWindowID, CGImage) -> Void) {
        guard Permissions.shared.screenRecording, Self.screenIsInView(),
              !Self.captureIsPaused(excludedAppsKey: excludedAppsKey) else {
            cancel()
            return
        }

        var seen = Set<CGWindowID>()
        let targets: [PreviewTarget] = items.compactMap { item in
            guard let id = item.previewWindowID, !seen.contains(id) else { return nil }
            seen.insert(id)
            return PreviewTarget(id: id,
                                 pid: item.windowOwnerPID,
                                 title: item.title,
                                 appName: item.appName,
                                 frame: item.frame,
                                 isMinimized: item.isMinimized)
        }

        captureTask?.cancel()
        pruneCache(keeping: seen)

        captureTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var pending: [PreviewTarget] = []
            for target in targets {
                guard !Task.isCancelled else { return }
                let captureIsPaused = await MainActor.run { Self.captureIsPaused(excludedAppsKey: excludedAppsKey) }
                guard !captureIsPaused else { return }
                let capturedImage = await Self.captureViaWindowServer(target.id)
                guard !Task.isCancelled else { return }
                guard let image = capturedImage else {
                    pending.append(target)
                    continue
                }
                if let grid = SwitcherSupport.alphaGrid(of: image),
                   SwitcherSupport.captureLooksTransformed(alphaGrid: grid) {
                    let needsPreview = await MainActor.run { !Task.isCancelled && self.cache[target.id] == nil }
                    guard needsPreview else { continue }
                    if let rectified = Self.rectifiedStripCapture(image) {
                        let copy = Self.bitmapCopy(rectified)
                        await MainActor.run {
                            guard !Task.isCancelled, self.cache[target.id] == nil else { return }
                            self.store(copy, for: target.id)
                            onUpdate(target.id, copy)
                        }
                    }
                    continue
                }
                if !target.isMinimized,
                   !SwitcherSupport.captureCoversWindow(imageWidth: image.width,
                                                        imageHeight: image.height,
                                                        windowSize: target.frame.size) {
                    pending.append(target)
                    continue
                }
                let scaled = Self.bitmapCopy(image, maxPixelSize: maxPixelSize)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.store(scaled, for: target.id)
                    onUpdate(target.id, scaled)
                }
            }
            guard !pending.isEmpty else { return }

            let captureIsPaused = await MainActor.run { Self.captureIsPaused(excludedAppsKey: excludedAppsKey) }
            guard !captureIsPaused else { return }

            guard let content = await Self.windowServerCaptures.perform({
                try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            }) else { return }
            let scWindows = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })

            for target in pending {
                guard !Task.isCancelled else { return }
                let captureIsPaused = await MainActor.run { Self.captureIsPaused(excludedAppsKey: excludedAppsKey) }
                guard !captureIsPaused else { return }
                guard let scWindow = scWindows[target.id]
                    ?? Self.bestWindowMatch(for: target, in: content.windows) else { continue }

                let source = scWindow.frame.width > 1 && scWindow.frame.height > 1
                    ? scWindow.frame
                    : target.frame
                let configuration = SCStreamConfiguration()
                let scale = min(1, maxPixelSize / max(source.width, source.height, 1))
                configuration.width = max(1, Int((source.width * scale).rounded()))
                configuration.height = max(1, Int((source.height * scale).rounded()))
                configuration.showsCursor = false

                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                guard let image = await Self.windowServerCaptures.perform({
                    try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                }) else { continue }
                guard !Task.isCancelled else { return }

                if let grid = SwitcherSupport.alphaGrid(of: image),
                   SwitcherSupport.captureLooksTransformed(alphaGrid: grid) {
                    let needsPreview = await MainActor.run { !Task.isCancelled && self.cache[target.id] == nil }
                    guard needsPreview else { continue }
                    if let rectified = Self.rectifiedStripCapture(image) {
                        let copy = Self.bitmapCopy(rectified)
                        await MainActor.run {
                            guard !Task.isCancelled, self.cache[target.id] == nil else { return }
                            self.store(copy, for: target.id)
                            onUpdate(target.id, copy)
                        }
                    }
                    continue
                }

                let copy = Self.bitmapCopy(image, maxPixelSize: maxPixelSize)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.store(copy, for: target.id)
                    onUpdate(target.id, copy)
                }
            }
        }
    }

    // MARK: - Window-server capture

    private typealias CGSConnectionID = UInt32
    private typealias CGSCaptureFunction =
        @convention(c) (CGSConnectionID, UnsafeMutablePointer<UInt32>, UInt32, UInt32) -> Unmanaged<CFArray>?

    private static let windowServerCapture: CGSCaptureFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSHWCaptureWindowList")
        else { return nil }
        return unsafeBitCast(symbol, to: CGSCaptureFunction.self)
    }()

    private static let windowServerConnection: CGSConnectionID = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSMainConnectionID")
        else { return 0 }
        typealias ConnectionFunction = @convention(c) () -> CGSConnectionID
        return unsafeBitCast(symbol, to: ConnectionFunction.self)()
    }()

    private static let windowServerCaptureOptions: UInt32 = (1 << 8) | (1 << 11)

    private static let windowServerCaptures = WindowServerCaptureQueue(
        checkPermission: WindowServerCaptureQueue.screenRecordingCheck ?? {})

    static func captureViaScreenCaptureKit<Value>(_ operation: @escaping () async -> Value?) async -> Value? {
        await windowServerCaptures.perform(operation)
    }

    static var capturesArePaused: Bool { !windowServerCaptures.acceptsCaptures }

    static func captureViaWindowServer(_ windowID: CGWindowID,
                                       waitingForOtherCaptures: Bool = true) async -> CGImage? {
        guard windowServerConnection != 0, let capture = windowServerCapture else { return nil }
        return await windowServerCaptures.capture(waitingForOtherCaptures: waitingForOtherCaptures) {
            var id = UInt32(windowID)
            guard let array = capture(windowServerConnection, &id, 1, windowServerCaptureOptions)?
                .takeRetainedValue(),
                CFArrayGetCount(array) > 0,
                let value = CFArrayGetValueAtIndex(array, 0)
            else { return nil }
            let candidate = unsafeBitCast(value, to: CFTypeRef.self)
            guard CFGetTypeID(candidate) == CGImage.typeID else { return nil }
            let image = unsafeBitCast(candidate, to: CGImage.self)
            guard image.width > 1, image.height > 1 else { return nil }
            return image
        }
    }

    private static let rectifyContext = CIContext()

    private static func rectifiedStripCapture(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 16, height > 16 else { return nil }
        let bytesPerPixel = 4
        var data = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress,
                                          width: width,
                                          height: height,
                                          bitsPerComponent: 8,
                                          bytesPerRow: width * bytesPerPixel,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        guard drawn else { return nil }
        var alpha = [UInt8](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            alpha[index] = data[index * bytesPerPixel + 3]
        }
        guard let corners = SwitcherSupport.opaqueQuadCorners(alpha: alpha, width: width, height: height)
        else { return nil }

        func vector(_ point: CGPoint) -> CIVector {
            CIVector(x: point.x, y: CGFloat(height - 1) - point.y)
        }
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        filter.setValue(vector(corners.topLeft), forKey: "inputTopLeft")
        filter.setValue(vector(corners.topRight), forKey: "inputTopRight")
        filter.setValue(vector(corners.bottomRight), forKey: "inputBottomRight")
        filter.setValue(vector(corners.bottomLeft), forKey: "inputBottomLeft")
        guard let corrected = filter.outputImage,
              corrected.extent.width > 16, corrected.extent.height > 16
        else { return nil }

        let maxSide = max(corrected.extent.width, corrected.extent.height)
        let upscale = min(3.0, 900.0 / maxSide)
        var output = corrected
        if upscale > 1.05,
           let lanczos = CIFilter(name: "CILanczosScaleTransform"),
           let sharpen = CIFilter(name: "CISharpenLuminance") {
            lanczos.setValue(corrected, forKey: kCIInputImageKey)
            lanczos.setValue(upscale, forKey: kCIInputScaleKey)
            lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
            sharpen.setValue(lanczos.outputImage, forKey: kCIInputImageKey)
            sharpen.setValue(0.5, forKey: kCIInputSharpnessKey)
            output = sharpen.outputImage ?? corrected
        }
        guard let rendered = rectifyContext.createCGImage(output, from: output.extent) else { return nil }
        return rendered
    }

    private static func bitmapCopy(_ image: CGImage,
                                   maxPixelSize: CGFloat = .greatestFiniteMagnitude) -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = min(1, maxPixelSize / max(width, height, 1))
        let scaledWidth = max(1, Int(width * scale))
        let scaledHeight = max(1, Int(height * scale))
        guard let context = CGContext(data: nil,
                                      width: scaledWidth,
                                      height: scaledHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = scale < 1 ? .high : .default
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(scaledWidth), height: CGFloat(scaledHeight)))
        return context.makeImage() ?? image
    }

    func cancel() {
        captureTask?.cancel()
        captureTask = nil
    }

    // MARK: - Cache lifetime

    private func pruneCache(keeping active: Set<CGWindowID>) {
        let existing = Self.existingWindowIDs() ?? Set(cache.keys)
        cache = cache.filter { existing.contains($0.key) }
        lastTouched = lastTouched.filter { cache[$0.key] != nil }
        let victims = SwitcherSupport.staleCacheVictims(ids: Set(cache.keys),
                                                        active: active,
                                                        lastTouched: lastTouched,
                                                        limit: Self.cacheLimit)
        for id in victims {
            cache[id] = nil
            lastTouched[id] = nil
        }
        let byteVictims = SwitcherSupport.cacheByteBudgetVictims(
            sizes: cache.mapValues { $0.bytesPerRow * $0.height },
            active: active,
            lastTouched: lastTouched,
            budget: Self.cacheByteBudget)
        for id in byteVictims {
            cache[id] = nil
            lastTouched[id] = nil
        }
    }

    private static func existingWindowIDs() -> Set<CGWindowID>? {
        guard let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        return Set(info.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
    }

    private func store(_ image: CGImage, for id: CGWindowID) {
        cache[id] = image
        lastTouched[id] = ProcessInfo.processInfo.systemUptime
    }

    // MARK: - Opportunistic warming

    func startWarming() {
        guard activationToken == nil else { return }
        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.scheduleWarm(pid: app.processIdentifier)
        }
        if let front = NSWorkspace.shared.frontmostApplication {
            scheduleWarm(pid: front.processIdentifier)
        }
    }

    func stopWarming() {
        if let activationToken {
            NSWorkspace.shared.notificationCenter.removeObserver(activationToken)
        }
        activationToken = nil
        pendingWarmPid = nil
        warmTask?.cancel()
        warmTask = nil
    }

    private static let warmEnumerationQueue = DispatchQueue(label: "com.vorssaint.preview.warm-enumeration",
                                                            qos: .utility)

    private func scheduleWarm(pid: pid_t) {
        let excludedAppsKey = DefaultsKey.switcherPreviewExcludedApps
        guard Permissions.shared.screenRecording, Self.screenIsInView(),
              !Self.captureIsPaused(excludedAppsKey: excludedAppsKey) else { return }
        pendingWarmPid = pid
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self,
                  self.pendingWarmPid == pid,
                  self.activationToken != nil,
                  Self.screenIsInView(),
                  !Self.captureIsPaused(excludedAppsKey: excludedAppsKey)
            else { return }
            self.pendingWarmPid = nil
            warmTask?.cancel()
            let snapshot = WindowEnumerator.snapshot()
            warmTask = Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                let items = await withCheckedContinuation { continuation in
                    Self.warmEnumerationQueue.async {
                        continuation.resume(returning: WindowEnumerator.listWindows(for: pid, snapshot: snapshot))
                    }
                }
                guard !items.isEmpty, !Task.isCancelled else { return }
                for item in items {
                    guard !Task.isCancelled, let id = item.previewWindowID else { continue }
                    let captureIsPaused = await MainActor.run { Self.captureIsPaused(excludedAppsKey: excludedAppsKey) }
                    guard !captureIsPaused else { return }
                    let capturedImage = await Self.captureViaWindowServer(id, waitingForOtherCaptures: false)
                    guard !Task.isCancelled else { return }
                    guard let image = capturedImage else { continue }
                    if let grid = SwitcherSupport.alphaGrid(of: image),
                       SwitcherSupport.captureLooksTransformed(alphaGrid: grid) {
                        let needsPreview = await MainActor.run { !Task.isCancelled && self.cache[id] == nil }
                        guard needsPreview else { continue }
                        if let rectified = Self.rectifiedStripCapture(image) {
                            let copy = Self.bitmapCopy(rectified)
                            await MainActor.run {
                                guard !Task.isCancelled, self.cache[id] == nil else { return }
                                self.store(copy, for: id)
                            }
                        }
                        continue
                    }
                    if !item.isMinimized,
                       !SwitcherSupport.captureCoversWindow(imageWidth: image.width,
                                                            imageHeight: image.height,
                                                            windowSize: item.frame.size) {
                        continue
                    }
                    let scaled = Self.bitmapCopy(image, maxPixelSize: Self.defaultMaxPixelSize)
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        self.store(scaled, for: id)
                    }
                }
                await MainActor.run { self.pruneCache(keeping: []) }
            }
        }
    }

    private static func screenIsInView() -> Bool {
        SwitcherSupport.screenIsInView(session: CGSessionCopyCurrentDictionary() as? [String: Any],
                                       displaysAsleep: CGDisplayIsAsleep(CGMainDisplayID()) != 0)
    }

    private static func captureIsPaused(excludedAppsKey: String) -> Bool {
        let excluded = Defaults.sanitizedBundleIdentifierList(
            UserDefaults.standard.stringArray(forKey: excludedAppsKey) ?? [])
        let front = NSWorkspace.shared.frontmostApplication
        return SwitcherSupport.shouldPausePreviewCapture(
            frontmostBundleIdentifier: front?.bundleIdentifier,
            frontmostExecutablePath: front?.executableURL?.path,
            excludedBundleIdentifiers: excluded)
    }

    private struct PreviewTarget {
        let id: CGWindowID
        let pid: pid_t
        let title: String
        let appName: String
        let frame: CGRect
        let isMinimized: Bool
    }

    private static func bestWindowMatch(for target: PreviewTarget, in windows: [SCWindow]) -> SCWindow? {
        let candidates = windows.filter { window in
            window.owningApplication?.processID == target.pid
        }
        guard !candidates.isEmpty else { return nil }

        if let titled = candidates.first(where: { titlesMatch($0.title, target.title) }) {
            return titled
        }

        let frameMatches = candidates
            .map { window in (window: window, score: frameDistance(window.frame, target.frame)) }
            .filter { $0.score < 80 }
            .sorted { $0.score < $1.score }

        if let closest = frameMatches.first?.window {
            return closest
        }

        if candidates.count == 1 {
            return candidates[0]
        }
        return nil
    }

    private static func titlesMatch(_ lhs: String?, _ rhs: String) -> Bool {
        let left = (lhs ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right
    }

    private static func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.midX - rhs.midX)
            + abs(lhs.midY - rhs.midY)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }
}
