// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum RecorderImageRenderer {
    private static let pixelBudget = 24_000_000

    private static var cache: [String: CGImage] = [:]
    private static var cachedPixels = 0
    private static let lock = NSLock()

    static func image(for overlay: RecorderImageOverlay, canvas: CGSize) -> CGImage? {
        let url = URL(fileURLWithPath: overlay.path)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey,
                                                             .fileSizeKey,
                                                             .contentModificationDateKey]),
              values.isRegularFile == true,
              let source = MediaSupport.imageDisplaySize(at: url),
              let drawn = RecorderImageOverlay.drawnSize(source: source,
                                                         size: overlay.size,
                                                         canvas: canvas),
              MediaSupport.imageRenderSizeIsSafe(drawn)
        else { return nil }

        let stamp = "\(values.fileSize ?? 0)|"
            + "\(values.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0)"
        let key = "\(overlay.path)|\(Int(drawn.width))x\(Int(drawn.height))|\(stamp)"
        lock.lock()
        if let hit = cache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        guard let image = render(overlay.path, drawn: drawn) else { return nil }
        lock.lock()
        if cachedPixels > pixelBudget {
            cache.removeAll()
            cachedPixels = 0
        }
        cache[key] = image
        cachedPixels += image.width * image.height
        lock.unlock()
        return image
    }

    private static func render(_ path: String, drawn: CGSize) -> CGImage? {
        let width = Int(drawn.width)
        let height = Int(drawn.height)
        guard let picture = MediaSupport.imageThumbnail(at: URL(fileURLWithPath: path),
                                                        maxPixel: max(width, height)),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(picture, in: CGRect(origin: .zero, size: drawn))
        return context.makeImage()
    }
}
