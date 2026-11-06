// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

struct RecorderBlurRegion: Codable, Equatable, Identifiable, RecorderTimelineBlock {
    var id: UUID
    var start: Double
    var end: Double
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var strength: Int

    init(id: UUID = UUID(),
         start: Double,
         end: Double,
         rect: CGRect = defaultRect,
         strength: Int = ScreenshotSupport.BlurStrength.defaultLevel) {
        self.id = id
        self.start = start
        self.end = end
        x = Double(rect.origin.x)
        y = Double(rect.origin.y)
        width = Double(rect.width)
        height = Double(rect.height)
        self.strength = strength
    }

    private enum CodingKeys: String, CodingKey {
        case id, start, end, x, y, width, height, strength
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        start = try container.decode(Double.self, forKey: .start)
        end = try container.decode(Double.self, forKey: .end)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        strength = try container.decodeIfPresent(Int.self, forKey: .strength)
            ?? ScreenshotSupport.BlurStrength.defaultLevel
    }

    var duration: Double { max(0, end - start) }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    static let defaultRect = CGRect(x: 0.35, y: 0.4, width: 0.3, height: 0.2)
    static let minimumSide: Double = 0.01

    func covers(_ time: Double) -> Bool {
        time >= start && time <= end
    }

    func pixelRect(in size: CGSize) -> CGRect {
        CGRect(x: CGFloat(x) * size.width,
               y: (1 - CGFloat(y + height)) * size.height,
               width: CGFloat(width) * size.width,
               height: CGFloat(height) * size.height).integral
    }

    static func normalizedRect(from first: CGPoint, to second: CGPoint) -> CGRect? {
        func clamped(_ value: CGFloat) -> CGFloat { min(1, max(0, value)) }
        let minX = clamped(min(first.x, second.x))
        let maxX = clamped(max(first.x, second.x))
        let minY = clamped(min(first.y, second.y))
        let maxY = clamped(max(first.y, second.y))
        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard rect.width >= minimumSide, rect.height >= minimumSide else { return nil }
        return rect
    }

    func sanitized(duration recordingDuration: Double) -> RecorderBlurRegion? {
        guard recordingDuration > 0, start.isFinite, end.isFinite,
              x.isFinite, y.isFinite, width.isFinite, height.isFinite
        else { return nil }
        var copy = self
        copy.start = max(0, min(start, recordingDuration))
        copy.end = max(0, min(end, recordingDuration))
        guard copy.duration >= 0.2 else { return nil }
        guard let rect = Self.normalizedRect(from: rect.origin,
                                             to: CGPoint(x: rect.maxX, y: rect.maxY))
        else { return nil }
        copy.x = Double(rect.origin.x)
        copy.y = Double(rect.origin.y)
        copy.width = Double(rect.width)
        copy.height = Double(rect.height)
        copy.strength = ScreenshotSupport.BlurStrength.sanitized(strength)
        return copy
    }

    static func normalized(_ regions: [RecorderBlurRegion],
                           duration: Double) -> [RecorderBlurRegion] {
        regions.compactMap { $0.sanitized(duration: duration) }
            .sorted { $0.start < $1.start }
    }
}
