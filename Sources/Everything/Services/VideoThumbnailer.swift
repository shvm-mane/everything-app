// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import AppKit

enum VideoThumbnailer {
    static func thumbnail(for url: URL, pointSize: CGFloat = ImageThumbnailer.defaultPointSize) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration),
              duration.isValid, duration.seconds > 0 else {
            return await frame(from: asset, at: .zero, pointSize: pointSize)
        }
        let offsetSeconds = min(1.0, duration.seconds * 0.1)
        let time = CMTime(seconds: offsetSeconds, preferredTimescale: 600)
        return await frame(from: asset, at: time, pointSize: pointSize)
    }

    private static func frame(from asset: AVURLAsset, at time: CMTime, pointSize: CGFloat) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let scale = await MainActor.run { ImageThumbnailer.backingScale }
        let maxPixels = pointSize * scale
        generator.maximumSize = CGSize(width: maxPixels, height: maxPixels)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        guard let cgImage = try? await generator.image(at: time).image else { return nil }
        let size = NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
        return NSImage(cgImage: cgImage, size: size)
    }
}
