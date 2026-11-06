// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum ScreenshotRenderer {
    private static let blurContext = CIContext(options: [.cacheIntermediates: false])

    static func color(_ id: ScreenshotSupport.ColorID, alpha: CGFloat = 1) -> CGColor {
        let c = id.components
        return CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: alpha)
    }

    static func nsColor(_ id: ScreenshotSupport.ColorID) -> NSColor {
        let c = id.components
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    static func fontSize(for textSize: Int, scale: CGFloat) -> CGFloat {
        CGFloat(textSize) * scale
    }

    static func textBounds(_ text: String,
                           at origin: CGPoint,
                           textSize: Int,
                           scale: CGFloat) -> CGRect {
        let font = NSFont.systemFont(ofSize: fontSize(for: textSize, scale: scale), weight: .semibold)
        let measured = (text.isEmpty ? " " : text).size(withAttributes: [.font: font])
        return CGRect(origin: origin,
                      size: CGSize(width: ceil(measured.width) + 4, height: ceil(measured.height)))
    }

    // MARK: - Annotation pass

    static func drawAnnotations(_ annotations: [ScreenshotSupport.Annotation],
                                in context: CGContext,
                                blurSources: BlurSources,
                                imageSize: CGSize,
                                scale: CGFloat,
                                annotationShadowsEnabled: Bool,
                                skippingText editingID: UUID? = nil,
                                spotlightDimStrength: CGFloat = 0.5) {
        blurSources.eraseCache?.beginPass(image: blurSources.image, textRuns: blurSources.textRuns)
        blurSources.imageLayerCache?.beginPass(base: blurSources.image)
        var precedingImages: [ScreenshotSupport.Annotation] = []
        let bounds = CGRect(origin: .zero, size: imageSize)
        let topSpotlight = annotations.lastIndex { litRegion($0, within: bounds) != nil }
        for (index, annotation) in annotations.enumerated() {
            switch annotation.tool {
            case .pixelate:
                let images = ImageLayerCache.images(below: annotation, among: precedingImages,
                                                    textRuns: blurSources.textRuns, imageSize: imageSize)
                if ImageLayerCache.usesCapture(annotation, below: images) {
                    drawBlurArea(annotation, in: context, sources: blurSources, imageSize: imageSize)
                } else if let sources = blurSources.imageLayerCache?.sources(
                    for: annotation, images: images, original: blurSources) {
                    drawBlurArea(annotation, in: context, sources: sources, imageSize: imageSize)
                } else {
                    context.saveGState()
                    context.setBlendMode(.copy)
                    context.setFillColor(CGColor(gray: 0, alpha: 1))
                    context.fill(annotation.rect.intersection(CGRect(origin: .zero, size: imageSize)))
                    context.restoreGState()
                }
            case .redact:
                context.setFillColor(color(annotation.color))
                context.fill(annotation.rect)
            case .highlight:
                context.saveGState()
                context.setBlendMode(.multiply)
                context.setFillColor(color(annotation.color, alpha: 0.42))
                context.fill(annotation.rect)
                context.restoreGState()
            case .rect:
                strokeShape(in: context, annotation: annotation, scale: scale,
                            shadowsEnabled: annotationShadowsEnabled) {
                    context.stroke(annotation.rect)
                }
            case .ellipse:
                strokeShape(in: context, annotation: annotation, scale: scale,
                            shadowsEnabled: annotationShadowsEnabled) {
                    context.strokeEllipse(in: annotation.rect)
                }
            case .line:
                drawLine(annotation, in: context, scale: scale,
                         shadowsEnabled: annotationShadowsEnabled)
            case .arrow:
                drawArrow(annotation, in: context, scale: scale,
                          shadowsEnabled: annotationShadowsEnabled)
            case .freehand:
                drawFreehand(annotation, in: context, scale: scale,
                             shadowsEnabled: annotationShadowsEnabled)
            case .text:
                if annotation.id != editingID {
                    drawText(annotation, in: context, scale: scale,
                             shadowsEnabled: annotationShadowsEnabled)
                }
            case .sticker:
                drawSticker(annotation, in: context, scale: scale,
                            shadowsEnabled: annotationShadowsEnabled)
            case .counter:
                drawCounter(annotation, in: context, imageSize: imageSize, scale: scale,
                            shadowsEnabled: annotationShadowsEnabled)
            case .image:
                ScreenshotImageLayerRendering.draw(annotation, in: context)
                precedingImages.append(annotation)
            case .spotlight:
                if index == topSpotlight {
                    drawSpotlight(annotations, dimStrength: spotlightDimStrength,
                                  imageSize: imageSize, in: context)
                }
            case .select, .crop, .expandCanvas:
                break
            }
        }
    }

    private static func litRegion(_ annotation: ScreenshotSupport.Annotation,
                                  within bounds: CGRect) -> CGRect? {
        guard annotation.tool == .spotlight else { return nil }
        let region = annotation.rect.standardized.intersection(bounds)
        return region.isEmpty ? nil : region
    }

    private static func drawSpotlight(_ annotations: [ScreenshotSupport.Annotation],
                                      dimStrength: CGFloat,
                                      imageSize: CGSize,
                                      in context: CGContext) {
        let strength = ScreenshotSupport.sanitizedSpotlightDim(dimStrength)
        let bounds = CGRect(origin: .zero, size: imageSize)
        let regions = annotations.compactMap { litRegion($0, within: bounds) }
        guard let first = regions.first, strength > 0 else { return }
        let lit = regions.dropFirst().reduce(CGPath(rect: first, transform: nil)) {
            $0.union(CGPath(rect: $1, transform: nil))
        }
        let dimmed = CGMutablePath()
        dimmed.addRect(bounds)
        dimmed.addPath(lit)
        context.saveGState()
        context.setBlendMode(.sourceAtop)
        context.setFillColor(CGColor(gray: 0, alpha: strength))
        context.addPath(dimmed)
        context.fillPath(using: .evenOdd)
        context.restoreGState()
    }

    private static func strokeShape(in context: CGContext,
                                    annotation: ScreenshotSupport.Annotation,
                                    scale: CGFloat,
                                    shadowsEnabled: Bool,
                                    stroke: () -> Void) {
        context.saveGState()
        applyShadow(context, scale: scale, enabled: shadowsEnabled)
        context.setStrokeColor(color(annotation.color))
        context.setLineWidth(annotation.stroke.width * scale)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        stroke()
        context.restoreGState()
    }

    private static func drawLine(_ annotation: ScreenshotSupport.Annotation,
                                 in context: CGContext,
                                 scale: CGFloat,
                                 shadowsEnabled: Bool) {
        guard annotation.points.count >= 2 else { return }
        let start = annotation.points[0]
        let end = annotation.points[1]
        let width = annotation.stroke.width * scale
        context.saveGState()
        applyShadow(context, scale: scale, enabled: shadowsEnabled)
        context.setStrokeColor(color(annotation.color))
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawArrow(_ annotation: ScreenshotSupport.Annotation,
                                  in context: CGContext,
                                  scale: CGFloat,
                                  shadowsEnabled: Bool) {
        guard annotation.points.count >= 2 else { return }
        let start = annotation.points[0]
        let end = annotation.points[1]
        let width = annotation.stroke.width * scale

        context.saveGState()
        applyShadow(context, scale: scale, enabled: shadowsEnabled)
        context.setStrokeColor(color(annotation.color))
        context.setFillColor(color(annotation.color))
        context.setLineWidth(width)
        context.setLineJoin(.round)
        context.setLineCap(.round)

        if let outline = ScreenshotSupport.arrowStrokePath(from: start,
                                                           to: end,
                                                           strokeWidth: width,
                                                           style: annotation.arrowStyle,
                                                           seed: annotation.scribbleSeed) {
            context.addPath(outline)
            context.strokePath()
        } else {
            context.addPath(ScreenshotSupport.arrowSilhouette(from: start,
                                                              to: end,
                                                              strokeWidth: width))
            context.fillPath()
        }
        context.restoreGState()
    }

    private static func drawFreehand(_ annotation: ScreenshotSupport.Annotation,
                                     in context: CGContext,
                                     scale: CGFloat,
                                     shadowsEnabled: Bool) {
        guard annotation.points.count > 1 else { return }
        context.saveGState()
        applyShadow(context, scale: scale, enabled: shadowsEnabled)
        context.setStrokeColor(color(annotation.color))
        context.setLineWidth(annotation.stroke.width * scale)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.beginPath()
        context.move(to: annotation.points[0])
        for index in 1..<annotation.points.count {
            let current = annotation.points[index]
            let previous = annotation.points[index - 1]
            let mid = CGPoint(x: (current.x + previous.x) / 2, y: (current.y + previous.y) / 2)
            context.addQuadCurve(to: mid, control: previous)
        }
        if let last = annotation.points.last {
            context.addLine(to: last)
        }
        context.strokePath()
        context.restoreGState()
    }

    private static func drawText(_ annotation: ScreenshotSupport.Annotation,
                                 in context: CGContext,
                                 scale: CGFloat,
                                 shadowsEnabled: Bool) {
        guard !annotation.text.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: fontSize(for: annotation.textSize, scale: scale),
                                     weight: .semibold)
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: nsColor(annotation.color),
        ]
        if shadowsEnabled {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
            shadow.shadowBlurRadius = 2.5 * scale
            shadow.shadowOffset = NSSize(width: 0, height: -1 * scale)
            attributes[.shadow] = shadow
        }
        context.saveGState()
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        annotation.text.draw(at: CGPoint(x: annotation.rect.minX + 2, y: annotation.rect.minY),
                             withAttributes: attributes)
        NSGraphicsContext.current = previous
        context.restoreGState()
    }

    private static func drawCounter(_ annotation: ScreenshotSupport.Annotation,
                                    in context: CGContext,
                                    imageSize: CGSize,
                                    scale: CGFloat,
                                    shadowsEnabled: Bool) {
        let diameter = ScreenshotSupport.counterDiameter(for: annotation.renderReferenceSize ?? imageSize, scale: 1)
        let rect = CGRect(x: annotation.rect.midX - diameter / 2,
                          y: annotation.rect.midY - diameter / 2,
                          width: diameter,
                          height: diameter)
        context.saveGState()
        applyShadow(context, scale: scale, enabled: shadowsEnabled)
        context.setFillColor(color(annotation.color))
        context.fillEllipse(in: rect)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        context.setLineWidth(max(1.5, diameter * 0.05))
        context.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))
        context.restoreGState()

        let label = "\(annotation.number)"
        let font = NSFont.systemFont(ofSize: diameter * 0.52, weight: .bold)
        let textColor: NSColor = annotation.color == .white
            ? NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 1) : .white
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let size = label.size(withAttributes: attributes)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        label.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                   withAttributes: attributes)
        NSGraphicsContext.current = previous
    }

    private static func drawSticker(_ annotation: ScreenshotSupport.Annotation,
                                    in context: CGContext,
                                    scale: CGFloat,
                                    shadowsEnabled: Bool) {
        let sticker = ScreenshotSupport.StickerID.sanitized(annotation.text)
        let fontSize = max(10 * scale, min(annotation.rect.width, annotation.rect.height) * 0.82)
        let font = NSFont(name: "Apple Color Emoji", size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if shadowsEnabled {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
            shadow.shadowBlurRadius = 3 * scale
            shadow.shadowOffset = NSSize(width: 0, height: -1 * scale)
            attributes[.shadow] = shadow
        }
        let glyph = sticker.glyph
        let size = glyph.size(withAttributes: attributes)
        let origin = CGPoint(x: annotation.rect.midX - size.width / 2,
                             y: annotation.rect.midY - size.height / 2)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        glyph.draw(at: origin, withAttributes: attributes)
        NSGraphicsContext.current = previous
    }

    // MARK: - Blur areas

    struct BlurSources {
        var mosaics: [Int: CGImage] = [:]
        var softBlurs: [Int: CGImage] = [:]
        var image: CGImage?
        var imageOrigin = CGPoint.zero
        var eraseCache: EraseCache?
        var textRuns: [CGRect]?
        var imageLayerCache: ImageLayerCache?

        static let none = BlurSources()
    }

    private static func drawBlurArea(_ annotation: ScreenshotSupport.Annotation,
                                     in context: CGContext,
                                     sources: BlurSources,
                                     imageSize: CGSize) {
        let rect = annotation.rect.standardized
        guard rect.width > 0, rect.height > 0 else { return }
        let runs = annotation.blurTextOnly
            ? ScreenshotSupport.blurTextRuns(in: rect, from: sources.textRuns)
            : [rect]
        guard !runs.isEmpty else { return }
        switch annotation.blurStyle {
        case .pixelate:
            guard let mosaic = sources.mosaics[annotation.blurLevel] else { return }
            drawSample(mosaic, in: context, imageSize: imageSize,
                       clippedTo: runs.map { $0.intersection(rect) }, interpolation: .none)
        case .blur:
            guard let blurred = sources.softBlurs[annotation.blurLevel] else { return }
            drawSample(blurred, in: context, imageSize: imageSize,
                       clippedTo: runs.map { $0.intersection(rect) }, interpolation: .high)
        case .erase:
            guard let image = sources.image else { return }
            let origin = sources.imageOrigin
            let local = { (canvas: CGRect) in canvas.offsetBy(dx: -origin.x, dy: -origin.y) }
            let text = (annotation.blurTextOnly ? (sources.textRuns ?? []) : []).map(local)
            let bounds = CGRect(origin: .zero, size: imageSize)
            for run in runs {
                guard let patch = sources.eraseCache?.patch(for: local(run), in: image, skipping: text)
                        ?? erasePatch(for: local(run), in: image, skipping: text) else { continue }
                let target = patch.rect.offsetBy(dx: origin.x, dy: origin.y)
                context.saveGState()
                context.clip(to: run.intersection(rect).intersection(bounds))
                context.setBlendMode(.copy)
                context.translateBy(x: 0, y: target.minY + target.maxY)
                context.scaleBy(x: 1, y: -1)
                context.interpolationQuality = .high
                context.draw(patch.image, in: target)
                context.restoreGState()
            }
        }
    }

    private static func drawSample(_ sample: CGImage,
                                   in context: CGContext,
                                   imageSize: CGSize,
                                   clippedTo regions: [CGRect],
                                   interpolation: CGInterpolationQuality) {
        context.saveGState()
        context.clip(to: CGRect(origin: .zero, size: imageSize))
        context.clip(to: regions)
        context.setBlendMode(.copy)
        context.translateBy(x: 0, y: imageSize.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = interpolation
        context.draw(sample, in: CGRect(origin: .zero, size: imageSize))
        context.restoreGState()
    }

    private static func applyShadow(_ context: CGContext,
                                    scale: CGFloat,
                                    enabled: Bool) {
        guard enabled else { return }
        context.setShadow(offset: CGSize(width: 0, height: -1 * scale),
                          blur: 3 * scale,
                          color: CGColor(gray: 0, alpha: 0.38))
    }

    // MARK: - Watermark

    static func drawWatermark(_ style: ScreenshotSupport.WatermarkStyle,
                              image: CGImage?,
                              in context: CGContext,
                              imageSize: CGSize,
                              scale: CGFloat,
                              shadowsEnabled: Bool,
                              cornerRadius: CGFloat = 0) {
        let style = style.sanitized()
        let contentSize: CGSize
        let draw: (CGRect) -> Void
        switch style.kind {
        case .none:
            return
        case .text:
            let font = NSFont.systemFont(
                ofSize: ScreenshotSupport.watermarkFontSize(for: imageSize,
                                                            factor: CGFloat(style.size)),
                weight: .semibold)
            let color = ScreenshotSupport.ColorID(rawValue: style.color) ?? .white
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: nsColor(color),
            ]
            let measured = style.text.size(withAttributes: attributes)
            contentSize = CGSize(width: ceil(measured.width), height: ceil(measured.height))
            draw = { rect in
                let previous = NSGraphicsContext.current
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
                style.text.draw(at: rect.origin, withAttributes: attributes)
                NSGraphicsContext.current = previous
            }
        case .image:
            guard let image, image.width > 0, image.height > 0 else { return }
            let width = ScreenshotSupport.watermarkImageWidth(for: imageSize,
                                                              factor: CGFloat(style.size))
            contentSize = CGSize(width: width,
                                 height: width * CGFloat(image.height) / CGFloat(image.width))
            draw = { rect in
                context.scaleBy(x: 1, y: -1)
                context.interpolationQuality = .high
                context.draw(image, in: rect)
            }
        }
        guard let placement = ScreenshotSupport.watermarkPlacement(contentSize: contentSize,
                                                                   rotation: style.rotation,
                                                                   anchor: style.anchor,
                                                                   in: imageSize,
                                                                   cornerRadius: cornerRadius)
        else { return }

        context.saveGState()
        applyShadow(context, scale: scale, enabled: shadowsEnabled)
        context.setAlpha(CGFloat(style.opacity))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.translateBy(x: placement.center.x, y: placement.center.y)
        context.rotate(by: -CGFloat(style.rotation) * .pi / 180)
        context.scaleBy(x: placement.fit, y: placement.fit)
        draw(CGRect(x: -contentSize.width / 2, y: -contentSize.height / 2,
                    width: contentSize.width, height: contentSize.height))
        context.endTransparencyLayer()
        context.restoreGState()
    }

    // MARK: - Blur samples

    static func pixelatedImage(from image: CGImage,
                               level: Int = ScreenshotSupport.BlurStrength.defaultLevel,
                               referenceSize: CGSize? = nil) -> CGImage? {
        let block = ScreenshotSupport.pixelBlockSize(
            for: referenceSize ?? CGSize(width: image.width, height: image.height), level: level)
        let smallWidth = max(1, image.width / block)
        let smallHeight = max(1, image.height / block)
        guard let small = CGContext(data: nil,
                                    width: smallWidth,
                                    height: smallHeight,
                                    bitsPerComponent: 8,
                                    bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        small.interpolationQuality = .medium
        small.draw(image, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))
        scrambleSamples(in: small)
        return small.makeImage()
    }

    static func softBlurredImage(from image: CGImage,
                                 level: Int = ScreenshotSupport.BlurStrength.defaultLevel,
                                 referenceSize: CGSize? = nil) -> CGImage? {
        let block = ScreenshotSupport.pixelBlockSize(
            for: referenceSize ?? CGSize(width: image.width, height: image.height), level: level)
        let step = max(1, block / 4)
        let smallWidth = max(1, image.width / step)
        let smallHeight = max(1, image.height / step)
        guard let small = CGContext(data: nil,
                                    width: smallWidth,
                                    height: smallHeight,
                                    bitsPerComponent: 8,
                                    bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        small.interpolationQuality = .medium
        small.draw(image, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))
        scrambleSamples(in: small)
        guard let sampled = small.makeImage() else { return nil }
        let input = CIImage(cgImage: sampled)
        let radius = 0.8 * Double(block) / Double(step)
        let blurred = input.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: input.extent)
        return blurContext.createCGImage(blurred, from: input.extent)
    }

    private static func scrambleSamples(in context: CGContext) {
        guard let data = context.data else { return }
        let bytes = data.bindMemory(to: UInt8.self,
                                    capacity: context.bytesPerRow * context.height)
        var randomRow = [UInt8](repeating: 0, count: context.width)
        for row in 0..<context.height {
            arc4random_buf(&randomRow, randomRow.count)
            for column in 0..<context.width {
                let offset = row * context.bytesPerRow + column * 4
                let noise = Int(randomRow[column] % 19) - 9
                for channel in 0..<3 {
                    let value = Int(bytes[offset + channel]) + noise
                    bytes[offset + channel] = UInt8(max(0, min(255, value)))
                }
            }
        }
    }

    // MARK: - Erasing

    final class EraseCache {
        private struct Key: Hashable {
            let x, y, width, height: Int
            let skipsText: Bool
        }

        private struct Entry {
            let image: CGImage
            let rect: CGRect
            var pass: Int
        }

        private var image: CGImage?
        private var textRuns: [CGRect]?
        private var patches: [Key: Entry] = [:]
        private var pass = 0

        func beginPass(image: CGImage?, textRuns: [CGRect]?) {
            if self.image !== image || self.textRuns != textRuns {
                self.image = image
                self.textRuns = textRuns
                patches.removeAll()
            } else if patches.count > 256 {
                patches = patches.filter { $0.value.pass == pass }
            }
            pass += 1
        }

        func patch(for region: CGRect, in image: CGImage,
                   skipping text: [CGRect] = []) -> (image: CGImage, rect: CGRect)? {
            if self.image !== image {
                self.image = image
                patches.removeAll()
            }
            let area = region.integral
            let key = Key(x: Int(area.minX), y: Int(area.minY),
                          width: Int(area.width), height: Int(area.height),
                          skipsText: !text.isEmpty)
            if let entry = patches[key] {
                patches[key]?.pass = pass
                return (entry.image, entry.rect)
            }
            guard let patch = erasePatch(for: region, in: image, skipping: text) else { return nil }
            patches[key] = Entry(image: patch.image, rect: patch.rect, pass: pass)
            return patch
        }
    }

    static func erasePatch(for region: CGRect, in image: CGImage,
                           skipping text: [CGRect] = []) -> (image: CGImage, rect: CGRect)? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let area = region.integral.intersection(bounds)
        guard !area.isNull, area.width >= 1, area.height >= 1 else { return nil }
        let band = CGFloat(max(2, min(8, Int((min(area.width, area.height) * 0.12).rounded()))))
        let space = eraseColorSpace(for: image)

        var sides: [EraseSide.Edge: EraseSide] = [:]
        for (outside, skipped) in [(true, text), (true, []), (false, [])] where sides.isEmpty {
            for edge in EraseSide.Edge.allCases {
                sides[edge] = EraseSide(edge: edge, area: area, band: band, outside: outside,
                                        skipping: skipped, image: image, space: space)
            }
        }
        guard !sides.isEmpty else { return nil }

        let cell = max(4, max(area.width, area.height) / 128)
        let columns = Int((area.width / cell).rounded(.up)) + 1
        let rows = Int((area.height / cell).rounded(.up)) + 1
        let width = Float(area.width)
        let height = Float(area.height)
        let xs = (0..<columns).map { Float($0) / Float(columns - 1) * width }
        let ys = (0..<rows).map { Float($0) / Float(rows - 1) * height }
        func weights(_ edge: EraseSide.Edge, _ distances: [Float]) -> [Float] {
            guard let side = sides[edge] else { return [Float](repeating: 0, count: distances.count) }
            return distances.map { 1 / max(0.5, $0 + side.offset) }
        }
        func colors(_ edge: EraseSide.Edge, _ positions: [Float], _ length: Float) -> [Float] {
            sides[edge]?.colors(at: positions, along: length)
                ?? [Float](repeating: 0, count: positions.count * 4)
        }
        let top = colors(.top, xs, width)
        let bottom = colors(.bottom, xs, width)
        let left = colors(.left, ys, height)
        let right = colors(.right, ys, height)
        let topWeights = weights(.top, ys)
        let bottomWeights = weights(.bottom, ys.map { height - $0 })
        let leftWeights = weights(.left, xs)
        let rightWeights = weights(.right, xs.map { width - $0 })

        var bytes = [UInt8](repeating: 0, count: columns * rows * 4)
        for row in 0..<rows {
            for column in 0..<columns {
                let sum = topWeights[row] + bottomWeights[row] + leftWeights[column] + rightWeights[column]
                var color: [Float] = [0, 0, 0, 0]
                for channel in 0..<4 {
                    color[channel] = (topWeights[row] * top[column * 4 + channel]
                        + bottomWeights[row] * bottom[column * 4 + channel]
                        + leftWeights[column] * left[row * 4 + channel]
                        + rightWeights[column] * right[row * 4 + channel]) / sum
                }
                let offset = (row * columns + column) * 4
                let alpha = min(255, max(0, color[3].rounded()))
                bytes[offset + 3] = UInt8(alpha)
                for channel in 0..<3 {
                    bytes[offset + channel] = UInt8(min(alpha, max(0, color[channel].rounded())))
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let patch = CGImage(width: columns, height: rows,
                                  bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: columns * 4,
                                  space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil,
                                  shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        let cellWidth = area.width / CGFloat(columns - 1)
        let cellHeight = area.height / CGFloat(rows - 1)
        return (patch, area.insetBy(dx: -cellWidth / 2, dy: -cellHeight / 2))
    }

    private static func eraseColorSpace(for image: CGImage) -> CGColorSpace {
        if let own = image.colorSpace, own.model == .rgb, own.supportsOutput,
           CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                     space: own, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) != nil {
            return own
        }
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    private struct EraseSide {
        enum Edge: CaseIterable {
            case top, bottom, left, right
        }

        let medians: [Float]
        let count: Int
        let offset: Float

        func colors(at positions: [Float], along length: Float) -> [Float] {
            var colors = [Float](repeating: 0, count: positions.count * 4)
            for (index, position) in positions.enumerated() {
                let place = min(max(position / length * Float(count) - 0.5, 0), Float(count - 1))
                let lower = Int(place)
                let fraction = place - Float(lower)
                let first = lower * 4
                let second = min(lower + 1, count - 1) * 4
                for channel in 0..<4 {
                    colors[index * 4 + channel] = medians[first + channel]
                        + (medians[second + channel] - medians[first + channel]) * fraction
                }
            }
            return colors
        }

        static func segmentCount(along length: CGFloat, band: CGFloat) -> Int {
            max(1, min(48, Int(length / max(12, band * 4))))
        }

        init?(edge: Edge, area: CGRect, band: CGFloat, outside: Bool, skipping text: [CGRect],
              image: CGImage, space: CGColorSpace) {
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let thickness = outside ? band : min(band, area.width, area.height)
            let strip: CGRect
            switch (edge, outside) {
            case (.top, true): strip = CGRect(x: area.minX, y: area.minY - thickness,
                                              width: area.width, height: thickness)
            case (.bottom, true): strip = CGRect(x: area.minX, y: area.maxY,
                                                 width: area.width, height: thickness)
            case (.left, true): strip = CGRect(x: area.minX - thickness, y: area.minY,
                                               width: thickness, height: area.height)
            case (.right, true): strip = CGRect(x: area.maxX, y: area.minY,
                                                width: thickness, height: area.height)
            case (.top, false): strip = CGRect(x: area.minX, y: area.minY,
                                               width: area.width, height: thickness)
            case (.bottom, false): strip = CGRect(x: area.minX, y: area.maxY - thickness,
                                                  width: area.width, height: thickness)
            case (.left, false): strip = CGRect(x: area.minX, y: area.minY,
                                                width: thickness, height: area.height)
            case (.right, false): strip = CGRect(x: area.maxX - thickness, y: area.minY,
                                                 width: thickness, height: area.height)
            }
            let visible = strip.intersection(bounds)
            guard !visible.isNull, visible.width >= 1, visible.height >= 1,
                  let pixels = Self.pixels(of: visible, in: image, space: space)
            else { return nil }
            let alongX = edge == .top || edge == .bottom
            let width = Int(visible.width)
            let length = alongX ? width : Int(visible.height)
            let depth = alongX ? Int(visible.height) : width
            let count = Self.segmentCount(along: CGFloat(length), band: band)
            let skipped = text.filter { $0.intersects(visible) }
            let limit = 32
            var medians = [Float](repeating: 0, count: count * 4)
            var found = [Bool](repeating: false, count: count)
            var samples = [UInt8](repeating: 0, count: 4 * limit)
            for segment in 0..<count {
                let start = segment * length / count
                let span = max(1, (segment + 1) * length / count - start)
                let attempts = min(limit, span * depth)
                var taken = 0
                var flat = true
                for attempt in 0..<attempts {
                    let along = start + attempt * span / attempts
                    let across = attempt % depth
                    let column = alongX ? along : across
                    let row = alongX ? across : along
                    if !skipped.isEmpty {
                        let point = CGPoint(x: visible.minX + CGFloat(column) + 0.5,
                                            y: visible.minY + CGFloat(row) + 0.5)
                        if skipped.contains(where: { $0.contains(point) }) { continue }
                    }
                    let pixel = (row * width + column) * 4
                    for channel in 0..<4 {
                        let value = pixels[pixel + channel]
                        samples[channel * limit + taken] = value
                        if value != samples[channel * limit] { flat = false }
                    }
                    taken += 1
                }
                guard taken > 0 else { continue }
                found[segment] = true
                for channel in 0..<4 {
                    let first = channel * limit
                    if flat {
                        medians[segment * 4 + channel] = Float(samples[first])
                    } else {
                        let sorted = samples[first..<(first + taken)].sorted()
                        medians[segment * 4 + channel] = Float(sorted[taken / 2])
                    }
                }
            }
            guard found.contains(true) else { return nil }
            for segment in 0..<count where !found[segment] {
                let nearest = (0..<count).filter { found[$0] }
                    .min { abs($0 - segment) < abs($1 - segment) } ?? segment
                for channel in 0..<4 {
                    medians[segment * 4 + channel] = medians[nearest * 4 + channel]
                }
            }
            self.medians = medians
            self.count = count
            offset = outside ? Float(depth) / 2 : 0
        }

        private static func pixels(of rect: CGRect, in image: CGImage, space: CGColorSpace) -> [UInt8]? {
            guard let cropped = image.cropping(to: rect) else { return nil }
            let width = Int(rect.width)
            let height = Int(rect.height)
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            return drawn ? bytes : nil
        }
    }

    // MARK: - Export

    enum BackdropFill {
        case none
        case colors([(red: Double, green: Double, blue: Double)])
        case image(CGImage)
    }

    struct Export {
        let image: CGImage
        let scale: CGFloat
    }

    static func renderExport(baseImage: CGImage,
                             annotations: [ScreenshotSupport.Annotation],
                             blurSources: BlurSources,
                             scale: CGFloat,
                             annotationShadowsEnabled: Bool,
                             watermark: ScreenshotSupport.WatermarkStyle,
                             watermarkImage: CGImage?,
                             style: ScreenshotSupport.BackdropStyle,
                             fill: BackdropFill,
                             downscaleTo1x: Bool,
                             spotlightDimStrength: CGFloat = 0.5) -> Export? {
        let imageSize = CGSize(width: baseImage.width, height: baseImage.height)
        let corner = ScreenshotSupport.cardCornerRadius(for: imageSize,
                                                        factor: style.cornerRadius)
        guard let flattened = renderFlattened(baseImage: baseImage,
                                              annotations: annotations,
                                              blurSources: blurSources,
                                              scale: scale,
                                              annotationShadowsEnabled: annotationShadowsEnabled,
                                              watermark: watermark,
                                              watermarkImage: watermarkImage,
                                              cornerRadius: corner,
                                              spotlightDimStrength: spotlightDimStrength)
        else { return nil }

        var result = flattened
        if case .none = fill {
            if corner > 0, let rounded = roundedAlpha(flattened, corner: corner) {
                result = rounded
            }
        } else if let composed = renderBackdrop(fill,
                                                behind: flattened,
                                                imageSize: imageSize,
                                                paddingFactor: CGFloat(style.padding),
                                                corner: corner,
                                                outlineCorner: max(corner, ScreenshotSupport
                                                    .transparentCornerRadius(of: baseImage)),
                                                blurFactor: CGFloat(style.blur),
                                                scale: scale) {
            result = composed
        }
        if downscaleTo1x, scale > 1 {
            let target = ScreenshotSupport.downscaledSize(
                pixelSize: CGSize(width: result.width, height: result.height), scale: scale)
            if let smaller = resized(result, to: target) {
                return Export(image: smaller, scale: 1)
            }
        }
        return Export(image: result, scale: scale)
    }

    private static func roundedAlpha(_ image: CGImage, corner: CGFloat) -> CGImage? {
        guard let context = CGContext(data: nil,
                                      width: image.width,
                                      height: image.height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.addPath(CGPath(roundedRect: rect,
                               cornerWidth: corner, cornerHeight: corner, transform: nil))
        context.clip()
        context.draw(image, in: rect)
        return context.makeImage()
    }

    private static func renderFlattened(baseImage: CGImage,
                                        annotations: [ScreenshotSupport.Annotation],
                                        blurSources: BlurSources,
                                        scale: CGFloat,
                                        annotationShadowsEnabled: Bool,
                                        watermark: ScreenshotSupport.WatermarkStyle,
                                        watermarkImage: CGImage?,
                                        cornerRadius: CGFloat,
                                        spotlightDimStrength: CGFloat) -> CGImage? {
        let width = baseImage.width
        let height = baseImage.height
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(baseImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        drawAnnotations(annotations,
                        in: context,
                        blurSources: blurSources,
                        imageSize: CGSize(width: width, height: height),
                        scale: scale,
                        annotationShadowsEnabled: annotationShadowsEnabled,
                        spotlightDimStrength: spotlightDimStrength)
        drawWatermark(watermark,
                      image: watermarkImage,
                      in: context,
                      imageSize: CGSize(width: width, height: height),
                      scale: scale,
                      shadowsEnabled: annotationShadowsEnabled,
                      cornerRadius: cornerRadius)
        return context.makeImage()
    }

    private static func renderBackdrop(_ fill: BackdropFill,
                                       behind image: CGImage,
                                       imageSize: CGSize,
                                       paddingFactor: CGFloat,
                                       corner: CGFloat,
                                       outlineCorner: CGFloat,
                                       blurFactor: CGFloat,
                                       scale: CGFloat) -> CGImage? {
        let padding = ScreenshotSupport.backdropPadding(for: imageSize, factor: paddingFactor)
        let width = Int(imageSize.width + padding * 2)
        let height = Int(imageSize.height + padding * 2)
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        drawFill(fill, in: context, size: CGSize(width: width, height: height))
        if blurFactor > 0, let background = context.makeImage() {
            let blurred = blurredBackdrop(background, factor: blurFactor)
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(blurred, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        let imageRect = CGRect(x: padding, y: padding,
                               width: imageSize.width, height: imageSize.height)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -6 * scale),
                          blur: 22 * scale,
                          color: CGColor(gray: 0, alpha: 0.4))
        let outline = CGPath(roundedRect: imageRect,
                             cornerWidth: outlineCorner, cornerHeight: outlineCorner, transform: nil)
        let path = CGPath(roundedRect: imageRect,
                          cornerWidth: corner, cornerHeight: corner, transform: nil)
        context.addRect(CGRect(x: 0, y: 0, width: width, height: height))
        context.addPath(outline)
        context.clip(using: .evenOdd)
        context.addPath(outline)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.draw(image, in: imageRect)
        context.restoreGState()
        return context.makeImage()
    }

    static func blurredBackdrop(_ image: CGImage, factor: CGFloat) -> CGImage {
        let radius = ScreenshotSupport.backdropBlurRadius(
            for: CGSize(width: image.width, height: image.height),
            factor: factor)
        guard radius > 0 else { return image }
        let input = CIImage(cgImage: image)
        let filtered = input.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: input.extent)
        return blurContext.createCGImage(filtered, from: input.extent) ?? image
    }

    private static func drawFill(_ fill: BackdropFill, in context: CGContext, size: CGSize) {
        switch fill {
        case .none:
            break
        case .colors(let components):
            if components.count == 1, let single = components.first {
                context.setFillColor(CGColor(srgbRed: single.red, green: single.green,
                                             blue: single.blue, alpha: 1))
                context.fill(CGRect(origin: .zero, size: size))
            } else if components.count >= 2 {
                let colors = components.map {
                    CGColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1)
                } as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                             colors: colors,
                                             locations: [0, 1]) {
                    context.drawLinearGradient(gradient,
                                               start: CGPoint(x: 0, y: size.height),
                                               end: CGPoint(x: size.width, y: 0),
                                               options: [])
                }
            }
        case .image(let backdropImage):
            let imageWidth = CGFloat(backdropImage.width)
            let imageHeight = CGFloat(backdropImage.height)
            guard imageWidth > 0, imageHeight > 0 else { break }
            let scale = max(size.width / imageWidth, size.height / imageHeight)
            let drawSize = CGSize(width: imageWidth * scale, height: imageHeight * scale)
            let origin = CGPoint(x: (size.width - drawSize.width) / 2,
                                 y: (size.height - drawSize.height) / 2)
            context.saveGState()
            context.clip(to: CGRect(origin: .zero, size: size))
            context.interpolationQuality = .high
            context.draw(backdropImage, in: CGRect(origin: origin, size: drawSize))
            context.restoreGState()
        }
    }

    private static func resized(_ image: CGImage, to size: CGSize) -> CGImage? {
        guard let context = CGContext(data: nil,
                                      width: Int(size.width),
                                      height: Int(size.height),
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    // MARK: - Encoding

    static func pngData(from image: CGImage, scale: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        let properties = [
            kCGImagePropertyDPIWidth: Double(scale) * 72,
            kCGImagePropertyDPIHeight: Double(scale) * 72,
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func tiffData(from image: CGImage, scale: CGFloat) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        bitmap.size = NSSize(width: CGFloat(image.width) / scale,
                             height: CGFloat(image.height) / scale)
        return bitmap.tiffRepresentation
    }
}
