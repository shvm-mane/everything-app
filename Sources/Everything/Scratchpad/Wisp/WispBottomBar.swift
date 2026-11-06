import SwiftUI

struct BottomBar: View {
    let wordCount: Int
    let notice: String?
    let saveFailed: Bool
    let fontSize: FontSize
    let onCycleFontSize: () -> Void
    let themePreference: ThemePreference
    let onCycleTheme: () -> Void
    let hasUnseenTips: Bool
    let onHelpClick: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 12) {
            Spacer()
            if saveFailed {
                Text("couldn't save")
                    .foregroundStyle(.orange)
                    .help("The scratchpad can't write to its storage folder. Your text is still here — pick another folder in Settings.")
            }
            ZStack(alignment: .trailing) {
                if let notice {
                    Text(notice)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else if wordCount > 0 {
                    Text(wordsLabel)
                        .monospacedDigit()
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: notice)
        }
        .font(.system(size: 10.5, weight: .regular))
        .foregroundStyle(contrast == .increased ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    private var wordsLabel: String {
        wordCount == 1 ? "1 word" : "\(wordCount) words"
    }
}

struct QuietButton<Content: View>: View {
    let action: () -> Void
    let help: String
    @ViewBuilder let content: () -> Content

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            content().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(style)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { hovering = inside }
        }
        .pointerCursor()
        .help(help)
        .accessibilityLabel(help)
    }

    private var style: AnyShapeStyle {
        switch (hovering, contrast == .increased) {
        case (false, false): return AnyShapeStyle(.tertiary)
        case (true, false), (false, true): return AnyShapeStyle(.secondary)
        case (true, true): return AnyShapeStyle(.primary)
        }
    }
}
