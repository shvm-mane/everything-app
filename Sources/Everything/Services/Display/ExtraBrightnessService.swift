// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Metal
import QuartzCore

final class ExtraBrightnessService: ObservableObject {
    static let shared = ExtraBrightnessService()

    @Published private(set) var supported = false
    @Published private(set) var boosting = false

    private var overlayWindows: [NSWindow] = []
    private var overlayLayers: [CAMetalLayer] = []
    private var triggerWindow: NSWindow?
    private var triggerLayer: CAMetalLayer?
    private var overlaySpace: NotchOverlaySpace?
    private var metalDevice: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pollTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screensAsleep = false
    private var renderedFactor = 1.0
    private var disengagedTicks = 0
    private var overlayDisplayID: UInt32?

    private init() {}

    func syncWithPreferences() {
        refreshSupported()
        let enabled = AppFeature.extraBrightness.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.extraBrightnessEnabled)
        if enabled, supported {
            start()
        } else if enabled {
            installObserver()
            stop(preservingObservers: true)
        } else {
            stop()
        }
    }

    func levelDidChange() {
        guard pollTimer != nil else { return }
        renderIfNeeded(immediate: true)
    }

    // MARK: - Detection

    private static let modelIdentifier: String? = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }()

    private static let panelReference = ExtraBrightnessSupport.panelReference(model: modelIdentifier)

    private static func builtInXDRScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
                && ExtraBrightnessSupport.isSupportedPanel(
                    model: modelIdentifier,
                    localizedName: screen.localizedName,
                    potentialEDR: Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue))
        }
    }

    private var overlayScreen: NSScreen? {
        guard let overlayDisplayID else { return nil }
        return NSScreen.screens.first { Self.displayID(of: $0) == overlayDisplayID }
    }

    private func refreshSupported() {
        let now = Self.builtInXDRScreen() != nil
        if supported != now { supported = now }
    }

    // MARK: - Lifecycle

    private func start() {
        guard pollTimer == nil else { return }
        guard let screen = Self.builtInXDRScreen() else { return }
        showOverlay(on: screen)
        installObserver()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.renderIfNeeded()
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        renderIfNeeded()
    }

    func stop() {
        stop(preservingObservers: false)
    }

    private func stop(preservingObservers: Bool) {
        guard pollTimer != nil || !overlayWindows.isEmpty || screenObserver != nil else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        if !preservingObservers { removeObserver() }
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows = []
        overlayLayers = []
        overlayDisplayID = nil
        triggerWindow?.orderOut(nil)
        triggerWindow = nil
        triggerLayer = nil
        overlaySpace?.close()
        overlaySpace = nil
        commandQueue = nil
        metalDevice = nil
        renderedFactor = 1.0
        disengagedTicks = 0
        if boosting { boosting = false }
    }

    private func installObserver() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.handleScreenChange()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.screensAsleep = true
            },
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.screensAsleep = false
                self?.renderIfNeeded()
            },
            workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.handleActiveSpaceChange()
            },
        ]
    }

    private func removeObserver() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { workspace.removeObserver(observer) }
        workspaceObservers = []
        screensAsleep = false
    }

    private func handleActiveSpaceChange() {
        guard pollTimer != nil else { return }
        guard let screen = Self.builtInXDRScreen() else {
            handleScreenChange()
            return
        }
        if !overlayWindows.isEmpty, let triggerWindow,
           ExtraBrightnessSupport.canReuseSpaceWindows(
               sameDisplay: overlayDisplayID == Self.displayID(of: screen),
               inOwnSpace: overlaySpace != nil,
               overlayOnActiveSpace: overlayWindows.allSatisfy(\.isOnActiveSpace),
               triggerOnActiveSpace: triggerWindow.isOnActiveSpace) {
            renderIfNeeded()
            return
        }
        showOverlay(on: screen)
        renderIfNeeded()
    }

    private func handleScreenChange() {
        refreshSupported()
        let enabled = AppFeature.extraBrightness.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.extraBrightnessEnabled)
        guard enabled else {
            stop()
            return
        }
        guard let screen = Self.builtInXDRScreen() else {
            stop(preservingObservers: true)
            return
        }
        guard pollTimer != nil else {
            start()
            return
        }
        if !overlayWindows.isEmpty, overlayDisplayID == Self.displayID(of: screen) {
            let frames = ExtraBrightnessSupport.overlayFrames(for: screen.frame)
            if overlayWindows.map(\.frame) != frames {
                for (window, frame) in zip(overlayWindows, frames) {
                    window.setFrame(frame, display: false)
                }
                triggerWindow?.setFrame(Self.triggerFrame(on: screen), display: false)
                renderIfNeeded()
            }
        } else {
            showOverlay(on: screen)
            renderIfNeeded()
        }
    }

    private static func displayID(of screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func triggerFrame(on screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.maxX - 1, y: screen.frame.minY, width: 1, height: 1)
    }

    private static func systemAuthorizationUIIsActive() -> Bool {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.SecurityAgent").isEmpty {
            return true
        }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.AppStore"
    }

    private static let overlayCollectionBehavior: NSWindow.CollectionBehavior = [
        .ignoresCycle, .fullScreenAuxiliary, .canJoinAllApplications,
        .canJoinAllSpaces, .stationary,
    ]

    private static let overlayWindowLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))

    // MARK: - Overlay

    private func showOverlay(on screen: NSScreen) {
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows = []
        overlayLayers = []
        triggerWindow?.orderOut(nil)
        overlaySpace?.close()
        overlaySpace = NotchOverlaySpace()

        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return }
        for frame in ExtraBrightnessSupport.overlayFrames(for: screen.frame) {
            let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.level = Self.overlayWindowLevel
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            window.sharingType = .none
            window.collectionBehavior = Self.overlayCollectionBehavior

            let layer = CAMetalLayer()
            layer.device = device
            layer.pixelFormat = .rgba16Float
            layer.wantsExtendedDynamicRangeContent = true
            layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
            layer.isOpaque = false
            layer.compositingFilter = "multiply"
            layer.drawableSize = CGSize(width: 2, height: 2)
            layer.frame = CGRect(origin: .zero, size: frame.size)

            let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
            view.wantsLayer = true
            view.layer = layer
            window.contentView = view
            overlayWindows.append(window)
            overlayLayers.append(layer)
        }

        overlayDisplayID = Self.displayID(of: screen)
        metalDevice = device
        commandQueue = queue
        render(factor: renderedFactor, waitUntilScheduled: true)
        overlayWindows.forEach { overlaySpace?.add($0) }
        overlayWindows.forEach { $0.orderFrontRegardless() }
        showTrigger(on: screen, device: device, queue: queue)
    }

    private func showTrigger(on screen: NSScreen, device: MTLDevice, queue: MTLCommandQueue) {
        triggerWindow?.orderOut(nil)
        triggerWindow = nil
        triggerLayer = nil

        let window = NSWindow(contentRect: Self.triggerFrame(on: screen), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.level = Self.overlayWindowLevel
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.sharingType = .none
        window.collectionBehavior = Self.overlayCollectionBehavior

        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .rgba16Float
        layer.wantsExtendedDynamicRangeContent = true
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        layer.drawableSize = CGSize(width: 1, height: 1)
        layer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        view.wantsLayer = true
        view.layer = layer
        window.contentView = view
        triggerWindow = window
        triggerLayer = layer
        presentTrigger(waitUntilScheduled: true)
        overlaySpace?.add(window)
        window.orderFrontRegardless()
    }

    private func presentTrigger(waitUntilScheduled: Bool = false) {
        guard let layer = triggerLayer,
              let queue = commandQueue,
              let drawable = layer.nextDrawable(),
              let commands = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 1.8, green: 1.8, blue: 1.8, alpha: 1.0)
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
        if waitUntilScheduled { commands.waitUntilScheduled() }
    }

    private func renderIfNeeded(immediate: Bool = false) {
        guard !screensAsleep else { return }
        guard let screen = overlayScreen, !overlayLayers.isEmpty else { return }
        guard !Self.systemAuthorizationUIIsActive() else {
            overlayWindows.forEach { $0.orderOut(nil) }
            triggerWindow?.orderOut(nil)
            return
        }
        for window in overlayWindows where !window.isVisible { window.orderFrontRegardless() }
        if let triggerWindow, !triggerWindow.isVisible { triggerWindow.orderFrontRegardless() }
        presentTrigger()
        let level = Double(UserDefaults.standard.integer(forKey: DefaultsKey.extraBrightnessLevel)) / 100.0
        let headroom = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
        let potential = Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
        let engaged = headroom > ExtraBrightnessSupport.headroomThreshold
        disengagedTicks = engaged ? 0 : disengagedTicks + 1
        let instantaneous = ExtraBrightnessSupport.renderFactor(level: level, currentEDR: headroom,
                                                                potentialEDR: potential,
                                                                reference: Self.panelReference)
        if immediate {
            renderedFactor = instantaneous
        } else {
            let target = ExtraBrightnessSupport.gracedTarget(instantaneous: instantaneous,
                                                             previous: renderedFactor,
                                                             engaged: engaged,
                                                             disengagedTicks: disengagedTicks)
            renderedFactor = ExtraBrightnessSupport.rampedFactor(previous: renderedFactor,
                                                                 target: target)
        }
        render(factor: renderedFactor)
    }

    private func render(factor: Double, waitUntilScheduled: Bool = false) {
        let drawables = overlayLayers.compactMap { $0.nextDrawable() }
        guard !drawables.isEmpty, drawables.count == overlayLayers.count,
              let queue = commandQueue,
              let commands = queue.makeCommandBuffer() else { return }
        for drawable in drawables {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = drawable.texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: factor, green: factor,
                                                                blue: factor, alpha: 1.0)
            guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
            encoder.endEncoding()
            commands.present(drawable)
        }
        commands.commit()
        if waitUntilScheduled { commands.waitUntilScheduled() }
        let visible = factor > 1.001
        if boosting != visible { boosting = visible }
    }
}
