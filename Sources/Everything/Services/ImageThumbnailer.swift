// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO

enum ImageThumbnailer {
    static let defaultPointSize: CGFloat = 20

    static func thumbnail(for url: URL, pointSize: CGFloat = defaultPointSize) -> NSImage? {
        thumbnail(for: url, pointSize: pointSize, scale: backingScale)
    }

    static func thumbnail(for url: URL, pointSize: CGFloat = defaultPointSize) async -> NSImage? {
        let scale = await MainActor.run { backingScale }
        return thumbnail(for: url, pointSize: pointSize, scale: scale)
    }

    private static func thumbnail(for url: URL, pointSize: CGFloat, scale: CGFloat) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        return thumbnail(source: source, pointSize: pointSize, scale: scale)
    }

    static func thumbnail(data: Data, pointSize: CGFloat, scale: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData,
                                                       [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return thumbnail(source: source, pointSize: pointSize, scale: scale)
    }

    private static func thumbnail(source: CGImageSource, pointSize: CGFloat, scale: CGFloat) -> NSImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize(for: pointSize, scale: scale)
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / scale,
                                                   height: CGFloat(image.height) / scale))
    }

    static func thumbnail(for image: NSImage, pointSize: CGFloat = defaultPointSize) -> NSImage? {
        let pixels = pixelSize(for: pointSize, scale: backingScale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pixels,
                                         pixelsHigh: pixels,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else {
            return nil
        }

        let logicalSize = NSSize(width: pointSize, height: pointSize)
        rep.size = logicalSize
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: logicalSize).fill()
        image.draw(in: NSRect(origin: .zero, size: logicalSize),
                   from: .zero,
                   operation: .sourceOver,
                   fraction: 1,
                   respectFlipped: false,
                   hints: nil)
        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: logicalSize)
        result.addRepresentation(rep)
        return result
    }

    static func estimatedBitmapCost(pointSize: CGFloat = defaultPointSize) -> Int {
        let pixels = pixelSize(for: pointSize, scale: backingScale)
        return pixels * pixels * 4
    }

    static var backingScale: CGFloat {
        max(1, NSScreen.main?.backingScaleFactor ?? 2)
    }

    private static func pixelSize(for pointSize: CGFloat, scale: CGFloat) -> Int {
        max(16, Int((pointSize * scale).rounded(.up)))
    }
}
