// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ScreenshotCanvasExpansionPreview: View {
    let originalSize: CGSize
    let draft: CGRect
    let fill: ScreenshotCanvasSupport.Fill
    let zoom: CGFloat
    let scale: CGFloat
    let cardCornerRadius: CGFloat

    static let checker: CGColor = {
        var callbacks = CGPatternCallbacks(version: 0, drawPattern: { _, context in
            context.setFillColor(CGColor(gray: 0.7, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            context.setFillColor(CGColor(gray: 0.9, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            context.fill(CGRect(x: 4, y: 4, width: 4, height: 4))
        }, releaseInfo: nil)
        let pattern = CGPattern(info: nil, bounds: CGRect(x: 0, y: 0, width: 8, height: 8),
                                matrix: .identity, xStep: 8, yStep: 8,
                                tiling: .constantSpacing, isColored: true, callbacks: &callbacks)!
        return CGColor(patternSpace: CGColorSpace(patternBaseSpace: nil)!,
                       pattern: pattern, components: [1])!
    }()

    var body: some View {
        let displayScale = scale * zoom
        let layout = Layout(draftSize: CGSize(width: draft.width * zoom, height: draft.height * zoom),
                            displayScale: displayScale)
        return Canvas { context, _ in
            context.withCGContext { cg in
                let outer = layout.draft
                let old = CGRect(x: outer.minX - draft.minX * zoom, y: outer.minY - draft.minY * zoom,
                                 width: originalSize.width * zoom, height: originalSize.height * zoom)
                cg.saveGState()
                cg.addRect(outer)
                cg.addPath(Self.cardHole(old, in: outer, cornerRadius: cardCornerRadius))
                cg.clip(using: .evenOdd)
                cg.setFillColor(fill == .transparent ? Self.checker : fill.cgColor)
                cg.fill(outer)
                cg.restoreGState()
                cg.setStrokeColor(CGColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 1))
                cg.setLineWidth(1)
                cg.stroke(outer.insetBy(dx: 0.5, dy: 0.5))
                cg.setStrokeColor(CGColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 0.9))
                cg.setLineWidth(layout.gripLineWidth)
                for dot in layout.grips {
                    cg.setFillColor(CGColor(gray: 1, alpha: 1))
                    cg.fillEllipse(in: dot)
                    cg.strokeEllipse(in: dot)
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .offset(x: -layout.draft.minX, y: -layout.draft.minY)
        .allowsHitTesting(false)
    }

    struct Layout {
        let size: CGSize
        let draft: CGRect
        let grips: [CGRect]
        let gripLineWidth: CGFloat

        init(draftSize: CGSize, displayScale: CGFloat) {
            let radius = 3.5 * displayScale
            let lineWidth = 1.5 * displayScale
            let outset = ((radius + lineWidth) / 8).rounded(.up) * 8
            let frame = CGRect(origin: CGPoint(x: outset, y: outset), size: draftSize)
            size = CGSize(width: draftSize.width + outset * 2, height: draftSize.height + outset * 2)
            draft = frame
            gripLineWidth = lineWidth
            grips = ScreenshotSupport.Handle.allCases.map { handle in
                let point = handle.position(in: frame)
                return CGRect(x: point.x - radius, y: point.y - radius,
                              width: radius * 2, height: radius * 2)
            }
        }
    }

    static func cardHole(_ card: CGRect, in draft: CGRect, cornerRadius: CGFloat) -> CGPath {
        func moved(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) > 0.001 }
        let left = moved(card.minX, draft.minX), top = moved(card.minY, draft.minY)
        let right = moved(card.maxX, draft.maxX), bottom = moved(card.maxY, draft.maxY)
        let radius = cornerRadius > 0 ? cornerRadius + 1 : 0
        func corner(_ meetsMargin: Bool) -> CGFloat { meetsMargin ? radius : 0 }
        let radii = RectangleCornerRadii(topLeading: corner(top || left),
                                         bottomLeading: corner(bottom || left),
                                         bottomTrailing: corner(bottom || right),
                                         topTrailing: corner(top || right))
        return UnevenRoundedRectangle(cornerRadii: radii, style: .continuous).path(in: card).cgPath
    }
}
