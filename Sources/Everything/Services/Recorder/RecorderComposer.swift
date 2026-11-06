// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import AppKit
import CoreImage

final class RecorderComposer {
    // MARK: - Plan

    struct Plan {
        let sourceSize: CGSize
        let canvasSize: CGSize
        let cardRect: CGRect
        let frameRate: Int
        let positions: [CGPoint]
        let zoom: [Double]
        let travel: [CGPoint]
        let pressScale: [Double]
        let ring: [Double]
        let showsPointer: Bool
        let pointerShapes: [RecorderPointerTrack.CursorShape]
        let pointerShapeIndex: [Int]
        let pointerVisible: [Bool]
        let pointerOpacity: [Double]
        let pointerScale: CGFloat
        let pointerPixelSize: CGFloat
        let showsClickRing: Bool
        let plate: CIImage?
        let mask: CIImage?
        let texts: [RecorderTextOverlay]
        let textOpacity: [[Double]]
        let images: [RecorderImageOverlay]
        let imageSprites: [CGImage?]
        let imageOpacity: [[Double]]
        let blurs: [RecorderBlurRegion]
        let blurCovers: [[Bool]]
    }

    private let plan: Plan
    private let decodedShapes: [CGImage?]
    private let fallbackArrow: CGImage?

    init(plan: Plan) {
        self.plan = plan
        decodedShapes = plan.showsPointer ? plan.pointerShapes.map { $0.image } : []
        fallbackArrow = (plan.showsPointer && plan.pointerShapes.isEmpty)
            ? RecorderCursorSprite.arrow(pixelSize: plan.pointerPixelSize * 3)
            : nil
    }

    var canvasSize: CGSize { plan.canvasSize }

    // MARK: - Rendering

    func render(_ source: CIImage, at seconds: Double) -> CIImage {
        let index = frameIndex(for: seconds)
        var content = source.cropped(to: CGRect(origin: .zero, size: plan.sourceSize))
        content = blurred(content, at: seconds)

        let pointerWasOnScreen = plan.pointerVisible.indices.contains(index)
            ? plan.pointerVisible[index] : true
        let opacity = plan.pointerOpacity.indices.contains(index) ? plan.pointerOpacity[index] : 1
        if plan.showsPointer, pointerWasOnScreen, opacity > 0.01, index < plan.positions.count {
            content = drawPointer(on: content, index: index)
        }
        content = zoomed(content, index: index)
        content = fitted(content)

        if let mask = plan.mask {
            let background = plan.plate ?? CIImage(color: .black)
                .cropped(to: CGRect(origin: .zero, size: plan.canvasSize))
            content = content.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: background,
                kCIInputMaskImageKey: mask,
            ])
        } else if let plate = plan.plate {
            content = content.composited(over: plate)
        }
        content = drawImages(on: content, index: index)
        content = drawTexts(on: content, index: index)
        return content.cropped(to: CGRect(origin: .zero, size: plan.canvasSize))
    }

    private func drawImages(on content: CIImage, index: Int) -> CIImage {
        guard !plan.images.isEmpty else { return content }
        var result = content
        for (order, overlay) in plan.images.enumerated() {
            guard plan.imageOpacity.indices.contains(order),
                  plan.imageOpacity[order].indices.contains(index),
                  plan.imageSprites.indices.contains(order),
                  let sprite = plan.imageSprites[order] else { continue }
            let opacity = plan.imageOpacity[order][index]
            guard opacity > 0.01 else { continue }
            let size = CGSize(width: sprite.width, height: sprite.height)
            let origin = overlay.anchor.origin(of: size, in: plan.canvasSize)
            result = faded(CIImage(cgImage: sprite), opacity: opacity)
                .transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))
                .composited(over: result)
        }
        return result
    }

    private func drawTexts(on content: CIImage, index: Int) -> CIImage {
        guard !plan.texts.isEmpty else { return content }
        var result = content
        for (order, overlay) in plan.texts.enumerated() {
            guard plan.textOpacity.indices.contains(order),
                  plan.textOpacity[order].indices.contains(index) else { continue }
            let opacity = plan.textOpacity[order][index]
            guard opacity > 0.01,
                  let image = RecorderTextRenderer.image(for: overlay,
                                                         canvasHeight: plan.canvasSize.height)
            else { continue }
            let size = CGSize(width: image.width, height: image.height)
            let origin = overlay.anchor.origin(of: size, in: plan.canvasSize)
            result = faded(CIImage(cgImage: image), opacity: opacity)
                .transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))
                .composited(over: result)
        }
        return result
    }

    private func blurred(_ content: CIImage, at seconds: Double) -> CIImage {
        guard !plan.blurs.isEmpty else { return content }
        let position = max(0, seconds) * Double(plan.frameRate)
        let last = max(0, plan.positions.count - 1)
        let lower = min(last, Int(position.rounded(.down)))
        let upper = min(last, Int(position.rounded(.up)))
        var result = content
        for (order, region) in plan.blurs.enumerated() {
            guard plan.blurCovers.indices.contains(order),
                  (lower...upper).contains(where: {
                      plan.blurCovers[order].indices.contains($0)
                          && plan.blurCovers[order][$0]
                  }) else { continue }
            let rect = region.pixelRect(in: plan.sourceSize)
            guard rect.width >= 1, rect.height >= 1 else { continue }
            let block = RecorderSupport.blurBlockSize(for: rect.size, strength: region.strength)
            let hidden = content.clampedToExtent()
                .applyingFilter("CIPixellate", parameters: [
                    kCIInputScaleKey: block,
                    kCIInputCenterKey: CIVector(x: rect.minX, y: rect.minY),
                ])
                .applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: block * 0.6,
                ])
                .cropped(to: rect)
            result = hidden.composited(over: result)
        }
        return result
    }

    private func frameIndex(for seconds: Double) -> Int {
        let raw = Int((max(0, seconds) * Double(plan.frameRate)).rounded())
        return min(max(0, raw), max(0, plan.positions.count - 1))
    }

    private func faded(_ image: CIImage, opacity: Double) -> CIImage {
        guard opacity < 0.999 else { return image }
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity)),
        ])
    }

    private func drawPointer(on content: CIImage, index: Int) -> CIImage {
        let uv = plan.positions[index]
        guard uv.x > -0.2, uv.x < 1.2, uv.y > -0.2, uv.y < 1.2 else { return content }
        let press = plan.pressScale.indices.contains(index) ? plan.pressScale[index] : 1
        let x = uv.x * plan.sourceSize.width
        let y = (1 - uv.y) * plan.sourceSize.height

        var result = content
        if plan.showsClickRing, plan.ring.indices.contains(index), plan.ring[index] >= 0 {
            result = drawRing(progress: plan.ring[index],
                              at: CGPoint(x: x, y: y),
                              on: result)
        }

        let shapeIndex = plan.pointerShapeIndex.indices.contains(index)
            ? plan.pointerShapeIndex[index] : 0
        if let sprite = decodedShapes.indices.contains(shapeIndex)
            ? decodedShapes[shapeIndex] : decodedShapes.first ?? nil,
           let shape = plan.pointerShapes.indices.contains(shapeIndex)
            ? plan.pointerShapes[shapeIndex] : plan.pointerShapes.first {
            let drawnWidth = shape.pointSize.width * plan.pointerScale * CGFloat(press)
            let drawnHeight = shape.pointSize.height * plan.pointerScale * CGFloat(press)
            guard drawnWidth > 0, drawnHeight > 0, sprite.width > 0 else { return result }
            let factor = drawnWidth / CGFloat(sprite.width)
            let hotX = shape.hotSpot.x * plan.pointerScale * CGFloat(press)
            let hotY = shape.hotSpot.y * plan.pointerScale * CGFloat(press)
            let opacity = plan.pointerOpacity.indices.contains(index)
                ? plan.pointerOpacity[index] : 1
            return faded(CIImage(cgImage: sprite)
                .transformed(by: CGAffineTransform(scaleX: factor, y: factor)),
                         opacity: opacity)
                .transformed(by: CGAffineTransform(translationX: x - hotX,
                                                   y: y - drawnHeight + hotY))
                .composited(over: result)
        }

        guard let sprite = fallbackArrow, sprite.width > 0 else { return result }
        let drawn = RecorderCursorSprite.fallbackSize.width * plan.pointerScale * CGFloat(press)
        let factor = drawn / CGFloat(sprite.width)
        let height = CGFloat(sprite.height) * factor
        let hot = CGPoint(x: RecorderCursorSprite.fallbackHotSpot.x * plan.pointerScale
                            * CGFloat(press),
                          y: RecorderCursorSprite.fallbackHotSpot.y * plan.pointerScale
                            * CGFloat(press))
        return CIImage(cgImage: sprite)
            .transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            .transformed(by: CGAffineTransform(translationX: x - hot.x, y: y - height + hot.y))
            .composited(over: result)
    }

    private func drawRing(progress: Double, at point: CGPoint, on content: CIImage) -> CIImage {
        let eased = 1 - pow(1 - progress, 3)
        let unit = plan.pointerPixelSize / 34
        let radius = RecorderMotion.ringRadius * unit * eased
        let width = max(0.6, 2.4 * (1 - progress)) * unit
        let alpha = 0.35 * (1 - progress * progress)
        guard radius > 1, alpha > 0.01,
              let ring = RecorderCursorSprite.ring(radius: radius, lineWidth: width, alpha: alpha)
        else { return content }
        let side = CGFloat(ring.width)
        return CIImage(cgImage: ring)
            .transformed(by: CGAffineTransform(translationX: point.x - side / 2,
                                               y: point.y - side / 2))
            .composited(over: content)
    }

    private func zoomed(_ content: CIImage, index: Int) -> CIImage {
        guard plan.zoom.indices.contains(index) else { return content }
        let z = plan.zoom[index]
        guard z > 1.001, plan.travel.indices.contains(index) else { return content }
        let origin = RecorderMotion.viewportOrigin(travel: plan.travel[index], zoom: z)
        let bottom = 1 - origin.y - 1 / z
        let transform = CGAffineTransform(scaleX: CGFloat(z), y: CGFloat(z))
            .concatenating(CGAffineTransform(
                translationX: -origin.x * plan.sourceSize.width * CGFloat(z),
                y: -bottom * plan.sourceSize.height * CGFloat(z)))
        return content.transformed(by: transform)
            .cropped(to: CGRect(origin: .zero, size: plan.sourceSize))
    }

    private func fitted(_ content: CIImage) -> CIImage {
        guard plan.sourceSize.width > 0, plan.sourceSize.height > 0 else { return content }
        let scaleX = plan.cardRect.width / plan.sourceSize.width
        let scaleY = plan.cardRect.height / plan.sourceSize.height
        return content
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(translationX: plan.cardRect.origin.x,
                                               y: plan.cardRect.origin.y))
    }

    // MARK: - Composition

    static func videoComposition(track: AVAssetTrack,
                                 asset: AVAsset,
                                 duration: CMTime,
                                 frameRate: Int,
                                 composer: RecorderComposer?,
                                 sourceSize: CGSize,
                                 outputSize: CGSize,
                                 playbackSpeed: Double = 1) async -> AVMutableVideoComposition? {
        if let composer {
            nonisolated(unsafe) let threadSafeComposer = composer
            let timing = RecorderExportTiming(speed: playbackSpeed)
            let composition = try? await AVMutableVideoComposition.videoComposition(
                with: asset) { request in
                    let rendered = threadSafeComposer.render(
                        request.sourceImage,
                        at: timing.sourceTime(forOutputTime: CMTimeGetSeconds(request.compositionTime)))
                    request.finish(with: rendered, context: nil)
                }
            guard let composition else { return nil }
            composition.frameDuration = CMTime(value: 1,
                                               timescale: CMTimeScale(max(1, frameRate)))
            composition.renderSize = composer.canvasSize
            composition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid
            return composition
        }
        let naturalSize = (try? await track.load(.naturalSize)) ?? sourceSize
        let preferredTransform = (try? await track.load(.preferredTransform)) ?? .identity
        return plainComposition(track: track,
                                naturalSize: naturalSize,
                                preferredTransform: preferredTransform,
                                outputSize: outputSize,
                                frameRate: frameRate,
                                duration: duration)
    }

    static func plainComposition(track: AVAssetTrack,
                                 naturalSize: CGSize,
                                 preferredTransform: CGAffineTransform,
                                 outputSize: CGSize,
                                 frameRate: Int,
                                 duration: CMTime) -> AVMutableVideoComposition {
        let composition = AVMutableVideoComposition()
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, frameRate)))
        composition.renderSize = outputSize
        composition.sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        let geometry = RecorderSupport.videoGeometry(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform)
        if geometry.size.width > 0, geometry.size.height > 0 {
            let scale = CGAffineTransform(scaleX: outputSize.width / geometry.size.width,
                                          y: outputSize.height / geometry.size.height)
            layer.setTransform(geometry.transform.concatenating(scale), at: .zero)
        }
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]
        return composition
    }
}
