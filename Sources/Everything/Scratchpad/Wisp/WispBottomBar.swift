import SwiftUI

struct BottomBar: View {
    let wordCount: Int
    let notice: String?
    let saveFailed: Bool
    let fontSize: FontSize
    let onCycleFontSize: () -> Void
    let themePreference: ThemePreference
    let onCycleTheme: () -> Void
    /// Something in the help overlay is new to this user.
    let hasUnseenTips: Bool
    let onHelpClick: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        // Everything: just the count (or a brief notice), bottom right.
        HStack(spacing: 12) {
            Spacer()
            if saveFailed {
                Text("couldn't save")
                    .foregroundStyle(.orange)
                    .help("The scratchpad can't write to its storage folder. Your text is still here — pick another folder in Settings.")
            }
            // The notice stands in for the count briefly, so the footer
            // never grows a second line of chrome.
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

    private var themeIconName: String {
        switch themePreference {
        case .light: return "sun.max"
        case .dark: return "moon"
        case .system: return "circle.lefthalf.filled"
        }
    }

    private var themeButtonHelp: String {
        switch themePreference.next {
        case .light: return "Switch to light theme"
        case .dark: return "Switch to dark theme"
        case .system: return "Follow system appearance"
        }
    }

    private var wordsLabel: String {
        wordCount == 1 ? "1 word" : "\(wordCount) words"
    }
}

/// Chrome controls sit at tertiary until hovered, then lift a step, so
/// they read as quiet text until the pointer shows they're buttons.
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
