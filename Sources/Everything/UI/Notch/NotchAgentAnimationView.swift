// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import QuartzCore

/// Small decorative layers, stepped at a limited rate while they show.
/// Settings retains its view hierarchy when closed, so disappearance alone
/// cannot stop motion: observe the actual window's visibility as well.
final class NotchAgentAnimationView: NSView {
    private let artwork = CALayer()
    private var image: NSImage?
    private var tint: NSColor?
    private let dot = CAShapeLayer()
    private let ring = CAShapeLayer()
    private var isPulse = false
    private var size: CGFloat = 0
    private var animates = false
    private var visibilityObserver: NSObjectProtocol?
    private(set) var motionStart: CFTimeInterval = 0
    private lazy var clock = NotchDecorativeClock { [weak self] time in self?.step(at: time) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(artwork)
        layer?.addSublayer(dot)
        layer?.addSublayer(ring)
        ring.fillColor = nil
        ring.lineWidth = 1
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configureGlyph(image: NSImage?, size: CGFloat, tint: NSColor?, animates: Bool) {
        let changed = self.image !== image || self.size != size || self.tint != tint || isPulse
        isPulse = false
        self.image = image
        self.tint = tint
        self.size = size
        self.animates = animates
        if changed { renderArtwork() }
        updateLayers()
    }

    func configurePulse(size: CGFloat, tint: NSColor, animates: Bool) {
        isPulse = true
        self.size = size
        self.animates = animates
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.fillColor = tint.cgColor
        ring.strokeColor = tint.cgColor
        CATransaction.commit()
        updateLayers()
    }

    func stop() {
        animates = false
        updateLayers()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: window, queue: .main) { [weak self] _ in
                self?.updateLayers()
            }
        }
        renderArtwork()
        updateLayers()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        renderArtwork()
    }

    /// Rasterize only when the mark, tint, size or display scale changes.
    /// The compositor reuses this small image for every animation frame.
    private func renderArtwork() {
        guard !isPulse, let image, size > 0 else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixels = max(1, Int(ceil(size * scale)))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let factor = CGFloat(pixels) / max(1, max(image.size.width, image.size.height))
        let width = image.size.width * factor
        let height = image.size.height * factor
        let rect = CGRect(x: (CGFloat(pixels) - width) / 2, y: (CGFloat(pixels) - height) / 2,
                          width: width, height: height)
        image.draw(in: rect)
        if let tint {
            tint.setFill()
            rect.fill(using: .sourceAtop)
        }
        NSGraphicsContext.restoreGraphicsState()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artwork.contents = bitmap.cgImage
        artwork.contentsScale = scale
        CATransaction.commit()
    }

    override func viewDidHide() { super.viewDidHide(); updateLayers() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateLayers() }
    override func layout() { super.layout(); updateLayers() }

    var isMoving: Bool { clock.isRunning }

    private func updateLayers() {
        let moving = animates && !isHiddenOrHasHiddenAncestor
            && window?.isVisible == true && window?.occlusionState.contains(.visible) == true
        // Snapshot, time and geometry updates keep the motion's phase.
        if moving, !clock.isRunning { motionStart = CACurrentMediaTime() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artwork.isHidden = isPulse
        dot.isHidden = !isPulse
        ring.isHidden = !isPulse || !moving
        // Bounds and position rather than frames: the moving layer is scaled.
        let box = CGRect(x: 0, y: 0, width: size, height: size)
        for layer in [artwork, dot, ring] {
            layer.bounds = box
            layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        for shape in [dot, ring] where shape.path?.boundingBox != box {
            shape.path = CGPath(ellipseIn: box, transform: nil)
        }
        // Everything: the spinner's frames are a keyframe animation the
        // window server plays; only the pulse still needs the app's clock.
        let spins = moving && !isPulse && !Self.spinner.frames.isEmpty
        if spins {
            if artwork.animation(forKey: Self.spinnerKey) == nil {
                let spinner = Self.spinner
                let loop = spinner.ends.last ?? 1
                let animation = CAKeyframeAnimation(keyPath: "contents")
                animation.values = spinner.frames
                animation.keyTimes = ([0] + spinner.ends.dropLast()).map { NSNumber(value: $0 / loop) }
                animation.calculationMode = .discrete
                animation.duration = loop
                animation.repeatCount = .infinity
                animation.isRemovedOnCompletion = false
                artwork.contentsGravity = .resizeAspect
                artwork.contents = spinner.frames.first
                artwork.add(animation, forKey: Self.spinnerKey)
                spinnerShowing = 0
            }
            artwork.transform = CATransform3DIdentity
            artwork.opacity = 1
        } else {
            artwork.removeAnimation(forKey: Self.spinnerKey)
            show(at: moving ? CACurrentMediaTime() : nil)
        }
        CATransaction.commit()
        if moving && isPulse { clock.start(in: self) } else { clock.stop() }
    }

    // MARK: Claude's spinner

    /// Claude's "thinking" animation, played from its own GIF: each frame
    /// shows for its own delay, and a step only swaps the layer's contents.
    private static let spinner: (frames: [CGImage], ends: [CFTimeInterval]) = {
        guard let url = Bundle.main.url(forResource: "ClaudeThinking", withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return ([], []) }
        var frames: [CGImage] = []
        var ends: [CFTimeInterval] = []
        var total: CFTimeInterval = 0
        for index in 0..<CGImageSourceGetCount(source) {
            guard let raw = CGImageSourceCreateImageAtIndex(source, index, nil),
                  let image = keyedOutWhite(raw) else { continue }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime as String] as? Double) ?? 0.1
            total += max(0.02, delay)
            frames.append(image)
            ends.append(total)
        }
        return (frames, ends)
    }()
    private var spinnerShowing = -1
    private static let spinnerKey = "everything.spinner"

    /// The GIF is drawn on white. Each pixel's distance from white becomes its
    /// alpha, filled with Claude's orange, so the spark sits on the island's
    /// black with its own soft edges.
    private static func keyedOutWhite(_ image: CGImage) -> CGImage? {
        // Everything: kept at the most it is ever drawn at (about 16 pt at
        // 3x), not the GIF's 220 px: 8 frames now take ~90 KB, not 1.5 MB.
        let side = min(image.width, 56)
        let width = side, height = side
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        // Claude orange, the spark's own color.
        let orange: (r: Double, g: Double, b: Double) = (217, 119, 86)
        for index in stride(from: 0, to: width * height * 4, by: 4) {
            let blue = Double(pixels[index + 2])
            let alpha = min(1, max(0, (255 - blue) / (255 - orange.b)))
            pixels[index] = UInt8(orange.r * alpha)
            pixels[index + 1] = UInt8(orange.g * alpha)
            pixels[index + 2] = UInt8(orange.b * alpha)
            pixels[index + 3] = UInt8(255 * alpha)
        }
        return context.makeImage()
    }

    private func spinnerFrame(at elapsed: CFTimeInterval) -> Int? {
        let spinner = Self.spinner
        guard let loop = spinner.ends.last, loop > 0 else { return nil }
        let time = elapsed.truncatingRemainder(dividingBy: loop)
        return spinner.ends.firstIndex { time < $0 } ?? spinner.frames.count - 1
    }

    /// While working, the glyph is Claude's spinner; at rest it is the mark.
    /// The pulse's ring spreads from the dot as it fades. With no time, both rest.
    private func show(at time: CFTimeInterval?) {
        var spreading = (scale: 1.0, opacity: 0.0)
        if let time, isPulse {
            let spread = NotchDecorativeClock.pulse(time - motionStart, period: 1.6)
            spreading = (1 + 0.9 * spread, 0.6 * (1 - spread))
        } else if let time, !isPulse {
            if let step = spinnerFrame(at: time - motionStart), step != spinnerShowing {
                spinnerShowing = step
                artwork.contents = Self.spinner.frames[step]
                artwork.contentsGravity = .resizeAspect
            }
            artwork.transform = CATransform3DIdentity
            artwork.opacity = 1
            ring.transform = CATransform3DMakeScale(spreading.scale, spreading.scale, 1)
            ring.opacity = Float(spreading.opacity)
            return
        } else if !isPulse, spinnerShowing != -1 {
            spinnerShowing = -1
            renderArtwork()
        }
        artwork.transform = CATransform3DIdentity
        artwork.opacity = 1
        ring.transform = CATransform3DMakeScale(spreading.scale, spreading.scale, 1)
        ring.opacity = Float(spreading.opacity)
    }

    func step(at time: CFTimeInterval) {
        guard clock.isRunning else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        show(at: time)
        CATransaction.commit()
    }
}
