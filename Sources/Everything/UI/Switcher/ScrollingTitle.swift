// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ScrollingTitle: View {
    let text: String
    let weight: Font.Weight
    let width: CGFloat
    let alignment: Alignment
    let scrolls: Bool

    @State private var began: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldScroll: Bool {
        scrolls && !reduceMotion && overflows
    }

    private static let size: CGFloat = 13
    private static let speed: CGFloat = 26
    private static let gap: CGFloat = 20
    private static let startDelay: Double = 0.4
    private static let fade: CGFloat = 6

    private var overflows: Bool {
        SwitcherSupport.titleOverflows(text,
                                       width: width,
                                       fontSize: Self.size,
                                       weight: weight == .semibold ? .semibold : .regular)
    }

    var body: some View {
        Group {
            if shouldScroll {
                scrollingLine
            } else {
                Text(text)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.system(size: Self.size, weight: weight))
        .frame(width: width, alignment: alignment)
    }

    private var scrollingLine: some View {
        let measured = SwitcherSupport.titleWidth(text,
                                                  fontSize: Self.size,
                                                  weight: weight == .semibold ? .semibold : .regular)
        let run = measured + Self.gap
        let cycle = Double(run) / Double(Self.speed) + Self.startDelay
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let start = began ?? context.date
            let phase = context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: cycle)
            let travelled = max(0, phase - Self.startDelay)
            let moved = CGFloat(travelled) * Self.speed
            let lead = min(1, moved / Self.fade) * Self.fade / width
            HStack(spacing: Self.gap) {
                Text(text).lineLimit(1).fixedSize()
                Text(text).lineLimit(1).fixedSize()
            }
            .offset(x: -moved)
            .frame(width: width, alignment: .leading)
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: lead),
                    .init(color: .black, location: 1 - Self.fade / width),
                    .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
            )
        }
        .frame(width: width, alignment: .leading)
        .clipped()
        .onAppear { began = Date() }
        .onChange(of: text) { _, _ in began = Date() }
    }
}
