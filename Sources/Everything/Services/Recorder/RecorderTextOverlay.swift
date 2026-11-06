// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

struct RecorderTextOverlay: Codable, Equatable, Identifiable, RecorderTimelineBlock {
    enum Anchor: String, Codable, CaseIterable {
        case topLeading, top, topTrailing
        case leading, center, trailing
        case bottomLeading, bottom, bottomTrailing

        var unitPoint: CGPoint {
            switch self {
            case .topLeading: return CGPoint(x: 0, y: 0)
            case .top: return CGPoint(x: 0.5, y: 0)
            case .topTrailing: return CGPoint(x: 1, y: 0)
            case .leading: return CGPoint(x: 0, y: 0.5)
            case .center: return CGPoint(x: 0.5, y: 0.5)
            case .trailing: return CGPoint(x: 1, y: 0.5)
            case .bottomLeading: return CGPoint(x: 0, y: 1)
            case .bottom: return CGPoint(x: 0.5, y: 1)
            case .bottomTrailing: return CGPoint(x: 1, y: 1)
            }
        }

        func origin(of contentSize: CGSize, in canvas: CGSize) -> CGPoint {
            let margin = min(canvas.width, canvas.height) * 0.05
            let point = unitPoint
            let x = margin + (canvas.width - contentSize.width - margin * 2) * point.x
            let topY = margin + (canvas.height - contentSize.height - margin * 2) * point.y
            return CGPoint(x: x, y: canvas.height - topY - contentSize.height)
        }
    }

    enum Palette: String, Codable, CaseIterable {
        case white, black, accent, yellow, red, green

        var components: (red: Double, green: Double, blue: Double) {
            switch self {
            case .white: return (1, 1, 1)
            case .black: return (0.06, 0.06, 0.07)
            case .accent: return (0.04, 0.52, 1.00)
            case .yellow: return (1.00, 0.80, 0.00)
            case .red: return (0.96, 0.26, 0.21)
            case .green: return (0.20, 0.78, 0.35)
            }
        }
    }

    var id: UUID
    var text: String
    var start: Double
    var end: Double
    var anchor: Anchor
    var size: Double
    var palette: Palette

    init(id: UUID = UUID(),
         text: String,
         start: Double,
         end: Double,
         anchor: Anchor = .bottom,
         size: Double = 0.06,
         palette: Palette = .white) {
        self.id = id
        self.text = text
        self.start = start
        self.end = end
        self.anchor = anchor
        self.size = size
        self.palette = palette
    }

    var duration: Double { max(0, end - start) }

    static let sizeRange: ClosedRange<Double> = 0.03...0.16
    static let defaultLength: Double = 3.0
    static let fade: Double = 0.25

    func opacity(at time: Double) -> Double {
        RecorderMotion.overlayOpacity(at: time, start: start, end: end, fade: Self.fade)
    }

    func sanitized(duration recordingDuration: Double) -> RecorderTextOverlay? {
        guard recordingDuration > 0, start.isFinite, end.isFinite else { return nil }
        var copy = self
        copy.text = String(text.prefix(200))
        copy.start = max(0, min(start, recordingDuration))
        copy.end = max(0, min(end, recordingDuration))
        copy.size = size.isFinite
            ? min(Self.sizeRange.upperBound, max(Self.sizeRange.lowerBound, size))
            : 0.06
        guard copy.duration >= 0.2 else { return nil }
        return copy
    }

    static func normalized(_ overlays: [RecorderTextOverlay],
                           duration: Double) -> [RecorderTextOverlay] {
        overlays.compactMap { $0.sanitized(duration: duration) }
            .sorted { $0.start < $1.start }
    }
}
