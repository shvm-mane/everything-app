// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import QuartzCore

struct NotchFileDropActions {
    let canAccept: (NSPasteboard) -> Bool
    let enter: (NSPasteboard) -> Void
    let accept: (NSPasteboard) -> Bool
    let exit: () -> Void
    var update: ((CGPoint) -> Bool)? = nil
}

enum NotchContentTransition { case none, reveal, dismiss, depart, replace }

final class NotchWindowHost: NSObject, CAAnimationDelegate {
    let panel: NotchPanel
    private let canvas: NotchCanvas
    private let quickAccessContainer: NotchQuickAccessContainer?
    private var quickAccessConfiguration: NotchQuickAccessConfiguration?
    private var quickAccessNotchSize = CGSize.zero
    private var quickAccessAnimate = false
    private var currentGeometry: NotchGeometry
    private var appliedFrame = CGRect.zero
    private var animationGeneration = 0
    private var isAnimating = false
    private var hidesWhenSettled = false
    private var targetUsesGlass = false
    private var mouseEventsBeforeHide: Bool?
    private var frameProbe: NotchFrameProbe?
    private var missionControlTimer: Timer?
    private var concealedForMissionControl = false
    private var missionControlAlpha: CGFloat = 1
    private var missionControlMouseEvents = false
    private var desktopReadings = 0
    private var lastMissionControlCheck: TimeInterval = -.infinity
    private var lastMissionControlProbe: TimeInterval = -.infinity
    private var overviewWasVisible = false
    private var restoringFromMissionControl = false
    var missionControlDidRestore: (() -> Void)?
    private let overlaySpace = NotchOverlaySpace()
    private var concealedForFrameChange = false
    private var restoresKeyAfterFrameChange = false
    private var relocationHidden = false
    private var relocationGeneration = 0
    private var restoresKeyAfterRelocation = false
    private var settledActions: [() -> Void] = []
    private(set) var targetSize: CGSize
    private(set) var resizeCount = 0
    private(set) var concealedFrameChanges = 0
    private(set) var missionControlFrameProbeCount = 0

    init(content: AnyView, geometry: NotchGeometry, size: CGSize,
         background: (NotchBackdropPresentation) -> AnyView = { _ in AnyView(Color.black) },
         quickAccess: ((NotchQuickAccessMotion, NotchBackdropPresentation) -> AnyView)? = nil) {
        targetSize = size
        currentGeometry = geometry
        panel = NotchPanel(contentRect: geometry.frame(for: size),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        let mainCanvas = NotchCanvas(content: content, background: background, size: size)
        canvas = mainCanvas
        quickAccessContainer = quickAccess.map { NotchQuickAccessContainer(canvas: mainCanvas, content: $0) }
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = NotchPanel.normalLevel
        panel.collectionBehavior = NotchPanel.overlayCollectionBehavior
        panel.contentView = quickAccessContainer ?? canvas
        panel.setFrame(pixelAligned(geometry.frame(for: size)), display: false)
        canvas.islandMinX = { [weak self] size in self?.islandMinX(size) }
        canvas.stageCentreX = { [weak self] in
            guard let self else { return nil }
            return self.currentGeometry.screen.midX - self.panel.frame.minX - self.canvas.convert(CGPoint.zero, to: nil).x
        }
        canvas.setFloatingGap(geometry.floatingGap)
        canvas.layoutSubtreeIfNeeded()
        appliedFrame = panel.frame
        overlaySpace?.add(panel)
        panel.visibilityDidChange = { [weak self] in self?.syncMissionControlMonitoring() }
    }

    var departsContent: Bool { canvas.departsContent }

    func finishDeparture() { canvas.finishDeparture() }

    private var isPresented: Bool { panel.isVisible || concealedForFrameChange || relocationHidden }
    var isConcealedForMissionControl: Bool {
        guard Thread.isMainThread else { return concealedForMissionControl || hidesWhenSettled }
        if !panel.isVisible && !concealedForFrameChange { refreshMissionControlState() }
        return concealedForMissionControl
    }

    func blocksHoverReveal() -> Bool {
        refreshMissionControlState(now: true)
        return concealedForMissionControl
    }

    func setMouseEventsIgnored(_ ignored: Bool) {
        if concealedForMissionControl { missionControlMouseEvents = ignored }
        if mouseEventsBeforeHide != nil { mouseEventsBeforeHide = ignored }
        let effective = ignored || concealedForMissionControl || hidesWhenSettled
        if panel.ignoresMouseEvents != effective { panel.ignoresMouseEvents = effective }
    }

    func setOutline(enabled: Bool, color: NSColor) {
        canvas.setOutline(enabled: enabled, color: color)
    }

    func bridgeMascot(look: NotchMascotLook, size: CGFloat, mood: NotchMascotMood, from: CGFloat, to: CGFloat,
                      baseline: CGFloat, duration: CFTimeInterval, scale: (from: CGFloat, to: CGFloat) = (1, 1),
                      trailsGrowth: Bool = false, hop: CGFloat = 0) {
        canvas.showMascotBridge(look: look, size: size, mood: mood, from: from, to: to, baseline: baseline,
                                duration: duration, scale: scale, trailsGrowth: trailsGrowth, hop: hop)
    }

    func endMascotBridge(fading: Bool = false) { canvas.hideMascotBridge(fading: fading) }

    func reactMascotBridge(_ event: NotchMascotReactionEvent, lift: CGFloat) {
        canvas.reactMascotBridge(event, lift: lift)
    }

    func canRelocateOnScreen() -> Bool { isPresented && panel.attachedSheet == nil }

    func orderOutForRelocation() -> Bool {
        guard canRelocateOnScreen() else { return false }
        relocationGeneration += 1
        guard !relocationHidden else { return true }
        relocationHidden = true
        restoresKeyAfterRelocation = panel.isKeyWindow || restoresKeyAfterFrameChange
        concealedForFrameChange = false
        restoresKeyAfterFrameChange = false
        panel.holdsWave = true
        panel.orderOut(nil)
        CATransaction.flush()
        return true
    }

    func orderFrontForRelocation() {
        guard relocationHidden else { return }
        guard !hidesWhenSettled else { cancelRelocation(); return }
        let generation = relocationGeneration
        panel.contentView?.layoutSubtreeIfNeeded()
        guard relocationHidden, generation == relocationGeneration else { return }
        guard !hidesWhenSettled else { cancelRelocation(); return }
        let restoreKey = restoresKeyAfterRelocation
        relocationHidden = false
        restoresKeyAfterRelocation = false
        panel.orderFrontRegardless()
        CATransaction.flush()
        guard generation == relocationGeneration else { return }
        if restoreKey, panel.isVisible, !hidesWhenSettled { panel.makeKey() }
        panel.contentView?.releaseEqualizerPose()
        panel.holdsWave = false
    }

    func cancelRelocation() {
        relocationGeneration += 1
        relocationHidden = false
        restoresKeyAfterRelocation = false
        panel.contentView?.releaseEqualizerPose()
        panel.holdsWave = false
    }

    func holdWave() {
        panel.holdsWave = true
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.contentView?.refreshEqualizerMotion()
    }

    func releaseWave() { panel.holdsWave = false }

    func keepWave() { panel.holdsWave = true }

    func matchWave(from other: NSView?) {
        guard let other, let content = panel.contentView else { return }
        let pose = other.collectEqualizerHeights()
        guard !pose.isEmpty else { return }
        content.layoutSubtreeIfNeeded()
        content.adoptEqualizerHeights(pose)
    }

    func hide(animated: Bool, transitionContent: NotchContentTransition = .dismiss) {
        guard isPresented else { return }
        let animate = animated && !relocationHidden && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard !hidesWhenSettled || !animate else { return }
        if relocationHidden {
            restoresKeyAfterRelocation = false
            panel.contentView?.releaseEqualizerPose()
        }
        present(size: CGSize(width: currentGeometry.collapsed.width, height: 0), geometry: currentGeometry,
                animated: animate, transitionContent: transitionContent == .depart ? .depart : .dismiss,
                hideWhenSettled: true)
    }

    func present(size: CGSize, geometry: NotchGeometry, animated: Bool, transitionContent: NotchContentTransition = .none,
                 quickAccess: NotchQuickAccessConfiguration? = nil, revealFromHidden: Bool = false,
                 hideWhenSettled: Bool = false, usesGlass: Bool = false, steady: Bool = false) {
        canvas.setFloatingGap(geometry.floatingGap)
        hidesWhenSettled = hideWhenSettled
        if relocationHidden { panel.holdsWave = !hideWhenSettled }
        if hideWhenSettled {
            if mouseEventsBeforeHide == nil {
                mouseEventsBeforeHide = concealedForMissionControl ? missionControlMouseEvents : panel.ignoresMouseEvents
            }
            panel.ignoresMouseEvents = true
        } else if let previous = mouseEventsBeforeHide {
            panel.ignoresMouseEvents = previous
            mouseEventsBeforeHide = nil
        }
        if concealedForMissionControl { panel.ignoresMouseEvents = true }
        canvas.updateContrast()
        let revealing = revealFromHidden && !isPresented
        if isPresented || revealing {
            let probe = frameProbe ?? NotchFrameProbe(collectionBehavior: panel.collectionBehavior)
            frameProbe = probe
            probe.attach(level: panel.level, screen: geometry.screen)
        }
        let canAnimate = animated && !relocationHidden && (isPresented || revealing)
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let previousGutter = quickAccessConfiguration == nil ? 0 : NotchQuickAccessLayout.gutter
        let previousBottom = quickAccessBottomInset(for: targetSize, geometry: currentGeometry)
        let previousFrame = currentGeometry.frame(for: CGSize(width: targetSize.width + previousGutter * 2, height: targetSize.height + previousBottom))
        let withdrawing = !revealing && quickAccessConfiguration != nil && quickAccess == nil
        if revealing { quickAccessContainer?.motion.setVisible(false, animated: false) }
        quickAccessConfiguration = quickAccessContainer == nil ? nil : quickAccess
        quickAccessAnimate = canAnimate
        if quickAccessConfiguration != nil { quickAccessNotchSize = size }
        if withdrawing { quickAccessContainer?.motion.setVisible(false, animated: canAnimate) }
        let gutter = quickAccessConfiguration == nil ? 0 : NotchQuickAccessLayout.gutter
        let bottom = quickAccessBottomInset(for: size, geometry: geometry)
        let frame = geometry.frame(for: CGSize(width: size.width + gutter * 2, height: size.height + bottom))
        let changesFrame = revealing || relocationHidden || (hideWhenSettled && !canAnimate) || size != targetSize
            || frame != previousFrame || (!isAnimating && panel.frame != appliedFrame)
        targetUsesGlass = usesGlass
        if canvas.backdropPresentation.stripHeight != geometry.stripHeight {
            canvas.backdropPresentation.stripHeight = geometry.stripHeight
        }
        if canAnimate && changesFrame && (usesGlass || canvas.usesGlass) {
            let start = revealing ? 0 : canvas.visibleSize?.height ?? targetSize.height
            if usesGlass, canvas.closingToBlack { canvas.backdropPresentation.shut() }
            canvas.backdropPresentation.planFade(from: start, to: size.height, endsInGlass: usesGlass)
            canvas.updateCanvasBlack()
        }
        canvas.setUsesGlass(usesGlass || (((canAnimate && changesFrame) || isAnimating) && canvas.usesGlass))
        guard changesFrame || transitionContent != .none else {
            currentGeometry = geometry
            configureQuickAccess()
            if !isAnimating { quickAccessContainer?.motion.setVisible(quickAccessConfiguration != nil, animated: canAnimate) }
            return
        }
        if canAnimate { canvas.transitionContent(revealing ? .reveal : transitionContent) }
        else if animated && changesFrame && (revealing || transitionContent == .reveal) {
            canvas.transitionContent(.reveal, shapeSnaps: true)
        } else { canvas.restoreContent() }
        guard changesFrame else { configureQuickAccess(); return }
        let previousWidth = revealing ? geometry.collapsed.width : canvas.bounds.width
        let previousPath = revealing
            ? NotchShape(attached: true, radius: 0, floatingGap: geometry.floatingGap)
                .path(in: CGRect(x: 0, y: 0, width: previousWidth, height: 0)).cgPath
            : canvas.visiblePath
        let sameScreen = geometry.screen == currentGeometry.screen
        let previousShift = currentGeometry.surfaceShift
        let drawnShift = canvas.visibleShift.map { abs($0 - previousShift) < 1 ? previousShift : $0 } ?? previousShift
        let startShift = revealing ? 0 : drawnShift
        animationGeneration += 1
        let generation = animationGeneration
        targetSize = size
        currentGeometry = geometry
        resizeCount += 1
        guard canAnimate, sameScreen || revealing, let previousPath else {
            settle()
            return
        }

        let drawn = revealing ? canvas.surfaceSize(of: previousPath) : canvas.visibleSize ?? canvas.surfaceSize(of: previousPath)
        let steady = steady && drawn.height == size.height
        let startOffset = startShift - geometry.surfaceShift
        let carried = isAnimating && !revealing && !steady && !withdrawing && startOffset == 0
            ? canvas.carriedMotion(to: size, at: CACurrentMediaTime()) : nil
        let start = carried?.start ?? drawn
        let motion = carried?.frames() ?? NotchMotion.frames(from: start, to: size, steady: steady, offset: startOffset)
        let offsets = motion.keyTimes.map {
            $0 == 1 ? 0 : NotchMotion.offset(at: motion.duration * $0, from: start, to: size, start: startOffset, steady: steady)
        }
        var envelope = NotchMotion.envelope(from: start, to: size)
        let reach = zip(motion.sizes, offsets).map { $0.width + 2 * abs($1) }.max() ?? 0
        envelope.width = max(envelope.width, reach.rounded(.up))
        let tallest = motion.sizes.map(\.height).max() ?? 0
        envelope.height = max(envelope.height, tallest.rounded(.up))
        if !revealing {
            envelope = CGSize(width: max(envelope.width, canvas.bounds.width), height: max(envelope.height, canvas.bounds.height))
        }
        envelope = NotchMotion.reservation(envelope, centring: size)
        let reservedGutter = max(quickAccessContainer?.gutter ?? 0, gutter)
        let reservedBottom = max(quickAccessContainer?.bottomInset ?? 0, bottom)
        let concealed = concealForFrameChange(to: reservedFrame(mainSize: envelope, gutter: reservedGutter, bottom: reservedBottom),
                                              generation: generation)
        defer { if concealed { reinstateAfterFrameChange() } }
        guard generation == animationGeneration else { return }
        isAnimating = false
        canvas.motionStart = start
        canvas.motionStartOffset = startOffset
        defer { canvas.motionStart = nil; canvas.motionStartOffset = 0 }
        canvas.stopMotion()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.setContentSize(size)
        setFrame(mainSize: envelope, gutter: reservedGutter, bottom: reservedBottom)
        guard generation == animationGeneration else { CATransaction.commit(); return }
        configureQuickAccess()
        canvas.layoutSubtreeIfNeeded()
        guard generation == animationGeneration else { CATransaction.commit(); return }
        let paths = zip(motion.sizes, offsets).map { canvas.silhouettePath(for: $0, offset: $1) }
        if quickAccessConfiguration != nil {
            quickAccessContainer?.motion.setVisible(true, animated: canAnimate,
                                                    delay: NotchMotion.arrivalTime(from: start, to: size))
        }
        let animation = CAKeyframeAnimation(keyPath: "path")
        animation.values = paths
        animation.keyTimes = motion.keyTimes.map { NSNumber(value: $0) }
        animation.calculationMode = .linear
        animation.duration = motion.duration
        if let carried {
            animation.beginTime = carried.begin
            animation.fillMode = .backwards
        }
        animation.delegate = self
        animation.setValue(generation, forKey: "notchGeneration")
        isAnimating = true
        canvas.collapsesToBlack = !targetUsesGlass && canvas.usesGlass && !revealing && carried == nil
            && size.height < start.height
        canvas.closingToBlack = !targetUsesGlass && canvas.usesGlass && size.height < start.height
        canvas.updateCanvasBlack()
        canvas.growsIntoGlass = targetUsesGlass && carried == nil && offsets.allSatisfy { $0 == 0 }
            && size.width >= start.width && size.height >= start.height && size != start
        canvas.animate(animation, from: paths.first, motion: carried ?? NotchMotionTimeline(
            from: start, to: size, begin: animation.beginTime > 0 ? animation.beginTime : CACurrentMediaTime(),
            steady: steady, offset: startOffset))
        CATransaction.commit()
        CATransaction.flush()
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard isAnimating, anim.value(forKey: "notchGeneration") as? Int == animationGeneration else { return }
        settle()
    }

    private func settle() {
        let generation = animationGeneration
        let gutter: CGFloat = quickAccessConfiguration == nil ? 0 : NotchQuickAccessLayout.gutter
        let bottom = quickAccessBottomInset(for: targetSize, geometry: currentGeometry)
        if hidesWhenSettled, panel.isVisible, !isAnimating {
            panel.orderOut(nil)
            CATransaction.flush()
        }
        let concealed = !hidesWhenSettled
            && concealForFrameChange(to: reservedFrame(mainSize: targetSize, gutter: gutter, bottom: bottom), generation: generation)
        defer { if concealed { reinstateAfterFrameChange() } }
        guard generation == animationGeneration else { return }
        isAnimating = false
        canvas.stopMotion()
        canvas.setUsesGlass(targetUsesGlass)
        canvas.closingToBlack = false
        if targetUsesGlass { canvas.backdropPresentation.openFully() } else { canvas.backdropPresentation.shut() }
        canvas.updateCanvasBlack()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.setContentSize(targetSize)
        setFrame(mainSize: targetSize, gutter: gutter, bottom: bottom)
        guard generation == animationGeneration else { CATransaction.commit(); return }
        configureQuickAccess()
        canvas.layoutSubtreeIfNeeded()
        guard generation == animationGeneration else { CATransaction.commit(); return }
        CATransaction.commit()
        CATransaction.flush()
        quickAccessContainer?.motion.setVisible(quickAccessConfiguration != nil, animated: quickAccessAnimate)
        if hidesWhenSettled {
            panel.orderOut(nil)
            concealedForFrameChange = false
            restoresKeyAfterFrameChange = false
        }
        runSettledActions()
    }

    private func reservedFrame(mainSize: CGSize, gutter: CGFloat, bottom: CGFloat) -> CGRect {
        pixelAligned(currentGeometry.frame(for: CGSize(width: mainSize.width + gutter * 2, height: mainSize.height + bottom)))
    }

    private func pixelAligned(_ rect: CGRect) -> CGRect {
        let scale = NSScreen.screens.first { $0.frame == currentGeometry.screen }?.backingScaleFactor
            ?? panel.backingScaleFactor
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let minX = snap(rect.minX), minY = snap(rect.minY)
        return CGRect(x: minX, y: minY, width: snap(rect.maxX) - minX, height: snap(rect.maxY) - minY)
    }

    private func islandMinX(_ size: CGSize) -> CGFloat {
        pixelAligned(currentGeometry.frame(for: size)).minX - panel.frame.minX - canvas.convert(CGPoint.zero, to: nil).x
    }

    private func quickAccessBottomInset(for size: CGSize, geometry: NotchGeometry) -> CGFloat {
        guard let configuration = quickAccessConfiguration else { return 0 }
        return configuration.hasBottom ? NotchQuickAccessLayout.gutter : 0
    }

    private func concealForFrameChange(to frame: CGRect, generation: Int) -> Bool {
        guard !concealedForFrameChange, panel.isVisible, panel.attachedSheet == nil,
              !NotchFrameProbe.matches(frame, panel.frame), let frameProbe else { return false }
        guard concealedForMissionControl || NotchFrameProbe.overviewIsVisible(on: currentGeometry.screen) else { return false }
        guard frameProbe.serverAnimatesFrames(level: panel.level, screen: currentGeometry.screen),
              generation == animationGeneration, panel.isVisible else { return false }
        concealedForFrameChange = true
        concealedFrameChanges += 1
        restoresKeyAfterFrameChange = panel.isKeyWindow
        panel.orderOut(nil)
        CATransaction.flush()
        return true
    }

    private func reinstateAfterFrameChange() {
        guard concealedForFrameChange else { return }
        concealedForFrameChange = false
        guard !relocationHidden, !hidesWhenSettled else { restoresKeyAfterFrameChange = false; return }
        panel.orderFrontRegardless()
        CATransaction.flush()
        if restoresKeyAfterFrameChange { panel.makeKey() }
        restoresKeyAfterFrameChange = false
    }

    private func setFrame(mainSize: CGSize, gutter: CGFloat, bottom: CGFloat) {
        quickAccessContainer?.gutter = gutter
        quickAccessContainer?.bottomInset = bottom
        panel.setFrame(reservedFrame(mainSize: mainSize, gutter: gutter, bottom: bottom), display: false)
        quickAccessContainer?.updateFrames()
        canvas.updateGeometry()
        panel.contentView?.layoutSubtreeIfNeeded()
        appliedFrame = panel.frame
    }

    private func configureQuickAccess() {
        guard let container = quickAccessContainer else { return }
        container.quickView.isHidden = quickAccessConfiguration == nil && container.gutter == 0 && container.bottomInset == 0
        guard let configuration = quickAccessConfiguration else {
            container.setHoverRects([])
            return
        }
        let shoulder = NotchLayout.shoulder(height: targetSize.height)
        let islandX = canvas.convert(CGPoint(x: islandMinX(quickAccessNotchSize), y: 0), to: container.quickView).x
        let body = CGRect(x: islandX + shoulder, y: 0,
                          width: quickAccessNotchSize.width - shoulder * 2, height: quickAccessNotchSize.height)
        container.motion.configure(configuration, body: body,
                                   headerTop: currentGeometry.quickAccessCenterY,
                                   animated: quickAccessAnimate)
        container.setHoverRects(container.motion.hoverRects.map {
            container.convert($0, from: container.quickView).intersection(container.bounds)
        })
    }

    func setHoverHandler(_ handler: @escaping (Bool) -> Void) {
        canvas.hoverChanged = handler
        quickAccessContainer?.hoverChanged = handler
    }

    func containsHover(_ screenPoint: CGPoint) -> Bool {
        guard isPresented, !concealedForMissionControl else { return false }
        if currentGeometry.contains(screenPoint, in: targetSize) { return true }
        guard let container = quickAccessContainer else { return false }
        let point = container.convert(panel.convertPoint(fromScreen: screenPoint), from: nil)
        return container.hoverRects.contains { $0.contains(point) }
    }

    func whenSettled(_ action: @escaping () -> Void) {
        settledActions.append(action)
        if !isAnimating { runSettledActions() }
    }

    private func runSettledActions() {
        let actions = settledActions
        settledActions.removeAll()
        for action in actions { DispatchQueue.main.async(execute: action) }
    }

    private func syncMissionControlMonitoring() {
        updateMissionControlTimer()
        if panel.isVisible { refreshMissionControlState(now: true) }
    }

    private var missionControlCheckInterval: TimeInterval {
        overviewWasVisible || concealedForMissionControl ? 0.08 : 1.0
    }

    private func updateMissionControlTimer() {
        guard panel.isVisible || concealedForMissionControl else {
            missionControlTimer?.invalidate()
            missionControlTimer = nil
            return
        }
        let interval = missionControlCheckInterval
        if missionControlTimer?.timeInterval != interval {
            missionControlTimer?.invalidate()
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                self?.refreshMissionControlState()
            }
            timer.tolerance = interval / 2
            missionControlTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func refreshMissionControlState(now immediate: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard immediate || now - lastMissionControlCheck >= missionControlCheckInterval else { return }
        lastMissionControlCheck = now
        defer { updateMissionControlTimer() }
        let overview = NotchFrameProbe.overviewIsVisible(on: currentGeometry.screen)
        let appeared = overview && !overviewWasVisible
        overviewWasVisible = overview
        guard overview || concealedForMissionControl else { return }
        let interval = concealedForMissionControl && !overview ? 0.08 : 0.5
        guard immediate || appeared || now - lastMissionControlProbe >= interval else { return }
        lastMissionControlProbe = now
        sampleMissionControl()
    }

    private func sampleMissionControl() {
        missionControlFrameProbeCount += 1
        let probe = frameProbe ?? NotchFrameProbe(collectionBehavior: panel.collectionBehavior)
        frameProbe = probe
        if probe.serverAnimatesFrames(level: panel.level, screen: currentGeometry.screen) {
            desktopReadings = 0
            guard !concealedForMissionControl else { panel.ignoresMouseEvents = true; return }
            concealedForMissionControl = true
            if !restoringFromMissionControl { missionControlAlpha = panel.alphaValue }
            missionControlMouseEvents = mouseEventsBeforeHide ?? panel.ignoresMouseEvents
            panel.ignoresMouseEvents = true
            if panel.isVisible { fadeMissionControl(to: 0) }
            else {
                panel.alphaValue = 0
                syncMissionControlMonitoring()
            }
        } else if concealedForMissionControl {
            desktopReadings += 1
            guard desktopReadings >= 3 else { return }
            restoreFromMissionControl()
        }
    }

    private func restoreFromMissionControl() {
        concealedForMissionControl = false
        desktopReadings = 0
        panel.ignoresMouseEvents = hidesWhenSettled ? true : missionControlMouseEvents
        if panel.isVisible {
            restoringFromMissionControl = true
            fadeMissionControl(to: missionControlAlpha) { [weak self] in self?.restoringFromMissionControl = false }
        } else {
            panel.alphaValue = missionControlAlpha
            syncMissionControlMonitoring()
        }
        missionControlDidRestore?()
    }

    private func fadeMissionControl(to alpha: CGFloat, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
            panel.animator().alphaValue = alpha
        }, completionHandler: completion)
    }

    var visibleFrame: CGRect {
        var frame = currentGeometry.frame(for: canvas.visibleSize ?? targetSize)
        if let shift = canvas.visibleShift, abs(shift - currentGeometry.surfaceShift) >= 1 {
            frame.origin.x += shift - currentGeometry.surfaceShift
        }
        return frame
    }

    func containsSurface(_ screenPoint: CGPoint) -> Bool {
        guard isPresented, !concealedForMissionControl else { return false }
        return canvas.containsVisiblePoint(canvas.convert(panel.convertPoint(fromScreen: screenPoint), from: nil))
    }

    func containsDestination(_ screenPoint: CGPoint) -> Bool {
        guard isPresented, !concealedForMissionControl else { return false }
        return canvas.containsDestinationPoint(canvas.convert(panel.convertPoint(fromScreen: screenPoint), from: nil))
    }

    func contains(_ screenPoint: CGPoint) -> Bool {
        if containsSurface(screenPoint) { return true }
        guard isPresented, !concealedForMissionControl, let container = quickAccessContainer else { return false }
        return container.motion.contains(container.quickView.convert(panel.convertPoint(fromScreen: screenPoint), from: nil))
    }

    func setFileDropActions(_ actions: NotchFileDropActions?) { canvas.setFileDropActions(actions) }

    func setActivationArea(_ rect: CGRect, title: String, willPress: @escaping () -> Void, activate: @escaping () -> Void) {
        canvas.setActivationArea(rect, title: title, willPress: willPress, activate: activate)
    }

#if VORSSAINT_DEVELOPMENT
    func probeOnNextLayout(_ action: @escaping () -> Void) {
        quickAccessContainer?.nextProbeLayout = action
        quickAccessContainer?.needsLayout = true
    }

    func probePresentDuringLayout(size: CGSize, geometry: NotchGeometry) -> Bool {
        guard let container = quickAccessContainer else { return false }
        var backingReady = false
        container.nextProbeLayout = { [weak self] in
            guard let self else { return }
            self.present(size: size, geometry: geometry, animated: true, quickAccess: .initial)
            backingReady = self.contentCanvasSize.height + 0.5 >= size.height
        }
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        return backingReady
    }

    var contentProbeOpacity: Float { canvas.contentProbeOpacity }
    var contentProbeAnimating: Bool { canvas.contentProbeAnimating }
    var contentProbeAlpha: CGFloat { canvas.contentProbeAlpha }
    var contentProbeReplacing: Bool { canvas.contentProbeReplacing }
    var contentProbeBlurred: Bool { canvas.contentProbeBlurred }
    var contentProbeGrowing: Bool { canvas.contentProbeGrowing }
    var contentProbeGrowthDrift: CGFloat { canvas.contentProbeGrowthDrift }
    var backdropProbeFrame: CGRect { canvas.backdropProbeFrame }
    var backdropProbeIndependent: Bool { canvas.backdropProbeIndependent }
    var backdropProbeFollowsSilhouette: Bool { canvas.backdropProbeFollowsSilhouette }
    var silhouetteProbePath: CGPath? { canvas.visiblePath }
    var silhouetteProbeFloatingGap: CGFloat? { canvas.floatingGap }
    var outlineProbeAllRound: Bool { canvas.outlineProbeAllRound }
    var motionProbeStart: CGSize? { canvas.motionProbeStart }
    var backdropProbeContour: Path { canvas.backdropPresentation.contour }
    var backdropProbeUsesGlass: Bool { canvas.usesGlass }
    var backdropProbeOpenness: Double { canvas.backdropPresentation.openness }
    var outlineProbeOpacity: Float { canvas.outlineProbeOpacity }
    var outlineProbeWidth: CGFloat { canvas.outlineProbeWidth }
    var outlineProbeTopOpen: Bool { canvas.outlineProbeTopOpen }
    var overlayProbeHolds: Bool? { overlaySpace.map { $0.probeHolds(panel) } }
    var backdropProbeScheduled: Bool { canvas.backdropDisplayLink != nil }
    var backdropProbeTicks: Int { canvas.backdropTicks }
    func synchronizeBackdropProbe() { canvas.synchronizeBackdrop() }

    var quickAccessProbeTrackingAreas: Int { quickAccessContainer?.trackingAreas.count ?? 0 }
    var quickAccessProbeInteractive: Bool { quickAccessContainer?.motion.interactive == true }
    var quickAccessProbeCenters: [CGPoint] {
        guard let container = quickAccessContainer else { return [] }
        let motion = container.motion
        return motion.placements.map { placement in
            panel.convertPoint(toScreen: container.quickView.convert(placement.center(progress: 1), to: nil))
        }
    }

    func quickAccessProbeOpacity(at screenPoint: CGPoint) -> CGFloat? {
        guard let view = quickAccessContainer?.quickView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let point = view.convert(panel.convertPoint(fromScreen: screenPoint), from: nil)
        let scale = CGFloat(bitmap.pixelsWide) / max(1, view.bounds.width)
        let row = view.isFlipped ? point.y : view.bounds.height - point.y
        return bitmap.colorAt(x: Int(point.x * scale), y: Int(row * scale))?.alphaComponent
    }

    func beginProbeDrop(_ pasteboard: NSPasteboard, localSource: Bool = false) -> NSDragOperation {
        canvas.beginDrop(pasteboard, localSource: localSource)
    }
    func finishProbeDrop(_ pasteboard: NSPasteboard) -> Bool { canvas.finishDrop(pasteboard) }
#endif

    var contentCanvasSize: CGSize { canvas.bounds.size }
    var contentStageSize: CGSize { canvas.hostedSize }

    var contentTopOnScreen: CGFloat {
        panel.convertPoint(toScreen: canvas.contentTopInWindow).y
    }

    func close() {
        missionControlTimer?.invalidate()
        missionControlTimer = nil
        panel.visibilityDidChange = nil
        cancelRelocation()
        animationGeneration += 1
        isAnimating = false
        concealedForFrameChange = false
        canvas.stopMotion()
        quickAccessContainer?.motion.setVisible(false, animated: false)
        quickAccessContainer?.setHoverRects([])
        panel.orderOut(nil)
        panel.contentView = nil
        overlaySpace?.close()
        frameProbe?.close()
        frameProbe = nil
        runSettledActions()
    }
}

enum NotchStage {
    static func size(including size: CGSize) -> CGSize {
        let largest = NSScreen.screens.reduce(CGSize.zero) {
            CGSize(width: max($0.width, $1.frame.width), height: max($0.height, $1.frame.height))
        }
        return CGSize(width: max(size.width, largest.width), height: max(size.height, largest.height))
    }

    static func frame(_ stage: CGSize, in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.midX - stage.width / 2, y: bounds.minY, width: stage.width, height: stage.height)
    }
}

private final class NotchFrameProbe {
    private let window: NotchPanel
    private var grown = false

    init(collectionBehavior: NSWindow.CollectionBehavior) {
        window = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 2, height: 2),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.collectionBehavior = collectionBehavior
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
        content.wantsLayer = true
        window.contentView = content
    }

    static func matches(_ frame: CGRect, _ other: CGRect) -> Bool {
        abs(frame.minX - other.minX) <= 0.5 && abs(frame.minY - other.minY) <= 0.5
            && abs(frame.width - other.width) <= 0.5 && abs(frame.height - other.height) <= 0.5
    }

    static func overviewIsVisible(on screen: CGRect) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        return windows.contains { window in
            let owner = window[kCGWindowOwnerName as String] as? String
            let layer = window[kCGWindowLayer as String] as? Int
            if owner == "Dock" { return layer == 18 }
            guard owner == "WindowManager", layer == 19,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            return (bounds["Width"] ?? 0) >= screen.width - 1 && (bounds["Height"] ?? 0) >= screen.height - 1
        }
    }

    func attach(level: NSWindow.Level, screen: CGRect) {
        if window.level != level { window.level = level }
        let side: CGFloat = grown ? 40 : 2
        let frame = CGRect(x: screen.minX, y: screen.minY, width: side, height: side)
        if !Self.matches(frame, window.frame) { window.setFrame(frame, display: false) }
        if !window.isVisible { window.orderFrontRegardless() }
    }

    func serverAnimatesFrames(level: NSWindow.Level, screen: CGRect) -> Bool {
        if !window.isVisible {
            attach(level: level, screen: screen)
            window.contentView?.layoutSubtreeIfNeeded()
            CATransaction.flush()
        }
        grown.toggle()
        attach(level: level, screen: screen)
        window.contentView?.layoutSubtreeIfNeeded()
        CATransaction.flush()
        guard let layer = window.contentView?.layer, let committed = layer.presentation()?.bounds.size,
              abs(committed.width - layer.bounds.width) <= 0.5, abs(committed.height - layer.bounds.height) <= 0.5,
              window.windowNumber > 0,
              let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(window.windowNumber))
                            as? [[String: Any]])?.first,
              let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
              let width = bounds["Width"], let height = bounds["Height"] else { return false }
        return abs(width - window.frame.width) > 0.5 || abs(height - window.frame.height) > 0.5
    }

    func close() { window.orderOut(nil) }
}

final class NotchPanel: NSPanel, NotchWaveHold {
    static let overlayCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle
    ]
    static let normalLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    static let fullscreenLevel = NSWindow.Level.floating
    var acceptsKeyFocus = false
    var handleScroll: ((NSEvent) -> Bool)?
    var visibilityDidChange: (() -> Void)?
    var holdsWave = false {
        didSet {
            guard holdsWave != oldValue else { return }
            guard holdsWave || !isVisible else { return }
            NotificationCenter.default.post(name: NotchEqualizerView.holdWaveNotification, object: self)
        }
    }
    override var canBecomeKey: Bool { acceptsKeyFocus }
    override var canBecomeMain: Bool { false }
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .unknown }

    override func orderOut(_ sender: Any?) {
        if let sheet = attachedSheet { endSheet(sheet, returnCode: .cancel) }
        super.orderOut(sender)
        visibilityDidChange?()
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        visibilityDidChange?()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel,
           handleScroll?(event) == true || HorizontalWheelScrolling.handle(event) { return }
        super.sendEvent(event)
    }
}

private final class NotchQuickAccessContainer: NSView {
    let canvas: NotchCanvas
    let motion: NotchQuickAccessMotion
    let quickView: NSHostingView<AnyView>
    private(set) var hoverRects: [CGRect] = []
    private var hoverTrackingAreas: [NSTrackingArea] = []
    var hoverChanged: ((Bool) -> Void)?
    var gutter: CGFloat = 0 { didSet { needsLayout = true } }
    var bottomInset: CGFloat = 0 { didSet { needsLayout = true } }
    private var stage = CGSize.zero
#if VORSSAINT_DEVELOPMENT
    var nextProbeLayout: (() -> Void)?
#endif
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    init(canvas: NotchCanvas, content: (NotchQuickAccessMotion, NotchBackdropPresentation) -> AnyView) {
        self.canvas = canvas
        let motion = NotchQuickAccessMotion()
        self.motion = motion
        quickView = NSHostingView(rootView: content(motion, canvas.backdropPresentation))
        quickView.sizingOptions = []
        quickView.wantsLayer = true
        quickView.isHidden = true
        super.init(frame: canvas.frame)
        wantsLayer = true
        autoresizesSubviews = false
        addSubview(quickView)
        addSubview(canvas)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        updateFrames()
#if VORSSAINT_DEVELOPMENT
        let probe = nextProbeLayout
        nextProbeLayout = nil
        probe?()
#endif
    }

    func updateFrames() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let frame = CGRect(x: gutter, y: 0, width: max(0, bounds.width - gutter * 2), height: max(0, bounds.height - bottomInset))
        if canvas.frame != frame { canvas.frame = frame }
        stage = NotchStage.size(including: CGSize(width: max(stage.width, bounds.width), height: max(stage.height, bounds.height)))
        let stageFrame = NotchStage.frame(stage, in: bounds)
        if quickView.frame != stageFrame { quickView.frame = stageFrame }
        CATransaction.commit()
    }

    func setHoverRects(_ rects: [CGRect]) {
        guard rects != hoverRects else { return }
        hoverTrackingAreas.forEach(removeTrackingArea)
        hoverRects = rects
        hoverTrackingAreas = rects.filter { !$0.isEmpty && !$0.isNull }.map { rect in
            NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag], owner: self, userInfo: nil)
        }
        hoverTrackingAreas.forEach(addTrackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        if hoverTrackingAreas.contains(where: { event.trackingArea === $0 }) { hoverChanged?(true) }
        else { super.mouseEntered(with: event) }
    }

    override func mouseExited(with event: NSEvent) {
        if hoverTrackingAreas.contains(where: { event.trackingArea === $0 }) { hoverChanged?(false) }
        else { super.mouseExited(with: event) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard canvas.containsVisiblePoint(canvas.convert(local, from: self))
                || motion.contains(quickView.convert(local, from: self)) else { return nil }
        return super.hitTest(point)
    }
}

private final class NotchBackdropTick: NSObject {
    weak var canvas: NotchCanvas?
    init(canvas: NotchCanvas) { self.canvas = canvas }
    @objc func fire(_ sender: CADisplayLink) {
        canvas?.advanceBackdrop(to: sender.targetTimestamp + (sender.targetTimestamp - sender.timestamp))
    }
}

private final class NotchCanvas: NSView {
    private let host: NotchHostingView
    private let backdrop: NotchHostingView
    let backdropPresentation = NotchBackdropPresentation()
    private var stage = CGSize.zero
    private(set) var backdropDisplayLink: CADisplayLink?
    private lazy var backdropTick = NotchBackdropTick(canvas: self)
    private(set) var backdropTicks = 0
    private let activationButton = NotchActivationButton()
    private var activationRect = CGRect.zero
    private var hoverTrackingArea: NSTrackingArea?
    var hoverChanged: ((Bool) -> Void)?
    private let silhouette = CAShapeLayer()
    private let edge = CAShapeLayer()
    private let edgeMask = CALayer()
    private(set) var floatingGap: CGFloat?
    private var silhouetteSize = CGSize.zero
    private var outlineEnabled = false
    private var outlineColor = NSColor.white
    private let contentVisibility = CALayer()
    private let mascotBridge = NotchMascotHostView(frame: .zero)
    private var mascotBridgeSpot: (offset: CGFloat, baseline: CGFloat, size: CGFloat)?
    private var dropActions: NotchFileDropActions?
    private var acceptingDrag = false
    private var contentSize: CGSize
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    init(content: AnyView, background: (NotchBackdropPresentation) -> AnyView, size: CGSize) {
        contentSize = size
        backdrop = NotchHostingView(rootView: background(backdropPresentation))
        backdrop.sizingOptions = []
        backdrop.wantsLayer = true
        backdrop.autoresizingMask = []
        host = NotchHostingView(rootView: content)
        host.sizingOptions = []
        host.wantsLayer = true
        host.autoresizingMask = []
        super.init(frame: CGRect(origin: .zero, size: size))
        autoresizesSubviews = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        layer?.mask = silhouette
        addSubview(backdrop)
        addSubview(host)
        mascotBridge.isHidden = true
        addSubview(mascotBridge)
        activationButton.isTransparent = true
        activationButton.isHidden = true
        activationButton.target = activationButton
        activationButton.action = #selector(NotchActivationButton.invoke)
        activationButton.setAccessibilityIdentifier("notch.activation")
        addSubview(activationButton)
        edge.fillColor = nil
        updateContrast()
        edge.zPosition = 2
        edgeMask.backgroundColor = NSColor.black.cgColor
        edgeMask.frame = CGRect(x: -10_000, y: Self.outlineTopGap, width: 20_000, height: 20_000)
        edge.mask = edgeMask
        layer?.addSublayer(edge)
        contentVisibility.name = "notch.contentVisibility"
        contentVisibility.backgroundColor = NSColor.black.cgColor
        contentVisibility.opacity = 1
        host.layer?.mask = contentVisibility
        setContentSize(size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setContentSize(_ size: CGSize) {
        contentSize = size
        needsLayout = true
    }

    func setActivationArea(_ rect: CGRect, title: String, willPress: @escaping () -> Void, activate: @escaping () -> Void) {
        activationRect = rect
        activationButton.isHidden = rect.isEmpty
        activationButton.setAccessibilityLabel(title)
        activationButton.willPress = willPress
        activationButton.activate = activate
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func updateContrast() {
        let increasedContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let color = (increasedContrast ? NSColor.white : outlineColor).withAlphaComponent(
            outlineEnabled ? (increasedContrast ? 0.85 : 0.65) : (increasedContrast ? 0.45 : 0)).cgColor
        let lineWidth: CGFloat = outlineEnabled ? NotchLayout.outlineWidth : 0.5
        let opacity: Float = outlineEnabled || contentSize.height > 64 ? 1 : 0
        guard edge.strokeColor != color || edge.lineWidth != lineWidth || edge.opacity != opacity else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edge.strokeColor = color
        edge.lineWidth = lineWidth
        edge.opacity = opacity
        CATransaction.commit()
    }

    func setOutline(enabled: Bool, color: NSColor) {
        guard outlineEnabled != enabled || outlineColor != color else { return }
        outlineEnabled = enabled
        outlineColor = color
        updateContrast()
    }

    func setFloatingGap(_ gap: CGFloat?) {
        guard floatingGap != gap else { return }
        floatingGap = gap
        stopMotion()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeMask.frame.origin.y = gap == nil ? Self.outlineTopGap : -10_000
        CATransaction.commit()
        backdropPresentation.floatingGap = gap ?? 0
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    static let outlineTopGap: CGFloat = 1

    var outlineProbeOpacity: Float { edge.opacity }
    var outlineProbeWidth: CGFloat { edge.lineWidth }
    var outlineProbeTopOpen: Bool {
        guard let mask = edge.mask else { return false }
        return mask.frame.minY >= edge.lineWidth / 2 && mask.frame.minY <= Self.outlineTopGap
    }
    var outlineProbeAllRound: Bool {
        guard let mask = edge.mask else { return true }
        return mask.frame.minY < -edge.lineWidth
    }

    func setFileDropActions(_ actions: NotchFileDropActions?) {
        let wasEnabled = dropActions != nil
        dropActions = actions
        guard wasEnabled != (actions != nil) else { return }
        unregisterDraggedTypes()
        if actions != nil { registerForDraggedTypes(ShelfService.tileDropTypes) }
        else { acceptingDrag = false }
    }

    func beginDrop(_ pasteboard: NSPasteboard, localSource: Bool) -> NSDragOperation {
        acceptingDrag = !localSource && dropActions?.canAccept(pasteboard) == true
        if acceptingDrag { dropActions?.enter(pasteboard) }
        return acceptingDrag ? .copy : []
    }

    func finishDrop(_ pasteboard: NSPasteboard) -> Bool {
        guard acceptingDrag else { return false }
        defer { acceptingDrag = false; dropActions?.exit() }
        return dropActions?.accept(pasteboard) == true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard containsVisiblePoint(convert(sender.draggingLocation, from: nil)) else {
            if acceptingDrag { acceptingDrag = false; dropActions?.exit() }
            return []
        }
        let operation = acceptingDrag ? .copy : beginDrop(sender.draggingPasteboard, localSource: sender.draggingSource != nil)
        if acceptingDrag, dropActions?.update?(convert(sender.draggingLocation, from: nil)) == false { return [] }
        return operation
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        acceptingDrag = false
        dropActions?.exit()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard containsVisiblePoint(convert(sender.draggingLocation, from: nil)) else {
            acceptingDrag = false
            dropActions?.exit()
            return false
        }
        if acceptingDrag, dropActions?.update?(convert(sender.draggingLocation, from: nil)) == false {
            acceptingDrag = false
            dropActions?.exit()
            return false
        }
        return finishDrop(sender.draggingPasteboard)
    }

#if VORSSAINT_DEVELOPMENT
    var contentProbeOpacity: Float { contentVisibility.presentation()?.opacity ?? contentVisibility.opacity }
    var contentProbeAnimating: Bool { contentVisibility.animation(forKey: "notch.opacity") != nil }
    var contentProbeAlpha: CGFloat { host.alphaValue }
    var contentProbeReplacing: Bool { host.layer?.animation(forKey: kCATransition) != nil }
    var contentProbeBlurred: Bool { host.layer?.filters?.isEmpty == false }
    var contentProbeGrowing: Bool { host.layer?.animation(forKey: Self.arrivalScaleKey) != nil }
    var contentProbeGrowthDrift: CGFloat {
        guard let layer = host.layer, let transform = layer.presentation()?.transform else { return 0 }
        let anchor = CGPoint(x: layer.anchorPoint.x * layer.bounds.width, y: layer.anchorPoint.y * layer.bounds.height)
        let top = CGPoint(x: layer.bounds.midX, y: layer.contentsAreFlipped() ? layer.bounds.minY : layer.bounds.maxY)
        let x = (top.x - anchor.x) * transform.m11 + (top.y - anchor.y) * transform.m21 + transform.m41 + anchor.x
        let y = (top.x - anchor.x) * transform.m12 + (top.y - anchor.y) * transform.m22 + transform.m42 + anchor.y
        return hypot(x - top.x, y - top.y)
    }
    var backdropProbeFrame: CGRect { backdropPresentation.contour.boundingRect }
    var backdropProbeFollowsSilhouette: Bool {
        visiblePath.map { backdropPresentation.contour == backdropContour($0) } ?? false
    }
    var backdropProbeIndependent: Bool {
        host.layer?.mask === contentVisibility && backdrop.layer?.mask == nil
            && (backdrop.layer?.presentation()?.opacity ?? backdrop.layer?.opacity) == 1
    }
#endif

    var hostedSize: CGSize { host.frame.size }
    var contentTopInWindow: CGPoint { host.convert(.zero, to: nil) }

    private static let motionKey = "notch.resize"
    private static let departureKey = "notchDeparture"
    var departsContent: Bool {
        contentVisibility.animation(forKey: "notch.opacity")?.value(forKey: Self.departureKey) as? Bool == true
    }
    var visiblePath: CGPath? {
        guard silhouette.animation(forKey: Self.motionKey) != nil else { return silhouette.path.map(inCanvas) }
        return (silhouette.presentation()?.path ?? silhouette.path).map(inCanvas)
    }

    private func inCanvas(_ path: CGPath) -> CGPath {
        var offset = CGAffineTransform(translationX: silhouette.frame.minX, y: 0)
        return path.copy(using: &offset) ?? path
    }

    func surfaceSize(of path: CGPath) -> CGSize {
        let box = path.boundingBoxOfPath
        guard !box.isNull else { return .zero }
        if let floatingGap { return NotchLayout.capsuleSurface(ofBody: box, gap: floatingGap) }
        return CGSize(width: box.width, height: max(0, box.maxY))
    }

    var visibleSize: CGSize? {
        guard let path = visiblePath else { return nil }
        guard silhouette.animation(forKey: Self.motionKey) != nil else { return silhouetteSize }
        return surfaceSize(of: path)
    }

    func containsVisiblePoint(_ point: CGPoint) -> Bool {
        contains(point, in: visiblePath)
    }

    func containsDestinationPoint(_ point: CGPoint) -> Bool {
        contains(point, in: silhouette.path.map(inCanvas))
    }

    private func contains(_ point: CGPoint, in path: CGPath?) -> Bool {
        guard let path else { return false }
        if path.contains(point) { return true }
        guard floatingGap != nil else { return false }
        let box = path.boundingBoxOfPath
        guard !box.isNull, box.width > 0, point.x >= box.minX, point.x <= box.maxX else { return false }
        return point.y >= 0 && point.y <= box.minY
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard containsVisiblePoint(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }

    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea === hoverTrackingArea { hoverChanged?(true) }
        else { super.mouseEntered(with: event) }
    }

    override func mouseExited(with event: NSEvent) {
        if event.trackingArea === hoverTrackingArea { hoverChanged?(false) }
        else { super.mouseExited(with: event) }
    }

    var islandMinX: ((CGSize) -> CGFloat?)?
    var stageCentreX: (() -> CGFloat?)?

    private func islandX(_ size: CGSize) -> CGFloat {
        islandMinX?(size) ?? (bounds.width - size.width) / 2
    }

    func silhouettePath(for size: CGSize, offset: CGFloat = 0) -> CGPath {
        var translation = CGAffineTransform(translationX: islandX(size) + offset - silhouette.frame.minX, y: 0)
        let path = NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: size.height),
                              floatingGap: floatingGap)
            .path(in: CGRect(origin: .zero, size: size)).cgPath
        return path.copy(using: &translation) ?? path
    }

    private var motionTimeline: NotchMotionTimeline?
    var motionProbeStart: CGSize? { motionTimeline?.start }

    func carriedMotion(to size: CGSize, at time: CFTimeInterval) -> NotchMotionTimeline? {
        guard let timeline = motionTimeline, let began = silhouette.animation(forKey: Self.motionKey)?.beginTime,
              began > 0, began <= time else { return nil }
        return timeline.rebased(to: began).continued(to: size, at: time)
    }

    var collapsesToBlack = false
    var growsIntoGlass = false
    private static let collapseFadeKey = "everything.collapseFade"

    func animate(_ animation: CAAnimation, from: CGPath?, motion: NotchMotionTimeline? = nil) {
        restoreHeldBackdrop()
        motionStart = nil
        motionStartOffset = 0
        motionTimeline = motion
        silhouette.path = silhouettePath(for: contentSize)
        silhouetteSize = contentSize
        edge.path = silhouette.path
        silhouette.add(animation, forKey: Self.motionKey)
        if let from { setBackdropContour(inCanvas(from)) }
        if growsIntoGlass {
            growsIntoGlass = false
            let fromBlack = backdropPresentation.restingBlack > 0.5
            let startColor = layer?.presentation()?.backgroundColor ?? layer?.backgroundColor
            setBackdropContour(inCanvas(silhouettePath(for: CGSize(width: contentSize.width + 3,
                                                                   height: contentSize.height + 2))))
            if fromBlack {
                let duration: CFTimeInterval = 0.24
                let glass = CAKeyframeAnimation(keyPath: "opacity")
                glass.values = [0, 1, 1]
                glass.keyTimes = [0, 0.55, 1]
                glass.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .linear)]
                let black = CAKeyframeAnimation(keyPath: "backgroundColor")
                black.values = [startColor ?? NSColor.black.cgColor, NSColor.black.cgColor,
                                layer?.backgroundColor ?? NSColor.clear.cgColor]
                black.keyTimes = [0, 0.45, 1]
                black.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeInEaseOut)]
                for (target, fade) in [(backdrop.layer, glass as CAAnimation), (layer, black as CAAnimation)] {
                    fade.duration = duration
                    target?.add(fade, forKey: Self.collapseFadeKey)
                }
            } else {
                let underlay = CABasicAnimation(keyPath: "backgroundColor")
                underlay.fromValue = NSColor.black.cgColor
                underlay.toValue = layer?.backgroundColor
                underlay.duration = 0.1
                underlay.timingFunction = CAMediaTimingFunction(name: .easeIn)
                layer?.add(underlay, forKey: "everything.growUnderlay")
            }
            if let borderAnimation = animation.copy() as? CAAnimation {
                borderAnimation.delegate = nil
                edge.add(borderAnimation, forKey: Self.motionKey)
            }
            return
        }
        if collapsesToBlack {
            collapsesToBlack = false
            let timing = CAMediaTimingFunction(name: .easeOut)
            let glass = CABasicAnimation(keyPath: "opacity")
            glass.fromValue = backdrop.layer?.presentation()?.opacity ?? 1
            glass.toValue = 0
            closingToBlack = true
            freezesBackdropContour = true
            layer?.removeAnimation(forKey: Self.collapseFadeKey)
            layer?.backgroundColor = NSColor.black.cgColor
            for (target, fade) in [(backdrop.layer, glass)] {
                fade.duration = 0.2
                fade.timingFunction = timing
                fade.fillMode = .forwards
                fade.isRemovedOnCompletion = false
                target?.add(fade, forKey: Self.collapseFadeKey)
            }
            if let borderAnimation = animation.copy() as? CAAnimation {
                borderAnimation.delegate = nil
                edge.add(borderAnimation, forKey: Self.motionKey)
            }
            return
        }
        let link = displayLink(target: backdropTick, selector: #selector(NotchBackdropTick.fire(_:)))
        backdropDisplayLink = link
        link.add(to: .main, forMode: .common)
        if let borderAnimation = animation.copy() as? CAAnimation {
            borderAnimation.delegate = nil
            edge.add(borderAnimation, forKey: Self.motionKey)
        }
    }
    func stopMotion() {
        motionTimeline = nil
        silhouette.removeAnimation(forKey: Self.motionKey)
        edge.removeAnimation(forKey: Self.motionKey)
        backdropDisplayLink?.invalidate()
        backdropDisplayLink = nil
        if freezesBackdropContour, layer?.animation(forKey: Self.collapseFadeKey) == nil,
           backdrop.layer?.animation(forKey: Self.collapseFadeKey) == nil {
            freezesBackdropContour = false
            synchronizeBackdrop()
        }
        endCollapseFade()
    }

    func endCollapseFade() {
        guard backdrop.layer?.animation(forKey: Self.collapseFadeKey) != nil
                || layer?.animation(forKey: Self.collapseFadeKey) != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        freezesBackdropContour = false
        synchronizeBackdrop()
        backdrop.layer?.opacity = 0
        layer?.backgroundColor = NSColor.black.cgColor
        backdrop.layer?.removeAnimation(forKey: Self.collapseFadeKey)
        layer?.removeAnimation(forKey: Self.collapseFadeKey)
        backdropHeldHidden = true
        CATransaction.commit()
    }

    private var backdropHeldHidden = false

    private func restoreHeldBackdrop() {
        guard backdropHeldHidden else { return }
        backdropHeldHidden = false
        backdrop.layer?.opacity = 1
    }

    var usesGlass: Bool { backdropPresentation.usesGlass }

    func setUsesGlass(_ enabled: Bool) {
        if enabled { restoreHeldBackdrop() }
        guard usesGlass != enabled else { return }
        backdropPresentation.usesGlass = enabled
        updateCanvasBlack()
    }

    var closingToBlack = false

    func updateCanvasBlack() {
        let alpha = usesGlass && !closingToBlack ? CGFloat(backdropPresentation.restingBlack) : 1
        let color = NSColor.black.withAlphaComponent(alpha).cgColor
        guard layer?.backgroundColor != color else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = color
        CATransaction.commit()
    }

    fileprivate func advanceBackdrop(to target: CFTimeInterval) {
        backdropTicks += 1
        guard let timeline = motionTimeline else { synchronizeBackdrop(); return }
        let time = max(target, timeline.begin)
        setBackdropContour(inCanvas(silhouettePath(for: timeline.size(at: time), offset: timeline.offset(at: time))))
    }

    var motionStart: CGSize?
    var motionStartOffset: CGFloat = 0

    var visibleShift: CGFloat? {
        guard let path = visiblePath, let centre = stageCentreX?() else { return nil }
        let box = path.boundingBoxOfPath
        guard !box.isNull, box.width > 0 else { return nil }
        return box.midX - centre
    }

    fileprivate func synchronizeBackdrop() {
        let path = backdropDisplayLink == nil ? silhouette.path.map(inCanvas) : visiblePath
        if let path { setBackdropContour(path) }
    }

    private func backdropContour(_ path: CGPath) -> Path {
        var offset = CGAffineTransform(translationX: -backdrop.frame.minX, y: 0)
        return Path(path.copy(using: &offset) ?? path)
    }

    var freezesBackdropContour = false

    private func setBackdropContour(_ path: CGPath) {
        guard !freezesBackdropContour else { return }
        let contour = backdropContour(path)
        guard backdropPresentation.contour != contour else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { backdropPresentation.contour = contour }
        updateCanvasBlack()
    }

    deinit { backdropDisplayLink?.invalidate() }

    func transitionContent(_ kind: NotchContentTransition, shapeSnaps: Bool = false) {
        guard kind != .none else { return }
        let currentOpacity = contentVisibility.presentation()?.opacity ?? contentVisibility.opacity
        let presentedArrival = self.presentedArrival
        contentVisibility.removeAnimation(forKey: "notch.opacity")
        host.layer?.removeAnimation(forKey: kCATransition)
        endArrival()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if kind == .dismiss {
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.values = [0, 0, 1]
            animation.keyTimes = [0, 0.75, 1]
            animation.duration = 0.34
            animation.timingFunctions = [CAMediaTimingFunction(name: .linear),
                                         CAMediaTimingFunction(name: .easeOut)]
            contentVisibility.opacity = 1
            contentVisibility.add(animation, forKey: "notch.opacity")
        } else if kind == .replace {
            let reveal = CAKeyframeAnimation(keyPath: "opacity")
            reveal.values = [0, 0, 1]
            reveal.keyTimes = [0, 0.18, 1]
            reveal.duration = 0.26
            reveal.timingFunctions = [CAMediaTimingFunction(name: .linear),
                                      CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)]
            contentVisibility.opacity = 1
            contentVisibility.add(reveal, forKey: "notch.opacity")
            beginArrival(opening: false, keyTimes: [0, 0.18, 1], duration: 0.26, resuming: nil)
        } else {
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            let start: Float = kind == .dismiss || currentOpacity == 1 ? 0 : currentOpacity
            let keyTimes: [NSNumber] = kind == .dismiss ? [0, 0.55, 1] : shapeSnaps ? [0, 0.2, 1] : [0, 0.24, 1]
            let duration: CFTimeInterval = kind == .dismiss ? 0.2 : shapeSnaps ? 0.14 : 0.2
            animation.values = [start, start, 1]
            animation.keyTimes = keyTimes
            animation.duration = duration
            animation.calculationMode = .linear
            animation.timingFunctions = [CAMediaTimingFunction(name: .linear),
                                         CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)]
            if kind == .depart {
                animation.values = [currentOpacity, 0]
                animation.keyTimes = [0, 1]
                animation.duration = 0.1
                animation.timingFunctions = [CAMediaTimingFunction(controlPoints: 0.4, 0, 0.7, 1)]
                animation.fillMode = .forwards
                animation.isRemovedOnCompletion = false
                animation.setValue(true, forKey: Self.departureKey)
            }
            contentVisibility.opacity = 1
            contentVisibility.add(animation, forKey: "notch.opacity")
            if !shapeSnaps, kind != .depart {
                beginArrival(opening: kind == .reveal, keyTimes: keyTimes, duration: duration,
                             resuming: start > 0 ? presentedArrival ?? (blur: 0, scale: 1) : nil)
            }
        }
        CATransaction.commit()
    }

    func finishDeparture() {
        guard departsContent else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0
        animation.toValue = 1
        animation.beginTime = CACurrentMediaTime() + 0.04
        animation.fillMode = .backwards
        animation.duration = 0.16
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        contentVisibility.removeAnimation(forKey: "notch.opacity")
        contentVisibility.add(animation, forKey: "notch.opacity")
        CATransaction.commit()
    }

    func restoreContent() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentVisibility.removeAnimation(forKey: "notch.opacity")
        contentVisibility.opacity = 1
        host.layer?.removeAnimation(forKey: kCATransition)
        CATransaction.commit()
        endArrival()
    }

    private struct Arrival {
        let begin: CFTimeInterval
        let duration: CFTimeInterval
        let scale: CGFloat
        var width: CGFloat = 0
    }

    private static let arrivalBlurName = "notchArrival"
    private static let arrivalBlurKey = "notch.arrival.blur"
    private static let arrivalScaleKey = "notch.arrival.scale"
    private var arrival: Arrival?
    private var arrivalGeneration = 0

    private static func makeArrivalBlur() -> NSObject? {
        let make = NSSelectorFromString("filterWithType:")
        guard let type = NSClassFromString("CAFilter") as? NSObject.Type, type.responds(to: make),
              let filter = type.perform(make, with: "gaussianBlur")?.takeUnretainedValue() as? NSObject else { return nil }
        filter.setValue(arrivalBlurName, forKey: "name")
        filter.setValue(0, forKey: "inputRadius")
        return filter
    }

    private var presentedArrival: (blur: CGFloat, scale: CGFloat)? {
        guard arrival != nil || host.layer?.animation(forKey: Self.arrivalBlurKey) != nil,
              let presentation = host.layer?.presentation() else { return nil }
        let blur = presentation.value(forKeyPath: "filters.\(Self.arrivalBlurName).inputRadius") as? NSNumber
        return (CGFloat(blur?.doubleValue ?? 0), presentation.transform.m11)
    }

    private func beginArrival(opening: Bool, keyTimes: [NSNumber], duration: CFTimeInterval,
                              resuming: (blur: CGFloat, scale: CGFloat)?) {
        guard let layer = host.layer else { return }
        arrivalGeneration += 1
        let generation = arrivalGeneration
        let begin = layer.convertTime(CACurrentMediaTime(), from: nil)
        let radius = resuming?.blur ?? (opening ? 12 : 6)
        if radius > 0, let filter = Self.makeArrivalBlur() {
            layer.filters = [filter]
            let blur = CAKeyframeAnimation(keyPath: "filters.\(Self.arrivalBlurName).inputRadius")
            blur.values = [radius, opening ? radius / 2 : radius, 0]
            blur.keyTimes = keyTimes
            blur.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeOut)]
            blur.beginTime = begin
            blur.duration = duration
            layer.add(blur, forKey: Self.arrivalBlurKey)
        }
        let scale = resuming?.scale ?? (opening ? 0.86 : 1)
        if scale != 1 {
            arrival = Arrival(begin: begin, duration: duration, scale: scale)
            installArrivalScale()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.arrivalGeneration == generation else { return }
            self.endArrival()
        }
    }

    private func installArrivalScale() {
        guard var arrival, let layer = host.layer,
              layer.convertTime(CACurrentMediaTime(), from: nil) < arrival.begin + arrival.duration else { return }
        arrival.width = layer.bounds.width
        self.arrival = arrival
        let growth = CABasicAnimation(keyPath: "transform")
        growth.fromValue = NSValue(caTransform3D: arrivalTransform(scale: arrival.scale, in: layer))
        growth.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        growth.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        growth.beginTime = arrival.begin
        growth.duration = arrival.duration
        layer.add(growth, forKey: Self.arrivalScaleKey)
    }

    private func arrivalTransform(scale: CGFloat, in layer: CALayer) -> CATransform3D {
        let anchor = CGPoint(x: layer.anchorPoint.x * layer.bounds.width, y: layer.anchorPoint.y * layer.bounds.height)
        let top = layer.contentsAreFlipped() ? layer.bounds.minY : layer.bounds.maxY
        let offset = CGPoint(x: layer.bounds.midX - anchor.x, y: top - anchor.y)
        let transform = CATransform3DScale(CATransform3DMakeTranslation(offset.x, offset.y, 0), scale, scale, 1)
        return CATransform3DTranslate(transform, -offset.x, -offset.y, 0)
    }

    func showMascotBridge(look: NotchMascotLook, size: CGFloat, mood: NotchMascotMood, from: CGFloat, to: CGFloat,
                          baseline: CGFloat, duration: CFTimeInterval, scale: (from: CGFloat, to: CGFloat),
                          trailsGrowth: Bool, hop: CGFloat) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let timing = trailsGrowth ? CAMediaTimingFunction(controlPoints: 0.6, 0, 0.3, 1)
            : CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        mascotBridgeSpot = (to, baseline, size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mascotBridge.configure(look: look, size: size, mood: mood, idles: false, reduceMotion: reduceMotion,
                               animated: false)
        layoutMascotBridge()
        mascotBridge.place(at: nil, visible: nil)
        mascotBridge.layer?.removeAnimation(forKey: "slide")
        mascotBridge.layer?.removeAnimation(forKey: "fade")
        mascotBridge.scale(from: scale.from, to: scale.to, duration: duration, timing: timing)
        mascotBridge.isHidden = false
        CATransaction.commit()
        guard !reduceMotion, abs(from - to) > 0.25, let layer = mascotBridge.layer else { return }
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = from - to
        slide.toValue = 0
        slide.isAdditive = true
        slide.duration = duration
        slide.timingFunction = timing
        layer.add(slide, forKey: "slide")
        layer.removeAnimation(forKey: "hop")
        guard hop > 0 else { return }
        let arc = CAKeyframeAnimation(keyPath: "position.y")
        arc.values = [0, -hop, 0]
        arc.keyTimes = [0, 0.3, 0.62]
        arc.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        arc.isAdditive = true
        arc.duration = duration
        layer.add(arc, forKey: "hop")
    }

    func reactMascotBridge(_ event: NotchMascotReactionEvent, lift: CGFloat) {
        guard mascotBridgeSpot != nil else { return }
        mascotBridge.react(event, lift: lift)
    }

    func hideMascotBridge(fading: Bool = false) {
        mascotBridgeSpot = nil
        guard fading, !mascotBridge.isHidden, let layer = mascotBridge.layer,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { concealMascotBridge(); return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? 1
        fade.toValue = 0
        fade.duration = 0.12
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.mascotBridgeSpot == nil else { return }
            self.concealMascotBridge()
        }
        layer.add(fade, forKey: "fade")
        CATransaction.commit()
    }

    private func concealMascotBridge() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mascotBridge.layer?.removeAnimation(forKey: "slide")
        mascotBridge.layer?.removeAnimation(forKey: "hop")
        mascotBridge.layer?.removeAnimation(forKey: "fade")
        mascotBridge.isHidden = true
        mascotBridge.scale(from: 1, to: 1, duration: 0)
        CATransaction.commit()
    }

    private func layoutMascotBridge() {
        guard let spot = mascotBridgeSpot else { return }
        let box = spot.size + 8
        let centre = (stageCentreX?() ?? bounds.midX) + spot.offset
        let frame = CGRect(x: centre - box / 2, y: spot.baseline - box / 2, width: box, height: box)
        if mascotBridge.frame != frame { mascotBridge.frame = frame }
    }

    private func endArrival() {
        arrivalGeneration += 1
        arrival = nil
        guard let layer = host.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAnimation(forKey: Self.arrivalBlurKey)
        layer.removeAnimation(forKey: Self.arrivalScaleKey)
        if layer.filters?.isEmpty == false { layer.filters = nil }
        CATransaction.commit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        updateGeometry()
    }

    func updateGeometry() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage = NotchStage.size(including: CGSize(width: max(stage.width, bounds.width), height: max(stage.height, bounds.height)))
        let centre = stageCentreX?() ?? bounds.midX
        let maskFrame = CGRect(x: centre - stage.width / 2, y: 0, width: stage.width, height: stage.height)
        if silhouette.frame != maskFrame {
            silhouette.frame = maskFrame
            edge.frame = maskFrame
        }
        silhouetteSize = motionStart ?? contentSize
        silhouette.path = silhouettePath(for: silhouetteSize, offset: motionStart == nil ? 0 : motionStartOffset)
        edge.path = silhouette.path
        updateContrast()
        var hostFrame = NotchStage.frame(stage, in: bounds)
        hostFrame.origin.x = centre - stage.width / 2
        if host.frame != hostFrame { host.frame = hostFrame }
        contentVisibility.frame = host.bounds
        layoutMascotBridge()
        if let arrival, arrival.width != host.layer?.bounds.width { installArrivalScale() }
        var backdropFrame = NotchStage.frame(stage, in: bounds)
        backdropFrame.origin.x = hostFrame.minX
        if backdrop.frame != backdropFrame { backdrop.frame = backdropFrame }
        synchronizeBackdrop()
        activationButton.frame = activationRect.offsetBy(dx: islandX(contentSize), dy: 0)
        let hoverRect = CGRect(x: islandX(contentSize), y: 0, width: contentSize.width, height: contentSize.height)
        if hoverTrackingArea?.rect != hoverRect {
            if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
            let area = NSTrackingArea(rect: hoverRect, options: [.mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag], owner: self, userInfo: nil)
            hoverTrackingArea = area
            addTrackingArea(area)
        }
        CATransaction.commit()
    }
}

final class NotchActivationButton: NSButton {
    var willPress: (() -> Void)?
    var activate: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func mouseDown(with event: NSEvent) {
        willPress?()
        super.mouseDown(with: event)
    }
    @objc func invoke() { activate?() }
}

private final class NotchHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

