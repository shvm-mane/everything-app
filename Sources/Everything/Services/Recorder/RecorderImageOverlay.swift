// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

struct RecorderImageOverlay: Codable, Equatable, Identifiable, RecorderTimelineBlock {
    typealias Anchor = RecorderTextOverlay.Anchor

    var id: UUID
    var path: String
    var start: Double
    var end: Double
    var anchor: Anchor
    var size: Double
    var opacity: Double

    init(id: UUID = UUID(),
         path: String,
         start: Double,
         end: Double,
         anchor: Anchor = .bottomTrailing,
         size: Double = RecorderImageOverlay.defaultSize,
         opacity: Double = 1) {
        self.id = id
        self.path = path
        self.start = start
        self.end = end
        self.anchor = anchor
        self.size = size
        self.opacity = opacity
    }

    var duration: Double { max(0, end - start) }

    static let sizeRange: ClosedRange<Double> = 0.04...0.6
    static let opacityRange: ClosedRange<Double> = 0.05...1
    static let defaultSize: Double = 0.18
    static let fade: Double = 0.25

    func opacity(at time: Double) -> Double {
        opacity * RecorderMotion.overlayOpacity(at: time,
                                                start: start,
                                                end: end,
                                                fade: Self.fade)
    }

    func sanitized(duration recordingDuration: Double) -> RecorderImageOverlay? {
        guard recordingDuration > 0, start.isFinite, end.isFinite else { return nil }
        var copy = self
        guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
        copy.start = max(0, min(start, recordingDuration))
        copy.end = max(0, min(end, recordingDuration))
        copy.size = size.isFinite
            ? min(Self.sizeRange.upperBound, max(Self.sizeRange.lowerBound, size))
            : Self.defaultSize
        copy.opacity = opacity.isFinite
            ? min(Self.opacityRange.upperBound, max(Self.opacityRange.lowerBound, opacity))
            : 1
        guard copy.duration >= 0.2 else { return nil }
        return copy
    }

    static func normalized(_ overlays: [RecorderImageOverlay],
                           duration: Double) -> [RecorderImageOverlay] {
        overlays.compactMap { $0.sanitized(duration: duration) }
            .sorted { $0.start < $1.start }
    }

    static func drawnSize(source: CGSize, size: Double, canvas: CGSize) -> CGSize? {
        guard source.width.isFinite, source.height.isFinite,
              canvas.width.isFinite, canvas.height.isFinite, size.isFinite,
              source.width > 0, source.height > 0,
              canvas.width > 0, canvas.height > 0, size > 0 else { return nil }
        let margin = min(canvas.width, canvas.height) * 0.05
        let available = CGSize(width: canvas.width - 2 * margin,
                               height: canvas.height - 2 * margin)
        var width = canvas.width * CGFloat(size)
        var height = width * source.height / source.width
        let scale = min(1, min(available.width / width, available.height / height))
        width *= scale
        height *= scale
        let drawn = CGSize(width: width.rounded(), height: height.rounded())
        guard drawn.width >= 1, drawn.height >= 1 else { return nil }
        return drawn
    }
}
