// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct ScratchpadFormatBar: View {
    enum Style {
        case pad
        case island

        var buttonSize: CGFloat { self == .pad ? 26 : 28 }
        var cornerRadius: CGFloat { self == .pad ? 6 : 9 }
        var isDark: Bool { self == .island }
    }

    let style: Style
    var editor: NSTextView?

    @ObservedObject private var service = ScratchpadService.shared
    @ObservedObject private var l10n = L10n.shared

    private var text: ScratchpadFeatureStrings { FeatureStrings.scratchpad(l10n.language) }
    private var tint: Color { style.isDark ? .white.opacity(0.55) : .secondary }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(ScratchpadMark.allCases, id: \.self) { markButton($0) }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func markButton(_ mark: ScratchpadMark) -> some View {
        Button { service.apply(mark, through: editor) } label: {
            Group {
                if let glyph = mark.glyph {
                    Text(verbatim: glyph).font(.system(size: 13, weight: .semibold))
                } else {
                    Image(systemName: mark.symbol).font(.system(size: 12, weight: .medium))
                }
            }
            .foregroundStyle(tint)
            .frame(width: style.buttonSize, height: style.buttonSize)
            .contentShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(text.label(for: mark))
        .accessibilityLabel(text.label(for: mark))
    }
}
